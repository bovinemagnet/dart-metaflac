import 'dart:convert';
import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';
import 'picture_type.dart';

final class PictureBlock extends FlacMetadataBlock {
  const PictureBlock({
    required this.pictureType,
    required this.mimeType,
    required this.description,
    required this.width,
    required this.height,
    required this.colorDepth,
    required this.indexedColors,
    required this.data,
  });

  final PictureType pictureType;
  final String mimeType;
  final String description;
  final int width;
  final int height;
  final int colorDepth;
  final int indexedColors;
  final Uint8List data;

  @override
  FlacBlockType get type => FlacBlockType.picture;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    final mimeBytes = utf8.encode(mimeType);
    final descBytes = utf8.encode(description);
    final totalSize = 4 +
        4 +
        mimeBytes.length +
        4 +
        descBytes.length +
        4 +
        4 +
        4 +
        4 +
        4 +
        data.length;
    final out = Uint8List(totalSize);
    final bd = ByteData.sublistView(out);
    var offset = 0;
    bd.setUint32(offset, pictureType.code, Endian.big);
    offset += 4;
    bd.setUint32(offset, mimeBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;
    bd.setUint32(offset, descBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + descBytes.length, descBytes);
    offset += descBytes.length;
    bd.setUint32(offset, width, Endian.big);
    offset += 4;
    bd.setUint32(offset, height, Endian.big);
    offset += 4;
    bd.setUint32(offset, colorDepth, Endian.big);
    offset += 4;
    bd.setUint32(offset, indexedColors, Endian.big);
    offset += 4;
    bd.setUint32(offset, data.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + data.length, data);
    return out;
  }
}
