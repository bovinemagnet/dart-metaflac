import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Minimal in-memory FLAC fixture used across mutation tests.
Uint8List buildFlacFixture({int paddingSize = 512}) {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0; // 2ch, 16bps hi
  siData[13] = (15 << 4); // 16bps lo

  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'fixture_vendor',
      entries: [
        VorbisCommentEntry(key: 'TITLE', value: 'Original Title'),
        VorbisCommentEntry(key: 'ARTIST', value: 'Original Artist'),
      ],
    ),
  );
  final vcData = vc.toPayloadBytes();

  final imgData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  final pic = PictureBlock(
    pictureType: PictureType.frontCover,
    mimeType: 'image/jpeg',
    description: 'Cover',
    width: 300,
    height: 300,
    colorDepth: 24,
    indexedColors: 0,
    data: imgData,
  );
  final picData = pic.toPayloadBytes();

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  // STREAMINFO
  out.addByte(0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  // VORBIS_COMMENT
  out.addByte(0x04);
  out.addByte((vcData.length >> 16) & 0xFF);
  out.addByte((vcData.length >> 8) & 0xFF);
  out.addByte(vcData.length & 0xFF);
  out.add(vcData);

  // PICTURE
  out.addByte(0x06);
  out.addByte((picData.length >> 16) & 0xFF);
  out.addByte((picData.length >> 8) & 0xFF);
  out.addByte(picData.length & 0xFF);
  out.add(picData);

  // PADDING (last)
  out.addByte(0x80 | 0x01);
  out.addByte((paddingSize >> 16) & 0xFF);
  out.addByte((paddingSize >> 8) & 0xFF);
  out.addByte(paddingSize & 0xFF);
  out.add(Uint8List(paddingSize));

  // Fake audio data
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(128));

  return out.toBytes();
}

/// FLAC fixture with padding scattered through the block list:
/// STREAMINFO, PADDING(100), PADDING(200), VORBIS_COMMENT, PADDING(300).
Uint8List buildScatteredPaddingFixture() {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0; // 2ch, 16bps hi
  siData[13] = (15 << 4); // 16bps lo

  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'fixture_vendor',
      entries: [VorbisCommentEntry(key: 'TITLE', value: 'Padded Title')],
    ),
  );
  final vcData = vc.toPayloadBytes();

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  // STREAMINFO
  out.addByte(0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  // PADDING (100) and PADDING (200), adjacent
  for (final size in [100, 200]) {
    out.addByte(0x01);
    out.addByte((size >> 16) & 0xFF);
    out.addByte((size >> 8) & 0xFF);
    out.addByte(size & 0xFF);
    out.add(Uint8List(size));
  }

  // VORBIS_COMMENT
  out.addByte(0x04);
  out.addByte((vcData.length >> 16) & 0xFF);
  out.addByte((vcData.length >> 8) & 0xFF);
  out.addByte(vcData.length & 0xFF);
  out.add(vcData);

  // PADDING (300, last)
  out.addByte(0x80 | 0x01);
  out.addByte((300 >> 16) & 0xFF);
  out.addByte((300 >> 8) & 0xFF);
  out.addByte(300 & 0xFF);
  out.add(Uint8List(300));

  // Fake audio data
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(128));

  return out.toBytes();
}

void main() {
  group('MetadataMutation types', () {
    test('SetTag stores key and values', () {
      const m = SetTag('TITLE', ['A', 'B']);
      expect(m.key, equals('TITLE'));
      expect(m.values, equals(['A', 'B']));
    });

    test('AddTag stores key and single value', () {
      const m = AddTag('ARTIST', 'Band');
      expect(m.key, equals('ARTIST'));
      expect(m.value, equals('Band'));
    });

    test('RemoveTag stores key', () {
      const m = RemoveTag('COMMENT');
      expect(m.key, equals('COMMENT'));
    });

    test('RemoveExactTagValue stores key and value', () {
      const m = RemoveExactTagValue('ARTIST', 'Old Name');
      expect(m.key, equals('ARTIST'));
      expect(m.value, equals('Old Name'));
    });

    test('SetPadding stores size', () {
      const m = SetPadding(4096);
      expect(m.size, equals(4096));
    });

    test('AddPicture stores picture block', () {
      final pic = PictureBlock(
        pictureType: PictureType.backCover,
        mimeType: 'image/png',
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: Uint8List(1),
      );
      final m = AddPicture(pic);
      expect(m.picture.pictureType, equals(PictureType.backCover));
    });

    test('ReplacePictureByType stores type and replacement', () {
      final replacement = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/jpeg',
        description: '',
        width: 600,
        height: 600,
        colorDepth: 24,
        indexedColors: 0,
        data: Uint8List(4),
      );
      final m = ReplacePictureByType(
        pictureType: PictureType.frontCover,
        replacement: replacement,
      );
      expect(m.pictureType, equals(PictureType.frontCover));
      expect(m.replacement.width, equals(600));
    });

    test('RemovePictureByType stores picture type', () {
      const m = RemovePictureByType(PictureType.backCover);
      expect(m.pictureType, equals(PictureType.backCover));
    });

    test('ClearTags and RemoveAllPictures are const constructable', () {
      const ct = ClearTags();
      const rap = RemoveAllPictures();
      expect(ct, isA<MetadataMutation>());
      expect(rap, isA<MetadataMutation>());
    });

    test('MergeAdjacentPadding and SortPadding are const constructable', () {
      const mp = MergeAdjacentPadding();
      const sp = SortPadding();
      expect(mp, isA<MetadataMutation>());
      expect(sp, isA<MetadataMutation>());
    });
  });

  group('padding merge and sort mutations', () {
    late FlacMetadataDocument doc;

    setUp(() {
      doc = FlacMetadataDocument.readFromBytes(buildScatteredPaddingFixture());
    });

    test('fixture has the expected scattered padding layout', () {
      expect(doc.blocks.length, equals(5));
      expect(doc.blocks[0], isA<StreamInfoBlock>());
      expect(doc.blocks[1], isA<PaddingBlock>());
      expect(doc.blocks[2], isA<PaddingBlock>());
      expect(doc.blocks[3], isA<VorbisCommentBlock>());
      expect(doc.blocks[4], isA<PaddingBlock>());
    });

    test('mergeAdjacentPadding coalesces adjacent padding runs', () {
      final updated = doc.edit((e) => e.mergeAdjacentPadding());
      // The two adjacent blocks merge; the absorbed block's 4-byte header
      // becomes padding, matching FLAC__metadata_chain_merge_padding.
      expect(updated.blocks.length, equals(4));
      expect(updated.blocks[0], isA<StreamInfoBlock>());
      expect(updated.blocks[1], isA<PaddingBlock>());
      expect((updated.blocks[1] as PaddingBlock).size, equals(100 + 4 + 200));
      expect(updated.blocks[2], isA<VorbisCommentBlock>());
      expect(updated.blocks[3], isA<PaddingBlock>());
      expect((updated.blocks[3] as PaddingBlock).size, equals(300));
    });

    test('mergeAdjacentPadding is a no-op with a single padding block', () {
      final single = FlacParser.parseBytes(buildFlacFixture(paddingSize: 512));
      final updated = single.edit((e) => e.mergeAdjacentPadding());
      expect(updated.blocks.length, equals(single.blocks.length));
      final padding = updated.blocks.whereType<PaddingBlock>().single;
      expect(padding.size, equals(512));
    });

    test('sortPadding moves all padding to the tail and merges into one', () {
      final updated = doc.edit((e) => e.sortPadding());
      expect(updated.blocks.length, equals(3));
      expect(updated.blocks[0], isA<StreamInfoBlock>());
      expect(updated.blocks[1], isA<VorbisCommentBlock>());
      expect(updated.blocks[2], isA<PaddingBlock>());
      // Two absorbed headers of 4 bytes each become padding.
      expect((updated.blocks[2] as PaddingBlock).size,
          equals(100 + 4 + 200 + 4 + 300));
    });

    test('sortPadding is a no-op when no padding is present', () {
      final noPadding = doc.edit((e) => e.setPadding(0));
      final updated = noPadding.edit((e) => e.sortPadding());
      expect(updated.blocks.whereType<PaddingBlock>(), isEmpty);
      expect(updated.blocks.length, equals(noPadding.blocks.length));
    });

    test('mergeAdjacentPadding survives a serialisation round-trip', () {
      final updated = doc.edit((e) => e.mergeAdjacentPadding());
      final reparsed = FlacMetadataDocument.readFromBytes(updated.toBytes());
      final padding = reparsed.blocks.whereType<PaddingBlock>().toList();
      expect(padding.length, equals(2));
      expect(padding[0].size, equals(304));
      expect(padding[1].size, equals(300));
      expect(reparsed.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['Padded Title']));
    });

    test('sortPadding survives a serialisation round-trip', () {
      final updated = doc.edit((e) => e.sortPadding());
      final reparsed = FlacMetadataDocument.readFromBytes(updated.toBytes());
      final padding = reparsed.blocks.whereType<PaddingBlock>().toList();
      expect(padding.length, equals(1));
      expect(padding.single.size, equals(608));
      expect(reparsed.blocks.last, isA<PaddingBlock>());
    });
  });

  group('FlacMetadataEditor mutations (unit)', () {
    late Uint8List flacBytes;
    late FlacMetadataDocument doc;

    setUp(() {
      flacBytes = buildFlacFixture();
      doc = FlacParser.parseBytes(flacBytes);
    });

    test('setTag replaces all values for a key', () {
      final updated = doc.edit((e) => e.setTag('TITLE', ['New Title']));
      expect(updated.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['New Title']));
    });

    test('addTag appends a value without removing existing', () {
      final updated = doc.edit((e) => e.addTag('ARTIST', 'Extra Artist'));
      final artists = updated.vorbisComment!.comments.valuesOf('ARTIST');
      expect(artists, containsAll(['Original Artist', 'Extra Artist']));
    });

    test('removeTag removes all values for key', () {
      final updated = doc.edit((e) => e.removeTag('TITLE'));
      expect(updated.vorbisComment!.comments.valuesOf('TITLE'), isEmpty);
      // Other tags must be untouched
      expect(updated.vorbisComment!.comments.valuesOf('ARTIST'),
          equals(['Original Artist']));
    });

    test('removeExactTagValue removes only the specified value', () {
      // Add a second artist first, then remove just the original
      final step1 = doc.edit((e) => e.addTag('ARTIST', 'Second Artist'));
      final step2 =
          step1.edit((e) => e.removeExactTagValue('ARTIST', 'Original Artist'));
      final artists = step2.vorbisComment!.comments.valuesOf('ARTIST');
      expect(artists, equals(['Second Artist']));
    });

    test('clearTags removes all vorbis comment entries', () {
      final updated = doc.edit((e) => e.clearTags());
      expect(updated.vorbisComment!.comments.entries, isEmpty);
    });

    test('addPicture appends a new picture', () {
      final newPic = PictureBlock(
        pictureType: PictureType.backCover,
        mimeType: 'image/png',
        description: 'Back',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      final updated = doc.edit((e) => e.addPicture(newPic));
      expect(updated.pictures.length, equals(2));
      expect(updated.pictures.last.pictureType, equals(PictureType.backCover));
    });

    test('removePictureByType removes only matching picture type', () {
      final newPic = PictureBlock(
        pictureType: PictureType.backCover,
        mimeType: 'image/png',
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: Uint8List(1),
      );
      final withTwo = doc.edit((e) => e.addPicture(newPic));
      final updated =
          withTwo.edit((e) => e.removePictureByType(PictureType.backCover));
      expect(updated.pictures.length, equals(1));
      expect(
          updated.pictures.first.pictureType, equals(PictureType.frontCover));
    });

    test('removeAllPictures removes all picture blocks', () {
      final updated = doc.edit((e) => e.removeAllPictures());
      expect(updated.pictures, isEmpty);
    });

    test('replacePictureByType replaces matching picture', () {
      final replacement = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/png',
        description: 'New Cover',
        width: 600,
        height: 600,
        colorDepth: 32,
        indexedColors: 0,
        data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      final updated = doc.edit(
        (e) => e.replacePictureByType(PictureType.frontCover, replacement),
      );
      expect(updated.pictures.length, equals(1));
      expect(updated.pictures.first.mimeType, equals('image/png'));
      expect(updated.pictures.first.description, equals('New Cover'));
    });

    test('setPadding replaces existing padding', () {
      final updated = doc.edit((e) => e.setPadding(2048));
      final paddingBlocks = updated.blocks.whereType<PaddingBlock>().toList();
      expect(paddingBlocks.length, equals(1));
      expect(paddingBlocks.first.size, equals(2048));
    });

    test('setPadding(0) removes all padding', () {
      final updated = doc.edit((e) => e.setPadding(0));
      expect(updated.blocks.whereType<PaddingBlock>(), isEmpty);
    });

    test('multiple mutations apply in sequence', () {
      final updated = doc.edit((e) {
        e.setTag('TITLE', ['Multi Updated']);
        e.addTag('GENRE', 'Rock');
        e.removeTag('ARTIST');
        e.setPadding(1024);
      });
      expect(updated.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['Multi Updated']));
      expect(
          updated.vorbisComment!.comments.valuesOf('GENRE'), equals(['Rock']));
      expect(updated.vorbisComment!.comments.valuesOf('ARTIST'), isEmpty);
      final padding = updated.blocks.whereType<PaddingBlock>().first;
      expect(padding.size, equals(1024));
    });
  });
}
