/// Integration tests covering streaming pipeline, document API lifecycle,
/// and cross-layer interactions.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/src/transform/stream_rewriter.dart';

import 'test_fixtures.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Stream<List<int>> chunkedStream(Uint8List bytes, int chunkSize) {
  final chunks = <List<int>>[];
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = i + chunkSize > bytes.length ? bytes.length : i + chunkSize;
    chunks.add(bytes.sublist(i, end));
  }
  return Stream.fromIterable(chunks);
}

/// Builds a FLAC with a custom-sized fake audio payload.
Uint8List buildFlacWithAudio(Uint8List audioPayload) {
  final siData = Uint8List(34);
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | ((1 & 0x7) << 1) | ((15 >> 4) & 0x1);
  siData[13] = ((15 & 0xF) << 4) | ((88200 >> 32) & 0xF);
  siData[14] = (88200 >> 24) & 0xFF;
  siData[15] = (88200 >> 16) & 0xFF;
  siData[16] = (88200 >> 8) & 0xFF;
  siData[17] = 88200 & 0xFF;

  final out = BytesBuilder();
  // fLaC marker
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);
  // STREAMINFO (last block)
  out.addByte(0x80);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);
  // Audio payload
  out.add(audioPayload);
  return out.toBytes();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // Group 1: Streaming Pipeline End-to-End
  // ═══════════════════════════════════════════════════════════════════════════
  group('Streaming pipeline end-to-end', () {
    test('multi-block stream transform', () async {
      final vc = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'test',
          entries: [
            VorbisCommentEntry(key: 'TITLE', value: 'Original'),
          ],
        ),
      );
      final pic = makeJpeg(description: 'cover art');
      final input = buildFlac(
        vorbisComment: vc,
        pictures: [pic],
        paddingSize: 256,
      );

      final transformer = FlacTransformer.fromStream(
        Stream.fromIterable([input]),
      );
      final outStream = await transformer.transformStream(
        mutations: [const SetTag('TITLE', ['Changed'])],
      );
      final outBytes = await collectStream(outStream);

      final doc = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Changed']),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.description, equals('cover art'));
      expect(doc.streamInfo.sampleRate, equals(44100));
      expect(doc.streamInfo.channelCount, equals(2));
    });

    test('multiple mutations via streaming', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [],
          ),
        ),
      );
      final newPic = makeJpeg(description: 'added');

      final transformer = FlacTransformer.fromStream(
        Stream.fromIterable([input]),
      );
      final outStream = await transformer.transformStream(
        mutations: [
          const SetTag('ARTIST', ['Bach']),
          AddPicture(newPic),
          const SetPadding(512),
        ],
      );
      final outBytes = await collectStream(outStream);

      final doc = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        doc.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Bach']),
      );
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.description, equals('added'));
      // Verify padding block exists
      final paddingBlocks =
          doc.blocks.whereType<PaddingBlock>().toList();
      expect(paddingBlocks, hasLength(1));
      expect(paddingBlocks.first.payloadLength, equals(512));
    });

    test('identity stream transform', () async {
      final vc = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'test',
          entries: [
            VorbisCommentEntry(key: 'ALBUM', value: 'Keep Me'),
          ],
        ),
      );
      final input = buildFlac(vorbisComment: vc, paddingSize: 128);

      final transformer = FlacTransformer.fromStream(
        Stream.fromIterable([input]),
      );
      final outStream = await transformer.transformStream(mutations: []);
      final outBytes = await collectStream(outStream);

      final doc = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        doc.vorbisComment!.comments.valuesOf('ALBUM'),
        equals(['Keep Me']),
      );
      expect(doc.streamInfo.sampleRate, equals(44100));
    });

    test('large audio payload preserved', () async {
      // 10 KB of distinctive audio bytes.
      final audioPayload = Uint8List(10240);
      for (var i = 0; i < audioPayload.length; i++) {
        audioPayload[i] = i % 256;
      }
      final input = buildFlacWithAudio(audioPayload);

      final transformer = FlacTransformer.fromStream(
        Stream.fromIterable([input]),
      );
      final outStream = await transformer.transformStream(
        mutations: [const SetTag('GENRE', ['Classical'])],
      );
      final outBytes = await collectStream(outStream);

      final doc = FlacMetadataDocument.readFromBytes(outBytes);
      // Audio data starts after metadata.
      final audioOut = outBytes.sublist(doc.audioDataOffset);
      expect(audioOut.length, equals(audioPayload.length));
      expect(audioOut, equals(audioPayload));
    });

    test('tiny chunks (1 byte at a time)', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Chunky'),
            ],
          ),
        ),
      );
      final stream = chunkedStream(input, 1);

      final transformer = FlacTransformer.fromStream(stream);
      final outStream = await transformer.transformStream(
        mutations: [const SetTag('TITLE', ['StillChunky'])],
      );
      final outBytes = await collectStream(outStream);

      final doc = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['StillChunky']),
      );
    });

    test('truncated stream throws', () async {
      final input = buildFlac();
      final half = input.sublist(0, input.length ~/ 2);

      final transformer = FlacTransformer.fromStream(
        Stream.fromIterable([half]),
      );
      expect(
        () => transformer.transformStream(mutations: []),
        throwsA(isA<FlacMetadataException>()),
      );
    });

    test('empty stream throws', () async {
      final transformer = FlacTransformer.fromStream(
        Stream<List<int>>.fromIterable([]),
      );
      expect(
        () => transformer.transformStream(mutations: []),
        throwsA(isA<FlacMetadataException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 2: Document API Full Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════
  group('Document API full lifecycle', () {
    test('double round-trip', () {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(vendorString: 'test', entries: []),
        ),
      );

      // First round-trip: set a tag.
      var doc = FlacMetadataDocument.readFromBytes(input);
      doc = doc.edit((e) => e.setTag('TITLE', ['First']));
      final bytes1 = doc.toBytes();

      var doc2 = FlacMetadataDocument.readFromBytes(bytes1);
      expect(
        doc2.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['First']),
      );

      // Second round-trip: add another tag.
      doc2 = doc2.edit((e) => e.setTag('ARTIST', ['Second']));
      final bytes2 = doc2.toBytes();

      final doc3 = FlacMetadataDocument.readFromBytes(bytes2);
      expect(
        doc3.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['First']),
      );
      expect(
        doc3.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Second']),
      );
    });

    test('chained edits', () {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(vendorString: 'test', entries: []),
        ),
      );

      final doc = FlacMetadataDocument.readFromBytes(input)
          .edit((e) => e.setTag('TITLE', ['T']))
          .edit((e) => e.setTag('ARTIST', ['A']));
      final outBytes = doc.toBytes();

      final parsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        parsed.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['T']),
      );
      expect(
        parsed.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['A']),
      );
    });

    test('stream source lifecycle', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(vendorString: 'test', entries: []),
        ),
      );
      final stream = Stream.fromIterable([input.toList()]);

      var doc = await FlacMetadataDocument.readFromStream(stream);
      doc = doc.edit((e) => e.setTag('GENRE', ['Jazz']));
      final outBytes = doc.toBytes();

      final parsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(
        parsed.vorbisComment!.comments.valuesOf('GENRE'),
        equals(['Jazz']),
      );
    });

    test('add new block type when none exists', () {
      // Build FLAC with NO vorbis comment — just STREAMINFO + padding.
      final input = buildFlac(paddingSize: 256);

      var doc = FlacMetadataDocument.readFromBytes(input);
      expect(doc.vorbisComment, isNull);

      doc = doc.edit((e) => e.setTag('TITLE', ['NewTag']));
      final outBytes = doc.toBytes();

      final parsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(parsed.vorbisComment, isNotNull);
      expect(
        parsed.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['NewTag']),
      );
    });

    test('remove all pictures', () {
      final pic1 = makeJpeg(
        type: PictureType.frontCover,
        description: 'front',
      );
      final pic2 = makeJpeg(
        type: PictureType.backCover,
        description: 'back',
      );
      final input = buildFlac(pictures: [pic1, pic2]);

      var doc = FlacMetadataDocument.readFromBytes(input);
      expect(doc.pictures, hasLength(2));

      doc = doc.edit((e) => e.removeAllPictures());
      final outBytes = doc.toBytes();

      final parsed = FlacMetadataDocument.readFromBytes(outBytes);
      expect(parsed.pictures, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 3: Cross-Layer Integration
  // ═══════════════════════════════════════════════════════════════════════════
  group('Cross-layer integration', () {
    test('StreamRewriter output feeds into readFromBytes', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Before'),
            ],
          ),
        ),
      );

      final rewrittenStream = await StreamRewriter.rewrite(
        input: Stream.fromIterable([input]),
        mutations: [const SetTag('TITLE', ['After'])],
      );
      final rewrittenBytes = await collectStream(rewrittenStream);

      final doc = FlacMetadataDocument.readFromBytes(rewrittenBytes);
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['After']),
      );
      expect(doc.streamInfo.sampleRate, equals(44100));
    });

    test('toBytes then transformStream', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(vendorString: 'test', entries: []),
        ),
      );

      // First transform via document API.
      var doc = FlacMetadataDocument.readFromBytes(input);
      doc = doc.edit((e) => e.setTag('TITLE', ['DocEdit']));
      final intermediate = doc.toBytes();

      // Second transform via streaming.
      final transformer = FlacTransformer.fromBytes(intermediate);
      final outStream = await transformer.transformStream(
        mutations: [const SetTag('ARTIST', ['StreamEdit'])],
      );
      final finalBytes = await collectStream(outStream);

      final parsed = FlacMetadataDocument.readFromBytes(finalBytes);
      expect(
        parsed.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['DocEdit']),
      );
      expect(
        parsed.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['StreamEdit']),
      );
    });

    test('sequential: stream to bytes to stream', () async {
      final input = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(vendorString: 'test', entries: []),
        ),
      );

      // Step 1: stream transform.
      final t1 = FlacTransformer.fromBytes(input);
      final s1 = await t1.transformStream(
        mutations: [const SetTag('TITLE', ['Step1'])],
      );
      final bytes1 = await collectStream(s1);

      // Step 2: bytes transform via document API.
      var doc = FlacMetadataDocument.readFromBytes(bytes1);
      doc = doc.edit((e) => e.setTag('ARTIST', ['Step2']));
      final bytes2 = doc.toBytes();

      // Step 3: stream transform again.
      final t3 = FlacTransformer.fromBytes(bytes2);
      final s3 = await t3.transformStream(
        mutations: [const SetTag('GENRE', ['Step3'])],
      );
      final finalBytes = await collectStream(s3);

      final parsed = FlacMetadataDocument.readFromBytes(finalBytes);
      expect(
        parsed.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Step1']),
      );
      expect(
        parsed.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Step2']),
      );
      expect(
        parsed.vorbisComment!.comments.valuesOf('GENRE'),
        equals(['Step3']),
      );
    });
  });
}
