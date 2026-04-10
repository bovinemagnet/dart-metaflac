/// Utility for computing whether transformed metadata fits within the
/// original metadata region and how much padding remains.
///
/// This class is not instantiable; all members are static.
class PaddingStrategy {
  PaddingStrategy._();

  /// Default padding size in bytes appended when creating new metadata.
  static const int defaultPadding = 8192;

  /// Compute the remaining padding after writing new metadata content
  /// into the original metadata region.
  ///
  /// Returns the difference between [originalMetadataRegionSize] and
  /// [newMetadataContentSize]. A negative result indicates that the new
  /// content exceeds the original region and a full rewrite is required.
  static int computeRemainingPadding({
    required int originalMetadataRegionSize,
    required int newMetadataContentSize,
  }) {
    return originalMetadataRegionSize - newMetadataContentSize;
  }

  /// Determine whether the new metadata content fits within the original
  /// metadata region without requiring a full file rewrite.
  ///
  /// Returns `true` when [newMetadataContentSize] is less than or equal
  /// to [originalMetadataRegionSize].
  static bool fitsExistingRegion({
    required int originalMetadataRegionSize,
    required int newMetadataContentSize,
  }) {
    return newMetadataContentSize <= originalMetadataRegionSize;
  }
}
