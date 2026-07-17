/// Integration tests for CLI exit codes and stdin/stdout behaviour.
///
/// Covers GitHub issues #28 (compat CLI returned exit 0 on failure),
/// #29 (`--import-tags-from=-` must read from stdin, matching real
/// metaflac and this tool's own export side), and the #30 item that
/// `--export-tags-to=-` must not emit an extra trailing blank line.
///
/// Each test runs `bin/metaflac.dart` as a subprocess, matching the
/// pattern used by `metaflac_parity_test.dart`.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_metaflac/dart_metaflac.dart';
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

/// Runs the CLI feeding [stdinText] on standard input.
Future<ProcessResult> runCliWithStdin(
    List<String> args, String stdinText) async {
  final process = await Process.start(
    'dart',
    ['run', 'bin/metaflac.dart', ...args],
    workingDirectory: projectRoot,
  );
  process.stdin.write(stdinText);
  await process.stdin.close();
  final stdoutText = await process.stdout.transform(utf8.decoder).join();
  final stderrText = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdoutText, stderrText);
}

String tmpFile(String name) => '${tmpDir.path}/$name';

void main() {
  projectRoot = Directory.current.path;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cli_exit_codes_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  String buildFixture({String name = 'test.flac'}) {
    final bytes = buildFlac(
      vorbisComment: _vc([
        ('ARTIST', 'Exit Code Artist'),
        ('TITLE', 'Exit Code Title'),
      ]),
    );
    final path = tmpFile(name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  group('issue #28: failures must not exit 0', () {
    test('--export-picture-to with no picture exits 1 and writes no file',
        () async {
      final path = buildFixture();
      final outPath = tmpFile('cover.jpg');

      final result = await runCli(['--export-picture-to=$outPath', path]);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('No picture found'));
      expect(File(outPath).existsSync(), isFalse);
    });

    test('malformed --set-tag exits 2 and leaves the file untouched', () async {
      final path = buildFixture();
      final before = File(path).readAsBytesSync();

      final result = await runCli(['--set-tag=BADTAG', path]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('Invalid tag format'));
      expect(File(path).readAsBytesSync(), before);
    });

    test('malformed --set-tag-from-file exits 2 and leaves the file untouched',
        () async {
      final path = buildFixture();
      final before = File(path).readAsBytesSync();

      final result = await runCli(['--set-tag-from-file=BADSPEC', path]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('Invalid --set-tag-from-file format'));
      expect(File(path).readAsBytesSync(), before);
    });
  });

  group('issue #29: --import-tags-from=- reads stdin', () {
    test('compat flag imports tags piped via stdin', () async {
      final path = buildFixture();

      final result = await runCliWithStdin(
        ['--import-tags-from=-', path],
        'GENRE=House\nDATE=1994\n',
      );

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      final listed = await runCli(['--show-all-tags', path]);
      expect(listed.stdout, contains('GENRE=House'));
      expect(listed.stdout, contains('DATE=1994'));
    });

    test('modern tags import reads stdin via --from -', () async {
      final path = buildFixture();

      final result = await runCliWithStdin(
        ['tags', 'import', '--from', '-', path],
        'GENRE=House\n',
      );

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      final listed = await runCli(['--show-all-tags', path]);
      expect(listed.stdout, contains('GENRE=House'));
    });

    test('export to stdout pipes back into import from stdin', () async {
      final source = buildFixture(name: 'source.flac');
      final target = buildFixture(name: 'target.flac');

      final exported = await runCli(['--export-tags-to=-', source]);
      expect(exported.exitCode, 0);

      final imported = await runCliWithStdin(
        ['--import-tags-from=-', target],
        exported.stdout as String,
      );

      expect(imported.exitCode, 0, reason: 'stderr: ${imported.stderr}');
      final listed = await runCli(['--show-all-tags', target]);
      // Original tags plus the imported duplicates.
      expect('ARTIST=Exit Code Artist'.allMatches(listed.stdout as String),
          hasLength(2));
    });
  });

  group('issue #30: --export-tags-to=- output is byte-exact', () {
    test('stdout export matches file export with no trailing blank line',
        () async {
      final path = buildFixture();
      final outPath = tmpFile('tags.txt');

      final toFile = await runCli(['--export-tags-to=$outPath', path]);
      expect(toFile.exitCode, 0);
      final toStdout = await runCli(['--export-tags-to=-', path]);
      expect(toStdout.exitCode, 0);

      expect(toStdout.stdout, File(outPath).readAsStringSync());
    });
  });
}

VorbisCommentBlock _vc(List<(String, String)> entries) {
  return VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac exit code test',
      entries: entries
          .map((e) => VorbisCommentEntry(key: e.$1, value: e.$2))
          .toList(),
    ),
  );
}
