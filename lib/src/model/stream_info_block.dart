import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class StreamInfoBlock extends FlacMetadataBlock {
  const StreamInfoBlock({
    required this.minBlockSize,
    required this.maxBlockSize,
    required this.minFrameSize,
    required this.maxFrameSize,
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.md5Signature,
  });

  final int minBlockSize;
  final int maxBlockSize;
  final int minFrameSize;
  final int maxFrameSize;
  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final int totalSamples;
  final Uint8List md5Signature;

  @override
  FlacBlockType get type => FlacBlockType.streamInfo;

  @override
  int get payloadLength => 34;

  @override
  Uint8List toPayloadBytes() {
    final out = Uint8List(34);
    final bd = ByteData.sublistView(out);
    bd.setUint16(0, minBlockSize, Endian.big);
    bd.setUint16(2, maxBlockSize, Endian.big);
    out[4] = (minFrameSize >> 16) & 0xFF;
    out[5] = (minFrameSize >> 8) & 0xFF;
    out[6] = minFrameSize & 0xFF;
    out[7] = (maxFrameSize >> 16) & 0xFF;
    out[8] = (maxFrameSize >> 8) & 0xFF;
    out[9] = maxFrameSize & 0xFF;
    final ch = channelCount - 1;
    final bps = bitsPerSample - 1;
    out[10] = (sampleRate >> 12) & 0xFF;
    out[11] = (sampleRate >> 4) & 0xFF;
    out[12] =
        ((sampleRate & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
    out[13] = ((bps & 0xF) << 4) | ((totalSamples >> 32) & 0xF);
    out[14] = (totalSamples >> 24) & 0xFF;
    out[15] = (totalSamples >> 16) & 0xFF;
    out[16] = (totalSamples >> 8) & 0xFF;
    out[17] = totalSamples & 0xFF;
    out.setRange(18, 34, md5Signature);
    return out;
  }
}
