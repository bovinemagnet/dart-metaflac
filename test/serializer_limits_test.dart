import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import 'test_fixtures.dart';

void main() {
  group('serialiser 24-bit length limit', () {
    test('throws instead of silently truncating an oversized padding block', () {
      final doc = FlacMetadataDocument.readFromBytes(buildFlac(paddingSize: -1));
      final updated = doc.edit((e) => e.setPadding(0x1000000)); // 16 MiB + 0
      expect(
        () => updated.toBytes(),
        throwsA(isA<FlacMetadataException>()),
      );
    });

    test('throws instead of silently truncating an oversized picture block', () {
      final doc = FlacMetadataDocument.readFromBytes(buildFlac(paddingSize: -1));
      final bigPicture = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/jpeg',
        description: '',
        width: 1,
        height: 1,
        colorDepth: 24,
        indexedColors: 0,
        data: Uint8List(0x1000000),
      );
      final updated = doc.edit((e) => e.addPicture(bigPicture));
      expect(
        () => updated.toBytes(),
        throwsA(isA<FlacMetadataException>()),
      );
    });

    test('a block at exactly the 24-bit maximum still serialises', () {
      final doc = FlacMetadataDocument.readFromBytes(buildFlac(paddingSize: -1));
      final updated = doc.edit((e) => e.setPadding(0xFFFFFF)); // max
      expect(updated.toBytes(), isNotEmpty);
    });
  });
}
