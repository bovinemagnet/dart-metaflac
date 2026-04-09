# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
dart test                              # Run all tests
dart test test/flac_parser_test.dart   # Run a single test file
dart test -n "test name"               # Run tests matching a name
dart analyze                           # Run linter (uses package:lints/recommended)
dart run bin/metaflac.dart             # Run the CLI tool
```

No build step required — pure Dart project using `dart test` directly.

## Architecture

This is a pure Dart FLAC metadata library with **no `dart:io` dependency** in the core. The core operates on `Uint8List` and `Stream<List<int>>` only, making it usable in Flutter Web and server environments.

### Layered Module Structure (`lib/src/`)

- **binary/** — Low-level parsing and serialisation. `FlacParser` reads FLAC bytes into typed blocks; `FlacSerializer` writes them back. `ByteReader`/`ByteWriter` handle endianness.
- **model/** — Immutable domain objects: `FlacMetadataDocument` (container), `VorbisComments`, `StreamInfoBlock`, `PictureBlock`, etc. All metadata block types (0–6) are modelled; unknown types are preserved as raw bytes.
- **edit/** — `FlacMetadataEditor` accumulates `MetadataMutation` operations (sealed class hierarchy) and produces updated documents. `PaddingStrategy` determines in-place vs full rewrite.
- **transform/** — Transform planning and streaming. `FlacTransformer` supports both in-memory (`transform()`) and streaming (`transformStream()`) transforms. `StreamRewriter` buffers only metadata, streaming audio through without loading it into memory.
- **api/** — High-level public APIs: `DocumentApi` (immutable), `ReadApi`, `TransformApi`.
- **io/** — File persistence adapters using `dart:io`. `FlacFileEditor` provides safe file read/write with `AtomicWriter` (temp file + rename). Supports write modes: `safeAtomic`, `outputToNewFile`, `inPlaceIfPossible`, `auto`. `ModTimePreserver` handles modification time capture/restore.
- **error/** — Typed exception hierarchy rooted at `FlacMetadataException`.

### Key Design Decisions

- **VorbisComments is NOT a map** — it preserves insertion order and duplicate keys. Use `valuesOf(key)`, not map access.
- **Immutable models** — edits return new instances via `document.edit((editor) => ...)`. The canonical high-level flow is: `FlacMetadataDocument.readFromBytes(bytes)` → `doc.edit(...)` → `updated.toBytes()`.
- **Unknown blocks survive round-trips** — they are preserved as-is during serialisation.
- **Tests use synthetic FLAC fixtures** built in-memory via `buildFlac()` helpers, not real audio files.

### CLI (`bin/metaflac.dart`)

Supports both modern subcommand style and `metaflac`-compatible `--flag` aliases. The CLI detects whether the first argument is a subcommand or a flag and routes accordingly.

**Modern subcommands:** `inspect`, `blocks list`, `tags list/set/add/remove/clear/import/export`, `picture add/remove/export`, `padding set/remove`.

**Compatibility flags:** `--list`, `--show-md5`, `--set-tag`, `--remove-tag`, `--export-tags-to`, `--import-tags-from`, `--export-picture-to`, `--import-picture-from`.

**Global options:** `--json`, `--dry-run`, `--continue-on-error`, `--quiet`/`-q`, `--preserve-modtime`, `--with-filename`. Exit codes: 0 (success), 1 (general error), 2 (invalid args), 3 (invalid FLAC), 4 (I/O error).

**CLI internals** live in `lib/src/cli/`: `BaseFlacCommand` (shared options), `MetaflacCommandRunner`, `formatters.dart` (output helpers), and command files in `commands/`.

### Planned but Not Yet Implemented

- `dart_metaflac_cli` as a separate package
- DartDoc comments and pub.dev documentation

## Design Documentation

Detailed specs live in `docs/design/`: `OVERVIEW.md` (vision), `TECH-SPEC.md` (comprehensive technical design), `PRD_v2.md` (product requirements), `PACKAGE-LAYOUT.md` (target package structure).
