import 'dart:io';

/// File modification time capture and restore.
class ModTimePreserver {
  ModTimePreserver._();

  /// Capture a file's last modification time.
  static Future<DateTime> capture(String path) async {
    return File(path).lastModified();
  }

  /// Restore a file's last modification time.
  static Future<void> restore(String path, DateTime modTime) async {
    await File(path).setLastModified(modTime);
  }
}
