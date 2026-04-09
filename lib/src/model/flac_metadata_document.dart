import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import 'flac_metadata_block.dart';
import 'picture_block.dart';
import 'stream_info_block.dart';
import 'vorbis_comment_block.dart';

final class FlacMetadataDocument {
  const FlacMetadataDocument({
    required this.blocks,
    required this.audioDataOffset,
    required this.sourceMetadataRegionLength,
    this.sourceBytes,
  });

  final List<FlacMetadataBlock> blocks;
  final int audioDataOffset;
  final int sourceMetadataRegionLength;
  final Uint8List? sourceBytes;

  StreamInfoBlock get streamInfo =>
      blocks.whereType<StreamInfoBlock>().single;

  VorbisCommentBlock? get vorbisComment =>
      blocks.whereType<VorbisCommentBlock>().firstOrNull;

  List<PictureBlock> get pictures =>
      blocks.whereType<PictureBlock>().toList(growable: false);

  // ── Factory constructors ──────────────────────────────────────────────────

  /// Parses a FLAC file from raw bytes and retains them for later
  /// serialisation via [toBytes].
  static FlacMetadataDocument readFromBytes(Uint8List bytes) {
    final doc = FlacParser.parseBytes(bytes);
    return FlacMetadataDocument(
      blocks: doc.blocks,
      audioDataOffset: doc.audioDataOffset,
      sourceMetadataRegionLength: doc.sourceMetadataRegionLength,
      sourceBytes: bytes,
    );
  }

  /// Collects a byte stream into memory, then parses it.
  static Future<FlacMetadataDocument> readFromStream(
      Stream<List<int>> stream) async {
    final bytes = await FlacParser.collectBytes(stream);
    return readFromBytes(bytes);
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  /// Serialises the current metadata blocks together with the original audio
  /// data into a complete FLAC byte sequence.
  ///
  /// Throws [StateError] when no source bytes are available (i.e. the
  /// document was not created via [readFromBytes] or [readFromStream]).
  Uint8List toBytes() {
    if (sourceBytes == null) {
      throw StateError(
        'Cannot serialise: no source bytes available. '
        'Use readFromBytes() or readFromStream() to create the document, '
        'or use FlacTransformer.transformStream() for streaming output.',
      );
    }
    final audioData = sourceBytes!.sublist(audioDataOffset);
    return FlacSerializer.serialize(blocks, audioData);
  }

  // ── Editing ──────────────────────────────────────────────────────────────

  FlacMetadataDocument edit(
      void Function(FlacMetadataEditor editor) updates) {
    final editor = FlacMetadataEditor.fromDocument(this);
    updates(editor);
    final built = editor.build();
    return FlacMetadataDocument(
      blocks: built.blocks,
      audioDataOffset: built.audioDataOffset,
      sourceMetadataRegionLength: built.sourceMetadataRegionLength,
      sourceBytes: sourceBytes,
    );
  }
}
