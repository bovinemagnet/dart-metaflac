/// Tests for StreamRewriter — single-pass stream transformation.
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/src/transform/stream_rewriter.dart';

// ─── FLAC Fixture Builder ─────────────────────────────────────────────────────

/// Builds an in-memory FLAC file with optional blocks.
///
/// [paddingSize] < 0 means no padding block.
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
  siData[12] =
      ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
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

  // Fake audio sync bytes + payload
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(200));

  return out.toBytes();
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Collects a [Stream<List<int>>] into a single [Uint8List].
Future<Uint8List> _collectStream(Stream<List<int>> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

/// Splits [bytes] into chunks of [chunkSize].
Stream<List<int>> _chunkedStream(Uint8List bytes, {int chunkSize = 64}) async* {
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = (i + chunkSize > bytes.length) ? bytes.length : i + chunkSize;
    yield bytes.sublist(i, end);
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('StreamRewriter', () {
    test('rewrites metadata and preserves audio via stream', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'vendor',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
      );
      final input = _chunkedStream(bytes, chunkSize: 64);

      final outputStream = await StreamRewriter.rewrite(
        input: input,
        mutations: [const SetTag('TITLE', ['New Title'])],
      );
      final output = await _collectStream(outputStream);

      // Verify the output parses correctly with the new tag.
      final doc = FlacParser.parseBytes(output);
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['New Title']),
      );

      // Verify audio sync bytes (0xFF 0xF8) are preserved.
      var foundSync = false;
      for (var i = 0; i < output.length - 1; i++) {
        if (output[i] == 0xFF && output[i + 1] == 0xF8) {
          foundSync = true;
          break;
        }
      }
      expect(foundSync, isTrue, reason: 'Audio sync bytes must be preserved');
    });

    test('output starts with fLaC marker', () async {
      final bytes = buildFlac(paddingSize: 256);
      final input = _chunkedStream(bytes, chunkSize: 64);

      final outputStream = await StreamRewriter.rewrite(
        input: input,
        mutations: [const AddTag('FOO', 'bar')],
      );
      final output = await _collectStream(outputStream);

      expect(output[0], equals(0x66)); // f
      expect(output[1], equals(0x4C)); // L
      expect(output[2], equals(0x61)); // a
      expect(output[3], equals(0x43)); // C
    });

    test('handles stream with no mutations (identity transform)', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Keep')],
          ),
        ),
        paddingSize: 512,
      );
      final input = _chunkedStream(bytes, chunkSize: 64);

      final outputStream = await StreamRewriter.rewrite(
        input: input,
        mutations: [],
      );
      final output = await _collectStream(outputStream);

      // Data should still be valid FLAC and preserve the tag.
      final doc = FlacParser.parseBytes(output);
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Keep']),
      );
    });

    test('applies explicit padding option', () async {
      final bytes = buildFlac(paddingSize: 512);
      final input = _chunkedStream(bytes, chunkSize: 64);

      final outputStream = await StreamRewriter.rewrite(
        input: input,
        mutations: [const AddTag('COMMENT', 'hello')],
        options: FlacTransformOptions(explicitPaddingSize: 2048),
      );
      final output = await _collectStream(outputStream);

      final doc = FlacParser.parseBytes(output);
      final padBlocks = doc.blocks.whereType<PaddingBlock>();
      expect(padBlocks.isNotEmpty, isTrue);
      expect(padBlocks.first.size, equals(2048));
    });

    test('throws on invalid FLAC stream', () async {
      final badBytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04]);
      final input = _chunkedStream(badBytes, chunkSize: 64);

      expect(
        () => StreamRewriter.rewrite(input: input, mutations: []),
        throwsA(isA<InvalidFlacException>()),
      );
    });
  });

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
}
