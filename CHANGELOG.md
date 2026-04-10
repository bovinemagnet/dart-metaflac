## 0.0.1

Initial public release.

- Pure-Dart FLAC metadata parser with no `dart:io` dependency in the core
  library. Works on the standalone Dart VM, Flutter (including Flutter
  Web and WASM), server isolates, and browser targets.
- Two public library entry points:
  - `package:dart_metaflac/dart_metaflac.dart` — core, pure Dart.
  - `package:dart_metaflac/io.dart` — file/IO adapters, requires
    `dart:io` (not available on Flutter Web).
- Complete support for every standard FLAC metadata block type
  (STREAMINFO, PADDING, APPLICATION, SEEKTABLE, VORBIS_COMMENT,
  CUESHEET, PICTURE). Unknown block types are preserved byte-for-byte
  on round-trip.
- Immutable document model with an editor-callback API for in-memory
  edits (`doc.edit((editor) => ...)`) and a `MetadataMutation` list
  API for file-based edits (`FlacFileEditor.updateFile`).
- Streaming transform API that never buffers audio data, so multi-gigabyte
  FLAC files can be edited in constant memory.
- File persistence via `FlacFileEditor` with safe atomic writes
  (temp file + rename), multiple write modes (`safeAtomic`, `auto`,
  `inPlaceIfPossible`, `outputToNewFile`), and optional modification-time
  preservation.
- `metaflac`-compatible CLI tool at `bin/metaflac.dart` supporting both
  modern subcommands (`inspect`, `blocks list`, `tags`, `picture`,
  `padding`) and classic `--flag` aliases (`--list`, `--set-tag`,
  `--export-tags-to`, etc). Global options include `--json`, `--dry-run`,
  `--continue-on-error`, `--quiet`, `--preserve-modtime`, and
  `--with-filename`. Exit codes follow the metaflac convention.
- Typed exception hierarchy rooted at `FlacMetadataException`.
- Runnable examples for reading, editing, pictures, streaming, file
  rewriting, Flutter Web / WASM in-memory round-trips, and a minimal
  Flutter app.
- Antora documentation site under `src/docs/` with getting-started,
  library guide, architecture, CLI reference, audio integrity, and
  migration guide.
- 258 tests covering parsing, serialisation, editing, transforms,
  streaming, file IO, CLI, and both synthetic and on-disc fixtures.
