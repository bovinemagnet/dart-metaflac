/// Tests for FlacMetadataDocument convenience API:
/// readFromBytes, readFromStream, toBytes.
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

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
