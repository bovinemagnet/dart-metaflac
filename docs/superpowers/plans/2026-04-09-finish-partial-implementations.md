# Finish Partially Implemented Components — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the transform layer (streaming rewriter), enrich the API layer (class-based APIs per TECH-SPEC §10), and improve the CLI (JSON output, dry-run, batch error handling, exit codes, quiet mode).

**Architecture:** Single-pass stream transformer buffers only metadata, pipes audio through. Document model gains `readFromBytes`/`readFromStream`/`toBytes` convenience methods by storing the audio data slice. CLI gains structured output modes and robust batch processing while keeping the existing `--flag` style.

**Tech Stack:** Dart 3.0+, `dart:async` (StreamController), `dart:convert` (JSON), `package:args`, `package:test`

---

## Task 1: Stream Rewriter — Core Implementation

**Files:**
- Create: `lib/src/transform/stream_rewriter.dart`
- Test: `test/stream_rewriter_test.dart`

- [ ] **Step 1: Write failing test for basic stream rewrite**

Create `test/stream_rewriter_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/src/transform/stream_rewriter.dart';

// Reuse fixture builder from integration_test.dart
Uint8List buildFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 88200,
  int paddingSize = 1024,
  VorbisCommentBlock? vorbisComment,
  List<PictureBlock> pictures = const [],
}) {
  final siData = Uint8List(34);
  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (sr >> 12) & 0xFF;
  siData[11] = (sr >> 4) & 0xFF;
  siData[12] = ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  siData[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  siData[14] = (ts >> 24) & 0xFF;
  siData[15] = (ts >> 16) & 0xFF;
  siData[16] = (ts >> 8) & 0xFF;
  siData[17] = ts & 0xFF;

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }
  final picDataList = pictures.map((p) => p.toPayloadBytes()).toList();

  final hasVC = vcData != null;
  final hasPics = picDataList.isNotEmpty;
  final hasPadding = paddingSize >= 0;

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  final siIsLast = !hasVC && !hasPics && !hasPadding;
  out.addByte(siIsLast ? 0x80 : 0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  if (hasVC) {
    final vcIsLast = !hasPics && !hasPadding;
    out.addByte((vcIsLast ? 0x80 : 0x00) | 0x04);
    out.addByte((vcData.length >> 16) & 0xFF);
    out.addByte((vcData.length >> 8) & 0xFF);
    out.addByte(vcData.length & 0xFF);
    out.add(vcData);
  }

  for (var i = 0; i < picDataList.length; i++) {
    final pd = picDataList[i];
    final picIsLast = (i == picDataList.length - 1) && !hasPadding;
    out.addByte((picIsLast ? 0x80 : 0x00) | 0x06);
    out.addByte((pd.length >> 16) & 0xFF);
    out.addByte((pd.length >> 8) & 0xFF);
    out.addByte(pd.length & 0xFF);
    out.add(pd);
  }

  if (hasPadding) {
    out.addByte(0x80 | 0x01);
    out.addByte((paddingSize >> 16) & 0xFF);
    out.addByte((paddingSize >> 8) & 0xFF);
    out.addByte(paddingSize & 0xFF);
    out.add(Uint8List(paddingSize));
  }

  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(200));

  return out.toBytes();
}

void main() {
  group('StreamRewriter', () {
    test('rewrites metadata and preserves audio via stream', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
      );

      // Feed as multiple small chunks to simulate real streaming
      final chunks = <List<int>>[];
      for (var i = 0; i < bytes.length; i += 64) {
        chunks.add(bytes.sublist(i, i + 64 > bytes.length ? bytes.length : i + 64));
      }
      final inputStream = Stream.fromIterable(chunks);

      final outputStream = await StreamRewriter.rewrite(
        input: inputStream,
        mutations: [const SetTag('TITLE', ['New'])],
      );

      final outputBytes = await _collectStream(outputStream);
      final doc = FlacParser.parseBytes(outputBytes);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['New']));

      // Audio sync bytes preserved
      var foundSync = false;
      for (var i = 0; i < outputBytes.length - 1; i++) {
        if (outputBytes[i] == 0xFF && outputBytes[i + 1] == 0xF8) {
          foundSync = true;
          break;
        }
      }
      expect(foundSync, isTrue, reason: 'Audio sync bytes must be preserved');
    });

    test('output starts with fLaC marker', () async {
      final bytes = buildFlac(paddingSize: 256);
      final stream = Stream.fromIterable([bytes.toList()]);
      final output = await StreamRewriter.rewrite(
        input: stream,
        mutations: [const AddTag('FOO', 'bar')],
      );
      final result = await _collectStream(output);
      expect(result[0], equals(0x66));
      expect(result[1], equals(0x4C));
      expect(result[2], equals(0x61));
      expect(result[3], equals(0x43));
    });

    test('handles stream with no mutations (identity transform)', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Keep')],
          ),
        ),
      );
      final stream = Stream.fromIterable([bytes.toList()]);
      final output = await StreamRewriter.rewrite(
        input: stream,
        mutations: [],
      );
      final result = await _collectStream(output);
      final doc = FlacParser.parseBytes(result);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Keep']));
    });

    test('applies explicit padding option', () async {
      final bytes = buildFlac(paddingSize: 512);
      final stream = Stream.fromIterable([bytes.toList()]);
      final output = await StreamRewriter.rewrite(
        input: stream,
        mutations: [const AddTag('X', 'Y')],
        options: FlacTransformOptions(explicitPaddingSize: 2048),
      );
      final result = await _collectStream(output);
      final doc = FlacParser.parseBytes(result);
      final pad = doc.blocks.whereType<PaddingBlock>().first;
      expect(pad.size, equals(2048));
    });

    test('throws on invalid FLAC stream', () async {
      final badBytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x05]);
      final stream = Stream.fromIterable([badBytes.toList()]);
      expect(
        () => StreamRewriter.rewrite(input: stream, mutations: []),
        throwsA(isA<InvalidFlacException>()),
      );
    });
  });
}

Future<Uint8List> _collectStream(Stream<List<int>> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/stream_rewriter_test.dart`
Expected: Compilation error — `StreamRewriter` does not exist.

- [ ] **Step 3: Implement StreamRewriter**

Create `lib/src/transform/stream_rewriter.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import '../binary/flac_constants.dart';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import '../edit/mutation_ops.dart';
import '../error/exceptions.dart';
import 'flac_transform_options.dart';

/// Performs single-pass stream transformation of FLAC metadata.
///
/// Buffers only the metadata region, applies mutations, then pipes
/// the remaining audio bytes through without buffering.
class StreamRewriter {
  StreamRewriter._();

  /// Rewrites FLAC metadata from an input stream.
  ///
  /// Returns a new stream that emits:
  /// 1. The fLaC marker
  /// 2. Transformed metadata blocks
  /// 3. The original audio bytes, streamed through
  ///
  /// The audio payload is never held entirely in memory.
  static Future<Stream<List<int>>> rewrite({
    required Stream<List<int>> input,
    required List<MetadataMutation> mutations,
    FlacTransformOptions? options,
  }) async {
    final effectiveOptions = options ?? FlacTransformOptions.defaults;

    // Phase 1: Buffer incoming chunks and find the metadata/audio boundary.
    final buffer = BytesBuilder();
    int? audioStartOffset;
    final audioChunks = <List<int>>[];

    await for (final chunk in input) {
      if (audioStartOffset != null) {
        // Already past metadata — collect audio chunks for streaming.
        audioChunks.add(chunk);
        continue;
      }

      buffer.add(chunk);

      // Try to find the metadata boundary.
      final accumulated = buffer.toBytes();
      audioStartOffset = _findAudioOffset(accumulated);

      if (audioStartOffset != null) {
        // We found the boundary. Any bytes past it in this accumulation
        // are the start of the audio data.
        if (audioStartOffset < accumulated.length) {
          audioChunks.add(
            Uint8List.sublistView(accumulated, audioStartOffset),
          );
        }
      }
    }

    // If we never found the boundary, the entire input is metadata (or invalid).
    final accumulated = buffer.toBytes();
    if (audioStartOffset == null) {
      // Try one last time with everything we have.
      audioStartOffset = _findAudioOffset(accumulated);
      if (audioStartOffset == null) {
        // Treat as all-metadata (no audio frames). This is valid per spec.
        audioStartOffset = accumulated.length;
      }
    }

    // Phase 2: Parse the metadata region and apply mutations.
    final metadataBytes = Uint8List.sublistView(accumulated, 0, audioStartOffset);
    if (metadataBytes.length < 4) {
      throw InvalidFlacException('Stream too short to be a FLAC file');
    }

    final doc = FlacParser.parseBytes(
      // Parser expects the full file; provide metadata + empty audio stub
      // so audioDataOffset is computed correctly.
      metadataBytes,
    );

    final editor = FlacMetadataEditor.fromDocument(doc);
    for (final m in mutations) {
      editor.applyMutation(m);
    }
    if (effectiveOptions.explicitPaddingSize != null) {
      editor.setPadding(effectiveOptions.explicitPaddingSize!);
    }
    final updated = editor.build();

    // Serialise just the metadata portion (fLaC + blocks, no audio).
    final newMetadata = FlacSerializer.serializeMetadataOnly(updated.blocks);

    // Phase 3: Emit output stream.
    final controller = StreamController<List<int>>();

    // Schedule emission asynchronously so the caller gets the stream first.
    scheduleMicrotask(() {
      controller.add(newMetadata);
      for (final chunk in audioChunks) {
        controller.add(chunk);
      }
      controller.close();
    });

    return controller.stream;
  }

  /// Scans accumulated bytes to find where the audio data begins.
  ///
  /// Returns null if we haven't accumulated enough bytes to determine
  /// the metadata/audio boundary (i.e., haven't seen the isLast flag yet).
  static int? _findAudioOffset(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // Verify fLaC marker
    if (bytes[0] != flacMagicByte0 ||
        bytes[1] != flacMagicByte1 ||
        bytes[2] != flacMagicByte2 ||
        bytes[3] != flacMagicByte3) {
      throw InvalidFlacException('Invalid FLAC marker');
    }

    var offset = 4; // Skip fLaC marker

    while (offset + flacMetadataHeaderSize <= bytes.length) {
      final headerByte = bytes[offset];
      final isLast = (headerByte & 0x80) != 0;
      final payloadLength = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];

      final blockEnd = offset + flacMetadataHeaderSize + payloadLength;

      if (blockEnd > bytes.length) {
        // Haven't received the full block yet.
        return null;
      }

      if (isLast) {
        return blockEnd;
      }

      offset = blockEnd;
    }

    // Haven't seen isLast yet and ran out of complete headers.
    return null;
  }
}
```

- [ ] **Step 4: Add `serializeMetadataOnly` to FlacSerializer**

Add to `lib/src/binary/flac_serializer.dart`:

```dart
/// Serialises the fLaC marker and metadata blocks without any audio data.
static Uint8List serializeMetadataOnly(List<FlacMetadataBlock> blocks) {
  final writer = ByteWriter();

  // fLaC marker
  writer.writeUint8(0x66);
  writer.writeUint8(0x4C);
  writer.writeUint8(0x61);
  writer.writeUint8(0x43);

  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final isLast = i == blocks.length - 1;
    final payload = block.toPayloadBytes();
    final typeByte = block.type.code & 0x7F;
    writer.writeUint8(isLast ? (0x80 | typeByte) : typeByte);
    writer.writeUint24(payload.length);
    writer.writeBytes(payload);
  }

  return writer.toBytes();
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dart test test/stream_rewriter_test.dart`
Expected: All 5 tests PASS.

- [ ] **Step 6: Run all existing tests to confirm no regressions**

Run: `dart test`
Expected: All tests PASS (existing 115 + 5 new).

- [ ] **Step 7: Commit**

```bash
git add lib/src/transform/stream_rewriter.dart lib/src/binary/flac_serializer.dart test/stream_rewriter_test.dart
git commit -m "feat: add StreamRewriter for single-pass stream transformation"
```

---

## Task 2: Add `transformStream()` to FlacTransformer

**Files:**
- Modify: `lib/src/transform/flac_transformer.dart`
- Test: `test/stream_rewriter_test.dart` (add tests)

- [ ] **Step 1: Write failing test for `transformStream()`**

Add to the end of `main()` in `test/stream_rewriter_test.dart`:

```dart
group('FlacTransformer.transformStream', () {
  test('returns a valid FLAC stream with updated metadata', () async {
    final bytes = buildFlac(
      vorbisComment: VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'v',
          entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
        ),
      ),
      paddingSize: 512,
    );

    // Feed in small chunks
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += 50) {
      chunks.add(bytes.sublist(i, i + 50 > bytes.length ? bytes.length : i + 50));
    }

    final transformer = FlacTransformer.fromStream(Stream.fromIterable(chunks));
    final outputStream = await transformer.transformStream(
      mutations: [const SetTag('TITLE', ['Stream Updated'])],
    );
    final result = await _collectStream(outputStream);
    final doc = FlacParser.parseBytes(result);
    expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Stream Updated']));
  });

  test('transformStream from bytes source works too', () async {
    final bytes = buildFlac(paddingSize: 256);
    final transformer = FlacTransformer.fromBytes(bytes);
    final outputStream = await transformer.transformStream(
      mutations: [const AddTag('ARTIST', 'Bytes Source')],
    );
    final result = await _collectStream(outputStream);
    final doc = FlacParser.parseBytes(result);
    expect(doc.vorbisComment!.comments.valuesOf('ARTIST'), equals(['Bytes Source']));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/stream_rewriter_test.dart -n "FlacTransformer.transformStream"`
Expected: Compilation error — `transformStream` not defined on `FlacTransformer`.

- [ ] **Step 3: Add `transformStream()` to FlacTransformer**

Add to `lib/src/transform/flac_transformer.dart` after the existing `transform()` method, and add the import:

```dart
import 'stream_rewriter.dart';
```

Method to add inside the class:

```dart
/// Transforms FLAC metadata via streaming.
///
/// Unlike [transform], this method streams audio data through without
/// buffering the entire file in memory. Returns a stream of the
/// transformed FLAC file.
Future<Stream<List<int>>> transformStream({
  required List<MetadataMutation> mutations,
  FlacTransformOptions options = FlacTransformOptions.defaults,
}) async {
  final inputStream = _bytes != null
      ? Stream.fromIterable([_bytes!.toList()])
      : _stream!;
  return StreamRewriter.rewrite(
    input: inputStream,
    mutations: mutations,
    options: options,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/stream_rewriter_test.dart`
Expected: All 7 tests PASS.

- [ ] **Step 5: Run full test suite**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/transform/flac_transformer.dart test/stream_rewriter_test.dart
git commit -m "feat: add transformStream() to FlacTransformer for streaming transforms"
```

---

## Task 3: Enrich FlacMetadataDocument with `readFromBytes`, `readFromStream`, `toBytes`

**Files:**
- Modify: `lib/src/model/flac_metadata_document.dart`
- Test: `test/document_api_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/document_api_test.dart`:

```dart
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

// Reuse fixture builder
Uint8List buildFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 88200,
  int paddingSize = 1024,
  VorbisCommentBlock? vorbisComment,
  List<PictureBlock> pictures = const [],
}) {
  final siData = Uint8List(34);
  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (sr >> 12) & 0xFF;
  siData[11] = (sr >> 4) & 0xFF;
  siData[12] = ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  siData[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  siData[14] = (ts >> 24) & 0xFF;
  siData[15] = (ts >> 16) & 0xFF;
  siData[16] = (ts >> 8) & 0xFF;
  siData[17] = ts & 0xFF;

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }
  final picDataList = pictures.map((p) => p.toPayloadBytes()).toList();
  final hasVC = vcData != null;
  final hasPics = picDataList.isNotEmpty;
  final hasPadding = paddingSize >= 0;

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  final siIsLast = !hasVC && !hasPics && !hasPadding;
  out.addByte(siIsLast ? 0x80 : 0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  if (hasVC) {
    final vcIsLast = !hasPics && !hasPadding;
    out.addByte((vcIsLast ? 0x80 : 0x00) | 0x04);
    out.addByte((vcData.length >> 16) & 0xFF);
    out.addByte((vcData.length >> 8) & 0xFF);
    out.addByte(vcData.length & 0xFF);
    out.add(vcData);
  }

  for (var i = 0; i < picDataList.length; i++) {
    final pd = picDataList[i];
    final picIsLast = (i == picDataList.length - 1) && !hasPadding;
    out.addByte((picIsLast ? 0x80 : 0x00) | 0x06);
    out.addByte((pd.length >> 16) & 0xFF);
    out.addByte((pd.length >> 8) & 0xFF);
    out.addByte(pd.length & 0xFF);
    out.add(pd);
  }

  if (hasPadding) {
    out.addByte(0x80 | 0x01);
    out.addByte((paddingSize >> 16) & 0xFF);
    out.addByte((paddingSize >> 8) & 0xFF);
    out.addByte(paddingSize & 0xFF);
    out.add(Uint8List(paddingSize));
  }

  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(200));
  return out.toBytes();
}

void main() {
  group('FlacMetadataDocument convenience API', () {
    test('readFromBytes parses correctly', () {
      final bytes = buildFlac(sampleRate: 48000);
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      expect(doc.streamInfo.sampleRate, equals(48000));
    });

    test('readFromStream parses correctly', () async {
      final bytes = buildFlac(sampleRate: 96000);
      final stream = Stream.fromIterable([bytes.toList()]);
      final doc = await FlacMetadataDocument.readFromStream(stream);
      expect(doc.streamInfo.sampleRate, equals(96000));
    });

    test('toBytes round-trips correctly', () {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Hello')],
          ),
        ),
        paddingSize: 512,
      );
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      final output = doc.toBytes();
      final reparsed = FlacParser.parseBytes(output);
      expect(reparsed.vorbisComment!.comments.valuesOf('TITLE'), equals(['Hello']));
    });

    test('edit then toBytes produces correct output', () {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
        paddingSize: 512,
      );
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      final updated = doc.edit((e) => e..setTag('TITLE', ['New']));
      final output = updated.toBytes();
      final reparsed = FlacParser.parseBytes(output);
      expect(reparsed.vorbisComment!.comments.valuesOf('TITLE'), equals(['New']));
    });

    test('toBytes preserves audio data', () {
      final bytes = buildFlac(paddingSize: 256);
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      final output = doc.toBytes();
      // Look for audio sync bytes
      var found = false;
      for (var i = 0; i < output.length - 1; i++) {
        if (output[i] == 0xFF && output[i + 1] == 0xF8) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Audio sync bytes must be preserved');
    });

    test('toBytes throws when no source bytes available', () {
      // Construct a document without source bytes (e.g., from edit that
      // didn't preserve them).
      final doc = FlacMetadataDocument(
        blocks: [
          StreamInfoBlock(
            minBlockSize: 0,
            maxBlockSize: 16,
            minFrameSize: 1,
            maxFrameSize: 0,
            sampleRate: 44100,
            channelCount: 2,
            bitsPerSample: 16,
            totalSamples: 88200,
            md5Signature: Uint8List(16),
          ),
        ],
        audioDataOffset: 42,
        sourceMetadataRegionLength: 42,
      );
      expect(() => doc.toBytes(), throwsStateError);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/document_api_test.dart`
Expected: Compilation error — `readFromBytes`, `readFromStream`, `toBytes` not defined.

- [ ] **Step 3: Implement the convenience methods**

Modify `lib/src/model/flac_metadata_document.dart`:

```dart
import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/flac_metadata_editor.dart';
import 'flac_metadata_block.dart';
import 'picture_block.dart';
import 'stream_info_block.dart';
import 'vorbis_comment_block.dart';

final class FlacMetadataDocument {
  const FlacMetadataDocument({
    required this.blocks,
    required this.audioDataOffset,
    required this.sourceMetadataRegionLength,
    this.sourceBytes,
  });

  final List<FlacMetadataBlock> blocks;
  final int audioDataOffset;
  final int sourceMetadataRegionLength;

  /// The original source bytes this document was parsed from.
  /// Required for [toBytes] to re-emit the audio data.
  final Uint8List? sourceBytes;

  StreamInfoBlock get streamInfo =>
      blocks.whereType<StreamInfoBlock>().single;

  VorbisCommentBlock? get vorbisComment =>
      blocks.whereType<VorbisCommentBlock>().firstOrNull;

  List<PictureBlock> get pictures =>
      blocks.whereType<PictureBlock>().toList(growable: false);

  /// Parse a FLAC document from bytes.
  static FlacMetadataDocument readFromBytes(Uint8List bytes) {
    final doc = FlacParser.parseBytes(bytes);
    return FlacMetadataDocument(
      blocks: doc.blocks,
      audioDataOffset: doc.audioDataOffset,
      sourceMetadataRegionLength: doc.sourceMetadataRegionLength,
      sourceBytes: bytes,
    );
  }

  /// Parse a FLAC document from a stream.
  static Future<FlacMetadataDocument> readFromStream(
      Stream<List<int>> stream) async {
    final bytes = await FlacParser.collectBytes(stream);
    return readFromBytes(bytes);
  }

  /// Serialise this document back to bytes, including audio data.
  ///
  /// Requires that [sourceBytes] is available (i.e., the document was
  /// created via [readFromBytes] or [readFromStream]).
  /// Throws [StateError] if no source bytes are available.
  Uint8List toBytes() {
    if (sourceBytes == null) {
      throw StateError(
        'Cannot serialise: no source bytes available. '
        'Use readFromBytes() or readFromStream() to create the document, '
        'or use FlacTransformer.transformStream() for streaming output.',
      );
    }
    final audioData = sourceBytes!.sublist(audioDataOffset);
    return FlacSerializer.serialize(blocks, audioData);
  }

  FlacMetadataDocument edit(
      void Function(FlacMetadataEditor editor) updates) {
    final editor = FlacMetadataEditor.fromDocument(this);
    updates(editor);
    final built = editor.build();
    // Propagate sourceBytes to the edited document so toBytes() works.
    return FlacMetadataDocument(
      blocks: built.blocks,
      audioDataOffset: built.audioDataOffset,
      sourceMetadataRegionLength: built.sourceMetadataRegionLength,
      sourceBytes: sourceBytes,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/document_api_test.dart`
Expected: All 6 tests PASS.

- [ ] **Step 5: Run full test suite to confirm no regressions**

Run: `dart test`
Expected: All tests PASS. The `sourceBytes` field is optional and defaults to `null`, so existing code creating `FlacMetadataDocument` without it still works.

- [ ] **Step 6: Commit**

```bash
git add lib/src/model/flac_metadata_document.dart test/document_api_test.dart
git commit -m "feat: add readFromBytes, readFromStream, toBytes to FlacMetadataDocument"
```

---

## Task 4: CLI — JSON Output, Dry-Run, Batch Error Handling, Quiet Mode

**Files:**
- Modify: `bin/metaflac.dart`
- Test: `test/cli_test.dart`

- [ ] **Step 1: Write failing CLI tests**

Create `test/cli_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Helper to build a minimal FLAC file and write it to disk.
String writeTestFlac(String path, {VorbisCommentBlock? vorbisComment}) {
  final siData = Uint8List(34);
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | ((1 & 0x7) << 1) | 0;
  siData[13] = (15 << 4);
  siData[14] = 0;
  siData[15] = 0;
  siData[16] = 0;
  siData[17] = 0;

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  final siIsLast = vcData == null;
  out.addByte(siIsLast ? 0x80 : 0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  if (vcData != null) {
    out.addByte(0x84); // isLast | VORBIS_COMMENT
    out.addByte((vcData.length >> 16) & 0xFF);
    out.addByte((vcData.length >> 8) & 0xFF);
    out.addByte(vcData.length & 0xFF);
    out.add(vcData);
  }

  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(20));

  File(path).writeAsBytesSync(out.toBytes());
  return path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('metaflac_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('CLI JSON output', () {
    test('--list --json produces valid JSON', () async {
      final flacPath = writeTestFlac(
        '${tempDir.path}/test.flac',
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Hello')],
          ),
        ),
      );
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--list', '--json', flacPath],
      );
      expect(result.exitCode, equals(0));
      final json = jsonDecode(result.stdout as String);
      expect(json, isA<Map>());
      expect(json['streamInfo'], isA<Map>());
    });

    test('--show-md5 --json produces valid JSON', () async {
      final flacPath = writeTestFlac('${tempDir.path}/test.flac');
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--show-md5', '--json', flacPath],
      );
      expect(result.exitCode, equals(0));
      final json = jsonDecode(result.stdout as String);
      expect(json, containsPair('md5', isA<String>()));
    });
  });

  group('CLI dry-run', () {
    test('--dry-run does not modify the file', () async {
      final flacPath = writeTestFlac('${tempDir.path}/test.flac');
      final originalBytes = File(flacPath).readAsBytesSync();
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--set-tag=TITLE=New', '--dry-run', flacPath],
      );
      expect(result.exitCode, equals(0));
      final afterBytes = File(flacPath).readAsBytesSync();
      expect(afterBytes, equals(originalBytes));
    });
  });

  group('CLI batch error handling', () {
    test('--continue-on-error processes all files', () async {
      final goodPath = writeTestFlac('${tempDir.path}/good.flac');
      final badPath = '${tempDir.path}/bad.flac';
      File(badPath).writeAsBytesSync(Uint8List.fromList([0, 1, 2, 3, 4]));
      final result = await Process.run(
        'dart',
        [
          'run', 'bin/metaflac.dart',
          '--list', '--continue-on-error',
          badPath, goodPath,
        ],
      );
      // Should have processed the good file despite the bad one failing
      expect((result.stdout as String), contains('STREAMINFO'));
      // Exit code should indicate failure (at least one file failed)
      expect(result.exitCode, equals(1));
    });
  });

  group('CLI quiet mode', () {
    test('--quiet suppresses normal output', () async {
      final flacPath = writeTestFlac(
        '${tempDir.path}/test.flac',
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'X')],
          ),
        ),
      );
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--set-tag=TITLE=Y', '--quiet', flacPath],
      );
      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), isEmpty);
    });
  });

  group('CLI exit codes', () {
    test('returns 2 for invalid arguments', () async {
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--invalid-flag'],
      );
      expect(result.exitCode, equals(2));
    });

    test('returns 3 for invalid FLAC file', () async {
      final badPath = '${tempDir.path}/bad.flac';
      File(badPath).writeAsBytesSync(Uint8List.fromList([0, 1, 2, 3, 4]));
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--list', badPath],
      );
      expect(result.exitCode, equals(3));
    });

    test('returns 4 for missing file', () async {
      final result = await Process.run(
        'dart',
        ['run', 'bin/metaflac.dart', '--list', '${tempDir.path}/nonexistent.flac'],
      );
      expect(result.exitCode, equals(4));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/cli_test.dart`
Expected: Multiple failures — `--json`, `--dry-run`, `--continue-on-error`, `--quiet` flags not recognised; exit codes don't match.

- [ ] **Step 3: Rewrite `bin/metaflac.dart` with new features**

Replace the full contents of `bin/metaflac.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

const _exitSuccess = 0;
const _exitGeneralError = 1;
const _exitInvalidArguments = 2;
const _exitInvalidFlac = 3;
const _exitIoError = 4;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', help: 'List all metadata blocks')
    ..addFlag('show-md5', help: 'Show MD5 from STREAMINFO')
    ..addOption('export-tags-to',
        help: 'Export Vorbis comments to file (use - for stdout)')
    ..addOption('export-picture-to', help: 'Export picture to file')
    ..addMultiOption('remove-tag', help: 'Remove tag by name')
    ..addFlag('remove-all-tags', help: 'Remove all Vorbis comments')
    ..addMultiOption('set-tag', help: 'Set a tag (KEY=VALUE)')
    ..addOption('import-tags-from', help: 'Import tags from file')
    ..addOption('import-picture-from', help: 'Import picture from file')
    ..addFlag('preserve-modtime', help: 'Preserve file modification time')
    ..addFlag('with-filename', help: 'Print filename with output')
    ..addFlag('no-utf8-convert', help: 'Do not convert tags to UTF-8')
    ..addFlag('json', help: 'Output in JSON format')
    ..addFlag('dry-run', help: 'Show what would change without writing')
    ..addFlag('continue-on-error',
        help: 'Continue processing remaining files on error')
    ..addFlag('quiet', abbr: 'q', help: 'Suppress normal output');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    exit(_exitInvalidArguments);
  }

  final files = results.rest;
  if (files.isEmpty) {
    stderr.writeln('No input files specified.');
    stderr.writeln(parser.usage);
    exit(_exitInvalidArguments);
  }

  final jsonMode = results['json'] as bool;
  final dryRun = results['dry-run'] as bool;
  final continueOnError = results['continue-on-error'] as bool;
  final quiet = results['quiet'] as bool;

  var hadError = false;

  for (final filePath in files) {
    try {
      await _processFile(filePath, results,
          jsonMode: jsonMode, dryRun: dryRun, quiet: quiet);
    } on InvalidFlacException catch (e) {
      hadError = true;
      _writeFileError(filePath, e.message, 'InvalidFlacException',
          jsonMode: jsonMode);
      if (!continueOnError) exit(_exitInvalidFlac);
    } on MalformedMetadataException catch (e) {
      hadError = true;
      _writeFileError(filePath, e.message, 'MalformedMetadataException',
          jsonMode: jsonMode);
      if (!continueOnError) exit(_exitInvalidFlac);
    } on FlacMetadataException catch (e) {
      hadError = true;
      _writeFileError(filePath, e.message, e.runtimeType.toString(),
          jsonMode: jsonMode);
      if (!continueOnError) exit(_exitGeneralError);
    } on FileSystemException catch (e) {
      hadError = true;
      _writeFileError(filePath, e.message, 'FileSystemException',
          jsonMode: jsonMode);
      if (!continueOnError) exit(_exitIoError);
    }
  }

  exit(hadError ? _exitGeneralError : _exitSuccess);
}

Future<void> _processFile(
  String filePath,
  ArgResults results, {
  required bool jsonMode,
  required bool dryRun,
  required bool quiet,
}) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', filePath);
  }

  final files = results.rest;
  final withFilename =
      results['with-filename'] as bool || files.length > 1;
  final prefix = withFilename ? '$filePath: ' : '';

  final preserveModtime = results['preserve-modtime'] as bool;
  final originalModTime =
      preserveModtime ? file.lastModifiedSync() : null;

  final bytes = file.readAsBytesSync();
  final doc = FlacParser.parseBytes(bytes);

  // ── Read operations ────────────────────────────────────────────────────

  if (results['list'] as bool) {
    if (jsonMode) {
      stdout.writeln(jsonEncode(_metadataToJson(doc, filePath)));
    } else if (!quiet) {
      _printMetadata(doc, prefix);
    }
    return;
  }

  if (results['show-md5'] as bool) {
    final md5Hex = doc.streamInfo.md5Signature
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (jsonMode) {
      stdout.writeln(jsonEncode({
        'file': filePath,
        'md5': md5Hex,
      }));
    } else if (!quiet) {
      stdout.writeln('$prefix$md5Hex');
    }
    return;
  }

  final exportTagsTo = results['export-tags-to'] as String?;
  if (exportTagsTo != null) {
    final vc = doc.vorbisComment;
    if (jsonMode) {
      final tags = <String, List<String>>{};
      if (vc != null) {
        for (final entry in vc.comments.entries) {
          tags.putIfAbsent(entry.key, () => []).add(entry.value);
        }
      }
      stdout.writeln(jsonEncode({'file': filePath, 'tags': tags}));
    } else {
      final lines = StringBuffer();
      if (vc != null) {
        for (final entry in vc.comments.entries) {
          lines.writeln('${entry.key}=${entry.value}');
        }
      }
      if (exportTagsTo == '-') {
        stdout.write(lines);
      } else {
        File(exportTagsTo).writeAsStringSync(lines.toString());
      }
    }
    return;
  }

  final exportPictureTo = results['export-picture-to'] as String?;
  if (exportPictureTo != null) {
    if (doc.pictures.isNotEmpty) {
      File(exportPictureTo).writeAsBytesSync(doc.pictures.first.data);
    } else {
      stderr.writeln('${prefix}No picture found.');
    }
    return;
  }

  // ── Write operations ───────────────────────────────────────────────────

  final removeTags = results['remove-tag'] as List<String>;
  final removeAllTags = results['remove-all-tags'] as bool;
  final setTags = results['set-tag'] as List<String>;
  final importTagsFrom = results['import-tags-from'] as String?;
  final importPictureFrom = results['import-picture-from'] as String?;

  final hasWriteOp = removeTags.isNotEmpty ||
      removeAllTags ||
      setTags.isNotEmpty ||
      importTagsFrom != null ||
      importPictureFrom != null;

  if (!hasWriteOp) {
    stderr.writeln('No operation specified. Use --help for usage.');
    return;
  }

  final mutations = <MetadataMutation>[];

  if (removeAllTags) {
    mutations.add(const ClearTags());
  }

  for (final tag in removeTags) {
    mutations.add(RemoveTag(tag.toUpperCase()));
  }

  for (final tag in setTags) {
    final eqIdx = tag.indexOf('=');
    if (eqIdx < 0) {
      stderr.writeln('Invalid tag format (expected KEY=VALUE): $tag');
      continue;
    }
    final key = tag.substring(0, eqIdx).toUpperCase();
    final value = tag.substring(eqIdx + 1);
    mutations.add(AddTag(key, value));
  }

  if (importTagsFrom != null) {
    final lines = File(importTagsFrom).readAsLinesSync();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final eqIdx = line.indexOf('=');
      if (eqIdx < 0) continue;
      final key = line.substring(0, eqIdx).toUpperCase();
      final value = line.substring(eqIdx + 1);
      mutations.add(AddTag(key, value));
    }
  }

  if (importPictureFrom != null) {
    final picFile = File(importPictureFrom);
    final ext = importPictureFrom.toLowerCase().split('.').last;
    final mimeType = _mimeTypeFromExtension(ext);
    mutations.add(AddPicture(PictureBlock(
      pictureType: PictureType.frontCover,
      mimeType: mimeType,
      description: '',
      width: 0,
      height: 0,
      colorDepth: 0,
      indexedColors: 0,
      data: picFile.readAsBytesSync(),
    )));
  }

  final result = await transformFlac(bytes, mutations);

  // ── Dry-run reporting ──────────────────────────────────────────────────

  if (dryRun) {
    final plan = result.plan;
    if (jsonMode) {
      stdout.writeln(jsonEncode({
        'file': filePath,
        'dryRun': true,
        'mutations': mutations.length,
        'originalMetadataSize': plan.originalMetadataRegionSize,
        'transformedMetadataSize': plan.transformedMetadataRegionSize,
        'fitsExistingRegion': plan.fitsExistingRegion,
        'requiresFullRewrite': plan.requiresFullRewrite,
      }));
    } else if (!quiet) {
      stdout.writeln('${prefix}Dry run — ${mutations.length} mutation(s)');
      stdout.writeln(
          '${prefix}  Original metadata size: ${plan.originalMetadataRegionSize}');
      stdout.writeln(
          '${prefix}  New metadata size: ${plan.transformedMetadataRegionSize}');
      stdout.writeln(
          '${prefix}  Fits existing region: ${plan.fitsExistingRegion}');
      stdout.writeln(
          '${prefix}  Requires full rewrite: ${plan.requiresFullRewrite}');
    }
    return;
  }

  // ── Write result ───────────────────────────────────────────────────────

  file.writeAsBytesSync(result.bytes);

  if (preserveModtime && originalModTime != null) {
    if (!Platform.isWindows) {
      final ts = originalModTime
          .toIso8601String()
          .replaceAll('T', ' ')
          .substring(0, 19);
      await Process.run('touch', ['-d', ts, filePath]);
    }
  }

  if (jsonMode) {
    stdout.writeln(jsonEncode({
      'file': filePath,
      'success': true,
      'operation': 'write',
      'mutations': mutations.length,
    }));
  }
}

void _writeFileError(
  String filePath,
  String message,
  String type, {
  required bool jsonMode,
}) {
  if (jsonMode) {
    stderr.writeln(jsonEncode({
      'file': filePath,
      'error': message,
      'type': type,
    }));
  } else {
    stderr.writeln('$filePath: $message');
  }
}

void _printMetadata(FlacMetadataDocument doc, String prefix) {
  final si = doc.streamInfo;
  stdout.writeln('${prefix}STREAMINFO:');
  stdout.writeln('$prefix  min_blocksize: ${si.minBlockSize}');
  stdout.writeln('$prefix  max_blocksize: ${si.maxBlockSize}');
  stdout.writeln('$prefix  min_framesize: ${si.minFrameSize}');
  stdout.writeln('$prefix  max_framesize: ${si.maxFrameSize}');
  stdout.writeln('$prefix  sample_rate: ${si.sampleRate}');
  stdout.writeln('$prefix  channels: ${si.channelCount}');
  stdout.writeln('$prefix  bits_per_sample: ${si.bitsPerSample}');
  stdout.writeln('$prefix  total_samples: ${si.totalSamples}');
  final md5Hex = si.md5Signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  stdout.writeln('$prefix  md5sum: $md5Hex');

  final vc = doc.vorbisComment;
  if (vc != null) {
    stdout.writeln('${prefix}VORBIS_COMMENT:');
    stdout.writeln(
        '$prefix  vendor_string: ${vc.comments.vendorString}');
    for (final entry in vc.comments.entries) {
      stdout.writeln('$prefix  ${entry.key}=${entry.value}');
    }
  }

  final pictures = doc.pictures;
  for (var i = 0; i < pictures.length; i++) {
    final pic = pictures[i];
    stdout.writeln('${prefix}PICTURE[$i]:');
    stdout.writeln('$prefix  type: ${pic.pictureType.code}');
    stdout.writeln('$prefix  mime_type: ${pic.mimeType}');
    stdout.writeln('$prefix  description: ${pic.description}');
    stdout.writeln('$prefix  width: ${pic.width}');
    stdout.writeln('$prefix  height: ${pic.height}');
    stdout.writeln('$prefix  color_depth: ${pic.colorDepth}');
    stdout.writeln('$prefix  data_length: ${pic.data.length}');
  }
}

Map<String, dynamic> _metadataToJson(
    FlacMetadataDocument doc, String filePath) {
  final si = doc.streamInfo;
  final md5Hex = si.md5Signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  final result = <String, dynamic>{
    'file': filePath,
    'streamInfo': {
      'minBlockSize': si.minBlockSize,
      'maxBlockSize': si.maxBlockSize,
      'minFrameSize': si.minFrameSize,
      'maxFrameSize': si.maxFrameSize,
      'sampleRate': si.sampleRate,
      'channels': si.channelCount,
      'bitsPerSample': si.bitsPerSample,
      'totalSamples': si.totalSamples,
      'md5sum': md5Hex,
    },
  };

  final vc = doc.vorbisComment;
  if (vc != null) {
    final tags = <String, List<String>>{};
    for (final entry in vc.comments.entries) {
      tags.putIfAbsent(entry.key, () => []).add(entry.value);
    }
    result['vorbisComment'] = {
      'vendorString': vc.comments.vendorString,
      'tags': tags,
    };
  }

  if (doc.pictures.isNotEmpty) {
    result['pictures'] = doc.pictures
        .map((p) => {
              'type': p.pictureType.code,
              'mimeType': p.mimeType,
              'description': p.description,
              'width': p.width,
              'height': p.height,
              'colorDepth': p.colorDepth,
              'dataLength': p.data.length,
            })
        .toList();
  }

  return result;
}

String _mimeTypeFromExtension(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}
```

- [ ] **Step 4: Run CLI tests**

Run: `dart test test/cli_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run full test suite**

Run: `dart test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add bin/metaflac.dart test/cli_test.dart
git commit -m "feat: add JSON output, dry-run, batch error handling, exit codes to CLI"
```

---

## Task 5: Run Analyser and Final Verification

**Files:** None new — verification only.

- [ ] **Step 1: Run dart analyze**

Run: `dart analyze`
Expected: No issues.

- [ ] **Step 2: Run full test suite**

Run: `dart test`
Expected: All tests PASS (existing + new).

- [ ] **Step 3: Fix any issues found**

Address any analyser warnings or test failures.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address analyser warnings and test issues"
```

---

## Verification

After all tasks are complete:

1. **Transform streaming**: `dart test test/stream_rewriter_test.dart` — all 7 tests pass
2. **Document API**: `dart test test/document_api_test.dart` — all 6 tests pass
3. **CLI**: `dart test test/cli_test.dart` — all tests pass
4. **No regressions**: `dart test` — all tests pass (original 115 + new tests)
5. **Static analysis**: `dart analyze` — no issues
6. **Manual CLI smoke test**:
   - Create a test FLAC: use the fixture builder in a script or an actual FLAC file
   - `dart run bin/metaflac.dart --list --json <file.flac>` — valid JSON output
   - `dart run bin/metaflac.dart --set-tag=ARTIST=Test --dry-run <file.flac>` — reports plan, file unchanged
   - `dart run bin/metaflac.dart --list bad.flac good.flac --continue-on-error` — processes both, exits 1
   - `dart run bin/metaflac.dart --set-tag=ARTIST=Test --quiet <file.flac>` — no stdout output
