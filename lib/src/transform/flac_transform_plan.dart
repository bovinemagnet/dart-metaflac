import '../model/flac_metadata_block.dart';

/// Detailed breakdown of how a transform was (or will be) applied.
///
/// A plan is produced as part of every [FlacTransformResult] and records
/// both the before/after block lists and the size calculations that
/// determine whether the file needs a full rewrite.
final class FlacTransformPlan {
  /// Create a transform plan.
  const FlacTransformPlan({
    required this.originalBlocks,
    required this.transformedBlocks,
    required this.originalMetadataRegionSize,
    required this.transformedMetadataRegionSize,
    required this.fitsExistingRegion,
    required this.requiresFullRewrite,
  });

  /// The metadata blocks present before the transform.
  final List<FlacMetadataBlock> originalBlocks;

  /// The metadata blocks produced by the transform.
  final List<FlacMetadataBlock> transformedBlocks;

  /// Total size (in bytes) of the original metadata region, including
  /// any padding.
  final int originalMetadataRegionSize;

  /// Total size (in bytes) of the transformed metadata region.
  final int transformedMetadataRegionSize;

  /// Whether the transformed metadata fits within the original metadata
  /// region without expanding the file.
  final bool fitsExistingRegion;

  /// Whether the audio data must be rewritten because the transformed
  /// metadata exceeds the original region.
  final bool requiresFullRewrite;
}
