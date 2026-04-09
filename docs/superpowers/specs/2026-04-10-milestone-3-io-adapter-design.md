# Design Spec: Milestone 3 — IO Adapter Layer

**Date:** 2026-04-10
**Status:** Approved
**Issue:** #5
**Scope:** File persistence and safety layer with safe atomic writes, write modes, and modtime preservation.

---

## 1. Context

The core library is IO-agnostic (no `dart:io`). File operations in the CLI use raw `File.readAsBytesSync` / `File.writeAsBytesSync` with no safety guarantees. Milestone 3 adds a proper IO adapter layer that handles safe file persistence.

---

## 2. New Files

### `lib/src/io/atomic_writer.dart`

Safe file replacement utility.

```dart
class AtomicWriter {
  /// Write bytes to path via temp file + rename (atomic on most filesystems).
  static Future<void> writeAtomic(String path, Uint8List bytes);

  /// Write bytes to a new file at the given path.
  static Future<void> writeToNew(String path, Uint8List bytes);
}
```

`writeAtomic` algorithm:
1. Create temp file in same directory as target: `<path>.tmp.<random>`
2. Write all bytes to temp file
3. Flush (ensure data hits disk)
4. Rename temp file over target path
5. On any failure, delete temp file if it exists

### `lib/src/io/flac_write_options.dart`

```dart
class FlacWriteOptions {
  const FlacWriteOptions({
    this.writeMode = WriteMode.safeAtomic,
    this.preserveModTime = false,
    this.outputPath,
    this.explicitPaddingSize,
  });

  final WriteMode writeMode;
  final bool preserveModTime;
  final String? outputPath;       // required for outputToNewFile
  final int? explicitPaddingSize;
}
```

Uses the existing `WriteMode` enum from `flac_transform_options.dart`.

### `lib/src/io/flac_file_editor.dart`

High-level file API.

```dart
class FlacFileEditor {
  /// Read and parse a FLAC file.
  static Future<FlacMetadataDocument> readFile(String path);

  /// Apply mutations to a FLAC file and write it back safely.
  static Future<void> updateFile(
    String path, {
    required List<MetadataMutation> mutations,
    FlacWriteOptions options = const FlacWriteOptions(),
  });
}
```

`updateFile` algorithm:
1. Read file bytes
2. Parse with `FlacParser.parseBytes()`
3. Apply mutations via `FlacMetadataEditor`
4. Compute transform plan
5. Serialise result bytes
6. Optionally capture original modtime (if `preserveModTime`)
7. Write based on `writeMode`:
   - `safeAtomic`: `AtomicWriter.writeAtomic(path, bytes)`
   - `outputToNewFile`: `AtomicWriter.writeToNew(options.outputPath!, bytes)`
   - `inPlaceIfPossible`: if `plan.fitsExistingRegion`, write in-place via `RandomAccessFile`; else throw `WriteConflictException`
   - `auto`: try in-place if fits, else fall back to `safeAtomic`
8. Restore modtime if requested

### `lib/src/io/modtime.dart`

```dart
class ModTimePreserver {
  /// Capture a file's modification time.
  static Future<DateTime> capture(String path);

  /// Restore a file's modification time.
  static Future<void> restore(String path, DateTime modTime);
}
```

Uses `File.lastModified()` / `File.setLastModified()` on supported platforms. Falls back silently on platforms where `setLastModified` is unavailable (note: Dart SDK 3.x supports this on all desktop platforms).

---

## 3. Exports

Add to `lib/dart_metaflac.dart`:

```dart
// IO adapters
export 'src/io/atomic_writer.dart';
export 'src/io/flac_file_editor.dart';
export 'src/io/flac_write_options.dart';
export 'src/io/modtime.dart';
```

---

## 4. CLI Update

Update `bin/metaflac.dart` to use `FlacFileEditor.updateFile()` for write operations instead of raw `file.writeAsBytesSync(result.bytes)`. The `--preserve-modtime` flag maps to `FlacWriteOptions(preserveModTime: true)`. Remove the `touch` process hack for modtime preservation.

---

## 5. Testing

### `test/atomic_writer_test.dart`
- Writes file atomically (temp created then renamed)
- Target file contains correct bytes after write
- Temp file cleaned up on write failure (simulate by writing to read-only directory)
- `writeToNew` creates file at specified path

### `test/flac_file_editor_test.dart`
- `readFile` returns valid document
- `updateFile` with `safeAtomic` writes correctly
- `updateFile` with `outputToNewFile` writes to new path, original unchanged
- `updateFile` with `inPlaceIfPossible` succeeds when metadata shrinks (fits)
- `updateFile` with `inPlaceIfPossible` throws WriteConflictException when metadata grows
- `updateFile` with `auto` falls back to safeAtomic when metadata grows
- `preserveModTime` option preserves file modification time
- Multiple mutations applied correctly through file API

### `test/modtime_test.dart`
- Capture returns a DateTime
- Restore sets the modtime correctly

---

## 6. Out of Scope

- Separate `dart_metaflac_io` package (keep in same package under `lib/src/io/`)
- Streaming file transforms (Milestone 3 uses bytes-based transforms via the file adapter)
- Cross-platform modtime edge cases (Windows NTFS precision, etc.)
