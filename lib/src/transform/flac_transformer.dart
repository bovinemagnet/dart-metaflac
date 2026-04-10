import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import '../edit/mutation_ops.dart';
import '../model/flac_metadata_document.dart';
import 'flac_transform_options.dart';
import 'flac_transform_plan.dart';
import 'flac_transform_result.dart';
import 'stream_rewriter.dart';

/// Apply [MetadataMutation] operations to FLAC data supplied as either
/// raw bytes or a byte stream.
///
/// Two factory constructors are provided:
///
/// * [FlacTransformer.fromBytes] — operates on an in-memory [Uint8List].
/// * [FlacTransformer.fromStream] — operates on a `Stream<List<int>>`,
///   enabling large-file processing without loading the entire file into
///   memory.
///
/// Use [readMetadata] to inspect existing metadata, [transform] for a
/// fully in-memory round-trip, or [transformStream] for a streaming
/// transform that avoids buffering audio data.
class FlacTransformer {
  FlacTransformer._fromBytes(this._bytes) : _stream = null;
  FlacTransformer._fromStream(this._stream) : _bytes = null;

  /// Create a transformer that operates on an in-memory FLAC file.
  factory FlacTransformer.fromBytes(Uint8List bytes) =>
      FlacTransformer._fromBytes(bytes);

  /// Create a transformer that operates on a FLAC byte stream.
  ///
  /// The stream is consumed lazily; for [readMetadata] and [transform]
  /// the entire stream is first collected into memory. For
  /// [transformStream], only the metadata portion is buffered.
  factory FlacTransformer.fromStream(Stream<List<int>> stream) =>
      FlacTransformer._fromStream(stream);

  final Uint8List? _bytes;
  final Stream<List<int>>? _stream;

  Future<Uint8List> _resolveBytes() async {
    if (_bytes != null) return _bytes!;
    return FlacParser.collectBytes(_stream!);
  }

  /// Parse the FLAC data and return its metadata document without
  /// applying any mutations.
  ///
  /// Throws a [FlacMetadataException] subclass if the data is not a
  /// valid FLAC file.
  Future<FlacMetadataDocument> readMetadata() async {
    final bytes = await _resolveBytes();
    return FlacParser.parseBytes(bytes);
  }

  /// Apply [mutations] to the FLAC data and return a fully serialised
  /// [FlacTransformResult].
  ///
  /// The entire file (metadata + audio) is held in memory during the
  /// transform. For large files where memory is a concern, prefer
  /// [transformStream].
  ///
  /// When [FlacTransformOptions.explicitPaddingSize] is set, a
  /// [SetPadding] mutation is appended automatically.
  ///
  /// Throws a [FlacMetadataException] subclass if the input data is not
  /// a valid FLAC file.
  Future<FlacTransformResult> transform({
    required List<MetadataMutation> mutations,
    FlacTransformOptions options = FlacTransformOptions.defaults,
  }) async {
    final input = await _resolveBytes();
    final doc = FlacParser.parseBytes(input);

    final editor = FlacMetadataEditor.fromDocument(doc);
    for (final m in mutations) {
      editor.applyMutation(m);
    }

    if (options.explicitPaddingSize != null) {
      editor.setPadding(options.explicitPaddingSize!);
    }

    final updated = editor.build();
    final audioData = input.sublist(doc.audioDataOffset);
    final outBytes = FlacSerializer.serialize(updated.blocks, audioData);

    final originalSize = doc.sourceMetadataRegionLength;
    final newSize = outBytes.length - audioData.length;
    final plan = FlacTransformPlan(
      originalBlocks: doc.blocks,
      transformedBlocks: updated.blocks,
      originalMetadataRegionSize: originalSize,
      transformedMetadataRegionSize: newSize,
      fitsExistingRegion: newSize <= originalSize,
      requiresFullRewrite: newSize > originalSize,
    );

    return FlacTransformResult(document: updated, bytes: outBytes, plan: plan);
  }

  /// Transform FLAC metadata via streaming.
  ///
  /// Unlike [transform], this method streams audio data through without
  /// buffering the entire file in memory. Returns a stream of the
  /// transformed FLAC file.
  ///
  /// When [FlacTransformOptions.explicitPaddingSize] is set, padding is
  /// adjusted accordingly.
  ///
  /// Throws a [FlacMetadataException] subclass if the input stream does
  /// not contain a valid FLAC file.
  Future<Stream<List<int>>> transformStream({
    required List<MetadataMutation> mutations,
    FlacTransformOptions options = FlacTransformOptions.defaults,
  }) async {
    final inputStream = _bytes != null
        ? Stream.fromIterable([_bytes!.toList()])
        : _stream!;
    return StreamRewriter.rewrite(
      input: inputStream,
      mutations: mutations,
      options: options,
    );
  }
}
