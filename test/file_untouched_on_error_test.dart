/// Tests that any failed read or edit leaves the source file untouched.
///
/// GitHub issue #12: when the tool cannot parse a block or apply an
/// edit, it must exit with an error without modifying the FLAC file —
/// no partial writes, no truncation, no stray output files. Covers both
/// the library (`FlacFileEditor`) and the CLI (compat flags and modern
/// subcommands), asserting the on-disc bytes are byte-identical after
/// every failure mode.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

late Directory tmpDir;
late String projectRoot;

Future<ProcessResult> runCli(List<String> args) {
  return Process.run(
    'dart',
    ['run', 'bin/metaflac.dart', ...args],
    workingDirectory: projectRoot,
  );
}

String tmpFile(String name) => '${tmpDir.path}/$name';

/// Writes [bytes] to [name] in the temp dir and returns the path.
String writeFixture(String name, List<int> bytes) {
  final path = tmpFile(name);
  File(path).writeAsBytesSync(bytes);
  return path;
}

/// A syntactically broken FLAC: valid marker, then a block header whose
/// declared payload extends beyond the end of the file.
Uint8List truncatedFlac() {
  final good = buildFlac();
  // Cut the file mid-metadata: keep the marker, STREAMINFO header and
  // half the STREAMINFO payload.
  return Uint8List.sublistView(good, 0, 4 + 4 + 17);
}

/// A FLAC whose PICTURE block's inner data-length field overruns the
/// declared block length (rejected by the hardened parser).
Uint8List overrunningFlac() {
  final streamInfo = Uint8List(34);
  streamInfo[1] = 16;
  streamInfo[2] = 1;
  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
  out.add([0x00, 0x00, 0x00, 34]); // STREAMINFO (not last)
  out.add(streamInfo);
  out.add([
    0x86, 0x00, 0x00, 0x20, // PICTURE (last), declared length 32
    0x00, 0x00, 0x00, 0x03, // picture type
    0x00, 0x00, 0x00, 0x00, // MIME length 0
    0x00, 0x00, 0x00, 0x00, // description length 0
    0x00, 0x00, 0x00, 0x00, // width
    0x00, 0x00, 0x00, 0x00, // height
    0x00, 0x00, 0x00, 0x00, // colour depth
    0x00, 0x00, 0x00, 0x00, // indexed colours
    0x00, 0x00, 0x00, 0x0A, // data length 10 — overruns the block
    0xFF, 0xF8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  ]);
  return out.toBytes();
}

void main() {
  projectRoot = Directory.current.path;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('untouched_on_error_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('library: FlacFileEditor failures leave the file untouched', () {
    test('updateFile on junk bytes throws and leaves the file unchanged',
        () async {
      final junk = List<int>.generate(64, (i) => i);
      final path = writeFixture('junk.flac', junk);

      await expectLater(
        FlacFileEditor.updateFile(path, mutations: [
          const SetTag('ARTIST', ['X'])
        ]),
        throwsA(isA<InvalidFlacException>()),
      );
      expect(File(path).readAsBytesSync(), junk);
    });

    test('updateFile on a truncated FLAC throws and leaves it unchanged',
        () async {
      final bytes = truncatedFlac();
      final path = writeFixture('truncated.flac', bytes);

      await expectLater(
        FlacFileEditor.updateFile(path, mutations: [
          const SetTag('ARTIST', ['X'])
        ]),
        throwsA(isA<FlacMetadataException>()),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('updateFile on a block-overrun FLAC throws and leaves it unchanged',
        () async {
      final bytes = overrunningFlac();
      final path = writeFixture('overrun.flac', bytes);

      await expectLater(
        FlacFileEditor.updateFile(path, mutations: [
          const SetTag('ARTIST', ['X'])
        ]),
        throwsA(isA<MalformedMetadataException>()),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });

    test(
        'inPlaceIfPossible write conflict throws and leaves the file '
        'unchanged', () async {
      // No padding, so any metadata growth cannot fit in place.
      final bytes = buildFlac(paddingSize: -1);
      final path = writeFixture('nopadding.flac', bytes);

      await expectLater(
        FlacFileEditor.updateFile(
          path,
          mutations: [
            SetTag('COMMENT', ['x' * 4096])
          ],
          options:
              const FlacWriteOptions(writeMode: WriteMode.inPlaceIfPossible),
        ),
        throwsA(isA<WriteConflictException>()),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('readFile on junk bytes throws without touching the file', () async {
      final junk = List<int>.generate(64, (i) => 255 - i);
      final path = writeFixture('junk2.flac', junk);
      final statBefore = File(path).statSync();

      await expectLater(
        FlacFileEditor.readFile(path),
        throwsA(isA<InvalidFlacException>()),
      );
      expect(File(path).readAsBytesSync(), junk);
      expect(File(path).statSync().modified, statBefore.modified);
    });
  });

  group('CLI: parse failures leave the file untouched', () {
    test('write op on junk bytes exits 3 and leaves the file unchanged',
        () async {
      final junk = List<int>.generate(64, (i) => i * 3 % 251);
      final path = writeFixture('junk.flac', junk);

      final result = await runCli(['--set-tag=ARTIST=X', path]);

      expect(result.exitCode, 3);
      expect(File(path).readAsBytesSync(), junk);
    });

    test('write op on a truncated FLAC exits 3 and leaves it unchanged',
        () async {
      final bytes = truncatedFlac();
      final path = writeFixture('truncated.flac', bytes);

      final result = await runCli(['--set-tag=ARTIST=X', path]);

      expect(result.exitCode, 3);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('write op on a block-overrun FLAC exits 3 and leaves it unchanged',
        () async {
      final bytes = overrunningFlac();
      final path = writeFixture('overrun.flac', bytes);

      final result = await runCli(['--remove-all-tags', path]);

      expect(result.exitCode, 3);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('modern tags set on junk bytes fails and leaves the file unchanged',
        () async {
      final junk = List<int>.generate(64, (i) => i);
      final path = writeFixture('junk.flac', junk);

      final result = await runCli(['tags', 'set', 'ARTIST=X', path]);

      expect(result.exitCode, isNot(0));
      expect(File(path).readAsBytesSync(), junk);
    });
  });

  group('CLI: missing auxiliary inputs leave the FLAC untouched', () {
    test('--set-tag-from-file with a missing value file exits 4, unchanged',
        () async {
      final bytes = buildFlac();
      final path = writeFixture('good.flac', bytes);

      final result = await runCli(
          ['--set-tag-from-file=COMMENT=${tmpFile('missing.txt')}', path]);

      expect(result.exitCode, 4);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('--import-tags-from with a missing tag file exits 4, unchanged',
        () async {
      final bytes = buildFlac();
      final path = writeFixture('good.flac', bytes);

      final result =
          await runCli(['--import-tags-from=${tmpFile('missing.txt')}', path]);

      expect(result.exitCode, 4);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('--import-picture-from with a missing picture exits 4, unchanged',
        () async {
      final bytes = buildFlac();
      final path = writeFixture('good.flac', bytes);

      final result = await runCli(
          ['--import-picture-from=${tmpFile('missing.jpg')}', path]);

      expect(result.exitCode, 4);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('--append with a missing block file exits 4, unchanged', () async {
      final bytes = buildFlac();
      final path = writeFixture('good.flac', bytes);

      final result = await runCli([
        '--append=${tmpFile('missing.bin')}',
        '--block-type=APPLICATION',
        path,
      ]);

      expect(result.exitCode, 4);
      expect(File(path).readAsBytesSync(), bytes);
    });
  });

  group('CLI: -o output mode never modifies the input', () {
    test('failed transform creates no output file and keeps input intact',
        () async {
      final bytes = truncatedFlac();
      final path = writeFixture('truncated.flac', bytes);
      final outPath = tmpFile('out.flac');

      final result = await runCli(['--set-tag=ARTIST=X', '-o', outPath, path]);

      expect(result.exitCode, 3);
      expect(File(path).readAsBytesSync(), bytes);
      expect(File(outPath).existsSync(), isFalse);
    });

    test('successful -o write leaves the input byte-identical', () async {
      final bytes = buildFlac();
      final path = writeFixture('good.flac', bytes);
      final outPath = tmpFile('out.flac');

      final result = await runCli(['--set-tag=ARTIST=X', '-o', outPath, path]);

      expect(result.exitCode, 0);
      expect(File(path).readAsBytesSync(), bytes);
      expect(File(outPath).existsSync(), isTrue);
    });
  });
}
