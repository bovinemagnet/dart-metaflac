import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import 'flac_metadata_block.dart';
import 'picture_block.dart';
import 'stream_info_block.dart';
import 'vorbis_comment_block.dart';

/// Immutable representation of a complete FLAC file's metadata.
///
/// A [FlacMetadataDocument] holds the ordered list of metadata [blocks],
/// positional information about where audio data begins, and optionally
/// the original source bytes for later serialisation.
///
/// Documents are typically created via [readFromBytes] or [readFromStream]
/// and modified through the [edit] method, which returns a new document
/// with the requested changes applied.
///
/// Example usage:
/// ```dart
/// final doc = FlacMetadataDocument.readFromBytes(bytes);
/// final updated = doc.edit((editor) {
///   editor.setTag('ARTIST', ['New Artist']);
/// });
/// final output = updated.toBytes();
/// ```
///
/// See also:
/// - [FlacMetadataEditor] for the mutation API used within [edit].
/// - [FlacMetadataBlock] for individual block types.
final class FlacMetadataDocument {
  /// Create a [FlacMetadataDocument] with the given components.
  ///
  /// Prefer [readFromBytes] or [readFromStream] for parsing real FLAC data.
  const FlacMetadataDocument({
    required this.blocks,
    required this.audioDataOffset,
    required this.sourceMetadataRegionLength,
    this.sourceBytes,
  });

  /// The ordered list of metadata blocks in this document.
  ///
  /// The first block is always a [StreamInfoBlock] as required by the FLAC
  /// specification. Subsequent blocks may appear in any order.
  final List<FlacMetadataBlock> blocks;

  /// The byte offset at which audio frame data begins in the source file.
  ///
  /// This is the position immediately after the last metadata block header
  /// and payload.
  final int audioDataOffset;

  /// The total byte length of the metadata region in the original source,
  /// including block headers.
  ///
  /// Used by the editor to determine whether an in-place update is possible
  /// without rewriting the entire file.
  final int sourceMetadataRegionLength;

  /// The original FLAC file bytes, retained for serialisation via [toBytes].
  ///
  /// This is `null` when the document was constructed directly rather than
  /// parsed from a byte source.
  final Uint8List? sourceBytes;

  /// The mandatory [StreamInfoBlock] for this FLAC file.
  ///
  /// Every valid FLAC file contains exactly one STREAMINFO block.
  ///
  /// Throws [StateError] if the document contains zero or more than one
  /// [StreamInfoBlock].
  StreamInfoBlock get streamInfo => blocks.whereType<StreamInfoBlock>().single;

  /// The [VorbisCommentBlock] if present, or `null` otherwise.
  ///
  /// A FLAC file may contain at most one Vorbis comment block holding
  /// user-facing tags such as ARTIST and TITLE.
  VorbisCommentBlock? get vorbisComment =>
      blocks.whereType<VorbisCommentBlock>().firstOrNull;

  /// All [PictureBlock] instances in this document.
  ///
  /// A FLAC file may contain multiple picture blocks, each representing a
  /// different image (e.g. front cover, back cover, artist photo).
  List<PictureBlock> get pictures =>
      blocks.whereType<PictureBlock>().toList(growable: false);

  // ── Factory constructors ──────────────────────────────────────────────────

  /// Parse a FLAC file from raw [bytes] and retain them for later
  /// serialisation via [toBytes].
  ///
  /// Throws [InvalidFlacException] if the bytes do not begin with a valid
  /// FLAC stream marker.
  ///
  /// Throws [MalformedMetadataException] if any metadata block cannot be
  /// parsed.
  static FlacMetadataDocument readFromBytes(Uint8List bytes) {
    final doc = FlacParser.parseBytes(bytes);
    return FlacMetadataDocument(
      blocks: doc.blocks,
      audioDataOffset: doc.audioDataOffset,
      sourceMetadataRegionLength: doc.sourceMetadataRegionLength,
      sourceBytes: bytes,
    );
  }

  /// Collect a byte [stream] into memory, then parse it as a FLAC file.
  ///
  /// This is a convenience wrapper around [readFromBytes] for use with
  /// streaming sources.
  ///
  /// Throws [InvalidFlacException] if the collected bytes do not form a
  /// valid FLAC file.
  static Future<FlacMetadataDocument> readFromStream(
      Stream<List<int>> stream) async {
    final bytes = await FlacParser.collectBytes(stream);
    return readFromBytes(bytes);
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  /// Serialise the current metadata blocks together with the original audio
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

  /// Apply mutations to this document and return a new [FlacMetadataDocument]
  /// with the changes.
  ///
  /// The [updates] callback receives a [FlacMetadataEditor] pre-populated
  /// with this document's current state. After the callback returns, the
  /// editor builds a new document preserving the original [sourceBytes] for
  /// subsequent serialisation.
  ///
  /// Example:
  /// ```dart
  /// final updated = doc.edit((editor) {
  ///   editor.setTag('TITLE', ['New Title']);
  /// });
  /// ```
  FlacMetadataDocument edit(void Function(FlacMetadataEditor editor) updates) {
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
