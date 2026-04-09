# Product Requirements Document v2

## dart-metaflac

**Pure Dart FLAC metadata toolkit with reusable library API and `metaflac`-compatible CLI**

**Document version:** 2.0
**Status:** Proposed
**Product name:** `dart-metaflac`
**Product type:** Core Dart library plus standalone CLI
**Target platforms:** Dart CLI on Windows, macOS, Linux; Flutter on iOS, Android, Web, and Desktop; server-side Dart runtimes; in-memory and stream-based environments. 

---

# 1. Executive summary

`dart-metaflac` is a pure Dart FLAC metadata toolkit designed to:

1. provide practical parity with the core metadata writing and inspection workflows of the `metaflac` utility, and
2. expose a reusable, platform-agnostic library API that can be embedded directly into Dart and Flutter applications without FFI, native binaries, or external system dependencies. 

The project is explicitly **library-first**. The standalone CLI is an adapter over the same core engine used by application developers.

The core package will be **I/O-agnostic** and work with byte arrays and streams rather than depending on `dart:io`, enabling use in Flutter Web, in-memory workflows, services, and desktop/mobile apps. File-path convenience APIs and safe on-disk replacement behavior will exist in an adapter layer above the core. 

The initial release will focus on the FLAC metadata operations that matter most in real use:

* Vorbis comment read/write/update/remove
* Picture block read/write/update/remove
* Padding-aware update logic
* Safe metadata rewrite behavior
* Metadata inspection and block listing
* Preservation of non-targeted blocks where possible

---

# 2. Product vision

Build the standard FLAC metadata editing package for the Dart ecosystem.

`dart-metaflac` should be the package a developer reaches for when they need to:

* inspect FLAC metadata without shelling out
* update tags and embedded art in a Flutter app
* normalize metadata in a backend asset pipeline
* replace common `metaflac` CLI workflows with a Dart-native tool
* build higher-level audio utilities on top of a reliable, typed library

The product should feel like a real Dart package, not a C CLI imitated awkwardly in Dart.

---

# 3. Problem statement

Dart and Flutter developers currently have poor options for FLAC metadata editing:

* call `metaflac` as a subprocess
* package native binaries
* rely on FFI or platform-specific plugins
* use incomplete libraries with weak FLAC support
* write their own binary metadata rewriting code

These approaches are fragile, hard to distribute, and often incompatible with Flutter Web or sandboxed environments.

Developers need a package that is:

* pure Dart
* safe for production metadata updates
* usable as both a library and a CLI
* stream-oriented and memory efficient
* portable across Dart and Flutter targets
* compatible with the most important `metaflac` workflows

---

# 4. Design interpretation and scope definition

This PRD interprets the product as a **FLAC metadata editing toolkit**, not a general Ogg/Vorbis container editor.

The earlier wording around “vorbis container” is interpreted as:

* support for **Vorbis comments inside FLAC**
* support for related FLAC metadata blocks commonly manipulated alongside comments
* support for safe block rewriting behavior comparable to `metaflac`

For v1, the product will center on:

* `VORBIS_COMMENT`
* `PICTURE`
* `PADDING`
* `STREAMINFO` read support
* raw preservation or read support for additional blocks such as `APPLICATION`, `SEEKTABLE`, and `CUESHEET` where practical. 

It will **not** attempt to become a general-purpose Ogg container library in v1.

---

# 5. Product principles

## 5.1 Library first

The CLI must be a thin wrapper over the library. No critical metadata logic may exist only in the CLI.

## 5.2 I/O-agnostic core

The core metadata engine must not depend on `dart:io`. It should operate on `Uint8List`, streams, and abstract read/write interfaces so it can run in Flutter Web and non-filesystem contexts. 

## 5.3 Safe by default

File corruption risk is unacceptable. Metadata rewrites must favor correctness and recoverability over clever but unsafe shortcuts.

## 5.4 Typed and ergonomic API

The public library API must feel natural in Dart. It should expose typed objects and clear operations, not just a translation layer for CLI flags.

## 5.5 Streaming where it matters

The product must support stream-based processing so large FLAC files can be updated without loading the audio payload into memory.  

## 5.6 Honest parity

The product should aim for parity with **core `metaflac` metadata workflows**, not promise literal one-to-one implementation of every obscure historical flag in v1.

---

# 6. Goals

## Primary goals

1. Implement FLAC metadata parsing and writing in 100% pure Dart. 
2. Provide practical parity with the core metadata capabilities of `metaflac`. 
3. Expose an embeddable library API suitable for Dart, Flutter, and Flutter Web. 
4. Support safe padding-aware updates and safe full rewrites when padding is insufficient.  
5. Preserve audio frames untouched during metadata updates.

## Secondary goals

1. Support JSON and automation-friendly CLI output.
2. Support multiple-file batch operations.
3. Preserve unknown or non-targeted blocks where possible.
4. Keep memory usage bounded on large files.

---

# 7. Non-goals

For v1, `dart-metaflac` will not:

* decode audio
* encode or transcode FLAC
* edit arbitrary Ogg/Vorbis containers
* become a general media tagging framework for all formats
* require native libraries
* guarantee exact emulation of every `metaflac` option in the first release
* support malformed-file authoring for experimental workflows

---

# 8. Users and personas

## 8.1 Flutter app developer

Needs to edit tags and album art inside an app without platform channels.

## 8.2 Backend/service developer

Needs to update or normalize FLAC metadata inside ingestion, cataloging, or archival pipelines.

## 8.3 CLI migration user

Needs familiar command-line behavior comparable to `metaflac`.

## 8.4 Package author

Needs a stable typed library to use as the metadata layer in another Dart project.

---

# 9. Product success criteria

The product is successful when:

1. A Dart developer can read and update FLAC Vorbis comments without calling external tools.
2. A Flutter developer can embed cover art and update tags without native plugins.
3. The CLI can replace common `metaflac` tag and picture operations.
4. Updates do not corrupt audio content.
5. Large-file rewrites run with bounded memory use.
6. The package can be used in stream-based and in-memory contexts, not only file-path workflows. 

---

# 10. Scope

## 10.1 In scope for v1

### Core parsing

* detect FLAC stream marker
* parse metadata block sequence
* expose block type, size, last-block flag, and typed representation where supported

### Core metadata support

* `STREAMINFO` read support
* `VORBIS_COMMENT` read/write/update/remove
* `PICTURE` read/write/update/remove
* `PADDING` read/write/update/remove
* `APPLICATION` read and preserve; optional limited write support if low risk
* `SEEKTABLE` read and preserve
* `CUESHEET` read and preserve

### Core update behaviors

* add, set, remove, and clear tags
* import/export tags
* add, replace, remove, and extract pictures
* consume or resize padding where valid
* rewrite metadata safely when padding is insufficient
* preserve audio frames unchanged

### Library surfaces

* byte-oriented API
* stream-oriented API
* high-level document/editor API
* typed exceptions
* deterministic serialization

### CLI surfaces

* inspection and listing
* tag mutation
* picture mutation
* padding management
* compatible aliases for common `metaflac` options
* batch mode
* JSON output
* dry-run

## 10.2 Out of scope for v1

* Ogg container editing
* non-FLAC tagging formats
* transcoding
* playback
* waveform analysis
* metadata lookup from online databases

---

# 11. Platform requirements

## 11.1 Core library

The core library must run anywhere standard Dart code can run, including Flutter Web, provided the caller supplies bytes or stream adapters rather than assuming local file mutation. 

## 11.2 File-based adapters

Desktop, server, and mobile-capable runtimes may use file-path helpers and safe replacement strategies.

## 11.3 Web

Web support is required for:

* byte-array parsing
* in-memory mutation
* generated output as bytes or streams

Web support does not imply direct local file rewriting semantics equivalent to desktop/server environments.

---

# 12. Architecture

The system will be split into strict layers.

## 12.1 Layer 1: Binary codec core

Responsibilities:

* parse FLAC metadata block headers and payloads
* serialize supported block types
* validate lengths and block structure
* preserve raw bytes for unknown blocks

Constraints:

* no `dart:io`
* pure Dart only
* deterministic behavior

## 12.2 Layer 2: Domain model

Responsibilities:

* typed block models
* Vorbis comment semantics
* picture metadata semantics
* block validation and normalization policies

## 12.3 Layer 3: Editing engine

Responsibilities:

* mutation operations
* add/set/remove/clear semantics
* block replacement logic
* padding-aware rewrite planning
* preservation policy for untouched blocks

## 12.4 Layer 4: Transformation engine

Responsibilities:

* produce transformed output as bytes or stream
* decide whether metadata can fit in existing space
* plan rewrite strategy without filesystem assumptions

## 12.5 Layer 5: Persistence/file adapter layer

Responsibilities:

* temp file creation
* safe atomic replacement where supported
* modtime preservation where requested
* file-based helpers using `dart:io`

This layer is where file-path convenience belongs, not in the core.

## 12.6 Layer 6: CLI

Responsibilities:

* parse CLI arguments
* map CLI semantics to library operations
* format results
* implement compatibility aliases for key `metaflac` flags

This layered structure is mandatory, not optional, because the uploaded design explicitly requires a core that is independent of `dart:io` and usable across Flutter and Web. 

---

# 13. Functional requirements

## 13.1 FLAC stream parsing

The library must:

* detect the `fLaC` marker
* parse metadata blocks in sequence
* expose block metadata:

  * type
  * length
  * isLast
  * raw payload
  * typed parsed form where supported
* stop reading metadata at the correct last block boundary
* leave audio frames untouched for metadata-only operations

### Acceptance criteria

* valid FLAC files parse successfully
* invalid headers fail with a typed exception
* multi-block files are parsed in order
* unknown blocks can be preserved as raw payloads

---

## 13.2 Vorbis comment support

The library must:

* parse vendor string
* parse all comment entries
* preserve multiple values for the same key
* support case-insensitive key matching for lookup and mutation
* distinguish:

  * add
  * set
  * remove key
  * remove exact pair
  * clear all
* create a Vorbis comment block if one is absent

### Public model requirement

The library must not rely only on a raw mutable `Map<String, List<String>>` as its canonical model. That view may be offered as a convenience, but the core model should preserve richer semantics such as ordering and duplicate entries.

Recommended shape:

* `VorbisComments` object or `List<VorbisCommentEntry>`
* optional convenience `asMap()` view

### Acceptance criteria

* duplicate keys are preserved correctly
* files without comments can be given a valid comment block
* logical tag round-tripping succeeds

---

## 13.3 Picture block support

The library must:

* read all picture blocks
* expose picture metadata:

  * picture type
  * MIME type
  * description
  * width
  * height
  * bit depth
  * indexed colors
  * raw bytes
* add picture blocks from bytes or adapters
* replace pictures by rule:

  * by index
  * by type
  * first matching
* remove pictures by:

  * index
  * type
  * all
* extract pictures to bytes or output adapter

### Acceptance criteria

* JPEG and PNG use cases work
* multiple picture blocks are supported
* extracted bytes match embedded bytes

---

## 13.4 Padding support

The library must:

* read padding blocks
* expose padding size
* consume existing padding when new metadata fits
* resize or replace padding during rewrite
* remove padding when requested

### Acceptance criteria

* small metadata expansions can succeed without rewriting the full file when sufficient padding exists
* padding size can be explicitly configured
* padding behavior is deterministic and testable

---

## 13.5 Additional metadata block support

The library must at minimum parse and preserve these blocks where present:

* `APPLICATION`
* `SEEKTABLE`
* `CUESHEET`

The library should expose typed models where practical, but preservation of raw valid payloads is more important than prematurely supporting every mutation path.

### Acceptance criteria

* such blocks survive round-trip updates when untouched
* files remain valid after rewrites

---

## 13.6 Safe update and rewrite behavior

This is the core technical feature.

The update engine must support the following logic:

1. read metadata region
2. compute new metadata size
3. if size fits existing allocation and block layout constraints, write compactly/in-place where valid
4. if not, produce a new output stream with rewritten metadata followed by streamed audio payload
5. in file-based adapters, safely persist the transformed output using temp-file replacement strategies

The core engine must not assume a filesystem. It should produce transformed output. The file adapter layer handles persistence safety.

### Write/persistence modes

At the adapter level, support:

* `safeAtomic`
* `auto`
* `inPlaceIfPossible`
* `outputToNewFile`

### Acceptance criteria

* metadata growth beyond existing padding triggers a streamed rewrite
* large audio payload is not fully loaded into memory
* file adapter defaults to safe replacement behavior
* failures do not silently corrupt the original file

---

## 13.7 Streaming API requirement

The uploaded design makes stream-based behavior a first-class requirement, so the library must expose a real streaming surface, not just byte-array helpers.  

Minimum required streaming capabilities:

* parse metadata from a stream-like source
* return a transformed output stream when performing rewrite operations
* avoid reading the full audio frame section into memory

### Acceptance criteria

* stream-driven update workflow is documented and tested
* large file tests demonstrate bounded memory use

---

## 13.8 High-level document/editor API requirement

Although streaming must be first-class, developer ergonomics still matter. The library must also expose a higher-level document/editor API for typical app use.

Required characteristics:

* immutable or controlled read model
* editor/builder mutation pattern
* clear write/transformation phase
* byte-oriented and stream-oriented output options

This gives consumers two valid entry points:

### High-level API

Best for application code and tests.

### Streaming API

Best for services, tools, and large-file pipelines.

Both are required.

---

# 14. Public API requirements

## 14.1 Suggested core types

* `FlacMetadataDocument`
* `FlacMetadataEditor`
* `FlacMetadataBlock`
* `StreamInfoBlock`
* `VorbisCommentBlock`
* `VorbisComments`
* `VorbisCommentEntry`
* `PictureBlock`
* `PaddingBlock`
* `ApplicationBlock`
* `SeekTableBlock`
* `CueSheetBlock`
* `FlacTransformer`
* `FlacReadOptions`
* `FlacTransformOptions`
* `FlacWriteOptions`

## 14.2 Suggested exception types

* `FlacMetadataException`
* `InvalidFlacException`
* `MalformedMetadataException`
* `UnsupportedBlockException`
* `FlacInsufficientPaddingException`
* `WriteConflictException`
* `FlacIoException`

The uploaded design explicitly calls for specific typed exceptions rather than generic failures, and that should remain a hard requirement. 

## 14.3 Example high-level API

```dart id="m2la5v"
final doc = await FlacMetadataDocument.readFromBytes(bytes);

final updated = doc.edit((e) => e
  ..setTag('ARTIST', ['New Artist Name'])
  ..setTag('ALBUM', ['Awesome Album'])
  ..replaceFrontCoverBytes(
    mimeType: 'image/jpeg',
    data: coverBytes,
    description: 'Front cover',
  )
  ..setPadding(8192),
);

final outBytes = await updated.toBytes();
```

## 14.4 Example streaming API

```dart id="7qlmfw"
final editor = FlacEditor(inputStream);

final metadata = await editor.readMetadata();

final transformed = await editor.updateMetadata(
  vorbisComments: metadata.vorbisComments.copyWith(
    set: {
      'ARTIST': ['New Artist Name'],
      'ALBUM': ['Awesome Album'],
    },
  ),
);

await transformed.pipe(outputSink);
```

This dual-surface model incorporates the uploaded draft’s stream-first design without losing the earlier PRD’s better ergonomics. 

---

# 15. CLI requirements

## 15.1 CLI design approach

The CLI should support both:

1. a modern structured command style
2. compatibility aliases for common `metaflac` flags

### Modern style examples

```bash id="uiux78"
dart-metaflac inspect file.flac
dart-metaflac blocks list file.flac
dart-metaflac tags list file.flac
dart-metaflac tags set file.flac ARTIST="Miles Davis"
dart-metaflac tags remove file.flac COMMENT
dart-metaflac picture add file.flac --file cover.jpg --type front-cover
dart-metaflac padding set file.flac 8192
```

### Compatibility alias examples

```bash id="pjlwmk"
dart-metaflac --list file.flac
dart-metaflac --show-md5 file.flac
dart-metaflac --set-tag="ARTIST=Miles Davis" file.flac
dart-metaflac --remove-tag=COMMENT file.flac
dart-metaflac --remove-all-tags file.flac
dart-metaflac --import-picture-from=cover.jpg file.flac
dart-metaflac --export-tags-to=tags.txt file.flac
```

This merged design keeps a clean Dart-native CLI while honoring the uploaded draft’s stronger requirement for practical command-line parity. 

## 15.2 Required CLI operations

### General options

* `--preserve-modtime`
* `--with-filename`
* `--no-utf8-convert` compatibility handling, with documented behavior if local charset conversion is intentionally not mirrored exactly in pure Dart contexts. 

### Read/inspect operations

* `inspect`
* `blocks list`
* `--list`
* `--show-md5`
* `tags list`
* `--export-tags-to`
* `--export-picture-to`

### Mutation operations

* `tags set`
* `tags add`
* `tags remove`
* `tags clear`
* `--set-tag`
* `--remove-tag`
* `--remove-all-tags`
* `--import-tags-from`
* `picture add`
* `picture replace`
* `picture remove`
* `--import-picture-from`
* `padding set`
* `padding remove`

## 15.3 CLI output

* human-readable default
* JSON mode for automation
* quiet mode
* explicit exit codes
* stable error structure in JSON mode

## 15.4 Batch behavior

* process multiple files
* continue-on-error option
* dry-run mode
* per-file result reporting

---

# 16. Parity statement

For v1, the product will claim:

> parity with the core FLAC metadata editing and inspection workflows of `metaflac`

This includes:

* tag inspection and mutation
* picture import/export
* metadata listing
* padding-aware updates
* safe rewrite behavior
* key compatibility options and aliases

It does not mean perfect literal support for every historical `metaflac` behavior in the first release.

That wording is materially better and safer than claiming “full parity” on day one.

---

# 17. Non-functional requirements

## 17.1 Performance

The product must avoid buffering full audio payloads during normal metadata rewrite operations. Audio frame data should be streamed. 

The uploaded draft proposes a strong target: a 50MB FLAC file should be updatable in under 100ms when sufficient padding exists. That is a good engineering benchmark target, but this PRD treats it as an internal performance objective rather than a public guarantee because actual timing will vary by runtime and device. 

Minimum requirements:

* metadata-only reads should be fast and not scan full audio payloads
* padding-hit updates should avoid full rewrite when valid
* full rewrites should use bounded memory

## 17.2 Memory efficiency

* audio frames must not be fully loaded into RAM during standard rewrite flow
* memory growth should be driven by metadata size and buffer size, not full file size

## 17.3 Reliability

* deterministic parsing and serialization
* predictable exceptions
* preservation of untouched valid blocks where possible

## 17.4 Safety

* safe defaults for file persistence
* temp-file replacement for file-based writes
* no shelling out
* no hidden native dependency

## 17.5 Testability

* minimum 85% unit coverage is a good target and aligns with the uploaded draft, though the more important metric is coverage of the binary parser, transform engine, and corruption edge cases. 

---

# 18. Security and robustness requirements

Because this product parses untrusted binary content, it must:

* validate declared block lengths before allocation
* reject truncated and malformed blocks safely
* avoid unchecked large allocations
* preserve unknown blocks only when structurally valid
* avoid temp-file naming vulnerabilities in file adapters
* never silently ignore write failures

---

# 19. Testing requirements

## 19.1 Unit tests

* FLAC marker validation
* metadata block header parsing
* typed block parsing
* Vorbis comment serialization
* picture serialization
* padding calculations
* exception mapping

## 19.2 Integration tests

* read/edit/write round trips
* stream-based update workflows
* file-based safe replacement workflows
* CLI command behavior
* JSON output behavior
* multiple-file processing

## 19.3 Compatibility tests

* compare supported workflows with expected `metaflac` outcomes
* validate rewritten files with external FLAC tools where possible in CI

## 19.4 Negative tests

* malformed headers
* invalid length fields
* truncated metadata
* insufficient padding cases
* invalid picture payloads
* corrupted block sequences

## 19.5 Fixture requirements

The fixture suite should include:

* minimal FLAC
* multi-block FLAC
* Vorbis-only FLAC
* picture-heavy FLAC
* padded FLAC
* files with unknown metadata blocks
* malformed samples

---

# 20. Documentation requirements

The product must ship with:

* README
* quick-start guide
* library usage guide
* Flutter guide
* Web/in-memory guide
* CLI guide
* migration guide from `metaflac`
* examples for:

  * reading tags
  * setting tags
  * appending multi-valued tags
  * importing/exporting pictures
  * using the streaming API
  * safe file rewrites
  * using the package in Flutter

---

# 21. Packaging and repository structure

Recommended monorepo layout:

```text id="rydx5j"
repo/
  packages/
    dart_metaflac/
      lib/
      test/
      example/
    dart_metaflac_io/
      lib/
      test/
    dart_metaflac_cli/
      bin/
      lib/
      test/
  fixtures/
  docs/
```

## Rationale

### `dart_metaflac`

Pure core package, no `dart:io`

### `dart_metaflac_io`

File adapters and persistence helpers for local filesystems

### `dart_metaflac_cli`

Executable package built on top of the core and IO adapter

This is a stronger design than a single flat package because it enforces the architecture required by the uploaded draft. 

---

# 22. Delivery milestones

The uploaded draft’s milestone structure is good and should be retained with more detail. 

## Milestone 1: Foundation and reading

Deliverables:

* FLAC marker parsing
* metadata block header parsing
* typed base models
* `STREAMINFO`, `VORBIS_COMMENT`, and `PICTURE` read support
* block listing support
* initial fixture library

Exit criteria:

* valid sample files parse correctly
* malformed inputs fail predictably

## Milestone 2: Writing and padding logic

Deliverables:

* Vorbis comment serialization
* picture serialization
* padding-aware transformation planning
* stream-based rewrite support
* round-trip tests

Exit criteria:

* tag and picture mutations succeed
* output files remain valid

## Milestone 3: File persistence and safety

Deliverables:

* IO adapter package
* safeAtomic mode
* outputToNewFile mode
* inPlaceIfPossible mode where valid
* modtime preservation option

Exit criteria:

* file rewrite tests pass
* failures do not silently corrupt source file

## Milestone 4: CLI completion

Deliverables:

* modern subcommand CLI
* compatibility aliases for key `metaflac` flags
* JSON output
* batch processing
* dry-run

Exit criteria:

* common automation workflows function end-to-end

## Milestone 5: Hardening and release

Deliverables:

* docs
* examples
* compatibility guide
* performance benchmarks
* release packaging for pub.dev

Exit criteria:

* all v1 acceptance criteria satisfied
* docs complete
* examples compile

---

# 23. Backlog priorities

## Must-have for v1

* pure core parser
* Vorbis comment CRUD
* picture CRUD
* padding-aware transformation
* safe file rewrite adapter
* stream-based API
* typed exceptions
* CLI inspect/list/tags/picture/padding
* compatibility aliases for key `metaflac` options

## Should-have for v1

* JSON mode
* batch processing
* tag import/export
* picture export
* preservation of unknown valid blocks
* Web-oriented examples

## Could-have

* additional application-block mutation support
* validation command
* backup-on-write option
* richer compatibility shim coverage

## Won’t-have for v1

* Ogg editing
* audio decoding
* transcoding
* non-FLAC format support

---

# 24. Acceptance criteria summary

The product is ready for v1 when all of the following are true:

1. The core package parses FLAC metadata without using `dart:io`.
2. The library supports both high-level document-style APIs and streaming transformation APIs.
3. Vorbis comments can be read, added, set, removed, and cleared.
4. Picture blocks can be read, embedded, replaced, extracted, and removed.
5. Padding can be inspected and used during metadata updates.
6. When padding is insufficient, the library can produce a correct transformed output stream without loading the full audio payload into memory.
7. File-based adapters provide safe replacement behavior.
8. The CLI supports the core metadata workflows of `metaflac`.
9. Key `metaflac` flags have documented compatibility aliases.
10. Rewritten files remain valid in external FLAC tooling.
11. The package is documented for Dart, Flutter, and Web/in-memory scenarios.

---

# 25. Final product statement

`dart-metaflac` is a **pure Dart FLAC metadata toolkit** that provides:

* a portable, reusable core library
* first-class stream and byte-based APIs
* safe padding-aware metadata transformation
* file-based persistence adapters
* a standalone CLI with practical `metaflac` compatibility

The most important architectural rule in this merged v2 is this:

**the core package is a binary metadata transformation library, not a file editor.**

That one decision is what makes the product reusable in Dart, Flutter, and Web while still allowing a strong CLI story. It is also the biggest improvement introduced by the uploaded design.
