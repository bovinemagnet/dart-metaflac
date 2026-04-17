import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

/// Builds a minimal FLAC containing STREAMINFO + one raw block with the
/// requested type code and payload + fake audio.
Uint8List _buildFlacWithRawBlock({
  required int typeCode,
  required Uint8List payload,
}) {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0;
  siData[13] = (15 << 4);

  final out = BytesBuilder()
    ..addByte(0x66)
    ..addByte(0x4C)
    ..addByte(0x61)
    ..addByte(0x43)
    // STREAMINFO
    ..addByte(0x00)
    ..addByte(0)
    ..addByte(0)
    ..addByte(34)
    ..add(siData)
    // Raw block with requested typeCode, last block
    ..addByte(0x80 | (typeCode & 0x7F))
    ..addByte((payload.length >> 16) & 0xFF)
    ..addByte((payload.length >> 8) & 0xFF)
    ..addByte(payload.length & 0xFF)
    ..add(payload)
    // Fake audio
    ..addByte(0xFF)
    ..addByte(0xF8)
    ..add(Uint8List(16));
  return out.toBytes();
}

void main() {
  group('UnknownBlock round-trip preserves rawTypeCode', () {
    test('type code 42 survives parse -> serialise -> parse', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytes = _buildFlacWithRawBlock(typeCode: 42, payload: payload);

      final doc = FlacParser.parseBytes(bytes);
      final unknown = doc.blocks.whereType<UnknownBlock>().single;
      expect(unknown.rawTypeCode, 42);

      final roundTripped = FlacSerializer.serialize(
        doc.blocks,
        bytes.sublist(doc.audioDataOffset),
      );
      final reparsed = FlacParser.parseBytes(roundTripped);
      final unknown2 = reparsed.blocks.whereType<UnknownBlock>().single;
      expect(unknown2.rawTypeCode, 42,
          reason: 'rawTypeCode must survive serialisation round-trip');
    });
  });
}
