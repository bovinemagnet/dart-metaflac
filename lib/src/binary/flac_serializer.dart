import 'dart:typed_data';

import '../model/flac_metadata_block.dart';
import 'byte_writer.dart';
import 'flac_constants.dart';

class FlacSerializer {
  FlacSerializer._();

  static Uint8List serialize(
      List<FlacMetadataBlock> blocks, Uint8List audioData) {
    final writer = _serializeBlocks(blocks);
    writer.writeBytes(audioData);
    return writer.toBytes();
  }

  /// Serialises only the metadata region (fLaC marker + metadata blocks).
  ///
  /// Unlike [serialize], no audio data is appended. This is used by
  /// [StreamRewriter] where audio is streamed separately.
  static Uint8List serializeMetadataOnly(List<FlacMetadataBlock> blocks) {
    return _serializeBlocks(blocks).toBytes();
  }

  /// Writes the fLaC marker and all metadata blocks to a [ByteWriter].
  static ByteWriter _serializeBlocks(List<FlacMetadataBlock> blocks) {
    final writer = ByteWriter();

    // fLaC marker
    writer.writeUint8(flacMagicByte0);
    writer.writeUint8(flacMagicByte1);
    writer.writeUint8(flacMagicByte2);
    writer.writeUint8(flacMagicByte3);

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isLast = i == blocks.length - 1;
      final payload = block.toPayloadBytes();
      final typeByte = block.type.code & 0x7F;
      writer.writeUint8(isLast ? (0x80 | typeByte) : typeByte);
      writer.writeUint24(payload.length);
      writer.writeBytes(payload);
    }

    return writer;
  }
}
