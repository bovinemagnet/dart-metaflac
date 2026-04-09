import 'dart:typed_data';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import '../edit/mutation_ops.dart';
import '../transform/flac_transform_options.dart';
import '../transform/flac_transform_plan.dart';
import '../transform/flac_transform_result.dart';

Future<FlacTransformResult> transformFlac(
  Uint8List input,
  List<MetadataMutation> mutations, {
  FlacTransformOptions options = FlacTransformOptions.defaults,
}) async {
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
