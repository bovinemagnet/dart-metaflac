import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

class PictureBlockProcessor {
  static PictureBlock decode(Uint8List data) {
    final bd = ByteData.sublistView(data);
    var offset = 0;

    final pictureType = bd.getUint32(offset, Endian.big);
    offset += 4;

    final mimeLength = bd.getUint32(offset, Endian.big);
    offset += 4;
    final mimeType = utf8.decode(data.sublist(offset, offset + mimeLength));
    offset += mimeLength;

    final descLength = bd.getUint32(offset, Endian.big);
    offset += 4;
    final description = utf8.decode(data.sublist(offset, offset + descLength));
    offset += descLength;

    final width = bd.getUint32(offset, Endian.big);
    offset += 4;
    final height = bd.getUint32(offset, Endian.big);
    offset += 4;
    final colorDepth = bd.getUint32(offset, Endian.big);
    offset += 4;
    final indexedColorCount = bd.getUint32(offset, Endian.big);
    offset += 4;

    final dataLength = bd.getUint32(offset, Endian.big);
    offset += 4;
    final pictureData = Uint8List.sublistView(data, offset, offset + dataLength);

    return PictureBlock(
      pictureType: pictureType,
      mimeType: mimeType,
      description: description,
      width: width,
      height: height,
      colorDepth: colorDepth,
      indexedColorCount: indexedColorCount,
      data: pictureData,
    );
  }

  static Uint8List encode(PictureBlock block) {
    final mimeBytes = utf8.encode(block.mimeType);
    final descBytes = utf8.encode(block.description);

    final totalSize = 4 + 4 + mimeBytes.length + 4 + descBytes.length +
        4 + 4 + 4 + 4 + 4 + block.data.length;

    final out = Uint8List(totalSize);
    final bd = ByteData.sublistView(out);
    var offset = 0;

    bd.setUint32(offset, block.pictureType, Endian.big);
    offset += 4;
    bd.setUint32(offset, mimeBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;
    bd.setUint32(offset, descBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + descBytes.length, descBytes);
    offset += descBytes.length;
    bd.setUint32(offset, block.width, Endian.big);
    offset += 4;
    bd.setUint32(offset, block.height, Endian.big);
    offset += 4;
    bd.setUint32(offset, block.colorDepth, Endian.big);
    offset += 4;
    bd.setUint32(offset, block.indexedColorCount, Endian.big);
    offset += 4;
    bd.setUint32(offset, block.data.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + block.data.length, block.data);

    return out;
  }
}
