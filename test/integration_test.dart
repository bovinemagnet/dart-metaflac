/// Integration tests for FlacTransformer and the transformFlac/applyMutations
/// top-level API functions.
///
/// These tests exercise the full pipeline:
///   bytes → parse → edit → serialize → parse (verify)
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import 'test_fixtures.dart';

// ─── FlacTransformer Tests ────────────────────────────────────────────────────

void main() {
  group('FlacTransformer.fromBytes', () {
    test('readMetadata returns correct STREAMINFO', () async {
      final bytes =
          buildFlac(sampleRate: 48000, channels: 1, bitsPerSample: 24);
      final transformer = FlacTransformer.fromBytes(bytes);
      final doc = await transformer.readMetadata();
      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(doc.streamInfo.channelCount, equals(1));
      expect(doc.streamInfo.bitsPerSample, equals(24));
    });

    test('transform with SetTag returns updated bytes', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'vendor',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
      );
      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [
          const SetTag('TITLE', ['New Title'])
        ],
      );
      final doc = FlacParser.parseBytes(result.bytes);
      expect(
          doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['New Title']));
    });

    test('transform plan fitsExistingRegion is true when metadata shrinks',
        () async {
      // Build a FLAC with many large tags + padding.
      // Clearing all tags makes the VC block much smaller, so the new metadata
      // region (same PaddingBlock, smaller VC) is smaller than the original.
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'vendor',
            entries: List.generate(
              20,
              (i) => VorbisCommentEntry(
                key: 'TAG$i',
                value: 'long_value_${'x' * 50}',
              ),
            ),
          ),
        ),
        paddingSize: 256,
      );
      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [const ClearTags()],
      );
      expect(result.plan.fitsExistingRegion, isTrue);
      expect(result.plan.requiresFullRewrite, isFalse);
    });

    test('transform plan detects full rewrite when no padding', () async {
      final bytes = buildFlac(paddingSize: -1);
      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [
          const SetTag('TITLE', ['Forced Rewrite'])
        ],
      );
      // No padding means metadata grows → full rewrite
      expect(result.plan.requiresFullRewrite, isTrue);
    });

    test('transform result document has updated blocks', () async {
      final bytes = buildFlac(paddingSize: 512);
      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [
          const SetTag('ALBUM', ['Test Album'])
        ],
      );
      expect(
        result.document.vorbisComment!.comments.valuesOf('ALBUM'),
        equals(['Test Album']),
      );
    });

    test('transform with explicit padding via options', () async {
      final bytes = buildFlac(paddingSize: 512);
      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [const AddTag('COMMENT', 'hello')],
        options: FlacTransformOptions(explicitPaddingSize: 2048),
      );
      final doc = FlacParser.parseBytes(result.bytes);
      final padBlocks = doc.blocks.whereType<PaddingBlock>();
      expect(padBlocks.isNotEmpty, isTrue);
      expect(padBlocks.first.size, equals(2048));
    });
  });

  group('FlacTransformer.fromStream', () {
    test('readMetadata works from stream input', () async {
      final bytes = buildFlac(sampleRate: 44100);
      final stream = Stream.fromIterable([bytes.toList()]);
      final doc = await FlacTransformer.fromStream(stream).readMetadata();
      expect(doc.streamInfo.sampleRate, equals(44100));
    });

    test('transform via stream produces parseable output', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Stream Title')],
          ),
        ),
        paddingSize: 512,
      );
      final stream = Stream.fromIterable([bytes.toList()]);
      final result = await FlacTransformer.fromStream(stream).transform(
        mutations: [const AddTag('ARTIST', 'Stream Artist')],
      );
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['Stream Title']));
      expect(doc.vorbisComment!.comments.valuesOf('ARTIST'),
          equals(['Stream Artist']));
    });
  });

  group('transformFlac() API', () {
    test('applies SetTag mutation', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Before')],
          ),
        ),
        paddingSize: 512,
      );
      final result = await transformFlac(bytes, [
        const SetTag('TITLE', ['After']),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['After']));
    });

    test('applies ClearTags mutation', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'T'),
              VorbisCommentEntry(key: 'ARTIST', value: 'A'),
            ],
          ),
        ),
        paddingSize: 512,
      );
      final result = await transformFlac(bytes, [const ClearTags()]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.vorbisComment!.comments.entries, isEmpty);
    });

    test('applies RemoveTag mutation', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Keep'),
              VorbisCommentEntry(key: 'COMMENT', value: 'Remove this'),
            ],
          ),
        ),
        paddingSize: 256,
      );
      final result = await transformFlac(bytes, [const RemoveTag('COMMENT')]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.vorbisComment!.comments.valuesOf('COMMENT'), isEmpty);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Keep']));
    });

    test('applies AddPicture mutation', () async {
      final bytes = buildFlac(paddingSize: 2048);
      final result = await transformFlac(bytes, [
        AddPicture(makeJpeg(description: 'Added Cover')),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.pictures.length, equals(1));
      expect(doc.pictures.first.description, equals('Added Cover'));
    });

    test('applies RemoveAllPictures mutation', () async {
      final bytes = buildFlac(
        pictures: [makeJpeg(), makeJpeg(type: PictureType.backCover)],
        paddingSize: 2048,
      );
      final result = await transformFlac(bytes, [const RemoveAllPictures()]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.pictures, isEmpty);
    });

    test('applies RemovePictureByType mutation', () async {
      final bytes = buildFlac(
        pictures: [
          makeJpeg(type: PictureType.frontCover),
          makeJpeg(type: PictureType.backCover),
        ],
        paddingSize: 2048,
      );
      final result = await transformFlac(bytes, [
        const RemovePictureByType(PictureType.backCover),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.pictures.length, equals(1));
      expect(doc.pictures.first.pictureType, equals(PictureType.frontCover));
    });

    test('applies ReplacePictureByType mutation', () async {
      final bytes = buildFlac(
        pictures: [makeJpeg(type: PictureType.frontCover, width: 300)],
        paddingSize: 2048,
      );
      final newCover = PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: 'image/png',
        description: 'Replaced',
        width: 600,
        height: 600,
        colorDepth: 32,
        indexedColors: 0,
        data: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      final result = await transformFlac(bytes, [
        ReplacePictureByType(
            pictureType: PictureType.frontCover, replacement: newCover),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(doc.pictures.length, equals(1));
      expect(doc.pictures.first.mimeType, equals('image/png'));
      expect(doc.pictures.first.width, equals(600));
    });

    test('applies multiple mutations in order', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Original'),
              VorbisCommentEntry(key: 'COMMENT', value: 'Remove me'),
            ],
          ),
        ),
        paddingSize: 1024,
      );
      final result = await transformFlac(bytes, [
        const SetTag('TITLE', ['Updated']),
        const RemoveTag('COMMENT'),
        const AddTag('GENRE', 'Jazz'),
        const SetPadding(4096),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);
      expect(
          doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Updated']));
      expect(doc.vorbisComment!.comments.valuesOf('COMMENT'), isEmpty);
      expect(doc.vorbisComment!.comments.valuesOf('GENRE'), equals(['Jazz']));
      final padding = doc.blocks.whereType<PaddingBlock>().first;
      expect(padding.size, equals(4096));
    });

    test('audio data is preserved across mutations', () async {
      final bytes = buildFlac(paddingSize: 512);
      final result = await transformFlac(bytes, [
        const SetTag('TITLE', ['Audio Preserved']),
      ]);
      // Fake audio sync bytes 0xFF 0xF8 must appear in result
      var found = false;
      for (var i = 0; i < result.bytes.length - 1; i++) {
        if (result.bytes[i] == 0xFF && result.bytes[i + 1] == 0xF8) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: 'Audio sync bytes must be preserved');
    });

    test('output starts with fLaC marker', () async {
      final bytes = buildFlac(paddingSize: 256);
      final result = await transformFlac(bytes, [const AddTag('FOO', 'bar')]);
      expect(result.bytes[0], equals(0x66)); // f
      expect(result.bytes[1], equals(0x4C)); // L
      expect(result.bytes[2], equals(0x61)); // a
      expect(result.bytes[3], equals(0x43)); // C
    });

    test('transform result bytes are parseable by FlacParser', () async {
      final bytes = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'X')],
          ),
        ),
        paddingSize: 512,
      );
      final result = await transformFlac(bytes, [const AddTag('ARTIST', 'Y')]);
      // Parsing the output must not throw
      expect(() => FlacParser.parseBytes(result.bytes), returnsNormally);
    });
  });

  group('applyMutations() API', () {
    test('applies mutations from stream input', () async {
      final bytes = buildFlac(paddingSize: 512);
      final stream = Stream.fromIterable([bytes.toList()]);
      final outBytes = await applyMutations(stream, [
        const SetTag('TITLE', ['Via Stream']),
      ]);
      final doc = FlacParser.parseBytes(outBytes);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['Via Stream']));
    });
  });

  group('Full round-trip integration', () {
    test('metadata survives serialization round-trip unchanged', () async {
      final bytes = buildFlac(
        sampleRate: 96000,
        channels: 2,
        bitsPerSample: 24,
        totalSamples: 9600000,
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'round-trip-test',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Round Trip'),
              VorbisCommentEntry(key: 'ARTIST', value: 'Integration Test'),
              VorbisCommentEntry(key: 'TRACKNUMBER', value: '7'),
            ],
          ),
        ),
        pictures: [makeJpeg(description: 'Original Cover', width: 400)],
        paddingSize: 1024,
      );

      // Round-trip: add a tag, then re-parse
      final result = await transformFlac(bytes, [
        const AddTag('GENRE', 'Classical'),
      ]);
      final doc = FlacParser.parseBytes(result.bytes);

      expect(doc.streamInfo.sampleRate, equals(96000));
      expect(doc.streamInfo.bitsPerSample, equals(24));
      expect(
          doc.vorbisComment!.comments.vendorString, equals('round-trip-test'));
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'),
          equals(['Round Trip']));
      expect(
          doc.vorbisComment!.comments.valuesOf('GENRE'), equals(['Classical']));
      expect(doc.pictures.first.description, equals('Original Cover'));
      expect(doc.pictures.first.width, equals(400));
    });

    test('double-transform produces correct output', () async {
      final bytes = buildFlac(paddingSize: 2048);

      // First mutation pass
      final r1 = await transformFlac(bytes, [
        const SetTag('TITLE', ['Pass 1'])
      ]);
      // Second mutation pass on already-modified bytes
      final r2 = await transformFlac(r1.bytes, [
        const SetTag('TITLE', ['Pass 2'])
      ]);

      final doc = FlacParser.parseBytes(r2.bytes);
      expect(doc.vorbisComment!.comments.valuesOf('TITLE'), equals(['Pass 2']));
    });

    test('FlacParser throws InvalidFlacException on corrupt bytes', () {
      final corrupt = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      expect(
        () => FlacParser.parseBytes(corrupt),
        throwsA(isA<InvalidFlacException>()),
      );
    });

    test('FlacParser throws MalformedMetadataException on truncated block', () {
      // Build a FLAC where block header claims a length > actual data
      final out = BytesBuilder();
      out.addByte(0x66);
      out.addByte(0x4C);
      out.addByte(0x61);
      out.addByte(0x43);
      // STREAMINFO claims 100 bytes but we only provide 4
      out.addByte(0x80); // isLast | STREAMINFO
      out.addByte(0x00);
      out.addByte(0x00);
      out.addByte(100); // says 100 bytes
      out.add(Uint8List(4)); // only 4 bytes present
      expect(
        () => FlacParser.parseBytes(Uint8List.fromList(out.toBytes())),
        throwsA(isA<FlacMetadataException>()),
      );
    });
  });
}
