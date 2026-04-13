import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// A single seek point within a [SeekTableBlock].
///
/// Each seek point maps a sample number to a byte offset within the audio
/// data, enabling fast random access during playback.
final class SeekPoint {
  /// Create a [SeekPoint] with the given [sampleNumber], byte [offset],
  /// and [frameSamples].
  const SeekPoint({
    required this.sampleNumber,
    required this.offset,
    required this.frameSamples,
  });

  /// The sample number of the target frame, or `0xFFFFFFFFFFFFFFFF` for a
  /// placeholder point.
  final int sampleNumber;

  /// The byte offset from the first byte of the first audio frame to the
  /// first byte of the target frame.
  final int offset;

  /// The number of samples in the target frame.
  final int frameSamples;
}

/// A FLAC seek table metadata block (type 3).
///
/// Contains an ordered list of [SeekPoint] entries that allow decoders to
/// seek to specific positions in the audio stream without scanning from
/// the beginning. Each seek point is 18 bytes in the serialised payload.
///
/// See also:
/// - [SeekPoint] for individual entries.
/// - [FlacBlockType.seekTable] for the block type code.
final class SeekTableBlock extends FlacMetadataBlock {
  /// Create a [SeekTableBlock] with the given list of seek [points].
  const SeekTableBlock({required this.points});

  /// The ordered list of seek points in this table.
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
      bd.setUint32(offset, (point.sampleNumber >> 32) & 0xFFFFFFFF, Endian.big);
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
