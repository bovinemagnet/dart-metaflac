# Product Requirements Document

## dart-metaflac

**Document status:** Draft v1
**Product type:** Dart package with CLI + reusable library
**Primary audience:** Dart/Flutter developers, backend tooling developers, audio pipeline maintainers
**Project name:** `dart-metaflac`

---

## 1. Overview

`dart-metaflac` is a pure Dart implementation of the metadata writing and updating capabilities commonly associated with the `metaflac` tool, designed first as an embeddable library and second as a standalone CLI.

The product will allow Dart and Flutter applications to inspect, create, update, remove, and rewrite FLAC metadata with strong support for Vorbis comments and other metadata blocks handled by `metaflac`. It must support use in local desktop/server workflows and in-app library usage without requiring native binaries, shelling out, or platform-specific plugins.

This product is not just a command-line clone. It is a metadata engine with a CLI wrapper.

---

## 2. Assumptions and interpretation

This PRD assumes the phrase “vorbis container writing and updating capability of metaflac” refers to:

* **FLAC metadata manipulation**
* especially **Vorbis comment block** reading/writing/updating
* plus adjacent writable FLAC metadata handled by `metaflac`, such as:

  * PADDING
  * APPLICATION
  * SEEKTABLE
  * CUESHEET
  * PICTURE
  * STREAMINFO constraints where writable
  * block ordering and rewrite behavior

This PRD **does not** define v1 support for general Ogg container editing or Ogg Vorbis file authoring. If that becomes important, it should be a separate package or a later extension.

---

## 3. Problem statement

Today, Dart and Flutter developers who need robust FLAC metadata editing usually have bad options:

* shell out to `metaflac`
* rely on platform channels or native binaries
* use incomplete tag libraries with weak FLAC support
* build ad hoc metadata rewriting code that is unsafe for production

That is not acceptable for portable Dart tooling.

Developers need a package that:

* works in **pure Dart**
* supports **library embedding**
* offers **metaflac-like parity**
* safely updates files without corrupting audio content
* exposes a modern API instead of only CLI semantics

---

## 4. Vision

Build the definitive FLAC metadata editing package for Dart:

* **library-first**
* **pure Dart**
* **safe, deterministic, testable**
* **CLI-compatible enough to replace `metaflac` in common workflows**
* **small enough to embed in Flutter or server applications**

---

## 5. Goals

### Primary goals

1. Provide a pure Dart library for reading and writing FLAC metadata.
2. Provide parity with the most commonly used `metaflac` metadata update capabilities.
3. Expose a clean public API for programmatic use in Dart and Flutter.
4. Provide a CLI that mirrors `metaflac` concepts closely enough for easy adoption.
5. Preserve file integrity through safe rewrite/update strategies.
6. Support large files without loading entire audio payloads into memory.

### Secondary goals

1. Make batch metadata operations simple.
2. Make library APIs typed and ergonomic.
3. Support streaming-oriented IO for non-UI and backend use cases.
4. Keep Flutter compatibility by avoiding `dart:ffi` and native dependencies.

---

## 6. Non-goals

For v1, `dart-metaflac` will **not**:

* decode or play audio
* transcode FLAC audio
* edit general Ogg Vorbis containers
* write arbitrary invalid metadata for edge-case experimentation
* support every obscure `metaflac` flag on day one if it does not map cleanly to library semantics
* depend on external executables
* require desktop/mobile-specific plugins

---

## 7. Target users

### 1. Dart/Flutter app developers

Need to inspect or modify album metadata, embedded art, and tags inside apps.

### 2. Backend/service developers

Need to batch update metadata in asset pipelines or catalogs.

### 3. CLI users migrating from `metaflac`

Need familiar commands for scripting and automation.

### 4. Package authors

Need a stable library dependency for higher-level audio tooling.

---

## 8. Core product principles

### Library first

The CLI must be a thin wrapper around a reusable core package. No CLI-only business logic.

### Pure Dart

No FFI. No system binary dependency. No platform channels as a requirement.

### Safe by default

Updates should prefer atomic writes and corruption prevention over raw speed.

### Typed API over stringly API

CLI can accept strings; library must expose typed objects and operations.

### Metadata correctness matters more than feature sprawl

The package should be strict about FLAC block rules and predictable behavior.

---

## 9. Scope

## In scope for v1

### Read support

* Parse FLAC metadata blocks
* Read Vorbis comments
* Read pictures
* Read padding
* Read application blocks
* Read seektable metadata
* Read cuesheet metadata
* Inspect block order and sizes
* Expose file-level metadata summary

### Write/update support

* Add/update/remove Vorbis comment entries
* Set tags with replace/append semantics
* Remove individual tags or all tags
* Import/export tag values in useful formats
* Add/remove/replace PICTURE blocks
* Add/remove/resize PADDING blocks
* Add/remove APPLICATION blocks
* Remove or rewrite specific metadata blocks where valid
* Preserve audio frames untouched
* Perform safe metadata block rewrites when in-place update is not possible

### CLI support

* Commands modeled after the common `metaflac` workflows
* File inspection
* Tag mutation
* Picture mutation
* Padding management
* Batch processing over multiple files

### Library support

* File-based API
* Byte stream / byte array API where practical
* Sync and async surfaces where reasonable
* Strong error types
* Transaction-like update operations

## Out of scope for v1

* Ogg container mutation
* audio decoding APIs
* waveform analysis
* metadata internet lookup
* tagging formats outside FLAC metadata scope

---

## 10. Success criteria

The product is successful if:

1. A developer can replace common `metaflac` shell calls with `dart-metaflac` CLI commands.
2. A developer can embed the package in a Dart or Flutter app without native code.
3. Typical operations on valid FLAC files do not corrupt audio data.
4. The public API feels like a library, not a CLI awkwardly wrapped in Dart.
5. The package passes compatibility tests against real-world FLAC samples and `metaflac` output expectations.

---

## 11. Functional requirements

## 11.1 FLAC parsing

The library must:

* detect valid FLAC streams from file headers
* parse metadata blocks in sequence
* expose:

  * block type
  * length
  * isLast flag
  * raw block payload
  * parsed typed representation where supported
* preserve unknown block types as raw blocks when rewriting, unless explicitly removed

### Acceptance criteria

* Valid FLAC file opens and all metadata blocks are enumerated in order.
* Unknown but well-formed blocks are preserved during read/write cycles unless the user removes them.

---

## 11.2 Vorbis comments

The library must support full CRUD operations for Vorbis comment blocks.

### Required capabilities

* read vendor string
* read all comment fields
* preserve repeated keys
* normalize key matching in a spec-consistent manner
* add field
* set field
* remove field by key
* remove field by exact key/value match
* remove all Vorbis comments
* create Vorbis comment block if missing
* preserve ordering where feasible or apply documented canonical ordering policy

### Semantics

The library must distinguish:

* **set**: replace existing values for a key
* **add**: append additional value
* **remove**: delete key or matching pair
* **clear**: remove all comments

### Acceptance criteria

* Files without Vorbis comments can receive a new block.
* Duplicate tags such as multiple `ARTIST` values remain valid.
* Round-trip write/read returns identical logical tags.

---

## 11.3 Picture block support

The library must support:

* read all PICTURE blocks
* add picture from bytes or file
* replace picture by type/index
* remove pictures by type/index/all
* expose MIME type, description, dimensions, color depth, indexed colors, data length
* support common cover art workflows

### Acceptance criteria

* JPEG and PNG images can be embedded and later extracted unchanged.
* Multiple picture blocks are supported.

---

## 11.4 Padding support

The library must support:

* inspect current padding blocks
* add padding block
* replace padding size
* remove padding
* use padding strategically to reduce future rewrites

### Acceptance criteria

* User can specify exact padding bytes for rewritten output.
* Metadata growth can consume padding before forcing full rewrite.

---

## 11.5 Block-level operations

The library must support selected block-level operations comparable to `metaflac` workflows:

* list blocks
* remove blocks by type
* export/import supported block payloads where applicable
* preserve unsupported block data during rewrite
* enforce valid ordering and FLAC constraints on rewritten output

### Acceptance criteria

* Blocks can be removed selectively without damaging remaining metadata.
* File remains readable by standard FLAC tools after rewrite.

---

## 11.6 Safe update and rewrite engine

This is the most important technical requirement.

### Required behavior

* If metadata changes fit within existing space, the library may update in place.
* If not, the library must rewrite metadata and stream audio frames through without loading the full file into memory.
* Default write mode should be safe and atomic where file system semantics allow.
* Temporary file strategy should be built in.
* Recovery-oriented failure behavior must be documented.

### Write modes

* **safeAtomic**: write temp file then replace original
* **inPlaceIfPossible**: only mutate in place when guaranteed safe, else fail
* **auto**: choose best strategy automatically
* **outputToNewFile**: write modified result to another path or sink

### Acceptance criteria

* A power loss or exception during `safeAtomic` does not leave a half-written original file in the normal success path.
* Large FLAC files can be rewritten without memory explosion.

---

## 11.7 CLI parity

The CLI should provide practical parity with `metaflac`, especially for metadata authoring tasks.

### CLI capabilities

* show metadata / list blocks
* export tags
* set/add/remove tags
* remove all tags
* import tags from file or stdin
* add/remove/replace pictures
* add/remove padding
* batch process files
* dry-run mode
* machine-readable output option, preferably JSON

### Compatibility direction

Flag names and concepts should be familiar to `metaflac` users, but exact parity is not required where it would produce a bad library design.

That said, the CLI should stay close enough that common shell scripts are easy to port.

### Acceptance criteria

* A user familiar with `metaflac` understands the command structure quickly.
* CLI help clearly documents divergences from `metaflac`.

---

## 11.8 Library API ergonomics

The library must not force consumers to think in terms of shell flags.

### Required API qualities

* typed model objects
* immutable read models where sensible
* builder or editor pattern for mutation
* async file APIs
* clear separation between parsing, editing, and serialization
* support for byte-level operations for in-memory use cases

### Example conceptual API

```dart
final doc = await FlacMetadata.readFromFile('track.flac');

final updated = doc.edit((m) => m
  ..setTag('ALBUM', ['Kind of Blue'])
  ..addTag('ARTIST', 'Miles Davis')
  ..removeTag('COMMENT')
  ..replaceFrontCoverBytes(
    mimeType: 'image/jpeg',
    data: coverBytes,
    description: 'Front cover',
  )
  ..setPadding(8192),
);

await updated.writeToFile(
  'track.flac',
  mode: WriteMode.safeAtomic,
);
```

### Acceptance criteria

* Common update flows require little boilerplate.
* Flutter consumers can use the package without platform-specific setup.

---

## 12. Public API requirements

## 12.1 Suggested package structure

### `dart_metaflac`

Core public library package.

### `dart_metaflac_cli`

CLI wrapper package, potentially in same repository.

## 12.2 Suggested public types

* `FlacMetadataDocument`
* `FlacMetadataBlock`
* `StreamInfoBlock`
* `VorbisCommentBlock`
* `PictureBlock`
* `PaddingBlock`
* `ApplicationBlock`
* `SeekTableBlock`
* `CueSheetBlock`
* `FlacMetadataEditor`
* `WriteMode`
* `FlacReadOptions`
* `FlacWriteOptions`
* `FlacMetadataException`
* `InvalidFlacException`
* `UnsupportedBlockException`
* `WriteConflictException`

## 12.3 API design rules

* prefer value objects over mutable maps
* expose raw bytes when users need exact preservation
* support both high-level operations and lower-level block manipulation
* clearly document when exact byte preservation is guaranteed vs logical preservation only

---

## 13. CLI requirements

## 13.1 Command design

Recommended CLI shape:

```bash
dart-metaflac inspect file.flac
dart-metaflac tags list file.flac
dart-metaflac tags set file.flac ALBUM="Kind of Blue"
dart-metaflac tags add file.flac ARTIST="Miles Davis"
dart-metaflac tags remove file.flac COMMENT
dart-metaflac picture add file.flac --type front-cover --file cover.jpg
dart-metaflac padding set file.flac 8192
dart-metaflac blocks list file.flac
```

I would not force a literal one-to-one copy of every `metaflac` flag. That becomes unpleasant in Dart CLI UX. Better approach:

* support a **compatibility mode** or aliases for familiar `metaflac` users
* keep the native CLI organized by noun/verb subcommands

That is a better product.

## 13.2 CLI output modes

* human-readable default
* quiet mode
* JSON output for automation
* explicit exit codes

## 13.3 CLI batch behavior

* process multiple files
* continue-on-error option
* aggregated results for JSON mode
* dry-run mode

---

## 14. Compatibility requirements

The package must be compatible with:

* Dart stable SDK
* Flutter stable SDK where file access model allows
* Windows
* macOS
* Linux
* mobile and web only for in-memory APIs where filesystem semantics differ

### Notes

Full file-path mutation APIs may not be meaningful on web. The library should still support byte-based APIs for browser or sandboxed environments if feasible.

---

## 15. Performance requirements

### Memory

* Must not load full FLAC audio payload into memory for typical rewrite operations.
* Metadata-only operations should scale with metadata size, not file size.

### Speed

* Reading metadata from typical files should feel immediate.
* Rewrites should stream efficiently using buffered IO.

### Acceptance criteria

* A large FLAC file can be updated with bounded memory usage.
* Benchmarks should be included for small, medium, and large files.

---

## 16. Reliability and integrity requirements

This package manipulates binary media files. Reliability is a product feature.

### Requirements

* strict validation on parse
* deterministic serialization
* preserve unknown block bytes when possible
* atomic write path by default
* configurable backup behavior
* corruption detection for malformed metadata lengths and block order violations
* detailed exceptions with recoverable categories

### Nice-to-have

* optional backup copy on write
* validation command in CLI

---

## 17. Error handling requirements

Errors must be actionable.

### Error categories

* invalid FLAC stream
* malformed metadata block
* unsupported operation
* illegal block state
* duplicate-conflict or policy violation
* file permission / IO failure
* atomic replace failure
* incompatible write mode

### Requirements

* library throws typed exceptions
* CLI maps exceptions to readable messages and exit codes
* JSON output contains structured error details

---

## 18. Security and safety considerations

Although this is not a security product, it parses untrusted binary input.

### Requirements

* guard against oversized length values
* avoid unchecked allocations
* validate metadata lengths before parsing payloads
* reject malformed structures safely
* no hidden shell execution
* no temp-file path vulnerabilities in default implementation

---

## 19. Developer experience requirements

### Documentation

* getting started guide
* migration guide for `metaflac` users
* Flutter usage examples
* in-memory byte API examples
* block model reference
* examples for:

  * set album/artist
  * append multi-valued tags
  * embed album art
  * batch CLI update
  * preserve unknown blocks

### Testing

* golden tests against real FLAC fixtures
* rewrite tests
* corruption-resistance tests
* CLI integration tests
* round-trip tests
* fuzz-ish malformed input tests

---

## 20. Detailed feature list by priority

## Must have

* parse FLAC metadata blocks
* read/write Vorbis comment block
* read/write/remove picture blocks
* padding management
* safe rewrite engine
* preserve audio frames
* library-first API
* CLI with common metadata operations
* typed exceptions
* test fixtures and round-trip validation

## Should have

* unknown block preservation
* JSON CLI output
* dry-run mode
* batch operations
* import/export tag files
* configurable write modes

## Could have

* compatibility aliases for `metaflac` flags
* backup-on-write option
* validation/report command
* stream-based input/output abstractions
* canonical tag ordering option

## Won’t have in v1

* Ogg Vorbis container editing
* transcoding
* audio decode APIs
* waveform or analysis tooling

---

## 21. User stories

### As a CLI user

I want to set album tags on many FLAC files without installing native binaries.

### As a Flutter developer

I want to embed album art into FLAC metadata from within my app using pure Dart.

### As a backend developer

I want to update Vorbis comments safely in a server job without risking file corruption.

### As a library consumer

I want typed metadata block objects instead of parsing shell output.

### As a migration user

I want familiar `metaflac` concepts so I can move existing workflows easily.

---

## 22. Example use cases

## 22.1 Standalone CLI usage

A user runs:

```bash
dart-metaflac tags set music.flac TITLE="Blue in Green"
dart-metaflac tags add music.flac ARTIST="Miles Davis"
dart-metaflac picture add music.flac --type front-cover --file cover.jpg
```

## 22.2 Embedded library usage in Dart backend

A service receives uploaded FLAC files and standardizes metadata before storing them.

## 22.3 Flutter media manager app

A user edits album metadata and art inside a mobile app with no native plugin dependency.

## 22.4 Batch asset cleanup

A script removes junk tags, sets canonical tags, and adds padding for future updates.

---

## 23. Product architecture requirements

## 23.1 Layering

### Layer 1: Binary codec layer

* FLAC header and metadata block parsing/serialization
* no CLI concerns
* minimal policy

### Layer 2: Metadata domain layer

* block models
* validation
* mutation rules
* logical tag operations

### Layer 3: Rewrite engine

* in-place edits where safe
* streaming rewrite
* atomic replacement

### Layer 4: Public API layer

* ergonomic read/edit/write methods
* options
* exception surface

### Layer 5: CLI layer

* argument parsing
* output formatting
* command aliases

This layering is non-negotiable if the package is meant to be reusable.

---

## 24. Design constraints

* pure Dart only
* minimal external dependencies
* deterministic serialization
* cross-platform filesystem behavior accounted for
* no assumption that file rename is always perfectly atomic across every environment
* no full-file memory buffering for normal operations

---

## 25. API design opinions

A few choices are worth stating clearly.

### 1. Do not mirror `metaflac` too literally in the library

That would produce a clumsy API. The library should feel like Dart, not like command flags glued onto methods.

### 2. Use a document/editor pattern

Binary formats with rewrite semantics benefit from:

* immutable read model
* controlled mutation object
* explicit write phase

That avoids subtle state bugs.

### 3. Preserve raw blocks where possible

Users will absolutely encounter files with metadata blocks your library does not fully understand. Destroying them is unacceptable.

### 4. Separate exact-byte preservation from logical preservation

Some rewrites will preserve exact bytes for untouched blocks. Some will preserve only logical content. The docs should be honest about that.

---

## 26. Acceptance criteria

The product is ready for v1 when all of the following are true:

1. A developer can read and update Vorbis comments in FLAC files using only Dart.
2. A developer can add, replace, and remove PICTURE blocks.
3. The library preserves unknown metadata blocks unless explicitly removed.
4. Large file rewrites are streamed with bounded memory use.
5. CLI supports common `metaflac`-style metadata tasks.
6. Rewritten files validate in external FLAC tooling.
7. Flutter consumers can use the library APIs without native dependencies.
8. Test coverage includes malformed input and real-world fixture files.

---

## 27. Example CLI compatibility mapping

`dart-metaflac` should document a mapping such as:

* `metaflac --show-tags file.flac`
  -> `dart-metaflac tags list file.flac`

* `metaflac --remove-tag=COMMENT file.flac`
  -> `dart-metaflac tags remove file.flac COMMENT`

* `metaflac --set-tag=ALBUM=Foo file.flac`
  -> `dart-metaflac tags set file.flac ALBUM=Foo`

* `metaflac --import-picture-from=cover.jpg file.flac`
  -> `dart-metaflac picture add file.flac --file cover.jpg`

This matters for adoption.

---

## 28. Release plan

## Milestone 1: Core parsing

* FLAC header parsing
* metadata block parsing
* typed block models
* fixture-based tests

## Milestone 2: Vorbis comments

* CRUD operations
* serialization
* rewrite path
* CLI tags commands

## Milestone 3: Pictures and padding

* PICTURE support
* PADDING support
* additional rewrite tests

## Milestone 4: Block parity and hardening

* APPLICATION/SEEKTABLE/CUESHEET block support as needed
* safe atomic writes
* performance tests
* malformed input tests

## Milestone 5: CLI polish and docs

* JSON mode
* help and examples
* migration guide from `metaflac`
* pub.dev ready release

---

## 29. Risks

### Spec complexity risk

FLAC metadata is simpler than full container editing, but binary rewrite correctness is still easy to get wrong.

### Cross-platform file semantics risk

Atomic replace behavior varies. The write strategy must be carefully documented and tested.

### False parity risk

Claiming “full parity” with `metaflac` too early is dangerous. Better wording is:

* parity for core metadata writing/update operations in v1
* expanding parity across less common flags over time

### Unknown block handling risk

If raw preservation is weak, users will lose metadata. This needs strong tests.

---

## 30. Open questions

These should be resolved before implementation starts:

1. Will v1 claim full `metaflac` parity, or “core metadata parity”?
2. Should the CLI default to the new noun/verb syntax with a compatibility alias mode?
3. Should the library preserve original Vorbis comment order by default?
4. What minimum Dart SDK version will be targeted?
5. Should web support be explicit for byte-array APIs in v1, or deferred?

My recommendation: do **not** claim full literal parity in the first public release. Claim parity for the metadata authoring operations that matter, then extend.

---

## 31. Proposed positioning

### One-line positioning

`dart-metaflac` is a pure Dart FLAC metadata editing toolkit with a reusable library API and a `metaflac`-style CLI.

### Value proposition

* no native binaries
* safe metadata updates
* Flutter-friendly
* scriptable CLI
* library-quality API

---

## 32. Final requirement summary

`dart-metaflac` must be delivered as a **library-centered, pure Dart FLAC metadata editing package** that supports **Vorbis comment writing/updating**, **picture and padding management**, and **safe metadata rewrites**, while also providing a **standalone CLI** familiar to `metaflac` users.

The core implementation must be reusable inside other Dart and Flutter projects without modification, and the CLI must be built on top of that same core.

That is the right product boundary, and it keeps the project from becoming a thin shell wrapper pretending to be a library.
