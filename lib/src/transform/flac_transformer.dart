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

class FlacTransformer {
  FlacTransformer._fromBytes(this._bytes) : _stream = null;
  FlacTransformer._fromStream(this._stream) : _bytes = null;

  factory FlacTransformer.fromBytes(Uint8List bytes) =>
      FlacTransformer._fromBytes(bytes);

  factory FlacTransformer.fromStream(Stream<List<int>> stream) =>
      FlacTransformer._fromStream(stream);

  final Uint8List? _bytes;
  final Stream<List<int>>? _stream;

  Future<Uint8List> _resolveBytes() async {
    if (_bytes != null) return _bytes!;
    return FlacParser.collectBytes(_stream!);
  }

  Future<FlacMetadataDocument> readMetadata() async {
    final bytes = await _resolveBytes();
    return FlacParser.parseBytes(bytes);
  }

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

  /// Transforms FLAC metadata via streaming.
  ///
  /// Unlike [transform], this method streams audio data through without
  /// buffering the entire file in memory. Returns a stream of the
  /// transformed FLAC file.
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
