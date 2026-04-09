import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class SeekPoint {
  const SeekPoint({
    required this.sampleNumber,
    required this.offset,
    required this.frameSamples,
  });
  final int sampleNumber;
  final int offset;
  final int frameSamples;
}

final class SeekTableBlock extends FlacMetadataBlock {
  const SeekTableBlock({required this.points});
  final List<SeekPoint> points;

  @override
  FlacBlockType get type => FlacBlockType.seekTable;

  @override
  int get payloadLength => points.length * 18;

  @override
  Uint8List toPayloadBytes() {
    final out = Uint8List(points.length * 18);
    final bd = ByteData.sublistView(out);
    var offset = 0;
    for (final point in points) {
      bd.setUint32(
          offset, (point.sampleNumber >> 32) & 0xFFFFFFFF, Endian.big);
      offset += 4;
      bd.setUint32(offset, point.sampleNumber & 0xFFFFFFFF, Endian.big);
      offset += 4;
      bd.setUint32(offset, (point.offset >> 32) & 0xFFFFFFFF, Endian.big);
      offset += 4;
      bd.setUint32(offset, point.offset & 0xFFFFFFFF, Endian.big);
      offset += 4;
      bd.setUint16(offset, point.frameSamples, Endian.big);
      offset += 2;
    }
    return out;
  }
}
