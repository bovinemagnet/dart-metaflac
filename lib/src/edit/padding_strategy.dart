class PaddingStrategy {
  PaddingStrategy._();

  static const int defaultPadding = 8192;

  static int computeRemainingPadding({
    required int originalMetadataRegionSize,
    required int newMetadataContentSize,
  }) {
    return originalMetadataRegionSize - newMetadataContentSize;
  }

  static bool fitsExistingRegion({
    required int originalMetadataRegionSize,
    required int newMetadataContentSize,
  }) {
    return newMetadataContentSize <= originalMetadataRegionSize;
  }
}
