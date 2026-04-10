import 'dart:io';

/// File modification time capture and restore utility.
///
/// Provide the ability to snapshot a file's last-modified timestamp
/// before performing edits and to restore it afterwards, so that
/// metadata-only changes do not alter the apparent modification date.
///
/// This class cannot be instantiated; all methods are static.
///
/// See also:
/// - [FlacWriteOptions.preserveModTime], which enables automatic
///   modification time preservation during file updates.
class ModTimePreserver {
  ModTimePreserver._();

  /// Capture the last-modified time of the file at [path].
  ///
  /// Return the [DateTime] representing when the file was last modified.
  ///
  /// Throws [FileSystemException] if the file does not exist or its
  /// metadata cannot be read.
  static Future<DateTime> capture(String path) async {
    return File(path).lastModified();
  }

  /// Restore the last-modified time of the file at [path] to [modTime].
  ///
  /// Set the file's last-modified timestamp to the previously captured
  /// [modTime] value, effectively undoing any timestamp change caused
  /// by a write operation.
  ///
  /// Throws [FileSystemException] if the file does not exist or its
  /// metadata cannot be updated.
  static Future<void> restore(String path, DateTime modTime) async {
    await File(path).setLastModified(modTime);
  }
}
