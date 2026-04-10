import 'dart:typed_data';
import '../model/flac_metadata_document.dart';
import 'flac_transform_plan.dart';

/// Outcome of a completed in-memory FLAC transform.
///
/// Bundles the updated [FlacMetadataDocument], the fully serialised
/// output [bytes], and the [FlacTransformPlan] that describes how the
/// transform was carried out.
///
/// Returned by [FlacTransformer.transform].
final class FlacTransformResult {
  /// Create a transform result.
  const FlacTransformResult({
    required this.document,
    required this.bytes,
    required this.plan,
  });

  /// The updated metadata document after mutations have been applied.
  final FlacMetadataDocument document;

  /// The complete serialised FLAC file (metadata + audio) as raw bytes.
  final Uint8List bytes;

  /// The transform plan describing original vs. transformed sizes and
  /// whether a full rewrite was required.
  final FlacTransformPlan plan;
}
