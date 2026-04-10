/// Library API tests using the real siren.flac fixture.
///
/// These tests exercise parsing, editing, round-tripping, file I/O, and
/// streaming against a real libFLAC-encoded file rather than synthetic
/// in-memory fixtures.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/src/transform/stream_rewriter.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  late Directory tempDir;
  late String sirenPath;
  late Uint8List originalBytes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('real_flac_test_');
    sirenPath = copySirenTo(tempDir);
    originalBytes = File(sirenPath).readAsBytesSync();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Uint8List audioBytes(FlacMetadataDocument doc, Uint8List bytes) {
    return bytes.sublist(doc.audioDataOffset);
  }

  String md5Hex(Uint8List md5) {
    return md5.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ─── Group 1: Parsing ──────────────────────────────────────────────────────

  group('Parsing siren.flac', () {
    test('reads correct STREAMINFO fields', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final si = doc.streamInfo;
      expect(si.sampleRate, equals(48000));
      expect(si.channelCount, equals(1));
      expect(si.bitsPerSample, equals(32));
      expect(si.totalSamples, equals(240000));
      expect(si.minBlockSize, equals(4096));
      expect(si.maxBlockSize, equals(4096));
    });

    test('reads non-zero MD5 signature', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      expect(
        md5Hex(doc.streamInfo.md5Signature),
        equals('09bffcd26cb9701e61558be6695a7680'),
      );
    });

    test('reads vorbis comment vendor string', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      expect(doc.vorbisComment, isNotNull);
      expect(
        doc.vorbisComment!.comments.vendorString,
        equals('reference libFLAC 1.5.0 20250211'),
      );
    });

    test('reads existing vorbis comment tag', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final values = doc.vorbisComment!.comments.valuesOf(
        'WAVEFORMATEXTENSIBLE_CHANNEL_MASK',
      );
      expect(values, equals(['0x0004']));
    });

    test('has no picture blocks', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      expect(doc.pictures, isEmpty);
    });

    test('detects seekTable, application, and padding blocks', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final types = doc.blocks.map((b) => b.type).toList();
      expect(types, contains(FlacBlockType.seekTable));
      expect(types, contains(FlacBlockType.application));
      expect(types, contains(FlacBlockType.padding));
    });

    test('has eight metadata blocks total', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      // streamInfo, seekTable, vorbisComment, 4× application, padding
      expect(doc.blocks, hasLength(8));
    });

    test('audioDataOffset is positive and within file size', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      expect(doc.audioDataOffset, greaterThan(0));
      expect(doc.audioDataOffset, lessThan(originalBytes.length));
    });

    test('parses via readFromStream with same results', () async {
      final stream = Stream.value(originalBytes);
      final doc = await FlacMetadataDocument.readFromStream(stream);
      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(doc.streamInfo.channelCount, equals(1));
      expect(doc.vorbisComment, isNotNull);
      expect(doc.blocks, hasLength(8));
    });
  });

  // ─── Group 2: Audio data integrity ─────────────────────────────────────────

  group('Audio data integrity', () {
    test('audio bytes preserved after adding a tag', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      final updated = doc.edit((e) => e.addTag('ARTIST', 'Test Artist'));
      final updatedBytes = updated.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(updatedBytes);
      final updatedAudio = audioBytes(reparsed, updatedBytes);

      expect(updatedAudio, equals(originalAudio));
    });

    test('audio bytes preserved after tag set, remove, clear cycle', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      // Set tag
      var current = doc.edit((e) => e.setTag('GENRE', ['Rock']));
      var bytes = current.toBytes();
      var reparsed = FlacMetadataDocument.readFromBytes(bytes);
      expect(audioBytes(reparsed, bytes), equals(originalAudio));

      // Remove tag
      current = reparsed.edit((e) => e.removeTag('GENRE'));
      bytes = current.toBytes();
      reparsed = FlacMetadataDocument.readFromBytes(bytes);
      expect(audioBytes(reparsed, bytes), equals(originalAudio));

      // Clear all tags
      current = reparsed.edit((e) => e.clearTags());
      bytes = current.toBytes();
      reparsed = FlacMetadataDocument.readFromBytes(bytes);
      expect(audioBytes(reparsed, bytes), equals(originalAudio));
    });

    test('audio bytes preserved after picture addition and removal', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      // Add picture
      final withPic = doc.edit((e) => e.addPicture(makeJpeg()));
      var bytes = withPic.toBytes();
      var reparsed = FlacMetadataDocument.readFromBytes(bytes);
      expect(audioBytes(reparsed, bytes), equals(originalAudio));

      // Remove picture
      final noPic = reparsed.edit((e) => e.removeAllPictures());
      bytes = noPic.toBytes();
      reparsed = FlacMetadataDocument.readFromBytes(bytes);
      expect(audioBytes(reparsed, bytes), equals(originalAudio));
    });

    test('audio bytes preserved after padding resize', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      final updated = doc.edit((e) => e.setPadding(4096));
      final updatedBytes = updated.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(updatedBytes);

      expect(audioBytes(reparsed, updatedBytes), equals(originalAudio));
    });

    test('audio bytes preserved via transformFlac API', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      final result = await transformFlac(
        originalBytes,
        [const AddTag('ALBUM', 'Siren Album')],
      );
      final reparsed = FlacMetadataDocument.readFromBytes(result.bytes);

      expect(audioBytes(reparsed, result.bytes), equals(originalAudio));
    });

    test('audio bytes preserved via streaming transform', () async {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final originalAudio = audioBytes(doc, originalBytes);

      final transformer = FlacTransformer.fromStream(
        Stream.value(originalBytes),
      );
      final outStream = await transformer.transformStream(
        mutations: [const AddTag('COMMENT', 'streamed')],
      );
      final outBytes = await collectStream(outStream);
      final reparsed = FlacMetadataDocument.readFromBytes(outBytes);

      expect(audioBytes(reparsed, outBytes), equals(originalAudio));
    });
  });

  // ─── Group 3: Round-trip fidelity ──────────────────────────────────────────

  group('Round-trip fidelity', () {
    test('identity round-trip preserves all metadata', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final roundTripped = doc.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(roundTripped);

      expect(reparsed.streamInfo.sampleRate, equals(48000));
      expect(reparsed.streamInfo.channelCount, equals(1));
      expect(reparsed.streamInfo.bitsPerSample, equals(32));
      expect(reparsed.streamInfo.totalSamples, equals(240000));
      expect(
        md5Hex(reparsed.streamInfo.md5Signature),
        equals('09bffcd26cb9701e61558be6695a7680'),
      );
      expect(
        reparsed.vorbisComment!.comments.vendorString,
        equals('reference libFLAC 1.5.0 20250211'),
      );
      expect(
        reparsed.vorbisComment!.comments.valuesOf(
          'WAVEFORMATEXTENSIBLE_CHANNEL_MASK',
        ),
        equals(['0x0004']),
      );
    });

    test('edit round-trip preserves unmodified tags alongside new ones', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final updated = doc.edit((e) => e.addTag('ARTIST', 'Siren'));
      final bytes = updated.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(bytes);

      expect(
        reparsed.vorbisComment!.comments.valuesOf(
          'WAVEFORMATEXTENSIBLE_CHANNEL_MASK',
        ),
        equals(['0x0004']),
      );
      expect(
        reparsed.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Siren']),
      );
    });

    test('double round-trip with different mutations each pass', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);

      // Pass 1: add TITLE
      final pass1 = doc.edit((e) => e.addTag('TITLE', 'Siren Song'));
      final bytes1 = pass1.toBytes();
      final reparsed1 = FlacMetadataDocument.readFromBytes(bytes1);

      // Pass 2: add ARTIST
      final pass2 = reparsed1.edit((e) => e.addTag('ARTIST', 'Test'));
      final bytes2 = pass2.toBytes();
      final reparsed2 = FlacMetadataDocument.readFromBytes(bytes2);

      expect(
        reparsed2.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Siren Song']),
      );
      expect(
        reparsed2.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Test']),
      );
      expect(
        reparsed2.vorbisComment!.comments.valuesOf(
          'WAVEFORMATEXTENSIBLE_CHANNEL_MASK',
        ),
        equals(['0x0004']),
      );
    });

    test('chained edits produce correct final state', () {
      final doc = FlacMetadataDocument.readFromBytes(originalBytes);
      final updated = doc
          .edit((e) => e.addTag('TITLE', 'X'))
          .edit((e) => e.addTag('ARTIST', 'Y'))
          .edit((e) => e.clearTags())
          .edit((e) => e.addTag('GENRE', 'Electronic'));

      final bytes = updated.toBytes();
      final reparsed = FlacMetadataDocument.readFromBytes(bytes);
      final comments = reparsed.vorbisComment!.comments;

      expect(comments.valuesOf('GENRE'), equals(['Electronic']));
      expect(comments.valuesOf('TITLE'), isEmpty);
      expect(comments.valuesOf('ARTIST'), isEmpty);
      expect(
        comments.valuesOf('WAVEFORMATEXTENSIBLE_CHANNEL_MASK'),
        isEmpty,
      );
    });
  });

  // ─── Group 4: FlacFileEditor ───────────────────────────────────────────────

  group('FlacFileEditor with real FLAC', () {
    test('readFile returns correct document', () async {
      final doc = await FlacFileEditor.readFile(sirenPath);
      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(doc.streamInfo.channelCount, equals(1));
      expect(doc.blocks, hasLength(8));
    });

    test('updateFile with safeAtomic writes updated tags', () async {
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('ARTIST', 'Safe Atomic')],
      );
      final doc = await FlacFileEditor.readFile(sirenPath);
      expect(
        doc.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['Safe Atomic']),
      );
    });

    test('updateFile with outputToNewFile leaves original unchanged', () async {
      final outputPath = '${tempDir.path}/output.flac';
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('TITLE', 'New File')],
        options: FlacWriteOptions(
          writeMode: WriteMode.outputToNewFile,
          outputPath: outputPath,
        ),
      );

      // Original unchanged
      final originalDoc = await FlacFileEditor.readFile(sirenPath);
      expect(originalDoc.vorbisComment!.comments.valuesOf('TITLE'), isEmpty);

      // Output has mutation
      final outputDoc = await FlacFileEditor.readFile(outputPath);
      expect(
        outputDoc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['New File']),
      );
    });

    test('updateFile with auto mode when metadata grows', () async {
      // Add enough tags to exceed existing padding
      final largeTags = List.generate(
        50,
        (i) => AddTag('TAG_$i', 'A long value to fill up padding space $i'),
      );
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: largeTags,
        options: const FlacWriteOptions(writeMode: WriteMode.auto),
      );
      final doc = await FlacFileEditor.readFile(sirenPath);
      expect(doc.vorbisComment!.comments.valuesOf('TAG_0'), isNotEmpty);
      expect(doc.vorbisComment!.comments.valuesOf('TAG_49'), isNotEmpty);
    });

    test('updateFile preserveModTime works', () async {
      // Set an old modification time
      final oldTime = DateTime(2020, 1, 1);
      File(sirenPath).setLastModifiedSync(oldTime);

      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('ARTIST', 'Preserved')],
        options: const FlacWriteOptions(preserveModTime: true),
      );

      final modTime = File(sirenPath).lastModifiedSync();
      // Allow 2-second tolerance for filesystem granularity
      expect(
        modTime.difference(oldTime).inSeconds.abs(),
        lessThanOrEqualTo(2),
      );
    });

    test('multiple sequential updateFile calls', () async {
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('ARTIST', 'First')],
      );
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('ALBUM', 'Second')],
      );
      await FlacFileEditor.updateFile(
        sirenPath,
        mutations: [const AddTag('GENRE', 'Third')],
      );

      final doc = await FlacFileEditor.readFile(sirenPath);
      expect(
        doc.vorbisComment!.comments.valuesOf('ARTIST'),
        equals(['First']),
      );
      expect(
        doc.vorbisComment!.comments.valuesOf('ALBUM'),
        equals(['Second']),
      );
      expect(
        doc.vorbisComment!.comments.valuesOf('GENRE'),
        equals(['Third']),
      );
    });
  });

  // ─── Group 5: Streaming ────────────────────────────────────────────────────

  group('Streaming with real audio', () {
    test('StreamRewriter.rewrite with real FLAC', () async {
      final outStream = await StreamRewriter.rewrite(
        input: Stream.value(originalBytes),
        mutations: [const SetTag('TITLE', ['Rewritten'])],
      );
      final outBytes = await collectStream(outStream);
      final doc = FlacMetadataDocument.readFromBytes(outBytes);

      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(
        doc.vorbisComment!.comments.valuesOf('TITLE'),
        equals(['Rewritten']),
      );
    });

    test('chunked stream (256-byte chunks) with real FLAC', () async {
      // Split into small chunks
      final chunks = <List<int>>[];
      for (var i = 0; i < originalBytes.length; i += 256) {
        final end =
            (i + 256 < originalBytes.length) ? i + 256 : originalBytes.length;
        chunks.add(originalBytes.sublist(i, end));
      }

      final transformer = FlacTransformer.fromStream(Stream.fromIterable(chunks));
      final result = await transformer.transform(
        mutations: [const AddTag('CHUNKED', 'yes')],
      );
      final doc = result.document;

      expect(doc.streamInfo.sampleRate, equals(48000));
      expect(
        doc.vorbisComment!.comments.valuesOf('CHUNKED'),
        equals(['yes']),
      );
    });

    test('unknown/application blocks survive streaming round-trip', () async {
      final outStream = await StreamRewriter.rewrite(
        input: Stream.value(originalBytes),
        mutations: [const AddTag('ROUNDTRIP', 'true')],
      );
      final outBytes = await collectStream(outStream);
      final doc = FlacMetadataDocument.readFromBytes(outBytes);

      final types = doc.blocks.map((b) => b.type).toList();
      final appCount =
          types.where((t) => t == FlacBlockType.application).length;
      expect(appCount, equals(4));
      expect(types, contains(FlacBlockType.seekTable));
    });
  });
}
