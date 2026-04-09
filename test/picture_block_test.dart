import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Encodes a [PictureBlock] into a minimal FLAC, parses it back, and
/// returns the decoded [PictureBlock].
PictureBlock roundTrip(PictureBlock block) {
  final picData = block.toPayloadBytes();
  final siData = Uint8List(34);
  final out = BytesBuilder();
  // fLaC marker
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);
  // STREAMINFO (not last)
  out.addByte(0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);
  // PICTURE (last)
  out.addByte(0x80 | 0x06);
  out.addByte((picData.length >> 16) & 0xFF);
  out.addByte((picData.length >> 8) & 0xFF);
  out.addByte(picData.length & 0xFF);
  out.add(picData);

  final doc = FlacParser.parseBytes(Uint8List.fromList(out.toBytes()));
  return doc.pictures.first;
}

void main() {
  group('PictureBlock', () {
    test('encodes and decodes basic picture block', () {
      final imgData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final block = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/jpeg',
        description: 'Front cover',
        width: 500,
        height: 500,
        colorDepth: 24,
        indexedColors: 0,
        data: imgData,
      );
      final decoded = roundTrip(block);
      expect(decoded.pictureType, equals(PictureType.frontCover));
      expect(decoded.mimeType, equals('image/jpeg'));
      expect(decoded.description, equals('Front cover'));
      expect(decoded.width, equals(500));
      expect(decoded.height, equals(500));
      expect(decoded.colorDepth, equals(24));
      expect(decoded.indexedColors, equals(0));
      expect(decoded.data, equals(imgData));
    });

    test('round-trips PNG picture block', () {
      final pngData = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final block = PictureBlock(
        pictureType: PictureType.other,
        mimeType: 'image/png',
        description: '',
        width: 100,
        height: 100,
        colorDepth: 32,
        indexedColors: 0,
        data: pngData,
      );
      final decoded = roundTrip(block);
      expect(decoded.mimeType, equals('image/png'));
      expect(decoded.data, equals(pngData));
    });

    test('round-trips empty picture data', () {
      final block = PictureBlock(
        pictureType: PictureType.other,
        mimeType: 'image/jpeg',
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: Uint8List(0),
      );
      final decoded = roundTrip(block);
      expect(decoded.data.length, equals(0));
    });

    test('handles unicode description', () {
      final block = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/jpeg',
        description: '表紙',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: Uint8List(0),
      );
      final decoded = roundTrip(block);
      expect(decoded.description, equals('表紙'));
    });

    test('various picture types', () {
      const types = [
        PictureType.other,
        PictureType.fileIcon32x32,
        PictureType.otherFileIcon,
        PictureType.frontCover,
        PictureType.backCover,
        PictureType.leafletPage,
      ];
      for (final ptype in types) {
        final block = PictureBlock(
          pictureType: ptype,
          mimeType: 'image/jpeg',
          description: '',
          width: 0,
          height: 0,
          colorDepth: 0,
          indexedColors: 0,
          data: Uint8List(1),
        );
        final decoded = roundTrip(block);
        expect(decoded.pictureType, equals(ptype));
      }
    });
  });
}
