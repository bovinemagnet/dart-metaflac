import 'dart:io';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'test_fixtures.dart';

VorbisCommentBlock _makeVorbisBlock(Map<String, List<String>> tags) {
  final entries = <VorbisCommentEntry>[];
  for (final entry in tags.entries) {
    for (final value in entry.value) {
      entries.add(VorbisCommentEntry(key: entry.key, value: value));
    }
  }
  return VorbisCommentBlock(
    comments: VorbisComments(vendorString: 'test', entries: entries),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('flac_file_editor_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('FlacFileEditor.readFile', () {
    test('returns valid document with streamInfo', () async {
      final bytes = buildFlac();
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      final doc = await FlacFileEditor.readFile(path);
      expect(doc.streamInfo.sampleRate, equals(44100));
      expect(doc.streamInfo.channelCount, equals(2));
      expect(doc.streamInfo.bitsPerSample, equals(16));
    });

    test('throws FlacIoException for missing file', () async {
      final path = '${tempDir.path}/nonexistent.flac';
      expect(
        () => FlacFileEditor.readFile(path),
        throwsA(isA<FlacIoException>()),
      );
    });
  });

  group('FlacFileEditor.updateFile', () {
    test('safeAtomic writes updated tags', () async {
      final bytes = buildFlac(
        vorbisComment: _makeVorbisBlock({'ARTIST': ['Original']}),
      );
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      await FlacFileEditor.updateFile(
        path,
        mutations: [const SetTag('ARTIST', ['Updated'])],
        options: const FlacWriteOptions(writeMode: WriteMode.safeAtomic),
      );

      final doc = FlacParser.parseBytes(File(path).readAsBytesSync());
      expect(doc.vorbisComment?.comments.valuesOf('ARTIST'),
          equals(['Updated']));
    });

    test('outputToNewFile writes to new path, original unchanged', () async {
      final bytes = buildFlac(
        vorbisComment: _makeVorbisBlock({'TITLE': ['Old']}),
      );
      final originalPath = '${tempDir.path}/original.flac';
      final outputPath = '${tempDir.path}/output.flac';
      File(originalPath).writeAsBytesSync(bytes);

      await FlacFileEditor.updateFile(
        originalPath,
        mutations: [const SetTag('TITLE', ['New'])],
        options: FlacWriteOptions(
          writeMode: WriteMode.outputToNewFile,
          outputPath: outputPath,
        ),
      );

      // Original unchanged.
      final origDoc =
          FlacParser.parseBytes(File(originalPath).readAsBytesSync());
      expect(origDoc.vorbisComment?.comments.valuesOf('TITLE'),
          equals(['Old']));

      // Output has new value.
      final outDoc =
          FlacParser.parseBytes(File(outputPath).readAsBytesSync());
      expect(
          outDoc.vorbisComment?.comments.valuesOf('TITLE'), equals(['New']));
    });

    test('inPlaceIfPossible succeeds when metadata shrinks', () async {
      // Build with large vorbis + padding so clearing tags will shrink.
      final bytes = buildFlac(
        vorbisComment: _makeVorbisBlock({
          'ARTIST': ['A long artist name to take up space'],
          'ALBUM': ['A long album name to take up space'],
        }),
        paddingSize: 2048,
      );
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      await FlacFileEditor.updateFile(
        path,
        mutations: [const ClearTags()],
        options: const FlacWriteOptions(
          writeMode: WriteMode.inPlaceIfPossible,
        ),
      );

      final doc = FlacParser.parseBytes(File(path).readAsBytesSync());
      final tags = doc.vorbisComment?.comments.entries ?? [];
      expect(tags, isEmpty);
    });

    test('inPlaceIfPossible throws when metadata grows', () async {
      // Build with no padding and minimal vorbis, then add a large tag.
      final bytes = buildFlac(paddingSize: -1);
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      expect(
        () => FlacFileEditor.updateFile(
          path,
          mutations: [
            const SetTag('DESCRIPTION', [
              'A very long description that will definitely not fit '
                  'in the existing metadata region because there is no '
                  'padding available at all in this file whatsoever.'
            ]),
          ],
          options: const FlacWriteOptions(
            writeMode: WriteMode.inPlaceIfPossible,
          ),
        ),
        throwsA(isA<WriteConflictException>()),
      );
    });

    test('auto falls back to safeAtomic when metadata grows', () async {
      // Build with no padding, then add tag — auto should succeed.
      final bytes = buildFlac(paddingSize: -1);
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      await FlacFileEditor.updateFile(
        path,
        mutations: [
          const SetTag('DESCRIPTION', [
            'A very long description that will definitely not fit '
                'in the existing metadata region because there is no '
                'padding available at all in this file whatsoever.'
          ]),
        ],
        options: const FlacWriteOptions(writeMode: WriteMode.auto),
      );

      final doc = FlacParser.parseBytes(File(path).readAsBytesSync());
      expect(doc.vorbisComment?.comments.valuesOf('DESCRIPTION'), isNotEmpty);
    });

    test('preserveModTime preserves modification time', () async {
      final bytes = buildFlac(
        vorbisComment: _makeVorbisBlock({'ARTIST': ['Test']}),
      );
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      // Set an old modification time.
      final oldModTime = DateTime(2020, 1, 1);
      await File(path).setLastModified(oldModTime);

      await FlacFileEditor.updateFile(
        path,
        mutations: [const SetTag('ARTIST', ['New Artist'])],
        options: const FlacWriteOptions(preserveModTime: true),
      );

      final restoredModTime = await File(path).lastModified();
      expect(
        restoredModTime.difference(oldModTime).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('multiple mutations applied correctly', () async {
      final bytes = buildFlac(
        vorbisComment: _makeVorbisBlock({'ARTIST': ['Old']}),
      );
      final path = '${tempDir.path}/test.flac';
      File(path).writeAsBytesSync(bytes);

      final picture = makeJpeg(description: 'Cover');

      await FlacFileEditor.updateFile(
        path,
        mutations: [
          const SetTag('ARTIST', ['New Artist']),
          AddPicture(picture),
        ],
      );

      final doc = FlacParser.parseBytes(File(path).readAsBytesSync());
      expect(doc.vorbisComment?.comments.valuesOf('ARTIST'),
          equals(['New Artist']));
      expect(doc.pictures, hasLength(1));
      expect(doc.pictures.first.description, equals('Cover'));
    });
  });
}
