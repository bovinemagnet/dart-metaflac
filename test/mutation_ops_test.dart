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
      final step2 = step1.edit(
          (e) => e.removeExactTagValue('ARTIST', 'Original Artist'));
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
      final paddingBlocks =
          updated.blocks.whereType<PaddingBlock>().toList();
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
      expect(updated.vorbisComment!.comments.valuesOf('GENRE'),
          equals(['Rock']));
      expect(updated.vorbisComment!.comments.valuesOf('ARTIST'), isEmpty);
      final padding = updated.blocks.whereType<PaddingBlock>().first;
      expect(padding.size, equals(1024));
    });
  });
}
