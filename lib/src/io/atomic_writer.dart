import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Safe file writing utilities.
class AtomicWriter {
  AtomicWriter._();

  /// Write bytes to [path] via temp file + rename.
  ///
  /// Creates a temp file in the same directory, writes all bytes,
  /// flushes to disk, then renames over the target. If anything fails,
  /// the temp file is cleaned up.
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

  /// Write bytes to a new file at [path].
  static Future<void> writeToNew(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
  }

  static String _randomSuffix() {
    final rng = Random();
    return rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  }
}
