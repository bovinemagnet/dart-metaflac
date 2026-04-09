# Engineering PRD

## dart-metaflac

**Pure Dart FLAC metadata editing library and CLI**

---

## 1. Document control

**Product name:** `dart-metaflac`
**Document type:** Engineering Product Requirements Document
**Version:** 1.0 draft
**Status:** Proposed
**Primary stakeholders:** Package maintainer, library consumers, CLI users, Flutter developers, backend developers
**Intended release:** v1 public release on pub.dev

---

## 2. Executive summary

`dart-metaflac` is a pure Dart package for reading, writing, and updating FLAC metadata, with a particular focus on Vorbis comments and parity with the practical metadata editing features of the `metaflac` tool. It will be delivered as:

1. a **reusable library** for Dart and Flutter projects
2. a **standalone CLI** built on top of the same core APIs

The product must not depend on native binaries, FFI, or platform-specific plugins. It must be safe for production use, preserve audio frames, and support deterministic metadata rewriting strategies.

The design is explicitly **library-first**. The CLI exists as a consumer of the core package, not as the center of the architecture.

---

## 3. Background and problem

Developers working in Dart and Flutter currently lack a robust, pure Dart solution for FLAC metadata editing. Existing approaches typically involve one or more of the following problems:

* invoking `metaflac` as an external process
* shipping native binaries
* using platform channels in Flutter
* relying on incomplete or unsafe tag editing libraries
* implementing ad hoc binary rewriting logic

This creates portability, deployment, and reliability problems.

There is a clear need for a package that can:

* read FLAC metadata in pure Dart
* edit Vorbis comments and related metadata blocks
* support reusable library integration
* expose a familiar CLI for scripting and automation
* preserve file integrity during updates

---

## 4. Product vision

Deliver the standard FLAC metadata editing package for the Dart ecosystem, suitable for:

* Flutter apps
* Dart command-line tools
* backend asset pipelines
* library reuse by higher-level media tooling

It should feel native to Dart while still being recognizable to users familiar with `metaflac`.

---

## 5. Product objectives

### Primary objectives

* Build a pure Dart implementation for FLAC metadata parsing and writing.
* Support practical parity with core `metaflac` metadata editing workflows.
* Offer a clean, typed public library API.
* Offer a CLI suitable for automation and migration from `metaflac`.
* Preserve file safety and audio integrity during metadata updates.

### Secondary objectives

* Support large-file processing with bounded memory usage.
* Provide reliable batch operation support.
* Expose good diagnostics and error handling.
* Remain Flutter-compatible.

---

## 6. Success metrics

The product will be considered successful when:

* Developers can perform common `metaflac` metadata operations using `dart-metaflac`.
* Developers can embed the package in Dart or Flutter without native code.
* Real-world FLAC files can be updated without audio corruption.
* The package has a stable and documented public API.
* Round-trip compatibility tests pass across a representative FLAC fixture set.
* The CLI is usable in shell automation and CI pipelines.

### Target success indicators

* 95%+ pass rate on supported `metaflac` parity fixture tests
* bounded memory usage during large-file rewrite tests
* all v1 acceptance criteria satisfied
* public pub.dev package published with examples and API docs

---

## 7. Scope

## 7.1 In scope for v1

### Core FLAC metadata support

* FLAC stream detection
* metadata block parsing
* metadata block serialization
* metadata block rewriting
* unknown block preservation where possible

### Supported metadata blocks

* `STREAMINFO` read support
* `VORBIS_COMMENT` read/write/update/remove
* `PICTURE` read/write/update/remove
* `PADDING` read/write/update/remove
* `APPLICATION` read/write/remove where valid
* `SEEKTABLE` read support and preserved rewrite behavior
* `CUESHEET` read support and preserved rewrite behavior

### Library capabilities

* read metadata from file path
* read metadata from bytes or stream-like input where practical
* mutate metadata with typed APIs
* write back to original file or new destination
* configurable write modes
* structured exceptions

### CLI capabilities

* inspect metadata
* list tags
* set/add/remove tags
* remove all tags
* add/remove/replace pictures
* manage padding
* list blocks
* process multiple files
* dry-run mode
* JSON output mode

## 7.2 Out of scope for v1

* Ogg container editing
* Ogg Vorbis authoring
* audio encoding or decoding
* playback APIs
* metadata lookup from online services
* waveform analysis
* tag editing for non-FLAC container formats
* full byte-for-byte emulation of every `metaflac` flag

---

## 8. Non-goals

The following are explicitly not goals of v1:

* becoming a general media framework
* supporting every historical corner case of `metaflac`
* supporting malformed file writing
* providing GUI features
* shipping platform-native helper binaries

---

## 9. Users and personas

### Persona 1: Flutter app developer

Needs to update album art and tags in-app using pure Dart.

### Persona 2: Backend developer

Needs to normalize metadata safely in ingestion or archival pipelines.

### Persona 3: CLI automation user

Needs a scriptable replacement for common `metaflac` usage.

### Persona 4: Package maintainer

Needs stable, typed APIs to build higher-level tools on top of `dart-metaflac`.

---

## 10. Key user stories

* As a developer, I want to read FLAC metadata without shelling out to system tools.
* As a Flutter developer, I want to add cover art and tags using pure Dart.
* As a CLI user, I want familiar commands for inspecting and editing FLAC metadata.
* As a backend developer, I want atomic file update behavior to reduce corruption risk.
* As a library consumer, I want high-level typed APIs rather than parsing raw CLI output.
* As a migration user, I want a clear mapping from `metaflac` workflows to `dart-metaflac`.

---

## 11. Functional requirements

## 11.1 FLAC file identification and parsing

### Requirements

* Detect valid FLAC file headers.
* Parse FLAC metadata blocks in sequence.
* Expose block metadata:

  * type
  * length
  * last-block flag
  * raw bytes
  * typed parsed representation where supported
* Preserve metadata block ordering unless a write operation requires reordering for validity.
* Preserve unknown block payloads where possible.

### Acceptance criteria

* Valid FLAC files are parsed correctly.
* Invalid FLAC files fail with typed exceptions.
* Unknown blocks survive a read/write cycle unless explicitly removed or impossible to preserve due to invalidity.

---

## 11.2 Vorbis comment support

### Requirements

* Read vendor string.
* Read all Vorbis comment fields.
* Support multiple values for the same key.
* Support case-insensitive key matching consistent with Vorbis comment semantics.
* Add a field without replacing existing values.
* Set a field by replacing all existing values for the key.
* Remove all values for a key.
* Remove a specific key/value pair.
* Remove all Vorbis comments.
* Create a Vorbis comment block when missing.
* Serialize comments correctly.

### Acceptance criteria

* Files without comments can be given a new Vorbis comment block.
* Multi-value fields are preserved.
* Logical round-tripping of tags succeeds.
* All common tag update operations are available from both library and CLI.

---

## 11.3 Picture block support

### Requirements

* Read all picture blocks.
* Add picture blocks from file or bytes.
* Replace picture blocks by index or type.
* Remove picture blocks by index, type, or all.
* Expose structured metadata:

  * picture type
  * MIME type
  * description
  * width
  * height
  * color depth
  * indexed colors
  * payload length

### Acceptance criteria

* Common JPEG and PNG cover art workflows succeed.
* Multiple picture blocks are supported.
* Extracted image bytes match original embedded bytes.

---

## 11.4 Padding support

### Requirements

* Read existing padding size and layout.
* Add padding blocks.
* Replace padding with a target size.
* Remove padding blocks.
* Allow rewrite policy to consume existing padding where possible.

### Acceptance criteria

* User can control padding size through library and CLI.
* Rewrites can use padding to avoid full metadata restructuring when feasible.

---

## 11.5 Additional metadata block support

### Requirements

* Read and preserve `APPLICATION`, `SEEKTABLE`, and `CUESHEET` blocks.
* Support `APPLICATION` add/remove where safe.
* Preserve unsupported or not-fully-modeled blocks as raw data where possible.
* Enforce FLAC structural validity.

### Acceptance criteria

* Known supported blocks can be read and rewritten.
* Unsupported but valid blocks are preserved.
* Files remain valid in external FLAC tooling after updates.

---

## 11.6 Rewrite and persistence engine

### Requirements

* Support safe file rewrite strategies.
* Avoid loading full audio payloads into memory.
* Support streaming copy of audio frames.
* Support write modes:

  * `safeAtomic`
  * `auto`
  * `inPlaceIfPossible`
  * `outputToNewFile`
* Fail safely when an operation cannot be completed under the chosen mode.
* Make default behavior safety-oriented.

### Acceptance criteria

* Large files can be updated with bounded memory use.
* Audio frames are preserved unchanged.
* Update failure does not silently corrupt the original file.
* Atomic replacement strategy is used by default where environment permits.

---

## 11.7 CLI support

### Requirements

* Provide commands for:

  * inspect
  * list blocks
  * list tags
  * set tag
  * add tag
  * remove tag
  * clear tags
  * add picture
  * replace picture
  * remove picture
  * set/remove padding
* Support multiple input files.
* Support JSON output.
* Support dry-run.
* Support non-zero exit codes for failures.

### Acceptance criteria

* Common metadata editing workflows can be performed from CLI.
* JSON output is stable enough for automation.
* Help output includes examples and migration hints from `metaflac`.

---

## 11.8 Library usability

### Requirements

* Expose high-level APIs for common tasks.
* Expose lower-level block manipulation APIs for advanced users.
* Avoid a purely flag-based design.
* Support async file APIs.
* Support in-memory APIs for environments without full file access.
* Keep APIs documented and discoverable.

### Acceptance criteria

* Common operations require minimal boilerplate.
* Library APIs are clearly more ergonomic than invoking the CLI programmatically.

---

## 12. Quality attributes

## 12.1 Reliability

* deterministic read/write behavior
* strong parse validation
* predictable exception handling
* unknown block preservation where feasible

## 12.2 Performance

* metadata parsing proportional to metadata size
* rewrite memory usage not proportional to full file size
* efficient buffered IO

## 12.3 Portability

* pure Dart
* compatible with Dart stable
* usable in Flutter
* no platform-native dependency requirement

## 12.4 Maintainability

* layered architecture
* testable binary codec
* CLI isolated from core business logic
* typed models and clear boundaries

## 12.5 Safety

* safe defaults
* bounded allocation behavior
* careful length validation
* no shell execution

---

## 13. Constraints

* Must be implemented in pure Dart.
* Must not depend on external binaries.
* Must avoid FFI as a requirement.
* Must support Flutter-compatible usage patterns.
* Must preserve audio payload during metadata rewrites.
* Must be usable as both library and CLI.

---

## 14. Assumptions

* v1 focuses on FLAC metadata, not general container support.
* “Parity with `metaflac`” refers primarily to practical metadata read/write/update workflows.
* Full literal flag parity is not required for initial release.
* Most library consumers care about logical metadata parity more than exact textual CLI parity.

---

## 15. Dependencies

### Internal dependencies

* Dart SDK stable
* package argument parser for CLI
* minimal IO and testing libraries

### External dependencies

* none requiring native integration

### Repository dependencies

Recommended mono-repo structure:

* `packages/dart_metaflac`
* `packages/dart_metaflac_cli`

---

## 16. Architecture requirements

## 16.1 High-level architecture

### Layer 1: Binary codec

Responsible for:

* parsing FLAC metadata structures
* serializing blocks
* validating binary lengths and layout

### Layer 2: Domain model

Responsible for:

* typed block representations
* validation rules
* logical metadata semantics

### Layer 3: Editing engine

Responsible for:

* mutation operations
* block replacement logic
* preservation policy
* ordering and normalization

### Layer 4: Persistence engine

Responsible for:

* in-place updates when safe
* full rewrites when necessary
* atomic replacement behavior
* stream-based copy

### Layer 5: Public API

Responsible for:

* ergonomic read/edit/write interface
* options and exceptions

### Layer 6: CLI

Responsible for:

* command parsing
* output formatting
* compatibility aliases
* automation-oriented UX

---

## 16.2 Architectural rules

* CLI must not contain unique business logic.
* Mutation logic must live in library core.
* Binary parsing must be separately testable.
* Low-level parsing types should not leak unnecessarily into simple user workflows.
* Unknown block preservation should happen below the CLI layer.

---

## 17. Proposed public API

## 17.1 Core types

```dart id="y89d2a"
class FlacMetadataDocument {}
class FlacMetadataEditor {}
class FlacMetadataBlock {}
class StreamInfoBlock extends FlacMetadataBlock {}
class VorbisCommentBlock extends FlacMetadataBlock {}
class PictureBlock extends FlacMetadataBlock {}
class PaddingBlock extends FlacMetadataBlock {}
class ApplicationBlock extends FlacMetadataBlock {}
class SeekTableBlock extends FlacMetadataBlock {}
class CueSheetBlock extends FlacMetadataBlock {}
```

## 17.2 Options and support types

```dart id="smey7l"
enum WriteMode {
  safeAtomic,
  auto,
  inPlaceIfPossible,
  outputToNewFile,
}
```

```dart id="chze1k"
class FlacReadOptions {}
class FlacWriteOptions {}
class PictureSpec {}
class TagEntry {}
```

## 17.3 Exceptions

```dart id="65hq0d"
class FlacMetadataException implements Exception {}
class InvalidFlacException extends FlacMetadataException {}
class MalformedMetadataException extends FlacMetadataException {}
class UnsupportedBlockException extends FlacMetadataException {}
class WriteConflictException extends FlacMetadataException {}
class FlacIoException extends FlacMetadataException {}
```

## 17.4 Example high-level API

```dart id="t5r0jf"
final doc = await FlacMetadataDocument.readFromFile('song.flac');

final updated = doc.edit((e) => e
  ..setTag('TITLE', ['Blue in Green'])
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
  'song.flac',
  options: FlacWriteOptions(mode: WriteMode.safeAtomic),
);
```

## 17.5 API design guidance

* Prefer immutable read models.
* Use an editor or builder pattern for mutation.
* Make `set` and `add` clearly different.
* Avoid leaking raw binary details into common workflows.
* Provide access to raw blocks for advanced callers.

---

## 18. CLI requirements and UX

## 18.1 Proposed command structure

```bash id="12x8yl"
dart-metaflac inspect file.flac
dart-metaflac blocks list file.flac
dart-metaflac tags list file.flac
dart-metaflac tags set file.flac ALBUM="Kind of Blue"
dart-metaflac tags add file.flac ARTIST="Miles Davis"
dart-metaflac tags remove file.flac COMMENT
dart-metaflac tags clear file.flac
dart-metaflac picture add file.flac --type front-cover --file cover.jpg
dart-metaflac picture remove file.flac --type front-cover
dart-metaflac padding set file.flac 8192
```

## 18.2 CLI design opinion

I would strongly keep the user-facing CLI organized by noun/verb subcommands instead of cloning `metaflac`’s older flag-heavy interface exactly. That will age better.

Still, the CLI should support:

* helpful aliases
* migration examples
* optional compatibility shortcuts where reasonable

## 18.3 Output requirements

### Human-readable

Default for interactive use.

### JSON

Stable machine-readable shape for:

* metadata listing
* operation results
* batch outcomes
* errors

### Exit codes

* `0` success
* non-zero for validation, IO, parse, or operation failures

---

## 19. Compatibility and parity definition

## 19.1 Parity statement

For v1, “parity with `metaflac`” means parity for **core FLAC metadata writing and updating use cases**, especially:

* Vorbis comments
* pictures
* padding
* metadata inspection
* block listing and selective block removal where supported

It does **not** mean perfect one-to-one implementation of all historical `metaflac` options in the first release.

## 19.2 Compatibility mapping examples

| `metaflac` workflow | `dart-metaflac` equivalent                             |
| ------------------- | ------------------------------------------------------ |
| show tags           | `dart-metaflac tags list file.flac`                    |
| set tag             | `dart-metaflac tags set file.flac KEY=VALUE`           |
| remove tag          | `dart-metaflac tags remove file.flac KEY`              |
| remove all tags     | `dart-metaflac tags clear file.flac`                   |
| import picture      | `dart-metaflac picture add file.flac --file cover.jpg` |
| show blocks         | `dart-metaflac blocks list file.flac`                  |

---

## 20. Detailed acceptance criteria

The v1 release is acceptable only if all of the following are true:

1. Valid FLAC files can be parsed and metadata blocks enumerated.
2. Vorbis comments can be read, added, replaced, removed, and cleared.
3. Picture blocks can be added, replaced, listed, and removed.
4. Padding can be inspected and configured.
5. Unknown valid metadata blocks are preserved where possible.
6. Rewrites preserve audio payload and keep files valid in external tools.
7. CLI supports common inspection and mutation workflows.
8. Library APIs are usable directly in Dart and Flutter apps.
9. Large file rewrite tests demonstrate bounded memory use.
10. Error handling is typed and documented.

---

## 21. Test strategy

## 21.1 Test categories

### Unit tests

* header parsing
* metadata block parsing
* block serialization
* Vorbis comment logic
* picture serialization
* padding behavior
* exception mapping

### Integration tests

* read/edit/write file workflows
* safe rewrite behavior
* CLI commands
* JSON output
* batch processing

### Compatibility tests

* compare behavior against known-good FLAC fixtures
* compare supported operations against `metaflac` expectations
* validate output files with external FLAC tooling in CI if available

### Negative tests

* malformed block length
* invalid header
* truncated file
* invalid block order
* oversized declared payloads
* unsupported write mode conditions

### Property or fuzz-style tests

* random malformed metadata payloads
* random tag sets
* repeated read/write round-trips

---

## 21.2 Test matrix

| Area            | Scenario                                        | Expected result                            |
| --------------- | ----------------------------------------------- | ------------------------------------------ |
| Parse           | valid FLAC with minimal metadata                | document loads successfully                |
| Parse           | invalid FLAC magic                              | `InvalidFlacException`                     |
| Parse           | unknown valid block type                        | raw block preserved                        |
| Vorbis comments | set single tag                                  | tag replaced correctly                     |
| Vorbis comments | add duplicate key                               | multiple values preserved                  |
| Vorbis comments | remove exact key                                | all matching values removed                |
| Vorbis comments | create block when missing                       | valid block created                        |
| Picture         | add JPEG cover                                  | picture block present and readable         |
| Picture         | replace front cover                             | previous front cover replaced as requested |
| Picture         | remove all pictures                             | no picture blocks remain                   |
| Padding         | set padding size                                | correct padding block written              |
| Rewrite         | metadata grows beyond padding                   | full rewrite succeeds                      |
| Rewrite         | safe atomic write                               | original preserved on failure path         |
| Rewrite         | in-place impossible                             | fails or falls back according to mode      |
| CLI             | tags list                                       | human-readable tag list shown              |
| CLI             | JSON inspect                                    | valid JSON returned                        |
| CLI             | batch processing mixed success                  | result summary includes per-file outcome   |
| Compatibility   | file opened by external FLAC tools after update | validation passes                          |
| Large file      | large audio payload rewrite                     | bounded memory use                         |

---

## 22. Performance requirements

### Functional performance expectations

* metadata parsing should complete without scanning entire audio payload when not needed
* common tag read operations should be fast
* rewrite operations should stream content

### Technical expectations

* no full-file memory buffering in standard rewrite flow
* large-file update memory use should be bounded primarily by metadata size and IO buffers
* buffered IO should be configurable internally if needed

### Benchmark targets

Targets can be refined during implementation, but at minimum:

* metadata-only read on typical files should feel immediate
* large-file rewrite should avoid memory spikes
* repeated batch edits should scale linearly with file count

---

## 23. Security and robustness requirements

* validate all metadata lengths before allocation
* reject malformed or truncated structures safely
* defend against oversized payload claims
* avoid temp file naming vulnerabilities
* avoid shelling out
* never silently ignore file write failures
* document what is preserved versus normalized during rewrite

---

## 24. Documentation requirements

The package must ship with:

* README with positioning and quick start
* library usage guide
* Flutter usage guide
* CLI usage guide
* migration guide from `metaflac`
* block support matrix
* examples for:

  * reading tags
  * setting tags
  * adding album art
  * batch CLI updates
  * safe write modes
  * in-memory usage

---

## 25. Packaging and repository layout

Recommended repository layout:

```text id="wyu0vf"
repo/
  packages/
    dart_metaflac/
      lib/
      test/
      example/
    dart_metaflac_cli/
      bin/
      lib/
      test/
  fixtures/
  docs/
```

### Packaging requirements

* core package must be independently publishable
* CLI may be a sibling package depending on core
* fixtures should include representative FLAC files with varied metadata

---

## 26. Milestones and delivery plan

## Milestone 1: Core binary parsing

**Goal:** parse FLAC header and metadata blocks reliably

### Deliverables

* FLAC header detection
* metadata block parser
* typed block base model
* raw unknown block handling
* initial fixture set
* unit tests for parser

### Exit criteria

* valid sample files parse correctly
* malformed files fail predictably

---

## Milestone 2: Vorbis comment editing

**Goal:** support the most important metadata workflow first

### Deliverables

* Vorbis comment typed model
* read/add/set/remove/clear operations
* serialization
* document editor pattern
* initial write-back support
* CLI `tags` commands

### Exit criteria

* supported tag operations succeed in round-trip tests
* files remain valid after comment edits

---

## Milestone 3: Picture and padding support

**Goal:** cover common real-world album management use cases

### Deliverables

* picture block parsing and writing
* add/replace/remove picture operations
* padding inspection and writing
* more rewrite logic
* CLI `picture` and `padding` commands

### Exit criteria

* embedded images survive round-trip
* padding policies function correctly

---

## Milestone 4: Rewrite hardening and block preservation

**Goal:** make the package production-safe

### Deliverables

* safe atomic rewrite engine
* stream-based copy
* write mode support
* unknown block preservation
* integration tests for large files
* structured error types

### Exit criteria

* large-file rewrite tests pass
* failure modes are documented and tested

---

## Milestone 5: CLI polish, docs, and release readiness

**Goal:** publish a stable v1

### Deliverables

* inspect/blocks CLI commands
* JSON output
* dry-run mode
* batch processing
* migration documentation
* examples
* pub.dev release prep

### Exit criteria

* documentation complete
* CLI usable for common automation
* v1 acceptance criteria met

---

## 27. Backlog structure

Suggested epics:

1. **Binary codec and parsing**
2. **Vorbis comment domain model**
3. **Picture and padding support**
4. **Rewrite and persistence engine**
5. **CLI surface**
6. **Quality, testing, and release**

---

## 28. Jira-ready backlog items

Below is a starter backlog with epics and stories.

---

# Epic 1: Binary codec and parsing

### DMF-1 — Parse FLAC stream header

**Type:** Story
**Description:** Implement detection and validation of FLAC file header.
**Acceptance criteria:**

* valid FLAC magic recognized
* invalid header rejected with typed exception
* unit tests added

### DMF-2 — Parse metadata block headers

**Type:** Story
**Description:** Parse metadata block type, last flag, and payload length.
**Acceptance criteria:**

* block header parsed correctly
* invalid or truncated header fails predictably
* tests cover edge lengths

### DMF-3 — Parse metadata block sequence

**Type:** Story
**Description:** Read all metadata blocks until last-block flag.
**Acceptance criteria:**

* blocks returned in file order
* parser stops at correct boundary
* tests include multi-block fixtures

### DMF-4 — Preserve unknown metadata blocks as raw payloads

**Type:** Story
**Description:** Support unknown but valid blocks via raw storage and rewrite preservation.
**Acceptance criteria:**

* unknown block type accessible as raw block
* raw payload preserved across read/write when untouched

### DMF-5 — Implement typed base model for metadata blocks

**Type:** Story
**Description:** Provide domain model hierarchy for supported block types.
**Acceptance criteria:**

* typed block API available
* supported block instances created during parsing

---

# Epic 2: Vorbis comment domain model

### DMF-10 — Parse Vorbis comment block

**Type:** Story
**Description:** Parse vendor string and comment entries.
**Acceptance criteria:**

* vendor string exposed
* comment list parsed correctly
* repeated keys supported

### DMF-11 — Implement case-insensitive tag key handling

**Type:** Story
**Description:** Normalize key matching while preserving stored values.
**Acceptance criteria:**

* lookups are case-insensitive
* serialization remains valid

### DMF-12 — Implement setTag operation

**Type:** Story
**Description:** Replace all values for a given tag key.
**Acceptance criteria:**

* existing values replaced
* absent key added cleanly
* tests cover single and multiple values

### DMF-13 — Implement addTag operation

**Type:** Story
**Description:** Append a new value without removing existing values.
**Acceptance criteria:**

* duplicate tag keys supported
* ordering behavior documented and tested

### DMF-14 — Implement removeTag and clearTags operations

**Type:** Story
**Description:** Remove one key or all comments.
**Acceptance criteria:**

* key removal works
* clear operation removes all comment fields
* tests added

### DMF-15 — Serialize Vorbis comment block

**Type:** Story
**Description:** Encode valid Vorbis comment block bytes from domain model.
**Acceptance criteria:**

* encoded bytes parse correctly on read-back
* sample files remain valid after update

---

# Epic 3: Picture and padding support

### DMF-20 — Parse PICTURE block

**Type:** Story
**Description:** Parse picture metadata and payload.
**Acceptance criteria:**

* type, MIME, description, dimensions, and data exposed
* JPEG and PNG fixtures tested

### DMF-21 — Add picture block from file or bytes

**Type:** Story
**Description:** Support embedding picture content.
**Acceptance criteria:**

* picture can be added through library API
* picture readable after write

### DMF-22 — Replace and remove picture blocks

**Type:** Story
**Description:** Support picture mutation by type and index.
**Acceptance criteria:**

* replace works by selected rule
* remove works by type/index/all

### DMF-23 — Parse and write PADDING block

**Type:** Story
**Description:** Support padding inspection and updates.
**Acceptance criteria:**

* padding size readable
* padding can be created, resized, or removed

---

# Epic 4: Rewrite and persistence engine

### DMF-30 — Implement metadata document editor pattern

**Type:** Story
**Description:** Provide immutable document plus mutation editor flow.
**Acceptance criteria:**

* document can be edited via callback or builder
* result is serializable

### DMF-31 — Implement outputToNewFile write mode

**Type:** Story
**Description:** Write modified FLAC to a different file path.
**Acceptance criteria:**

* original file unchanged
* output file valid after write

### DMF-32 — Implement safeAtomic write mode

**Type:** Story
**Description:** Write to temp file and replace original safely.
**Acceptance criteria:**

* replacement behavior implemented
* failure path does not silently corrupt source
* tests included

### DMF-33 — Implement inPlaceIfPossible mode

**Type:** Story
**Description:** Allow safe in-place metadata updates only when valid.
**Acceptance criteria:**

* in-place update occurs only when safe
* otherwise fails clearly

### DMF-34 — Stream audio payload during rewrite

**Type:** Story
**Description:** Rewrite metadata without loading full audio frames into memory.
**Acceptance criteria:**

* large-file rewrite uses bounded memory
* integration test added

### DMF-35 — Preserve unknown untouched blocks on rewrite

**Type:** Story
**Description:** Ensure raw unknown blocks survive update operations.
**Acceptance criteria:**

* preserved in output ordering and payload
* tested with fixture

---

# Epic 5: CLI surface

### DMF-40 — Create CLI entrypoint and argument parsing

**Type:** Story
**Description:** Build package executable with subcommand structure.
**Acceptance criteria:**

* executable runs
* help output available
* subcommand routing works

### DMF-41 — Implement `inspect` command

**Type:** Story
**Description:** Show file metadata summary and block overview.
**Acceptance criteria:**

* human-readable output works
* JSON output supported

### DMF-42 — Implement `tags` commands

**Type:** Story
**Description:** Add list, set, add, remove, and clear tag operations.
**Acceptance criteria:**

* commands call core library
* exit codes and help text added

### DMF-43 — Implement `picture` commands

**Type:** Story
**Description:** Add picture add/remove/replace/list support.
**Acceptance criteria:**

* operations function via CLI
* file fixtures validated

### DMF-44 — Implement `padding` commands

**Type:** Story
**Description:** Support padding inspection and updates.
**Acceptance criteria:**

* set/remove operations work
* help text included

### DMF-45 — Implement batch processing and dry-run

**Type:** Story
**Description:** Process multiple files with optional dry-run.
**Acceptance criteria:**

* multiple files supported
* dry-run avoids writes
* aggregate result reporting included

### DMF-46 — Implement JSON output mode

**Type:** Story
**Description:** Add stable machine-readable output for automation.
**Acceptance criteria:**

* JSON shape documented
* commands emit structured success and error payloads

---

# Epic 6: Quality, testing, and release

### DMF-50 — Build FLAC fixture library

**Type:** Story
**Description:** Assemble representative test files.
**Acceptance criteria:**

* minimal FLAC fixture
* multi-block fixture
* picture fixture
* padding fixture
* malformed fixtures

### DMF-51 — Add round-trip test suite

**Type:** Story
**Description:** Ensure parse/edit/write/read logical equivalence.
**Acceptance criteria:**

* tags round-trip correctly
* pictures round-trip correctly
* unknown blocks preserved where expected

### DMF-52 — Add malformed input and negative tests

**Type:** Story
**Description:** Harden parser against invalid files.
**Acceptance criteria:**

* malformed length tests added
* truncated file tests added
* oversized payload tests added

### DMF-53 — Write API documentation and examples

**Type:** Story
**Description:** Publish documentation for library and CLI usage.
**Acceptance criteria:**

* README complete
* examples compile
* migration guide drafted

### DMF-54 — Prepare pub.dev release

**Type:** Story
**Description:** Finalize versioning, metadata, and publish process.
**Acceptance criteria:**

* package metadata complete
* changelog created
* release checklist complete

---

## 29. Release checklist

Before v1 release:

* all must-have features complete
* all acceptance criteria satisfied
* examples compile and run
* CLI help audited
* documentation complete
* test suite green
* versioning and changelog complete
* package score acceptable for pub.dev
* fixture set included or properly referenced

---

## 30. Risks and mitigations

| Risk                                   | Impact | Mitigation                                               |
| -------------------------------------- | ------ | -------------------------------------------------------- |
| rewrite corruption bug                 | severe | default safeAtomic mode, extensive integration testing   |
| invalid preservation of unknown blocks | high   | raw block preservation model and dedicated fixtures      |
| over-promising full metaflac parity    | medium | document parity scope clearly                            |
| poor Flutter ergonomics                | medium | keep APIs pure Dart and avoid file-path-only assumptions |
| performance regression on large files  | high   | streaming rewrite design and large-file benchmarks       |

---

## 31. Open questions

These should be decided before implementation starts:

1. Should the first release say “core `metaflac` parity” instead of “full parity”?
2. Should web support be documented as byte-array-only in v1?
3. Should Vorbis comment entry order be preserved exactly by default?
4. Should the CLI include explicit compatibility aliases matching select `metaflac` flags?
5. Should APPLICATION block write support be included in v1 or deferred to v1.1?

### Recommended answers

* say **core parity** for v1
* support **byte-oriented web use** if practical, but do not over-promise filesystem behavior
* preserve Vorbis order where feasible
* add compatibility aliases only for high-value commands
* include APPLICATION write support only if it does not delay the rewrite engine

---

## 32. Final recommendation

The package should be developed as a **core FLAC metadata engine** with:

* strict binary parsing
* safe rewrite semantics
* typed domain APIs
* CLI layered on top

That architecture gives you a real library product, not a command wrapper pretending to be reusable.

The most important implementation priority is not the CLI. It is the **rewrite engine and metadata correctness**. If those are solid, everything else becomes much easier.
