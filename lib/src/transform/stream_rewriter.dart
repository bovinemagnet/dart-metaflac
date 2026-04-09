import 'dart:async';
import 'dart:typed_data';

import '../binary/flac_constants.dart';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import '../edit/mutation_ops.dart';
import 'flac_transform_options.dart';

/// Rewrites FLAC metadata in a single pass over a byte stream.
///
/// Only the metadata region is buffered; the audio payload is collected
/// as separate chunks and streamed through without being fully parsed.
class StreamRewriter {
  StreamRewriter._();

  /// Rewrites the metadata of a FLAC stream, applying [mutations] and
  /// emitting the result as a new stream.
  ///
  /// The [input] stream is consumed in chunks. Metadata blocks are
  /// buffered until the metadata/audio boundary is found; audio chunks
  /// are passed through without modification.
  static Future<Stream<List<int>>> rewrite({
    required Stream<List<int>> input,
    required List<MetadataMutation> mutations,
    FlacTransformOptions? options,
  }) async {
    final effectiveOptions = options ?? FlacTransformOptions.defaults;
    final buffer = BytesBuilder();
    int? audioStartOffset;
    final audioChunks = <List<int>>[];

    await for (final chunk in input) {
      if (audioStartOffset != null) {
        // Already past metadata — collect audio chunks directly.
        audioChunks.add(chunk);
        continue;
      }

      buffer.add(chunk);
      final accumulated = buffer.toBytes();
      audioStartOffset = _findAudioOffset(accumulated);

      if (audioStartOffset != null && audioStartOffset < accumulated.length) {
        // Split: bytes past boundary are first audio chunk.
        audioChunks.add(Uint8List.sublistView(accumulated, audioStartOffset));
      }
    }

    final accumulated = buffer.toBytes();
    if (audioStartOffset == null) {
      audioStartOffset = _findAudioOffset(accumulated) ?? accumulated.length;
    }

    // Parse the metadata region (FlacParser validates the fLaC marker).
    final doc = FlacParser.parseBytes(accumulated);

    // Apply mutations.
    final editor = FlacMetadataEditor.fromDocument(doc);
    for (final m in mutations) {
      editor.applyMutation(m);
    }

    if (effectiveOptions.explicitPaddingSize != null) {
      editor.setPadding(effectiveOptions.explicitPaddingSize!);
    }

    final updated = editor.build();

    // Serialise new metadata only.
    final newMetadata =
        FlacSerializer.serializeMetadataOnly(updated.blocks);

    // Emit metadata then audio chunks.
    final controller = StreamController<List<int>>();
    controller.add(newMetadata);
    for (final audioChunk in audioChunks) {
      controller.add(audioChunk);
    }
    controller.close();

    return controller.stream;
  }

  /// Scans accumulated bytes for the metadata/audio boundary.
  ///
  /// Walks block headers from offset 4 (after fLaC marker) until the
  /// isLast block is found. Returns the offset where audio data begins,
  /// or null if not enough bytes have been accumulated yet.
  static int? _findAudioOffset(Uint8List data) {
    if (data.length < 4) return null;

    // Check fLaC marker.
    if (data[0] != flacMagicByte0 ||
        data[1] != flacMagicByte1 ||
        data[2] != flacMagicByte2 ||
        data[3] != flacMagicByte3) {
      return null;
    }

    var offset = 4; // Skip fLaC marker.
    while (offset + flacMetadataHeaderSize <= data.length) {
      final headerByte = data[offset];
      final isLast = (headerByte & 0x80) != 0;
      final payloadLength = (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];
      final blockEnd = offset + flacMetadataHeaderSize + payloadLength;

      if (blockEnd > data.length) {
        // Not enough data accumulated yet for this block.
        return null;
      }

      offset = blockEnd;
      if (isLast) return offset;
    }

    return null;
  }
}
