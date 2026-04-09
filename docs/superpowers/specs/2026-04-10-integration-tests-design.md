# Design Spec: Integration Tests for New Features

**Date:** 2026-04-10
**Status:** Approved
**Scope:** Add integration tests for streaming pipeline, Document API lifecycle, and cross-layer interactions. Extract shared test fixtures.

---

## 1. Context

The recent implementation added StreamRewriter, FlacTransformer.transformStream(), FlacMetadataDocument convenience API (readFromBytes/readFromStream/toBytes), and CLI improvements. Each has unit-level tests, but cross-layer integration tests are missing. The `buildFlac()` fixture builder is duplicated across 3 test files.

---

## 2. Shared Test Fixtures

Extract `buildFlac()` and `makeJpeg()` helpers from `test/integration_test.dart` into `test/test_fixtures.dart`. Update existing test files to import from the shared location.

---

## 3. Integration Test File

**File:** `test/new_features_integration_test.dart`

### Group 1: Streaming Pipeline End-to-End

| Test | Description |
|------|-------------|
| Multi-block stream transform | FLAC with STREAMINFO + vorbis + picture + padding, transform via stream, verify all blocks survive |
| Multiple mutations via streaming | Set tag + add picture + set padding in one transformStream call |
| Identity stream transform | Empty mutations list, verify output equals a valid re-parse of original |
| Large audio payload | 10KB synthetic audio, verify all bytes survive streaming unchanged |
| Tiny chunks (1 byte) | Feed input 1 byte at a time, verify boundary detection works |
| Truncated stream | Stream ends mid-metadata-block, expect MalformedMetadataException |
| Empty stream | Zero bytes input, expect InvalidFlacException |

### Group 2: Document API Full Lifecycle

| Test | Description |
|------|-------------|
| Double round-trip | readFromBytes → edit → toBytes → readFromBytes → verify |
| Chained edits | doc.edit(...).edit(...).toBytes() — both edits present |
| Stream source lifecycle | readFromStream → edit → toBytes — full chain from stream |
| Add new block type | File with no vorbis, edit adds tags, toBytes has vorbis block |
| Remove all of a type | File with 2 pictures, edit removes all, toBytes has none |

### Group 3: Cross-Layer

| Test | Description |
|------|-------------|
| StreamRewriter → readFromBytes | Stream rewriter output parsed by Document API |
| toBytes → transformStream | Document API output fed into streaming transformer |
| Sequential transforms | stream → bytes → stream, data preserved throughout |

---

## 4. Out of Scope

- CLI integration tests (already covered in test/cli_test.dart)
- Performance/memory benchmarks
- Real FLAC file testing
