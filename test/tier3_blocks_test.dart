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

Uint8List _fixture({int paddingSize = 512}) {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0;
  siData[13] = (15 << 4);

  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'fixture_vendor',
      entries: [
        VorbisCommentEntry(key: 'TITLE', value: 'Original Title'),
      ],
    ),
  );
  final vcData = vc.toPayloadBytes();

  final pic = PictureBlock(
    pictureType: PictureType.frontCover,
    mimeType: 'image/jpeg',
    description: 'Cover',
    width: 300,
    height: 300,
    colorDepth: 24,
    indexedColors: 0,
    data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
  );
  final picData = pic.toPayloadBytes();

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
    // VORBIS_COMMENT
    ..addByte(0x04)
    ..addByte((vcData.length >> 16) & 0xFF)
    ..addByte((vcData.length >> 8) & 0xFF)
    ..addByte(vcData.length & 0xFF)
    ..add(vcData)
    // PICTURE
    ..addByte(0x06)
    ..addByte((picData.length >> 16) & 0xFF)
    ..addByte((picData.length >> 8) & 0xFF)
    ..addByte(picData.length & 0xFF)
    ..add(picData)
    // PADDING (last)
    ..addByte(0x80 | 0x01)
    ..addByte((paddingSize >> 16) & 0xFF)
    ..addByte((paddingSize >> 8) & 0xFF)
    ..addByte(paddingSize & 0xFF)
    ..add(Uint8List(paddingSize))
    // Fake audio
    ..addByte(0xFF)
    ..addByte(0xF8)
    ..add(Uint8List(128));
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

  group('RemoveBlocksByType', () {
    test('removes all PICTURE blocks', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated =
          doc.edit((e) => e.removeBlocksByType({FlacBlockType.picture}));
      expect(updated.blocks.whereType<PictureBlock>(), isEmpty);
      expect(updated.blocks.whereType<StreamInfoBlock>().length, 1);
    });

    test('removes multiple types at once', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) => e.removeBlocksByType(
            {FlacBlockType.picture, FlacBlockType.vorbisComment},
          ));
      expect(updated.blocks.whereType<PictureBlock>(), isEmpty);
      expect(updated.blocks.whereType<VorbisCommentBlock>(), isEmpty);
    });

    test('throws when STREAMINFO is included', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      expect(
        () => doc.edit((e) =>
            e.removeBlocksByType({FlacBlockType.streamInfo})),
        throwsA(isA<FlacMetadataException>()),
      );
    });

    test('empty set is a no-op', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final original = doc.blocks.length;
      final updated = doc.edit((e) => e.removeBlocksByType({}));
      expect(updated.blocks.length, original);
    });
  });
}
