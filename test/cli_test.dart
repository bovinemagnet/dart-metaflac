/// CLI integration tests for bin/metaflac.dart.
///
/// These tests exercise the CLI by running it as a subprocess via
/// `Process.run('dart', ['run', 'bin/metaflac.dart', ...])` against
/// synthetic FLAC files built in a temporary directory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

// ─── FLAC Fixture Builder ─────────────────────────────────────────────────────

/// Builds an in-memory FLAC file with optional blocks.
Uint8List buildFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 88200,
  int paddingSize = 1024,
  VorbisCommentBlock? vorbisComment,
  List<PictureBlock> pictures = const [],
}) {
  final siData = Uint8List(34);
  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (sr >> 12) & 0xFF;
  siData[11] = (sr >> 4) & 0xFF;
  siData[12] =
      ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  siData[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  siData[14] = (ts >> 24) & 0xFF;
  siData[15] = (ts >> 16) & 0xFF;
  siData[16] = (ts >> 8) & 0xFF;
  siData[17] = ts & 0xFF;

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }
  final picDataList = pictures.map((p) => p.toPayloadBytes()).toList();

  final hasVC = vcData != null;
  final hasPics = picDataList.isNotEmpty;
  final hasPadding = paddingSize >= 0;

  final out = BytesBuilder();
  out.addByte(0x66); // f
  out.addByte(0x4C); // L
  out.addByte(0x61); // a
  out.addByte(0x43); // C

  final siIsLast = !hasVC && !hasPics && !hasPadding;
  out.addByte(siIsLast ? 0x80 : 0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  if (hasVC) {
    final vcIsLast = !hasPics && !hasPadding;
    out.addByte((vcIsLast ? 0x80 : 0x00) | 0x04);
    out.addByte((vcData.length >> 16) & 0xFF);
    out.addByte((vcData.length >> 8) & 0xFF);
    out.addByte(vcData.length & 0xFF);
    out.add(vcData);
  }

  for (var i = 0; i < picDataList.length; i++) {
    final pd = picDataList[i];
    final picIsLast = (i == picDataList.length - 1) && !hasPadding;
    out.addByte((picIsLast ? 0x80 : 0x00) | 0x06);
    out.addByte((pd.length >> 16) & 0xFF);
    out.addByte((pd.length >> 8) & 0xFF);
    out.addByte(pd.length & 0xFF);
    out.add(pd);
  }

  if (hasPadding) {
    out.addByte(0x80 | 0x01);
    out.addByte((paddingSize >> 16) & 0xFF);
    out.addByte((paddingSize >> 8) & 0xFF);
    out.addByte(paddingSize & 0xFF);
    out.add(Uint8List(paddingSize));
  }

  // Fake audio sync bytes + payload
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(200));

  return out.toBytes();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

late Directory tmpDir;
late String projectRoot;

Future<ProcessResult> runCli(List<String> args) async {
  return Process.run(
    'dart',
    ['run', 'bin/metaflac.dart', ...args],
    workingDirectory: projectRoot,
  );
}

String tmpFile(String name) => '${tmpDir.path}/$name';

void writeFlac(String name, Uint8List bytes) {
  File(tmpFile(name)).writeAsBytesSync(bytes);
}

void main() {
  projectRoot = Directory.current.path;
  // Walk up if we're not at the project root
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    projectRoot = '/home/paul/gitHUB/dart-metaflac';
  }

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('metaflac_cli_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('--list --json', () {
    test('produces valid JSON with streamInfo key', () async {
      final flac = buildFlac(
        sampleRate: 48000,
        channels: 2,
        bitsPerSample: 24,
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test-vendor',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Test')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runCli(['--list', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('streamInfo'));
      expect(json['streamInfo'], contains('sampleRate'));
      expect(json['streamInfo']['sampleRate'], equals(48000));
      expect(json['streamInfo']['bitsPerSample'], equals(24));
    });

    test('includes vorbisComment in JSON output', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test-vendor',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'My Song'),
              VorbisCommentEntry(key: 'ARTIST', value: 'Test Artist'),
            ],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runCli(['--list', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('vorbisComment'));
      expect(json['vorbisComment']['vendorString'], equals('test-vendor'));
      expect(json['vorbisComment']['tags'], contains('TITLE'));
    });

    test('includes pictures in JSON output', () async {
      final flac = buildFlac(
        pictures: [
          PictureBlock(
            pictureType: PictureType.frontCover,
            mimeType: 'image/jpeg',
            description: 'Cover',
            width: 500,
            height: 500,
            colorDepth: 24,
            indexedColors: 0,
            data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
          ),
        ],
      );
      writeFlac('test.flac', flac);

      final result = await runCli(['--list', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('pictures'));
      expect((json['pictures'] as List).length, equals(1));
      expect(json['pictures'][0]['mimeType'], equals('image/jpeg'));
    });
  });

  group('--show-md5 --json', () {
    test('produces JSON with md5 key', () async {
      final flac = buildFlac();
      writeFlac('test.flac', flac);

      final result =
          await runCli(['--show-md5', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('md5'));
      expect(json, contains('file'));
    });
  });

  group('--export-tags-to=- --json', () {
    test('produces JSON with tags key', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Song'),
              VorbisCommentEntry(key: 'ARTIST', value: 'Band'),
            ],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runCli(
          ['--export-tags-to=-', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('tags'));
      expect(json, contains('file'));
    });
  });

  group('--dry-run', () {
    test('does not modify the file', () async {
      final flac = buildFlac(paddingSize: 512);
      writeFlac('test.flac', flac);
      final beforeBytes = File(tmpFile('test.flac')).readAsBytesSync();

      final result = await runCli([
        '--set-tag=TITLE=DryRunTest',
        '--dry-run',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final afterBytes = File(tmpFile('test.flac')).readAsBytesSync();
      expect(afterBytes, equals(beforeBytes));
    });

    test('reports what would change with --json', () async {
      final flac = buildFlac(paddingSize: 512);
      writeFlac('test.flac', flac);

      final result = await runCli([
        '--set-tag=TITLE=DryRunTest',
        '--dry-run',
        '--json',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('dryRun'));
      expect(json['dryRun'], isTrue);
      expect(json, contains('mutations'));
    });
  });

  group('--continue-on-error', () {
    test('processes all files even when one fails', () async {
      final flac = buildFlac();
      writeFlac('good.flac', flac);
      // Write a bad file (not valid FLAC)
      File(tmpFile('bad.flac')).writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

      final result = await runCli([
        '--list',
        '--json',
        '--continue-on-error',
        tmpFile('bad.flac'),
        tmpFile('good.flac'),
      ]);

      // Exit code 1 because at least one file failed
      expect(result.exitCode, equals(1));

      // The good file's output should still appear on stdout
      final stdoutStr = result.stdout as String;
      expect(stdoutStr, contains('streamInfo'));
    });
  });

  group('--quiet / -q', () {
    test('suppresses stdout on write operations', () async {
      final flac = buildFlac(paddingSize: 512);
      writeFlac('test.flac', flac);

      final result = await runCli([
        '--set-tag=TITLE=QuietTest',
        '--quiet',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), isEmpty);
    });
  });

  group('exit codes', () {
    test('exit code 2 for invalid arguments', () async {
      final result = await runCli(['--not-a-real-flag']);
      expect(result.exitCode, equals(2));
    });

    test('exit code 3 for invalid FLAC file', () async {
      File(tmpFile('bad.flac')).writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

      final result = await runCli(['--list', tmpFile('bad.flac')]);
      expect(result.exitCode, equals(3));
    });

    test('exit code 4 for missing file', () async {
      final result =
          await runCli(['--list', tmpFile('nonexistent.flac')]);
      expect(result.exitCode, equals(4));
    });

    test('exit code 2 when no files specified', () async {
      final result = await runCli(['--list']);
      expect(result.exitCode, equals(2));
    });
  });

  group('JSON write output', () {
    test('write operations output JSON with success flag', () async {
      final flac = buildFlac(paddingSize: 512);
      writeFlac('test.flac', flac);

      final result = await runCli([
        '--set-tag=TITLE=JsonWrite',
        '--json',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['operation'], equals('write'));
      expect(json, contains('mutations'));
    });
  });

  group('JSON error output', () {
    test('errors on stderr as JSON when --json is set', () async {
      File(tmpFile('bad.flac')).writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

      final result = await runCli(['--list', '--json', tmpFile('bad.flac')]);
      expect(result.exitCode, equals(3));

      final json =
          jsonDecode(result.stderr as String) as Map<String, dynamic>;
      expect(json, contains('error'));
      expect(json, contains('file'));
    });
  });
}
