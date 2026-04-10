import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Safe file writing utilities using atomic operations.
///
/// Provides two writing strategies: atomic writes via a temporary file
/// and rename (see [writeAtomic]), and direct writes to a new file
/// (see [writeToNew]). The atomic strategy ensures that the target file
/// is never left in a partially written state, even if the process is
/// interrupted or an error occurs.
///
/// This class cannot be instantiated; all methods are static.
class AtomicWriter {
  AtomicWriter._();

  /// Write [bytes] to [path] atomically via a temporary file and rename.
  ///
  /// Create a temporary file in the same directory as [path], write all
  /// [bytes] to it, flush to disc, then rename over the target. If any
  /// step fails, the temporary file is cleaned up before the exception
  /// propagates.
  ///
  /// Because the rename is atomic on most file systems, readers of
  /// [path] will either see the old content or the new content, never a
  /// partial write.
  ///
  /// Throws [FileSystemException] if the directory does not exist or the
  /// file cannot be written.
  static Future<void> writeAtomic(String path, Uint8List bytes) async {
    final targetFile = File(path);
    final dir = targetFile.parent;
    final tempName =
        '.${targetFile.uri.pathSegments.last}.tmp.${_randomSuffix()}';
    final tempFile = File('${dir.path}/$tempName');
    try {
      final raf = await tempFile.open(mode: FileMode.writeOnly);
      try {
        await raf.writeFrom(bytes);
        await raf.flush();
      } finally {
        await raf.close();
      }
      await tempFile.rename(path);
    } catch (e) {
      // Clean up temp file on failure.
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup failures.
      }
      rethrow;
    }
  }

  /// Write [bytes] directly to a new file at [path].
  ///
  /// Create or overwrite the file at [path] with [bytes] and flush to
  /// disc. Unlike [writeAtomic], this does not use a temporary file, so
  /// readers may observe a partially written file if the process is
  /// interrupted.
  ///
  /// Throws [FileSystemException] if the directory does not exist or the
  /// file cannot be written.
  static Future<void> writeToNew(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
  }

  static String _randomSuffix() {
    final rng = Random();
    return rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }
}
