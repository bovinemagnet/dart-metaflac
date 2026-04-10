import '../transform/flac_transform_options.dart';

/// Configuration for file-based FLAC write operations.
///
/// Control how [FlacFileEditor.updateFile] writes the modified FLAC data
/// back to disc. The [writeMode] determines the writing strategy, while
/// optional fields allow modification time preservation and explicit
/// padding control.
///
/// See also:
/// - [WriteMode], which enumerates the available writing strategies.
/// - [FlacTransformOptions], which controls transform-level options.
class FlacWriteOptions {
  /// Create a set of write options.
  ///
  /// All parameters are optional and default to safe, non-destructive
  /// values: [WriteMode.safeAtomic] for [writeMode], `false` for
  /// [preserveModTime], and `null` for both [outputPath] and
  /// [explicitPaddingSize].
  const FlacWriteOptions({
    this.writeMode = WriteMode.safeAtomic,
    this.preserveModTime = false,
    this.outputPath,
    this.explicitPaddingSize,
  });

  /// Strategy for writing the output file.
  ///
  /// Defaults to [WriteMode.safeAtomic]. See [WriteMode] for a
  /// description of each strategy.
  final WriteMode writeMode;

  /// Whether to preserve the original file's modification time.
  ///
  /// When `true`, the file's last-modified timestamp is captured before
  /// any changes and restored after the write completes. Useful when
  /// metadata edits should not alter the apparent modification date.
  final bool preserveModTime;

  /// Output file path for [WriteMode.outputToNewFile].
  ///
  /// Required when [writeMode] is [WriteMode.outputToNewFile]; ignored
  /// for all other write modes. An [ArgumentError] is thrown at write
  /// time if this is `null` and the mode requires it.
  final String? outputPath;

  /// Explicit padding size in bytes for the output metadata region.
  ///
  /// When non-null, the padding block in the output is resized to
  /// exactly this many bytes. When `null`, the library determines
  /// padding automatically.
  final int? explicitPaddingSize;
}
