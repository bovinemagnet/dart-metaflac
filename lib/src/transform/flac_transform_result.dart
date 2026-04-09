import 'dart:typed_data';
import '../model/flac_metadata_document.dart';
import 'flac_transform_plan.dart';

final class FlacTransformResult {
  const FlacTransformResult({
    required this.document,
    required this.bytes,
    required this.plan,
  });
  final FlacMetadataDocument document;
  final Uint8List bytes;
  final FlacTransformPlan plan;
}
