import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// The mandatory STREAMINFO metadata block (type 0).
///
/// Every valid FLAC file contains exactly one [StreamInfoBlock] as the first
/// metadata block. It describes the audio stream's fundamental properties
/// such as sample rate, channel count, bit depth, and total sample count,
/// along with minimum/maximum block and frame sizes and an MD5 digest of
/// the unencoded audio data.
///
/// The payload is always exactly 34 bytes.
///
/// See also:
/// - [FlacBlockType.streamInfo] for the block type code.
/// - [FlacMetadataDocument.streamInfo] for convenient access.
final class StreamInfoBlock extends FlacMetadataBlock {
  /// Create a [StreamInfoBlock] with the given audio stream properties.
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

  /// Minimum block size (in samples) used in the stream.
  final int minBlockSize;

  /// Maximum block size (in samples) used in the stream.
  final int maxBlockSize;

  /// Minimum frame size in bytes, or 0 if unknown.
  final int minFrameSize;

  /// Maximum frame size in bytes, or 0 if unknown.
  final int maxFrameSize;

  /// Sample rate in Hz (e.g. 44100, 48000).
  final int sampleRate;

  /// Number of audio channels (1 = mono, 2 = stereo, etc.).
  final int channelCount;

  /// Bits per sample (e.g. 16, 24).
  final int bitsPerSample;

  /// Total number of inter-channel samples in the stream, or 0 if unknown.
  final int totalSamples;

  /// 16-byte MD5 signature of the unencoded audio data.
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
