import 'dart:typed_data';

import '../error/exceptions.dart';
import '../model/flac_metadata_block.dart';
import '../model/unknown_block.dart';
import 'byte_writer.dart';
import 'flac_constants.dart';

/// The largest payload a metadata block header can describe: the length
/// field is 24 bits wide (see RFC 9639 §8.1).
const int _maxBlockPayloadLength = 0xFFFFFF;

/// Serialiser that writes [FlacMetadataBlock] lists back to FLAC binary format.
///
/// Produces a valid FLAC byte sequence consisting of the four-byte magic
/// marker (`fLaC`), followed by each metadata block (header + payload), and
/// optionally the raw audio data. The last block in the list is automatically
/// marked with the is-last flag.
///
/// All public entry points are static methods. The class cannot be
/// instantiated directly.
class FlacSerializer {
  FlacSerializer._();

  /// Serialise metadata [blocks] and [audioData] into a complete FLAC file.
  ///
  /// The returned [Uint8List] begins with the FLAC magic marker, followed by
  /// all metadata blocks with correct headers, and ends with the raw audio
  /// data bytes.
  ///
  /// When [id3v2Prefix] is non-null it is written verbatim before the magic
  /// marker, preserving a non-standard ID3v2 tag carried by the source file.
  static Uint8List serialize(
      List<FlacMetadataBlock> blocks, Uint8List audioData,
      {Uint8List? id3v2Prefix}) {
    final writer = ByteWriter();
    if (id3v2Prefix != null && id3v2Prefix.isNotEmpty) {
      writer.writeBytes(id3v2Prefix);
    }
    _serializeBlocks(blocks, writer);
    writer.writeBytes(audioData);
    return writer.toBytes();
  }

  /// Serialise only the metadata region (fLaC marker + metadata blocks).
  ///
  /// Unlike [serialize], no audio data is appended. This is used by the
  /// internal stream rewriter, where audio is streamed separately.
  static Uint8List serializeMetadataOnly(List<FlacMetadataBlock> blocks) {
    final writer = ByteWriter();
    _serializeBlocks(blocks, writer);
    return writer.toBytes();
  }

  /// Write the fLaC marker and all metadata blocks to [writer].
  static void _serializeBlocks(
      List<FlacMetadataBlock> blocks, ByteWriter writer) {
    // fLaC marker
    writer.writeUint8(flacMagicByte0);
    writer.writeUint8(flacMagicByte1);
    writer.writeUint8(flacMagicByte2);
    writer.writeUint8(flacMagicByte3);

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isLast = i == blocks.length - 1;
      final payload = block.toPayloadBytes();
      if (payload.length > _maxBlockPayloadLength) {
        throw MalformedMetadataException(
          'Metadata block payload is ${payload.length} bytes, which exceeds '
          'the 24-bit block length limit of $_maxBlockPayloadLength bytes.',
        );
      }
      final rawCode =
          block is UnknownBlock ? block.rawTypeCode : block.type.code;
      final typeByte = rawCode & 0x7F;
      writer.writeUint8(isLast ? (0x80 | typeByte) : typeByte);
      writer.writeUint24(payload.length);
      writer.writeBytes(payload);
    }
  }
}
