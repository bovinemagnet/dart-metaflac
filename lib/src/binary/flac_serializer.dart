import 'dart:typed_data';

import '../model/flac_metadata_block.dart';
import 'byte_writer.dart';

class FlacSerializer {
  FlacSerializer._();

  static Uint8List serialize(
      List<FlacMetadataBlock> blocks, Uint8List audioData) {
    final writer = ByteWriter();

    // fLaC marker
    writer.writeUint8(0x66);
    writer.writeUint8(0x4C);
    writer.writeUint8(0x61);
    writer.writeUint8(0x43);

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isLast = i == blocks.length - 1;
      final payload = block.toPayloadBytes();
      final typeByte = block.type.code & 0x7F;
      writer.writeUint8(isLast ? (0x80 | typeByte) : typeByte);
      writer.writeUint24(payload.length);
      writer.writeBytes(payload);
    }

    writer.writeBytes(audioData);
    return writer.toBytes();
  }
}
