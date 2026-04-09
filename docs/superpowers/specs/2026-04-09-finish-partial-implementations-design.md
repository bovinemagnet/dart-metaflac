# Design Spec: Finish Partially Implemented Components

**Date:** 2026-04-09
**Status:** Proposed
**Scope:** Complete the transform layer, API layer, and CLI — the three partially implemented areas identified in the gap analysis.

---

## 1. Context

The core library (binary parsing, domain models, editing, error handling) is complete and well-tested with 115 passing tests. Three areas are partially implemented and need finishing before Milestone 3 (IO adapters) work begins:

1. **Transform layer** — no streaming rewriter; audio data loaded into memory during transforms
2. **API layer** — thin function wrappers, not the class-based APIs described in TECH-SPEC section 10
3. **CLI** — basic `--flag` style works but missing JSON output, dry-run, batch error handling, exit codes

---

## 2. Transform Layer: Stream Rewriter

### Problem

`FlacTransformer.transform()` currently loads the entire file (including audio payload) into memory via `Uint8List`. For large FLAC files this is unacceptable.

### Solution

Add `lib/src/transform/stream_rewriter.dart` containing a `StreamRewriter` class that performs single-pass stream transformation:

1. Reads the input `Stream<List<int>>`, buffering only the metadata region (up to and including the block with `isLast = true`)
2. Applies mutations to the buffered metadata to produce new metadata bytes
3. Emits output as a `Stream<List<int>>`:
   - `fLaC` marker (4 bytes)
   - Transformed metadata blocks (serialised)
   - Remaining audio bytes piped straight through from the input stream
4. Audio payload is never held in memory

### API Addition

`FlacTransformer` gains:

```dart
/// Transforms a FLAC stream, returning a new stream with updated metadata.
/// Audio payload is streamed through without buffering.
Future<Stream<List<int>>> transformStream({
  required List<MetadataMutation> mutations,
  FlacTransformOptions? options,
});
```

### Internal Design

```dart
class StreamRewriter {
  /// Buffers metadata from the input stream, applies mutations,
  /// and returns a stream that emits transformed metadata followed
  /// by the remaining audio bytes.
  static Future<Stream<List<int>>> rewrite({
    required Stream<List<int>> input,
    required List<MetadataMutation> mutations,
    FlacTransformOptions? options,
  });
}
```

The stream rewriter:
- Uses a `BytesBuilder` to accumulate incoming chunks until the full metadata region is read
- Parses the metadata region using existing `FlacParser`
- Applies mutations using existing `FlacMetadataEditor`
- Serialises the new metadata using existing `FlacSerializer`
- Yields the new metadata bytes, then yields remaining audio chunks as they arrive from the input stream

### Files

- **New:** `lib/src/transform/stream_rewriter.dart`
- **Modified:** `lib/src/transform/flac_transformer.dart` — add `transformStream()` method

---

## 3. API Layer: Richer Class-Based APIs

### Problem

Current API files are minimal function wrappers. TECH-SPEC section 10 describes ergonomic class-based APIs for application developers.

### Solution

Enrich existing API files to support the documented patterns.

### `document_api.dart` Changes

Add convenience methods to `FlacMetadataDocument`:

```dart
/// Parse a FLAC document from bytes.
static FlacMetadataDocument readFromBytes(Uint8List bytes);

/// Parse a FLAC document from a stream.
static Future<FlacMetadataDocument> readFromStream(Stream<List<int>> stream);

/// Serialise this document (metadata + audio) back to bytes.
Uint8List toBytes();
```

**Note:** `toBytes()` requires access to the original audio data. The document will need to store the source bytes (or the audio portion extracted at parse time) so it can re-emit them during serialisation. For the bytes-based API this is straightforward — the parsed document retains a reference to the audio slice. For stream-based use, consumers should use `transformStream()` instead.

This enables the canonical high-level flow:

```dart
final doc = FlacMetadataDocument.readFromBytes(bytes);
final updated = doc.edit((e) => e..setTag('ARTIST', ['New Artist']));
final outBytes = updated.toBytes();
```

### `transform_api.dart` Changes

Ensure `FlacTransformer` exposes:

```dart
/// Create a transformer from a stream source.
factory FlacTransformer.fromStream(Stream<List<int>> stream);

/// Create a transformer from bytes.
factory FlacTransformer.fromBytes(Uint8List bytes);

/// Read metadata without transforming.
Future<FlacMetadataDocument> readMetadata();

/// Transform and return bytes + plan (existing, for small files).
Future<FlacTransformResult> transform({...});

/// Transform and return a stream (new, for large files).
Future<Stream<List<int>>> transformStream({...});
```

### `read_api.dart`

No changes needed — already functional.

### Exports

Update `lib/dart_metaflac.dart` to export new public surface cleanly.

### Files

- **Modified:** `lib/src/api/document_api.dart`
- **Modified:** `lib/src/api/transform_api.dart`
- **Modified:** `lib/src/model/flac_metadata_document.dart`
- **Modified:** `lib/dart_metaflac.dart`

---

## 4. CLI Improvements

### Problem

The CLI works for basic operations but lacks features needed for automation and robust batch use.

### Solution

Add four capabilities to the existing `--flag` style CLI in `bin/metaflac.dart`.

### 4.1 JSON Output (`--json`)

When `--json` is passed:
- Read operations (`--list`, `--show-md5`, `--export-tags-to=-`) emit structured JSON to stdout
- Mutation operations emit a result object: `{"file": "song.flac", "success": true, "operation": "set-tag", "changes": {...}}`
- Errors emit JSON to stderr: `{"error": "message", "file": "song.flac", "type": "InvalidFlacException"}`

### 4.2 Dry-Run (`--dry-run`)

When `--dry-run` is passed with mutation operations:
- Computes the transform plan but does not write
- Reports what would change: tags added/removed, picture operations, padding adjustment, whether a full rewrite would be needed
- Compatible with `--json` for structured output

### 4.3 Batch Error Handling (`--continue-on-error`)

When processing multiple files:
- Continue past failures instead of stopping at the first error
- Report per-file success/failure at the end
- Exit code reflects whether any file failed

### 4.4 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Invalid FLAC file |
| 4 | I/O error |

### 4.5 Quiet Mode (`--quiet` / `-q`)

Suppress normal output; only show errors.

### Files

- **Modified:** `bin/metaflac.dart`

---

## 5. Edit Layer Utilities (Minor)

Extract block ordering and normalisation logic from the serialiser into dedicated files as the TECH-SPEC specifies:

- **New:** `lib/src/edit/block_rewriter.dart` — block reordering (STREAMINFO first, PADDING last)
- **New:** `lib/src/edit/normalization.dart` — validation and normalisation policies

These are small extractions from existing inline logic, not new behaviour.

---

## 6. Testing Strategy

### Transform Layer Tests

- Stream rewriter: metadata-only buffering confirmed (no audio in memory)
- Round-trip: stream transform produces valid FLAC bytes
- Large synthetic payload: verify bounded memory usage pattern
- Error: truncated stream, invalid metadata in stream

### API Layer Tests

- `FlacMetadataDocument.readFromBytes()` → `edit()` → `toBytes()` round-trip
- `FlacMetadataDocument.readFromStream()` works
- `FlacTransformer.fromStream().transformStream()` produces valid output

### CLI Tests

- JSON output parsing for `--list --json`
- Dry-run does not modify file
- `--continue-on-error` processes all files
- Exit codes match spec
- Quiet mode suppresses normal output

---

## 7. Out of Scope

- Package split into `dart_metaflac_io` / `dart_metaflac_cli` (Milestone 3+)
- `ByteSource` / reopenable source abstraction (Milestone 3)
- Safe atomic file replacement (Milestone 3)
- Modern subcommand CLI style (later)
- DartDoc comments / pub.dev documentation (Milestone 5)
- Performance benchmarks (Milestone 5)
