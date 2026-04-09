import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  group('PictureBlockProcessor', () {
    test('encodes and decodes basic picture block', () {
      final imgData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final block = PictureBlock(
        pictureType: 3,
        mimeType: 'image/jpeg',
        description: 'Front cover',
        width: 500,
        height: 500,
        colorDepth: 24,
        indexedColorCount: 0,
        data: imgData,
      );
      final encoded = PictureBlockProcessor.encode(block);
      final decoded = PictureBlockProcessor.decode(encoded);
      expect(decoded.pictureType, equals(3));
      expect(decoded.mimeType, equals('image/jpeg'));
      expect(decoded.description, equals('Front cover'));
      expect(decoded.width, equals(500));
      expect(decoded.height, equals(500));
      expect(decoded.colorDepth, equals(24));
      expect(decoded.indexedColorCount, equals(0));
      expect(decoded.data, equals(imgData));
    });

    test('round-trips PNG picture block', () {
      final pngData = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final block = PictureBlock(
        pictureType: 0,
        mimeType: 'image/png',
        description: '',
        width: 100,
        height: 100,
        colorDepth: 32,
        indexedColorCount: 0,
        data: pngData,
      );
      final encoded = PictureBlockProcessor.encode(block);
      final decoded = PictureBlockProcessor.decode(encoded);
      expect(decoded.mimeType, equals('image/png'));
      expect(decoded.data, equals(pngData));
    });

    test('round-trips empty picture data', () {
      final block = PictureBlock(
        pictureType: 0,
        mimeType: 'image/jpeg',
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColorCount: 0,
        data: Uint8List(0),
      );
      final encoded = PictureBlockProcessor.encode(block);
      final decoded = PictureBlockProcessor.decode(encoded);
      expect(decoded.data.length, equals(0));
    });

    test('handles unicode description', () {
      final block = PictureBlock(
        pictureType: 3,
        mimeType: 'image/jpeg',
        description: '表紙',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColorCount: 0,
        data: Uint8List(0),
      );
      final encoded = PictureBlockProcessor.encode(block);
      final decoded = PictureBlockProcessor.decode(encoded);
      expect(decoded.description, equals('表紙'));
    });

    test('various picture types', () {
      for (final ptype in [0, 1, 2, 3, 4, 5]) {
        final block = PictureBlock(
          pictureType: ptype,
          mimeType: 'image/jpeg',
          description: '',
          width: 0,
          height: 0,
          colorDepth: 0,
          indexedColorCount: 0,
          data: Uint8List(1),
        );
        final encoded = PictureBlockProcessor.encode(block);
        final decoded = PictureBlockProcessor.decode(encoded);
        expect(decoded.pictureType, equals(ptype));
      }
    });
  });
}
