import '../transform/flac_transform_options.dart';

/// Options for file-based FLAC write operations.
class FlacWriteOptions {
  const FlacWriteOptions({
    this.writeMode = WriteMode.safeAtomic,
    this.preserveModTime = false,
    this.outputPath,
    this.explicitPaddingSize,
  });

  /// How to write the output file.
  final WriteMode writeMode;

  /// Whether to preserve the original file's modification time.
  final bool preserveModTime;

  /// Output file path (required for [WriteMode.outputToNewFile]).
  final String? outputPath;

  /// Explicit padding size to use in the output.
  final int? explicitPaddingSize;
}
