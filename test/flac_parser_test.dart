import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

Uint8List buildMinimalFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 1000,
}) {
  final streamInfo = Uint8List(34);
  streamInfo[0] = 0;
  streamInfo[1] = 16;
  streamInfo[2] = 1;
  streamInfo[3] = 0;

  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;

  streamInfo[10] = (sr >> 12) & 0xFF;
  streamInfo[11] = (sr >> 4) & 0xFF;
  streamInfo[12] = ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  streamInfo[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  streamInfo[14] = (ts >> 24) & 0xFF;
  streamInfo[15] = (ts >> 16) & 0xFF;
  streamInfo[16] = (ts >> 8) & 0xFF;
  streamInfo[17] = ts & 0xFF;

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);
  out.addByte(0x80); // isLast | type 0
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(streamInfo);

  return out.toBytes();
}

Uint8List buildFlacWithVorbisComment() {
  final base = buildMinimalFlac();

  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'test_vendor',
      entries: [
        VorbisCommentEntry(key: 'TITLE', value: 'Test Song'),
        VorbisCommentEntry(key: 'ARTIST', value: 'Test Artist'),
      ],
    ),
  );
  final vcData = vc.toPayloadBytes();

  final out = BytesBuilder();
  out.add(base.sublist(0, 4));

  // STREAMINFO block (not last)
  out.addByte(0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(base.sublist(8, 42));

  // VORBIS_COMMENT block (last)
  out.addByte(0x80 | 0x04);
  out.addByte((vcData.length >> 16) & 0xFF);
  out.addByte((vcData.length >> 8) & 0xFF);
  out.addByte(vcData.length & 0xFF);
  out.add(vcData);

  return out.toBytes();
}

void main() {
  group('FlacParser', () {
    test('parses minimal valid FLAC', () async {
      final bytes = buildMinimalFlac();
      final stream = Stream.value(bytes.toList());
      final doc = await FlacParser.parse(stream);
      expect(doc.streamInfo.sampleRate, equals(44100));
      expect(doc.streamInfo.channelCount, equals(2));
      expect(doc.streamInfo.bitsPerSample, equals(16));
      expect(doc.streamInfo.totalSamples, equals(1000));
    });

    test('throws InvalidFlacException for invalid magic', () async {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      final stream = Stream.value(bytes.toList());
      expect(
        () => FlacParser.parse(stream),
        throwsA(isA<InvalidFlacException>()),
      );
    });

    test('throws InvalidFlacException for too-short data', () async {
      final bytes = Uint8List.fromList([0x66, 0x4C]);
      final stream = Stream.value(bytes.toList());
      expect(
        () => FlacParser.parse(stream),
        throwsA(isA<InvalidFlacException>()),
      );
    });

    test('parses STREAMINFO fields', () async {
      final bytes = buildMinimalFlac(
        sampleRate: 48000,
        channels: 1,
        bitsPerSample: 24,
        totalSamples: 9999,
      );
      final stream = Stream.value(bytes.toList());
      final doc = await FlacParser.parse(stream);
      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(doc.streamInfo.channelCount, equals(1));
      expect(doc.streamInfo.bitsPerSample, equals(24));
      expect(doc.streamInfo.totalSamples, equals(9999));
    });

    test('parses VORBIS_COMMENT', () async {
      final bytes = buildFlacWithVorbisComment();
      final stream = Stream.value(bytes.toList());
      final doc = await FlacParser.parse(stream);
      expect(doc.vorbisComment, isNotNull);
      expect(doc.vorbisComment!.comments.vendorString, equals('test_vendor'));
      expect(
          doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Test Song']));
      expect(doc.vorbisComment!.comments.valuesOf('ARTIST'),
          equals(['Test Artist']));
    });

    test('md5 signature is 16 bytes of zeros for test FLAC', () async {
      final bytes = buildMinimalFlac();
      final stream = Stream.value(bytes.toList());
      final doc = await FlacParser.parse(stream);
      expect(doc.streamInfo.md5Signature.length, equals(16));
      expect(doc.streamInfo.md5Signature.every((b) => b == 0), isTrue);
    });
  });
}
