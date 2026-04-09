import 'dart:typed_data';
import 'models.dart';
import 'exceptions.dart';
import 'vorbis_comment_processor.dart';
import 'picture_block_processor.dart';

class FlacParser {
  static Future<FlacMetadata> parse(Stream<List<int>> stream) async {
    final bytes = await _collectBytes(stream);
    return parseBytes(bytes);
  }

  static Future<Uint8List> collectBytes(Stream<List<int>> stream) =>
      _collectBytes(stream);

  static Future<Uint8List> _collectBytes(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  static FlacMetadata parseBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FlacCorruptHeaderException('File too short to be a FLAC file');
    }
    // Verify fLaC marker
    if (bytes[0] != 0x66 || bytes[1] != 0x4C || bytes[2] != 0x61 || bytes[3] != 0x43) {
      throw const FlacCorruptHeaderException('Invalid FLAC marker');
    }

    var offset = 4;
    final allBlocks = <RawMetadataBlock>[];
    StreamInfoBlock? streamInfo;
    VorbisCommentBlock? vorbisComment;
    final pictures = <PictureBlock>[];

    while (offset + 4 <= bytes.length) {
      final headerByte = bytes[offset];
      final isLast = (headerByte & 0x80) != 0;
      final typeInt = headerByte & 0x7F;
      final length = (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;

      if (offset + length > bytes.length) {
        throw FlacCorruptHeaderException(
            'Block extends beyond file: type=$typeInt, length=$length, offset=$offset, fileSize=${bytes.length}');
      }

      final blockData = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;

      final type = MetadataBlockType.fromInt(typeInt);
      final header = MetadataBlockHeader(type: type, isLast: isLast, length: length);
      final rawBlock = RawMetadataBlock(header: header, data: blockData);
      allBlocks.add(rawBlock);

      switch (type) {
        case MetadataBlockType.streamInfo:
          streamInfo = _parseStreamInfo(blockData);
        case MetadataBlockType.vorbisComment:
          vorbisComment = VorbisCommentProcessor.decode(blockData);
        case MetadataBlockType.picture:
          pictures.add(PictureBlockProcessor.decode(blockData));
        default:
          break;
      }

      if (isLast) break;
    }

    if (streamInfo == null) {
      throw const FlacCorruptHeaderException('No STREAMINFO block found');
    }

    return FlacMetadata(
      streamInfo: streamInfo,
      vorbisComment: vorbisComment,
      pictures: pictures,
      allBlocks: allBlocks,
    );
  }

  static StreamInfoBlock _parseStreamInfo(Uint8List data) {
    if (data.length < 34) {
      throw const FlacCorruptHeaderException('STREAMINFO block too short');
    }
    final bd = ByteData.sublistView(data);
    final minBlockSize = bd.getUint16(0, Endian.big);
    final maxBlockSize = bd.getUint16(2, Endian.big);
    final minFrameSize = (data[4] << 16) | (data[5] << 8) | data[6];
    final maxFrameSize = (data[7] << 16) | (data[8] << 8) | data[9];

    final b10 = data[10];
    final b11 = data[11];
    final b12 = data[12];
    final b13 = data[13];
    final b14 = data[14];
    final b15 = data[15];
    final b16 = data[16];
    final b17 = data[17];

    final sampleRate = (b10 << 12) | (b11 << 4) | (b12 >> 4);
    final channels = ((b12 >> 1) & 0x07) + 1;
    final bitsPerSample = (((b12 & 0x01) << 4) | (b13 >> 4)) + 1;
    final totalSamples = ((b13 & 0x0F).toInt() << 32) |
        (b14 << 24) |
        (b15 << 16) |
        (b16 << 8) |
        b17;

    final md5 = Uint8List.sublistView(data, 18, 34);

    return StreamInfoBlock(
      minBlockSize: minBlockSize,
      maxBlockSize: maxBlockSize,
      minFrameSize: minFrameSize,
      maxFrameSize: maxFrameSize,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
      md5Signature: md5,
    );
  }
}
