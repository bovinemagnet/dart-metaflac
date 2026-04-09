/// Tests for StreamRewriter — single-pass stream transformation.
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/src/transform/stream_rewriter.dart';

import 'test_fixtures.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
      final output = await collectStream(outputStream);

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
      final output = await collectStream(outputStream);

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
      final output = await collectStream(outputStream);

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
      final output = await collectStream(outputStream);

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
      final result = await collectStream(outputStream);
      final doc = FlacParser.parseBytes(result);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Stream Updated']));
    });

    test('transformStream from bytes source works too', () async {
      final bytes = buildFlac(paddingSize: 256);
      final transformer = FlacTransformer.fromBytes(bytes);
      final outputStream = await transformer.transformStream(
        mutations: [const AddTag('ARTIST', 'Bytes Source')],
      );
      final result = await collectStream(outputStream);
      final doc = FlacParser.parseBytes(result);
      expect(doc.vorbisComment!.comments.valuesOf('ARTIST'), equals(['Bytes Source']));
    });
  });
}
