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
- **transform/** — Transform planning for streaming: computes whether edits fit in existing padding or require a full rewrite.
- **api/** — High-level public APIs: `DocumentApi` (immutable), `ReadApi`, `TransformApi`.
- **error/** — Typed exception hierarchy rooted at `FlacMetadataException`.

### Key Design Decisions

- **VorbisComments is NOT a map** — it preserves insertion order and duplicate keys. Use `valuesOf(key)`, not map access.
- **Immutable models** — edits return new instances via `document.edit((editor) => ...)`.
- **Unknown blocks survive round-trips** — they are preserved as-is during serialisation.
- **Tests use synthetic FLAC fixtures** built in-memory via helpers (`buildMinimalFlac()`, `buildFlac()`, `buildFlacWithVorbisComment()`), not real audio files.

### CLI (`bin/metaflac.dart`)

Aims for compatibility with the native `metaflac` command. Supports `--list`, `--show-md5`, `--set-tag`, `--remove-tag`, `--export-tags-to`, `--import-tags-from`, `--export-picture-to`, `--import-picture-from`.

### Planned but Not Yet Implemented

- `dart_metaflac_io` package — file persistence adapters with safe temp-file replacement
- `dart_metaflac_cli` as a separate package
- Full streaming transformer pipeline

## Design Documentation

Detailed specs live in `docs/design/`: `OVERVIEW.md` (vision), `TECH-SPEC.md` (comprehensive technical design), `PRD_v2.md` (product requirements), `PACKAGE-LAYOUT.md` (target package structure).
