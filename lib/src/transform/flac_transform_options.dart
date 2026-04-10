/// Strategy used when writing transformed FLAC data to disc.
///
/// See also: [FlacTransformOptions], which bundles a [WriteMode] with
/// other transform settings.
enum WriteMode {
  /// Write to a temporary file and atomically rename it over the
  /// original. This is the safest option as it avoids partial writes on
  /// failure.
  safeAtomic,

  /// Automatically choose between in-place and full rewrite based on
  /// whether the new metadata fits within the existing metadata region.
  auto,

  /// Attempt an in-place overwrite of the metadata region when the new
  /// metadata fits. Falls back to a full rewrite if it does not fit.
  inPlaceIfPossible,

  /// Write the transformed output to a new file, leaving the original
  /// untouched.
  outputToNewFile,
}

/// Configuration for a FLAC metadata transform operation.
///
/// Instances are typically passed to [FlacTransformer.transform] or
/// [FlacTransformer.transformStream].
final class FlacTransformOptions {
  /// Create transform options.
  ///
  /// [writeMode] defaults to [WriteMode.safeAtomic].
  /// [explicitPaddingSize], when non-null, overrides the default padding
  /// strategy with a fixed number of bytes.
  const FlacTransformOptions({
    this.writeMode = WriteMode.safeAtomic,
    this.explicitPaddingSize,
  });

  /// The file-write strategy to use.
  final WriteMode writeMode;

  /// An explicit padding size in bytes, or `null` to use the default
  /// [PaddingStrategy].
  final int? explicitPaddingSize;

  /// Sensible default options using [WriteMode.safeAtomic] and no
  /// explicit padding override.
  static const FlacTransformOptions defaults = FlacTransformOptions();
}
