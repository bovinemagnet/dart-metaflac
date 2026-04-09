import '../model/flac_metadata_block.dart';

final class FlacTransformPlan {
  const FlacTransformPlan({
    required this.originalBlocks,
    required this.transformedBlocks,
    required this.originalMetadataRegionSize,
    required this.transformedMetadataRegionSize,
    required this.fitsExistingRegion,
    required this.requiresFullRewrite,
  });

  final List<FlacMetadataBlock> originalBlocks;
  final List<FlacMetadataBlock> transformedBlocks;
  final int originalMetadataRegionSize;
  final int transformedMetadataRegionSize;
  final bool fitsExistingRegion;
  final bool requiresFullRewrite;
}
