# Technical Design Specification

## dart-metaflac

**Pure Dart FLAC metadata transformation library with CLI and file adapter layers**

**Document version:** 1.0
**Status:** Proposed
**Applies to:** `dart_metaflac`, `dart_metaflac_io`, `dart_metaflac_cli`

---

# 1. Purpose

This document defines the technical architecture, package structure, core abstractions, data model, transformation algorithms, persistence behavior, CLI layering, and testing strategy for `dart-metaflac`.

The system is designed to satisfy four non-negotiable constraints:

1. **Pure Dart implementation**
2. **I/O-agnostic core**
3. **Safe metadata updates**
4. **Usable both as a library and a CLI**  

---

# 2. Design goals

## 2.1 Primary goals

* Parse FLAC metadata blocks in pure Dart.
* Support read/write/update/remove of Vorbis comments.
* Support read/write/update/remove of PICTURE blocks.
* Support padding-aware transformations.
* Preserve non-targeted metadata blocks where possible.
* Expose both:

  * high-level document/editor APIs
  * low-level stream transformation APIs
* Provide file-safe persistence helpers separately from the pure core.
* Provide a CLI with modern commands and `metaflac` compatibility aliases.

## 2.2 Secondary goals

* Keep memory usage bounded for large files.
* Avoid loading audio frame payloads into memory during rewrites.
* Make library API ergonomic for Dart and Flutter developers.
* Make the CLI thin and deterministic.
* Enable Flutter Web and in-memory use by avoiding `dart:io` in the core. 

---

# 3. Non-goals

This design does not cover:

* FLAC audio decoding
* FLAC encoding/transcoding
* arbitrary Ogg container manipulation
* non-FLAC metadata formats
* playback
* waveform analysis

---

# 4. High-level architecture

The system is split into three packages.

```text
packages/
  dart_metaflac/
  dart_metaflac_io/
  dart_metaflac_cli/
```

## 4.1 `dart_metaflac`

Pure core package.

Responsibilities:

* binary parsing
* metadata domain model
* editing rules
* transform planning
* byte/stream transformation APIs

Must not import `dart:io`.

## 4.2 `dart_metaflac_io`

Filesystem and persistence adapter package.

Responsibilities:

* path-based convenience APIs
* temp file handling
* safe atomic replacement
* modtime preservation
* file-based input/output adapters

May import `dart:io`.

## 4.3 `dart_metaflac_cli`

Executable package.

Responsibilities:

* argument parsing
* compatibility alias parsing
* CLI output formatting
* batch file processing orchestration

Depends on `dart_metaflac` and `dart_metaflac_io`.

---

# 5. Architectural principles

## 5.1 Core is a transformation library, not a file editor

The core should transform FLAC metadata and produce a modified byte stream or byte sequence. It must not assume local file mutation semantics.

## 5.2 Parser, editor, and persistence are separate concerns

Parsing metadata, deciding how to modify it, and persisting it safely are different problems and should remain separated.

## 5.3 Unknown valid data should survive

If the library encounters valid metadata blocks it does not fully model, it should preserve their raw payload unless explicitly removed or invalidated by requested changes.

## 5.4 High-level and low-level APIs should coexist

The API should support both:

* easy application workflows
* advanced streaming and transformation workflows

## 5.5 CLI is an adapter

No metadata business logic should exist only in the CLI.

---

# 6. Data flow overview

There are two core usage modes.

## 6.1 High-level document mode

```text
Input bytes/stream
  -> parse metadata
  -> build FlacMetadataDocument
  -> edit via FlacMetadataEditor
  -> produce transform plan
  -> serialize new metadata
  -> emit bytes or transformed stream
```

## 6.2 Streaming transformation mode

```text
Input stream
  -> parse leading metadata region
  -> compute updated metadata region
  -> emit updated metadata
  -> stream-copy remaining audio frames
  -> output stream/sink
```

The second path is the critical one for large files and CLI usage.

---

# 7. FLAC format boundaries assumed by this design

The design assumes a FLAC stream layout conceptually like this:

```text
[ "fLaC" marker ]
[ metadata block 1 ]
[ metadata block 2 ]
...
[ metadata block N with isLast = true ]
[ audio frames ... ]
```

The core library is responsible only for:

* recognizing the marker
* parsing the metadata region
* identifying where audio frames begin
* rewriting the metadata region correctly
* preserving the audio payload unchanged

It is not responsible for decoding audio frames.

---

# 8. Package-level module structure

## 8.1 `dart_metaflac/lib/src/`

Suggested modules:

```text
src/
  binary/
    byte_reader.dart
    byte_writer.dart
    flac_constants.dart
    flac_block_header.dart
    flac_parser.dart
    flac_serializer.dart
  model/
    flac_metadata_document.dart
    flac_metadata_block.dart
    stream_info_block.dart
    vorbis_comment_block.dart
    vorbis_comments.dart
    picture_block.dart
    padding_block.dart
    application_block.dart
    seek_table_block.dart
    cue_sheet_block.dart
    unknown_block.dart
  edit/
    flac_metadata_editor.dart
    mutation_ops.dart
    block_rewriter.dart
    padding_strategy.dart
    normalization.dart
  transform/
    flac_transformer.dart
    flac_transform_plan.dart
    flac_transform_result.dart
    stream_rewriter.dart
  api/
    read_api.dart
    document_api.dart
    transform_api.dart
  error/
    exceptions.dart
  util/
    utf8_codec_helpers.dart
    validators.dart
```

## 8.2 `dart_metaflac_io/lib/src/`

```text
src/
  file_api.dart
  atomic_writer.dart
  temp_file_manager.dart
  file_metadata.dart
  io_adapters.dart
```

## 8.3 `dart_metaflac_cli/lib/src/`

```text
src/
  command_runner.dart
  commands/
    inspect_command.dart
    blocks_command.dart
    tags_command.dart
    picture_command.dart
    padding_command.dart
  compat/
    metaflac_alias_parser.dart
  output/
    human_output.dart
    json_output.dart
    exit_codes.dart
```

---

# 9. Core abstractions

## 9.1 Source and sink abstractions

The core must support multiple input styles. Rather than inventing a fully generic I/O framework, keep the public API simple and accept common Dart primitives.

Recommended public inputs:

* `Uint8List`
* `Stream<List<int>>`

Recommended public outputs:

* `Uint8List`
* `Stream<List<int>>`
* writer callback or sink adapter for advanced cases

Public API should not expose internal byte reader mechanics.

---

# 10. Public API design

## 10.1 High-level document API

This API is intended for app developers and tests.

```dart
final doc = await FlacMetadataDocument.readFromBytes(bytes);

final updated = doc.edit((e) => e
  ..setTag('ARTIST', ['New Artist'])
  ..setTag('ALBUM', ['Example Album'])
  ..replaceFrontCoverBytes(
    mimeType: 'image/jpeg',
    data: coverBytes,
    description: 'Front cover',
  )
  ..setPadding(8192),
);

final outBytes = await updated.toBytes();
```

### Characteristics

* easy to read
* immutable document + mutable editor flow
* good for memory-resident use cases
* suitable for Flutter UI code

## 10.2 Streaming transformer API

This API is intended for large files, services, CLI, and file adapter layers.

```dart
final transformer = FlacTransformer.fromStream(inputStream);

final metadata = await transformer.readMetadata();

final outputStream = await transformer.transform(
  mutations: [
    SetTag('ARTIST', ['New Artist']),
    RemoveTag('COMMENT'),
    ReplaceFrontCover(
      mimeType: 'image/png',
      data: coverBytes,
      description: 'Front cover',
    ),
  ],
);
```

### Characteristics

* parses only metadata region first
* emits transformed output stream
* does not require full file buffering

## 10.3 Path/file helpers

These belong in `dart_metaflac_io`, not the core.

```dart
await FlacFileEditor.updateFile(
  'song.flac',
  mutations: [
    SetTag('TITLE', ['Blue in Green']),
  ],
  options: FlacWriteOptions.safeAtomic(),
);
```

---

# 11. Domain model

## 11.1 Base metadata block

```dart
abstract class FlacMetadataBlock {
  FlacBlockType get type;
  int get length;
  bool get isLast;
  Uint8List toPayloadBytes();
}
```

### Notes

* `length` is derived from serialized payload size, not stored as mutable state
* `isLast` is applied during whole-document serialization, not trusted per block instance during editing

I would avoid making `isLast` a user-settable field on individual block objects. It is a property of the serialized sequence, not the logical block content.

## 11.2 Block type enum

```dart
enum FlacBlockType {
  streamInfo,
  padding,
  application,
  seekTable,
  vorbisComment,
  cueSheet,
  picture,
  unknown,
}
```

For unknown blocks, keep the original numeric code too.

```dart
final class UnknownBlock extends FlacMetadataBlock {
  final int rawTypeCode;
  final Uint8List rawPayload;
}
```

## 11.3 `FlacMetadataDocument`

```dart
final class FlacMetadataDocument {
  final Uint8List marker; // logically always fLaC
  final List<FlacMetadataBlock> blocks;
  final int audioDataOffset;

  VorbisCommentBlock? get vorbisComment;
  List<PictureBlock> get pictures;
  StreamInfoBlock get streamInfo;

  FlacMetadataDocument edit(void Function(FlacMetadataEditor e) updates);
}
```

### Design note

The document model should be logically immutable.

## 11.4 Vorbis comments model

Avoid using only `Map<String, List<String>>` as the canonical representation.

Preferred design:

```dart
final class VorbisComments {
  final String vendorString;
  final List<VorbisCommentEntry> entries;

  List<String> valuesOf(String key);
  VorbisComments set(String key, List<String> values);
  VorbisComments add(String key, String value);
  VorbisComments removeKey(String key);
  VorbisComments removeExact(String key, String value);
  Map<String, List<String>> asMultiMap();
}
```

```dart
final class VorbisCommentEntry {
  final String key;
  final String value;
}
```

### Why this is better

It preserves:

* repeated keys
* insertion order
* exact value-level operations
* easier future normalization policies

## 11.5 Picture block model

```dart
final class PictureBlock extends FlacMetadataBlock {
  final PictureType pictureType;
  final String mimeType;
  final String description;
  final int width;
  final int height;
  final int colorDepth;
  final int indexedColors;
  final Uint8List data;
}
```

## 11.6 Padding block model

```dart
final class PaddingBlock extends FlacMetadataBlock {
  final int size;
}
```

Padding payload is implicitly zero bytes of specified size.

## 11.7 StreamInfo block model

```dart
final class StreamInfoBlock extends FlacMetadataBlock {
  final int minBlockSize;
  final int maxBlockSize;
  final int minFrameSize;
  final int maxFrameSize;
  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final int totalSamples;
  final Uint8List md5Signature;
}
```

This is read-only in v1. Treat it as immutable and not user-editable unless there is a compelling case later.

---

# 12. Parsing design

## 12.1 Parsing strategy

The parser reads:

1. FLAC marker
2. metadata blocks in sequence
3. records byte offset immediately after the final metadata block

The parser should not parse audio frames.

## 12.2 Low-level byte reader

Internal reader should support:

* reading fixed-width unsigned integers
* reading 24-bit integers
* reading length-prefixed byte sequences
* reading UTF-8 strings
* bounds checking

Suggested internal API:

```dart
abstract interface class ByteReader {
  int get position;
  int get remaining;

  int readUint8();
  int readUint24();
  int readUint32LE();
  Uint8List readBytes(int length);
}
```

You will need both big-endian and little-endian operations because:

* FLAC block headers use big-endian-style field reading
* Vorbis comment lengths are little-endian

That is easy to get wrong, so keep it isolated in binary helpers.

## 12.3 Block header parsing

Each block header contains:

* last-metadata-block flag
* block type
* payload length

Use a dedicated value object:

```dart
final class FlacBlockHeader {
  final bool isLast;
  final int typeCode;
  final int payloadLength;
}
```

## 12.4 Per-block parsing

Dispatcher pattern:

```dart
FlacMetadataBlock parseBlock(FlacBlockHeader header, ByteReader reader) {
  switch (header.typeCode) {
    case 0: return parseStreamInfo(...);
    case 1: return parsePadding(...);
    case 2: return parseApplication(...);
    case 3: return parseSeekTable(...);
    case 4: return parseVorbisComment(...);
    case 5: return parseCueSheet(...);
    case 6: return parsePicture(...);
    default: return parseUnknown(...);
  }
}
```

## 12.5 Unknown block preservation

Unknown valid blocks should be stored as raw payloads exactly as parsed. That allows safe round-tripping when untouched.

---

# 13. Serialization design

## 13.1 Whole-document serialization

Serialization must operate on the block list as a sequence. It should:

* order blocks according to policy
* set the correct last-block flag on the final serialized block
* compute payload lengths from serialized content
* emit block header + payload per block

## 13.2 Block ordering policy

Recommended default ordering:

1. `STREAMINFO` first, always
2. zero or more non-padding metadata blocks
3. optional `PADDING`
4. final block flag applied to final actual block

### Why

This is predictable, conventional, and simplifies padding behavior.

I would not preserve arbitrary existing padding placement unless there is a strong compatibility reason. It complicates rewrites for little value.

## 13.3 Stable normalization policy

Document and implement a clear normalization policy:

* preserve unknown untouched blocks
* preserve relative ordering of non-padding untouched blocks where possible
* allow padding to move to the end of metadata region
* preserve order of Vorbis comment entries unless explicitly normalized

That balance is practical.

---

# 14. Mutation model

## 14.1 Mutation operations

Represent mutations as typed operations.

```dart
sealed class MetadataMutation {}

final class SetTag extends MetadataMutation {
  final String key;
  final List<String> values;
}

final class AddTag extends MetadataMutation {
  final String key;
  final String value;
}

final class RemoveTag extends MetadataMutation {
  final String key;
}

final class RemoveExactTagValue extends MetadataMutation {
  final String key;
  final String value;
}

final class ClearTags extends MetadataMutation {}

final class AddPicture extends MetadataMutation {
  final PictureBlock picture;
}

final class ReplacePictureByType extends MetadataMutation {
  final PictureType pictureType;
  final PictureBlock replacement;
}

final class RemovePictureByType extends MetadataMutation {
  final PictureType pictureType;
}

final class SetPadding extends MetadataMutation {
  final int size;
}
```

### Why mutation objects matter

They work well for:

* CLI translation
* batch transformations
* logging
* dry-run plans
* deterministic test cases

## 14.2 Editor API on top of mutations

The editor can simply accumulate mutation objects behind the scenes.

```dart
final class FlacMetadataEditor {
  final List<MetadataMutation> _mutations = [];

  void setTag(String key, List<String> values) { ... }
  void addTag(String key, String value) { ... }
  void removeTag(String key) { ... }
  void clearTags() { ... }
  void setPadding(int size) { ... }
}
```

---

# 15. Transformation planning

## 15.1 Why a transform plan exists

Before transforming output, the system should compute a plan describing:

* what blocks will change
* new metadata size
* whether existing padding is sufficient
* whether output can reuse current metadata allocation
* whether a full metadata rewrite is required

This makes the system easier to test and easier to expose in dry-run mode.

## 15.2 Transform plan structure

```dart
final class FlacTransformPlan {
  final List<FlacMetadataBlock> originalBlocks;
  final List<FlacMetadataBlock> transformedBlocks;

  final int originalMetadataRegionSize;
  final int transformedMetadataRegionSize;

  final bool fitsExistingRegion;
  final bool requiresPaddingAdjustment;
  final bool requiresFullRewrite;
}
```

## 15.3 Planning algorithm

1. parse document
2. apply mutations to logical block model
3. normalize block sequence
4. serialize transformed metadata blocks to estimate size
5. compare with original metadata allocation
6. decide transformation strategy

---

# 16. Padding strategy

This is one of the core design decisions.

## 16.1 Goals

* avoid rewriting audio payload when metadata still fits
* preserve or create padding for future edits
* keep behavior deterministic

## 16.2 Strategy rules

### Rule 1

If transformed metadata is smaller than original metadata allocation:

* shrink metadata content
* fill remainder with padding

### Rule 2

If transformed metadata equals original metadata allocation:

* rewrite metadata region exactly
* no extra padding added unless explicitly requested and already budgeted

### Rule 3

If transformed metadata exceeds original metadata allocation:

* perform transformed output rewrite
* emit new metadata region followed by streamed audio payload

## 16.3 Explicit padding request

If the user specifies `setPadding(n)`:

* transformed metadata region should include a padding block of exactly `n` bytes, unless impossible due to write mode constraints

## 16.4 Implicit padding policy

For v1, keep implicit padding behavior simple:

* do not automatically invent large padding unless the caller asks
* when metadata shrinks and no explicit padding mutation exists, preserve remaining capacity as padding

That is safer and less surprising.

---

# 17. Streaming rewrite algorithm

## 17.1 Problem

When transformed metadata does not fit in the original metadata allocation, we need to rewrite the leading metadata and then copy the remaining audio payload without loading it all into memory.

## 17.2 Rewrite algorithm

Pseudo-flow:

```text
parse input metadata region
compute transformed metadata bytes
emit "fLaC"
emit transformed block sequence
seek or continue reading from original audioDataOffset
stream-copy remaining bytes to output
```

## 17.3 Core streaming interface

```dart
abstract interface class FlacStreamTransformer {
  Future<FlacMetadataDocument> readMetadata();
  Future<Stream<List<int>>> transform({
    required List<MetadataMutation> mutations,
    FlacTransformOptions? options,
  });
}
```

## 17.4 Handling non-seekable streams

Important constraint:

* for non-seekable input streams, parsing metadata consumes bytes

Options:

1. buffer metadata region while reading, then continue piping remaining bytes
2. define API behavior that transformation requires either:

   * full stream control internally
   * or a reopenable/seekable source abstraction

### Recommended design

Use two streaming source modes:

#### A. `Stream<List<int>>`

Works for single-pass transformation where the transformer owns the input flow.

#### B. `ReopenableByteSource`

Optional advanced abstraction for sources that can reopen or seek.

Example:

```dart
abstract interface class ByteSource {
  Future<Stream<List<int>>> openStream();
  Future<int?> length();
}
```

The simplest implementation for v1 is:

* support bytes
* support single-pass stream transformation owned by the transformer
* support file-based reopening in `dart_metaflac_io`

Do not over-engineer generic seeking in the core unless needed.

---

# 18. File persistence design (`dart_metaflac_io`)

## 18.1 Responsibilities

* open file input stream
* perform transformation
* write temp file
* replace original safely
* preserve timestamps if requested

## 18.2 Write modes

```dart
enum WriteMode {
  safeAtomic,
  auto,
  inPlaceIfPossible,
  outputToNewFile,
}
```

## 18.3 `safeAtomic`

Process:

1. open source file
2. transform to temp file in same directory if possible
3. flush and close temp file
4. replace original
5. preserve modtime if requested

This should be the default.

## 18.4 `outputToNewFile`

Always write transformed output to another destination.

## 18.5 `inPlaceIfPossible`

Only allowed when:

* transformed metadata region fits existing allocation
* implementation can rewrite safely without altering audio payload
* no unsafe truncation or expansion needed

If not possible, throw `WriteConflictException` unless mode is `auto`.

## 18.6 `auto`

Behaves like:

* try in-place if safe and beneficial
* otherwise fall back to safe atomic

### My recommendation

Even in `auto`, be conservative. The value of risky in-place mutation is low compared with correctness.

---

# 19. In-place update strategy

In-place updates are only worth supporting for exact same-size or within-existing-region rewrites.

## 19.1 Conditions

Allow in-place only when:

* updated metadata region length <= original metadata region length
* no need to move audio data
* output block sequence is structurally valid
* write can be completed deterministically

## 19.2 Implementation note

This belongs in `dart_metaflac_io`, not the pure core.

The core should simply declare:

* `fitsExistingRegion = true`

The IO layer decides whether that enables true in-place rewrite or still prefers safe temp-file replacement.

---

# 20. CLI design

## 20.1 Command model

Modern subcommands:

```text
dart-metaflac inspect file.flac
dart-metaflac blocks list file.flac
dart-metaflac tags list file.flac
dart-metaflac tags set file.flac ARTIST=Foo
dart-metaflac tags add file.flac ARTIST=Bar
dart-metaflac picture add file.flac --file cover.jpg
dart-metaflac padding set file.flac 8192
```

## 20.2 Compatibility alias parser

The CLI should also accept:

```text
dart-metaflac --list file.flac
dart-metaflac --set-tag=ARTIST=Foo file.flac
dart-metaflac --remove-tag=COMMENT file.flac
dart-metaflac --remove-all-tags file.flac
```

The alias parser’s only job is to translate flag-style input into internal command objects or mutation objects.

## 20.3 Command execution flow

```text
CLI args
 -> parse modern or compatibility syntax
 -> build command model
 -> map to library mutations or read operations
 -> call IO adapter
 -> render output
```

## 20.4 Output model

Human mode:

* readable summaries
* filenames as needed
* errors on stderr

JSON mode:

* structured object per file
* stable keys
* explicit error type and message

Suggested JSON shape:

```json
{
  "file": "song.flac",
  "success": true,
  "operation": "set-tag",
  "changes": {
    "tagsSet": ["ARTIST", "ALBUM"]
  }
}
```

---

# 21. Error model

Use typed exceptions throughout the core.

## 21.1 Core exceptions

```dart
class FlacMetadataException implements Exception {}
class InvalidFlacException extends FlacMetadataException {}
class MalformedMetadataException extends FlacMetadataException {}
class UnsupportedBlockException extends FlacMetadataException {}
class FlacInsufficientPaddingException extends FlacMetadataException {}
class WriteConflictException extends FlacMetadataException {}
class FlacIoException extends FlacMetadataException {}
```

## 21.2 Error semantics

### `InvalidFlacException`

File or bytes do not begin with valid FLAC marker or structure.

### `MalformedMetadataException`

Metadata region exists but is structurally invalid.

### `UnsupportedBlockException`

User requested mutation on a supported file structure but an unsupported block operation.

### `FlacInsufficientPaddingException`

Caller explicitly required no full rewrite but transformed metadata exceeds available region.

### `WriteConflictException`

Selected write mode cannot satisfy required transformation safely.

### `FlacIoException`

Filesystem-level problems in IO adapter.

## 21.3 CLI mapping

Map exceptions to:

* human-readable messages
* stable exit codes
* JSON error objects

---

# 22. UTF-8 and tag encoding design

Vorbis comments are UTF-8-based. Keep the core strict and UTF-8-centric.

## 22.1 Core policy

* parse comment strings as UTF-8
* serialize as UTF-8
* do not implement platform-local charset conversion in the core

## 22.2 CLI `--no-utf8-convert`

This compatibility option should likely be accepted for script parity, but documented as:

* either a no-op in pure Dart mode
* or limited in behavior compared with legacy native tooling

That is better than pretending to fully mirror platform-charset behavior.

---

# 23. Validation rules

## 23.1 General

* `STREAMINFO` must remain first
* metadata lengths must fit FLAC constraints
* only one logical `STREAMINFO`
* block payload lengths must be correct

## 23.2 Vorbis comments

* keys must not contain `=`
* preserve repeated keys
* empty values allowed
* key comparisons are case-insensitive for lookup

## 23.3 Pictures

* MIME type required
* data required
* type required
* dimension metadata can be supplied by caller; v1 should not attempt to decode image files just to infer them unless explicitly added later

That is an important product choice: do not couple metadata editing to image decoding logic unless needed.

---

# 24. Internal class sketches

## 24.1 Parser

```dart
final class FlacParser {
  Future<FlacMetadataDocument> parseBytes(Uint8List bytes);
  Future<FlacMetadataDocument> parseStream(Stream<List<int>> stream);
}
```

Internally, `parseStream` may buffer just the metadata region as needed.

## 24.2 Transformer

```dart
final class FlacTransformer {
  Future<FlacMetadataDocument> readMetadata();
  Future<FlacTransformPlan> plan(List<MetadataMutation> mutations);
  Future<Stream<List<int>>> transform({
    required List<MetadataMutation> mutations,
    FlacTransformOptions? options,
  });
}
```

## 24.3 Serializer

```dart
final class FlacSerializer {
  Uint8List serializeDocument(FlacMetadataDocument document);
  Uint8List serializeBlocks(List<FlacMetadataBlock> blocks);
}
```

## 24.4 IO adapter

```dart
final class FlacFileEditor {
  static Future<void> updateFile(
    String path, {
    required List<MetadataMutation> mutations,
    FlacWriteOptions? options,
  });

  static Future<FlacMetadataDocument> readFile(
    String path, {
    FlacReadOptions? options,
  });
}
```

---

# 25. Test strategy

## 25.1 Unit tests

Focus on:

* block header parsing
* 24-bit length handling
* little-endian Vorbis comment fields
* picture block serialization
* padding size calculations
* block ordering normalization
* transform plan logic

## 25.2 Integration tests

* bytes in -> bytes out
* stream in -> stream out
* file in -> safe atomic replace
* CLI tag mutations
* CLI picture import/export
* JSON output shape

## 25.3 Fixture suite

Include:

* minimal FLAC
* FLAC with Vorbis comments
* FLAC with multiple picture blocks
* FLAC with large padding
* FLAC with zero padding
* FLAC with unknown metadata blocks
* malformed/truncated FLAC

## 25.4 Property-style tests

Useful for:

* random Vorbis comment lists
* repeated read/write round-trips
* unknown block preservation

---

# 26. Performance considerations

## 26.1 Metadata parsing

Metadata should be parsed without touching audio frame bytes beyond finding the start offset.

## 26.2 Rewrite memory usage

Full audio payload must be streamed, not fully buffered.

## 26.3 In-memory mode

For `Uint8List` inputs, it is acceptable that the full input is already resident in memory because that is the caller’s choice.

## 26.4 Benchmarks

Track at least:

* metadata read latency
* padding-hit update latency
* full rewrite throughput
* large file memory profile

The earlier uploaded draft suggested a strong target for fast updates when padding exists; that should be treated as a benchmark target rather than a hard external promise until measured. 

---

# 27. Concurrency and reentrancy

The core library should be stateless at the class level wherever possible.

Recommended rules:

* parser instances may be reusable but do not need shared mutable state
* transformers are one-shot per input
* documents are immutable
* editors are short-lived

This makes concurrent usage in services much safer.

---

# 28. Versioning and compatibility

## 28.1 SemVer policy

* public APIs in `dart_metaflac` follow SemVer strictly
* CLI argument alias additions are backward-compatible
* JSON output schemas should be documented and versioned if they become automation-critical

## 28.2 Compatibility priorities

1. library correctness
2. stable transformation behavior
3. CLI usability
4. legacy flag parity

That ordering matters.

---

# 29. Recommended implementation order

## Phase 1

* block header parsing
* document model
* `STREAMINFO`, `VORBIS_COMMENT`, `PICTURE`, `PADDING`
* serializer for those blocks

## Phase 2

* mutation model
* transform planning
* bytes-based transformations
* round-trip tests

## Phase 3

* stream transformer
* unknown block preservation
* large-file integration tests

## Phase 4

* IO adapter package
* safe atomic writes
* optional in-place rewrite support

## Phase 5

* CLI commands
* compatibility alias parser
* JSON output
* docs and examples

That is the order I would actually implement it in.

---

# 30. Key design decisions and opinions

## 30.1 Use a canonical `VorbisComments` model, not just a map

This avoids future regret.

## 30.2 Keep image metadata dumb in v1

Do not add image decoding dependencies just to infer dimensions unless there is strong demand.

## 30.3 Make the transform plan explicit

This helps debugging, testing, dry-run, and CLI reporting.

## 30.4 Keep the core ignorant of filesystems

This is the most important architectural decision in the whole design.

## 30.5 Be conservative about in-place updates

They are nice to have, but safe temp-file replacement is much more important.

---

# 31. Example end-to-end flows

## 31.1 Flutter app, in-memory update

```dart
final doc = await FlacMetadataDocument.readFromBytes(bytes);
final updated = doc.edit((e) => e
  ..setTag('TITLE', ['Track Title'])
  ..setTag('ARTIST', ['Artist Name']));
final result = await updated.toBytes();
```

## 31.2 Server job, stream-based rewrite

```dart
final transformer = FlacTransformer.fromStream(uploadedStream);
final output = await transformer.transform(
  mutations: [
    SetTag('ALBUM', ['Catalog Album']),
    RemoveTag('COMMENT'),
  ],
);
await output.pipe(storageSink);
```

## 31.3 CLI safe file update

```dart
await FlacFileEditor.updateFile(
  'song.flac',
  mutations: [
    SetTag('ARTIST', ['Miles Davis']),
    AddPicture(frontCover),
  ],
  options: FlacWriteOptions(
    mode: WriteMode.safeAtomic,
    preserveModTime: true,
  ),
);
```

---

# 32. Acceptance criteria for this technical design

This design is acceptable if implementation from it would naturally produce a system where:

* the core package has no `dart:io` dependency
* the library supports bytes and streams
* the file adapter handles persistence safety
* the CLI contains only orchestration and formatting logic
* Vorbis comments, pictures, and padding are first-class
* unknown valid metadata blocks can survive untouched
* audio frame payload is preserved during rewrites
* large-file rewrites do not require full memory buffering

---

# 33. Final recommendation

The most important implementation choice is to make `dart_metaflac` a **metadata transformation engine** and `dart_metaflac_io` a **persistence adapter**. That clean split will make the package usable in Flutter Web, backend services, desktop tooling, and CLI workflows without bending the design later.
