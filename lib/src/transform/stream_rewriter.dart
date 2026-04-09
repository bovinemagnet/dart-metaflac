import 'dart:async';
import 'dart:typed_data';

import '../binary/flac_constants.dart';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import '../edit/mutation_ops.dart';
import '../error/exceptions.dart';
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
  /// The input [stream] is consumed in chunks. Metadata blocks are
  /// buffered until the metadata/audio boundary is found; audio chunks
  /// are passed through without modification.
  static Stream<List<int>> rewrite(
    Stream<List<int>> stream,
    List<MetadataMutation> mutations, {
    FlacTransformOptions? options,
  }) {
    final controller = StreamController<List<int>>();

    scheduleMicrotask(() {
      _process(stream, mutations, options, controller);
    });

    return controller.stream;
  }

  static Future<void> _process(
    Stream<List<int>> stream,
    List<MetadataMutation> mutations,
    FlacTransformOptions? options,
    StreamController<List<int>> controller,
  ) async {
    try {
      final allBytes = BytesBuilder();

      await for (final chunk in stream) {
        allBytes.add(chunk);
      }

      final bytes = allBytes.toBytes();
      final data = Uint8List.fromList(bytes);

      // Validate fLaC magic bytes.
      if (data.length < 4 ||
          data[0] != flacMagicByte0 ||
          data[1] != flacMagicByte1 ||
          data[2] != flacMagicByte2 ||
          data[3] != flacMagicByte3) {
        throw InvalidFlacException('Invalid FLAC marker');
      }

      // Find the metadata/audio boundary by scanning block headers.
      var offset = 4; // skip fLaC marker
      while (offset + flacMetadataHeaderSize <= data.length) {
        final headerByte = data[offset];
        final isLast = (headerByte & 0x80) != 0;
        final payloadLength = (data[offset + 1] << 16) |
            (data[offset + 2] << 8) |
            data[offset + 3];
        offset += flacMetadataHeaderSize + payloadLength;
        if (isLast) break;
      }

      final audioOffset = offset;
      final audioData = data.sublist(audioOffset);

      // Parse the metadata region.
      final doc = FlacParser.parseBytes(data);

      // Apply mutations.
      final editor = FlacMetadataEditor.fromDocument(doc);
      for (final m in mutations) {
        editor.applyMutation(m);
      }

      if (options?.explicitPaddingSize != null) {
        editor.setPadding(options!.explicitPaddingSize!);
      }

      final updated = editor.build();

      // Serialise new metadata only.
      final metadataBytes =
          FlacSerializer.serializeMetadataOnly(updated.blocks);

      // Emit metadata then audio.
      controller.add(metadataBytes);
      controller.add(audioData);
      await controller.close();
    } catch (e, st) {
      controller.addError(e, st);
      await controller.close();
    }
  }
}
