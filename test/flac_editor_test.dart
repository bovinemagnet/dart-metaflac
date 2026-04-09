import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Builds a minimal in-memory FLAC file for testing.
Uint8List buildTestFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 1000,
  int paddingSize = 256,
  VorbisCommentBlock? vorbisComment,
  List<PictureBlock>? pictures,
}) {
  final siData = Uint8List(34);
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;

  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;
  siData[10] = (sr >> 12) & 0xFF;
  siData[11] = (sr >> 4) & 0xFF;
  siData[12] = ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  siData[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  siData[14] = (ts >> 24) & 0xFF;
  siData[15] = (ts >> 16) & 0xFF;
  siData[16] = (ts >> 8) & 0xFF;
  siData[17] = ts & 0xFF;

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }

  List<Uint8List>? picDataList;
  if (pictures != null && pictures.isNotEmpty) {
    picDataList = pictures.map((p) => p.toPayloadBytes()).toList();
  }

  final hasVC = vcData != null;
  final hasPics = picDataList != null && picDataList.isNotEmpty;
  // paddingSize < 0 means no padding
  final hasPadding = paddingSize >= 0;

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

  if (hasPics) {
    for (var i = 0; i < picDataList.length; i++) {
      final pd = picDataList[i];
      final picIsLast = (i == picDataList.length - 1) && !hasPadding;
      out.addByte((picIsLast ? 0x80 : 0x00) | 0x06);
      out.addByte((pd.length >> 16) & 0xFF);
      out.addByte((pd.length >> 8) & 0xFF);
      out.addByte(pd.length & 0xFF);
      out.add(pd);
    }
  }

  if (hasPadding) {
    out.addByte(0x80 | 0x01);
    out.addByte((paddingSize >> 16) & 0xFF);
    out.addByte((paddingSize >> 8) & 0xFF);
    out.addByte(paddingSize & 0xFF);
    out.add(Uint8List(paddingSize));
  }

  // fake audio frame data
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(100));

  return out.toBytes();
}

void main() {
  group('FlacMetadataEditor', () {
    test('reads metadata', () {
      final bytes = buildTestFlac(sampleRate: 44100);
      final doc = FlacParser.parseBytes(bytes);
      expect(doc.streamInfo.sampleRate, equals(44100));
    });

    test('updates vorbis comments', () {
      final bytes = buildTestFlac(
        paddingSize: 512,
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'original',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old Title')],
          ),
        ),
      );

      final doc = FlacParser.parseBytes(bytes);
      final updated = doc.edit((e) {
        e.setTag('TITLE', ['New Title']);
        e.setTag('ARTIST', ['New Artist']);
      });
      final audioData = bytes.sublist(doc.audioDataOffset);
      final updatedBytes = FlacSerializer.serialize(updated.blocks, audioData);

      final doc2 = FlacParser.parseBytes(updatedBytes);
      expect(
          doc2.vorbisComment!.comments.valuesOf('TITLE'), equals(['New Title']));
      expect(doc2.vorbisComment!.comments.valuesOf('ARTIST'),
          equals(['New Artist']));
    });

    test('updates picture blocks', () {
      final bytes = buildTestFlac(paddingSize: 512);
      final imgData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final doc = FlacParser.parseBytes(bytes);
      final updated = doc.edit((e) {
        e.addPicture(PictureBlock(
          pictureType: PictureType.frontCover,
          mimeType: 'image/jpeg',
          description: 'Cover',
          width: 500,
          height: 500,
          colorDepth: 24,
          indexedColors: 0,
          data: imgData,
        ));
      });
      final audioData = bytes.sublist(doc.audioDataOffset);
      final updatedBytes = FlacSerializer.serialize(updated.blocks, audioData);

      final doc2 = FlacParser.parseBytes(updatedBytes);
      expect(doc2.pictures.length, equals(1));
      expect(doc2.pictures.first.mimeType, equals('image/jpeg'));
      expect(doc2.pictures.first.data, equals(imgData));
    });

    test('full rewrite when no padding', () {
      final bytes = buildTestFlac(paddingSize: -1);
      final doc = FlacParser.parseBytes(bytes);
      final updated = doc.edit((e) {
        e.setTag('TITLE', ['New Song']);
      });
      final audioData = bytes.sublist(doc.audioDataOffset);
      final updatedBytes = FlacSerializer.serialize(updated.blocks, audioData);

      final doc2 = FlacParser.parseBytes(updatedBytes);
      expect(doc2.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['New Song']));
    });

    test('preserves audio data after metadata update', () {
      final bytes = buildTestFlac(paddingSize: 256);
      final doc = FlacParser.parseBytes(bytes);
      final updated = doc.edit((e) {
        e.setTag('TITLE', ['Updated']);
      });
      final audioData = bytes.sublist(doc.audioDataOffset);
      final updatedBytes = FlacSerializer.serialize(updated.blocks, audioData);

      var found = false;
      for (var i = 0; i < updatedBytes.length - 1; i++) {
        if (updatedBytes[i] == 0xFF && updatedBytes[i + 1] == 0xF8) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Audio sync bytes should be preserved');
    });
  });
}
