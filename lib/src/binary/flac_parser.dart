import 'dart:convert';
import 'dart:typed_data';

import '../error/exceptions.dart';
import '../model/application_block.dart';
import '../model/cue_sheet_block.dart';
import '../model/flac_metadata_block.dart';
import '../model/flac_metadata_document.dart';
import '../model/padding_block.dart';
import '../model/picture_block.dart';
import '../model/picture_type.dart';
import '../model/seek_table_block.dart';
import '../model/stream_info_block.dart';
import '../model/unknown_block.dart';
import '../model/vorbis_comment_block.dart';
import '../model/vorbis_comments.dart';
import 'byte_reader.dart';
import 'flac_block_header.dart';
import 'flac_constants.dart';

/// Parser that reads raw FLAC bytes into a [FlacMetadataDocument].
///
/// All public entry points are static factory methods. The class cannot be
/// instantiated directly.
///
/// Supports both in-memory parsing via [parseBytes] and streaming parsing via
/// [parse]. All standard FLAC metadata block types (0--6) are decoded into
/// their corresponding model objects; unknown block types are preserved as
/// [UnknownBlock] instances so they survive round-trips.
///
/// Throws [InvalidFlacException] if the data does not begin with the FLAC
/// magic marker or is missing a STREAMINFO block.
/// Throws [MalformedMetadataException] if a block header declares a payload
/// length that exceeds the remaining data.
class FlacParser {
  FlacParser._();

  /// Parse a FLAC stream into a [FlacMetadataDocument].
  ///
  /// Collect all bytes from [stream] into memory first, then delegate to
  /// [parseBytes]. For large files where only metadata is needed, consider
  /// using the streaming transform API instead.
  ///
  /// Throws [InvalidFlacException] if the data is not a valid FLAC stream.
  /// Throws [MalformedMetadataException] if any metadata block is malformed.
  static Future<FlacMetadataDocument> parse(
      Stream<List<int>> stream) async {
    final bytes = await _collectBytes(stream);
    return parseBytes(bytes);
  }

  /// Parse a FLAC byte buffer into a [FlacMetadataDocument].
  ///
  /// Validate the four-byte FLAC magic marker, then read each metadata block
  /// header and payload sequentially. The resulting document records the byte
  /// offset where audio data begins so that serialisation can reconstruct the
  /// full file.
  ///
  /// Throws [InvalidFlacException] if [bytes] is too short, lacks a valid
  /// FLAC marker, or contains no STREAMINFO block.
  /// Throws [MalformedMetadataException] if a metadata block extends beyond
  /// the available data.
  static FlacMetadataDocument parseBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw InvalidFlacException('File too short to be a FLAC file');
    }
    if (bytes[0] != flacMagicByte0 ||
        bytes[1] != flacMagicByte1 ||
        bytes[2] != flacMagicByte2 ||
        bytes[3] != flacMagicByte3) {
      throw InvalidFlacException('Invalid FLAC marker');
    }

    final reader = ByteReader(bytes);
    reader.skip(4); // consume fLaC marker

    final blocks = <FlacMetadataBlock>[];

    while (reader.remaining >= flacMetadataHeaderSize) {
      final header = _readBlockHeader(reader);
      if (reader.remaining < header.payloadLength) {
        throw MalformedMetadataException(
          'Block extends beyond file: typeCode=${header.typeCode}, '
          'payloadLength=${header.payloadLength}, '
          'remaining=${reader.remaining}',
        );
      }

      final payloadStart = reader.offset;
      final block = _parseBlock(header, reader, bytes);
      blocks.add(block);

      // Ensure reader consumed exactly payloadLength bytes.
      final consumed = reader.offset - payloadStart;
      if (consumed < header.payloadLength) {
        reader.skip(header.payloadLength - consumed);
      }

      if (header.isLast) break;
    }

    if (!blocks.any((b) => b is StreamInfoBlock)) {
      throw InvalidFlacException('No STREAMINFO block found');
    }

    final audioDataOffset = reader.offset;
    return FlacMetadataDocument(
      blocks: blocks,
      audioDataOffset: audioDataOffset,
      sourceMetadataRegionLength: audioDataOffset,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static FlacBlockHeader _readBlockHeader(ByteReader reader) {
    final headerByte = reader.readUint8();
    final isLast = (headerByte & 0x80) != 0;
    final typeCode = headerByte & 0x7F;
    final payloadLength = reader.readUint24();
    return FlacBlockHeader(
        isLast: isLast, typeCode: typeCode, payloadLength: payloadLength);
  }

  static FlacMetadataBlock _parseBlock(
    FlacBlockHeader header,
    ByteReader reader,
    Uint8List source,
  ) {
    switch (header.typeCode) {
      case 0:
        return _parseStreamInfo(reader, header.payloadLength);
      case 1:
        return _parsePadding(reader, header.payloadLength);
      case 2:
        return _parseApplication(reader, header.payloadLength);
      case 3:
        return _parseSeekTable(reader, header.payloadLength);
      case 4:
        return _parseVorbisComment(reader, header.payloadLength);
      case 5:
        return _parseCueSheet(reader, header.payloadLength, source);
      case 6:
        return _parsePicture(reader, header.payloadLength);
      default:
        return _parseUnknown(reader, header.typeCode, header.payloadLength);
    }
  }

  static StreamInfoBlock _parseStreamInfo(
      ByteReader reader, int payloadLength) {
    if (payloadLength < streamInfoPayloadLength) {
      throw MalformedMetadataException(
          'STREAMINFO block too short: $payloadLength');
    }
    final minBlockSize = reader.readUint16BE();
    final maxBlockSize = reader.readUint16BE();
    final minFrameSize = reader.readUint24();
    final maxFrameSize = reader.readUint24();

    final b10 = reader.readUint8();
    final b11 = reader.readUint8();
    final b12 = reader.readUint8();
    final b13 = reader.readUint8();
    final b14 = reader.readUint8();
    final b15 = reader.readUint8();
    final b16 = reader.readUint8();
    final b17 = reader.readUint8();

    final sampleRate = (b10 << 12) | (b11 << 4) | (b12 >> 4);
    final channelCount = ((b12 >> 1) & 0x07) + 1;
    final bitsPerSample = (((b12 & 0x01) << 4) | (b13 >> 4)) + 1;
    final totalSamples = ((b13 & 0x0F) << 32) |
        (b14 << 24) |
        (b15 << 16) |
        (b16 << 8) |
        b17;

    final md5 = reader.readBytes(16);

    return StreamInfoBlock(
      minBlockSize: minBlockSize,
      maxBlockSize: maxBlockSize,
      minFrameSize: minFrameSize,
      maxFrameSize: maxFrameSize,
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
      md5Signature: md5,
    );
  }

  static PaddingBlock _parsePadding(ByteReader reader, int payloadLength) {
    reader.skip(payloadLength);
    return PaddingBlock(payloadLength);
  }

  static ApplicationBlock _parseApplication(
      ByteReader reader, int payloadLength) {
    final appId = reader.readBytes(4);
    final data = reader.readBytes(payloadLength - 4);
    return ApplicationBlock(applicationId: appId, data: data);
  }

  static SeekTableBlock _parseSeekTable(
      ByteReader reader, int payloadLength) {
    final count = payloadLength ~/ 18;
    final points = <SeekPoint>[];
    for (var i = 0; i < count; i++) {
      final sampleHi = reader.readUint32BE();
      final sampleLo = reader.readUint32BE();
      final offsetHi = reader.readUint32BE();
      final offsetLo = reader.readUint32BE();
      final frameSamples = reader.readUint16BE();
      points.add(SeekPoint(
        sampleNumber: (sampleHi << 32) | sampleLo,
        offset: (offsetHi << 32) | offsetLo,
        frameSamples: frameSamples,
      ));
    }
    return SeekTableBlock(points: points);
  }

  static VorbisCommentBlock _parseVorbisComment(
      ByteReader reader, int payloadLength) {
    final vendorLength = reader.readUint32LE();
    final vendorBytes = reader.readBytes(vendorLength);
    final vendorString = utf8.decode(vendorBytes);
    final commentCount = reader.readUint32LE();
    final entries = <VorbisCommentEntry>[];
    for (var i = 0; i < commentCount; i++) {
      final len = reader.readUint32LE();
      final commentStr = utf8.decode(reader.readBytes(len));
      final eqIdx = commentStr.indexOf('=');
      if (eqIdx >= 0) {
        entries.add(VorbisCommentEntry(
          key: commentStr.substring(0, eqIdx).toUpperCase(),
          value: commentStr.substring(eqIdx + 1),
        ));
      }
    }
    return VorbisCommentBlock(
      comments: VorbisComments(
          vendorString: vendorString, entries: entries),
    );
  }

  static CueSheetBlock _parseCueSheet(
      ByteReader reader, int payloadLength, Uint8List source) {
    // Capture raw bytes for round-trip fidelity.
    final startOffset = reader.offset;
    final rawPayload =
        Uint8List.sublistView(source, startOffset, startOffset + payloadLength);
    reader.skip(payloadLength);

    // Minimal parse for the public model fields.
    final rawReader = ByteReader(rawPayload);
    final mcnBytes = rawReader.readBytes(128);
    final mcn = String.fromCharCodes(
        mcnBytes.takeWhile((b) => b != 0));
    final leadInHi = rawReader.readUint32BE();
    final leadInLo = rawReader.readUint32BE();
    final leadInSamples = (leadInHi << 32) | leadInLo;
    final flagByte = rawReader.readUint8();
    final isCd = (flagByte & 0x80) != 0;
    // 258 reserved bytes + 1 track count
    rawReader.skip(258);
    final trackCount = rawReader.readUint8();
    final tracks = <CueSheetTrack>[];
    for (var i = 0; i < trackCount; i++) {
      final offsetHi = rawReader.readUint32BE();
      final offsetLo = rawReader.readUint32BE();
      final trackOffset = (offsetHi << 32) | offsetLo;
      final number = rawReader.readUint8();
      final isrcBytes = rawReader.readBytes(12);
      final isrc =
          String.fromCharCodes(isrcBytes.takeWhile((b) => b != 0));
      rawReader.skip(14); // flags + reserved
      final indexCount = rawReader.readUint8();
      rawReader.skip(3); // reserved
      rawReader.skip(indexCount * 12);
      tracks.add(CueSheetTrack(
          offset: trackOffset, number: number, isrc: isrc));
    }

    return CueSheetBlock(
      mediaCatalogNumber: mcn,
      leadInSamples: leadInSamples,
      isCd: isCd,
      tracks: tracks,
      rawPayload: rawPayload,
    );
  }

  static PictureBlock _parsePicture(ByteReader reader, int payloadLength) {
    final typeCode = reader.readUint32BE();
    final mimeLen = reader.readUint32BE();
    final mimeType = utf8.decode(reader.readBytes(mimeLen));
    final descLen = reader.readUint32BE();
    final description = utf8.decode(reader.readBytes(descLen));
    final width = reader.readUint32BE();
    final height = reader.readUint32BE();
    final colorDepth = reader.readUint32BE();
    final indexedColors = reader.readUint32BE();
    final dataLen = reader.readUint32BE();
    final data = reader.readBytes(dataLen);
    return PictureBlock(
      pictureType: PictureType.fromCode(typeCode),
      mimeType: mimeType,
      description: description,
      width: width,
      height: height,
      colorDepth: colorDepth,
      indexedColors: indexedColors,
      data: data,
    );
  }

  static UnknownBlock _parseUnknown(
      ByteReader reader, int typeCode, int payloadLength) {
    final payload = reader.readBytes(payloadLength);
    return UnknownBlock(rawTypeCode: typeCode, rawPayload: payload);
  }

  /// Collect all chunks from a byte [stream] into a single [Uint8List].
  ///
  /// This is a convenience wrapper exposed for use by other components that
  /// need to buffer an entire stream before processing.
  static Future<Uint8List> collectBytes(Stream<List<int>> stream) =>
      _collectBytes(stream);

  static Future<Uint8List> _collectBytes(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final total = chunks.fold<int>(0, (s, c) => s + c.length);
    final result = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}
