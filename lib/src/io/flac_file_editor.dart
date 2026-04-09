import 'dart:io';
import 'dart:typed_data';
import '../api/transform_api.dart';
import '../edit/mutation_ops.dart';
import '../error/exceptions.dart';
import '../model/flac_metadata_document.dart';
import '../transform/flac_transform_options.dart';
import 'atomic_writer.dart';
import 'flac_write_options.dart';
import 'modtime.dart';

/// High-level file-based FLAC metadata editor.
class FlacFileEditor {
  FlacFileEditor._();

  /// Read and parse a FLAC file from [path].
  static Future<FlacMetadataDocument> readFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return FlacMetadataDocument.readFromBytes(bytes);
    } on FileSystemException catch (e) {
      throw FlacIoException('Failed to read file: $path', cause: e);
    }
  }

  /// Apply [mutations] to the FLAC file at [path] and write it back safely.
  static Future<void> updateFile(
    String path, {
    required List<MetadataMutation> mutations,
    FlacWriteOptions options = const FlacWriteOptions(),
  }) async {
    // 1. Optionally capture modtime before any changes.
    DateTime? originalModTime;
    if (options.preserveModTime) {
      originalModTime = await ModTimePreserver.capture(path);
    }

    // 2. Read and transform.
    final inputBytes = await File(path).readAsBytes();
    final transformOptions = FlacTransformOptions(
      explicitPaddingSize: options.explicitPaddingSize,
    );
    final result = await transformFlac(
      inputBytes,
      mutations,
      options: transformOptions,
    );

    // 3. Write based on mode.
    final targetPath = options.writeMode == WriteMode.outputToNewFile
        ? options.outputPath ??
            (throw ArgumentError(
                'outputPath is required for outputToNewFile mode'))
        : path;

    switch (options.writeMode) {
      case WriteMode.safeAtomic:
        await AtomicWriter.writeAtomic(targetPath, result.bytes);
      case WriteMode.outputToNewFile:
        await AtomicWriter.writeToNew(targetPath, result.bytes);
      case WriteMode.inPlaceIfPossible:
        if (result.plan.fitsExistingRegion) {
          await _writeInPlace(path, result.bytes, inputBytes.length);
        } else {
          throw WriteConflictException(
            'Metadata does not fit existing region. '
            'Use safeAtomic or auto mode instead.',
          );
        }
      case WriteMode.auto:
        if (result.plan.fitsExistingRegion) {
          await _writeInPlace(path, result.bytes, inputBytes.length);
        } else {
          await AtomicWriter.writeAtomic(targetPath, result.bytes);
        }
    }

    // 4. Restore modtime if requested.
    if (options.preserveModTime && originalModTime != null) {
      await ModTimePreserver.restore(targetPath, originalModTime);
    }
  }

  /// Write bytes in-place when the new content fits the existing file size.
  static Future<void> _writeInPlace(
    String path,
    Uint8List newBytes,
    int originalLength,
  ) async {
    final raf = await File(path).open(mode: FileMode.writeOnly);
    try {
      await raf.writeFrom(newBytes);
      // If new file is shorter, truncate.
      if (newBytes.length < originalLength) {
        await raf.truncate(newBytes.length);
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
  }
}
