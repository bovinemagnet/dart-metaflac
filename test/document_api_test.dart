/// Tests for FlacMetadataDocument convenience API:
/// readFromBytes, readFromStream, toBytes.
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import 'test_fixtures.dart';

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('FlacMetadataDocument.readFromBytes', () {
    test('parses correctly and exposes streamInfo', () {
      final bytes = buildFlac(sampleRate: 48000);
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      expect(doc.streamInfo.sampleRate, equals(48000));
    });
  });

  group('FlacMetadataDocument.readFromStream', () {
    test('parses correctly from a byte stream', () async {
      final bytes = buildFlac(sampleRate: 96000);
      final stream = Stream.fromIterable([bytes.toList()]);
      final doc = await FlacMetadataDocument.readFromStream(stream);
      expect(doc.streamInfo.sampleRate, equals(96000));
    });
  });

  group('FlacMetadataDocument.toBytes', () {
    test('round-trips correctly (parse, toBytes, re-parse)', () {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Hello')],
          ),
        ),
      );
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      final outBytes = doc.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        reparsed.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Hello']),
      );
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
      final updated = doc.edit((e) => e..setTag('ARTIST', ['New Artist']));
      final outBytes = updated.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        reparsed.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['New Artist']),
      );
    });

    test('preserves audio data (0xFF 0xF8 sync bytes present)', () {
      final bytes = buildFlac(paddingSize: 256);
      final doc = FlacMetadataDocument.readFromBytes(bytes);
      final outBytes = doc.toBytes();
      var found = false;
      for (var i = 0; i < outBytes.length - 1; i++) {
        if (outBytes[i] == 0xFF && outBytes[i + 1] == 0xF8) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Audio sync bytes must be preserved');
    });

    test('throws StateError when no sourceBytes available', () {
      final doc = FlacMetadataDocument(
        blocks: [
          StreamInfoBlock(
            minBlockSize: 0,
            maxBlockSize: 4096,
            minFrameSize: 0,
            maxFrameSize: 0,
            sampleRate: 44100,
            channelCount: 2,
            bitsPerSample: 16,
            totalSamples: 0,
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
