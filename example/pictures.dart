/// Example: adding and removing picture blocks.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  final flacBytes = _buildMinimalFlac();
  final doc = FlacMetadataDocument.readFromBytes(flacBytes);

  print('Pictures before: ${doc.pictures.length}');

  // Add a front cover picture.
  final withCover = doc.edit((editor) {
    editor.addPicture(PictureBlock(
      pictureType: PictureType.frontCover,
      mimeType: 'image/jpeg',
      description: 'Album front cover',
      width: 500,
      height: 500,
      colorDepth: 24,
      indexedColors: 0,
      data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]), // JPEG header stub
    ));
  });

  print('Pictures after adding cover: ${withCover.pictures.length}');
  for (final pic in withCover.pictures) {
    print('  Type: ${pic.pictureType}, MIME: ${pic.mimeType}, '
        '${pic.width}x${pic.height}, ${pic.data.length} bytes');
  }

  // Add a back cover.
  final withBoth = withCover.edit((editor) {
    editor.addPicture(PictureBlock(
      pictureType: PictureType.backCover,
      mimeType: 'image/png',
      description: 'Album back cover',
      width: 300,
      height: 300,
      colorDepth: 24,
      indexedColors: 0,
      data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]), // PNG header stub
    ));
  });

  print('Pictures after adding back cover: ${withBoth.pictures.length}');

  // Remove pictures by type.
  final withoutBack = withBoth.edit((editor) {
    editor.removePictureByType(PictureType.backCover);
  });

  print('Pictures after removing back cover: ${withoutBack.pictures.length}');

  // Remove all pictures.
  final noPictures = withoutBack.edit((editor) {
    editor.removeAllPictures();
  });

  print('Pictures after removing all: ${noPictures.pictures.length}');
}

Uint8List _buildMinimalFlac() {
  final siData = Uint8List(34);
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | ((1 & 0x7) << 1) | ((15 >> 4) & 0x1);
  siData[13] = ((15 & 0xF) << 4);

  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]);
  out.add([0x80, 0x00, 0x00, 34]);
  out.add(siData);
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(200));
  return out.toBytes();
}
