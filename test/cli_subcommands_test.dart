/// CLI subcommand integration tests.
///
/// Tests the new subcommand-style interface (inspect, blocks list, tags list)
/// by running the CLI as a subprocess.
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
  siData[12] = ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
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

Future<ProcessResult> runMetaflac(List<String> args) async {
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
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    projectRoot = '/home/paul/gitHUB/dart-metaflac';
  }

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('metaflac_subcmd_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('inspect', () {
    test('lists metadata containing STREAMINFO', () async {
      final flac = buildFlac(sampleRate: 48000);
      writeFlac('test.flac', flac);

      final result = await runMetaflac(['inspect', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));
      expect(result.stdout as String, contains('STREAMINFO'));
      expect(result.stdout as String, contains('sample_rate: 48000'));
    });

    test('--json produces valid JSON with streamInfo key', () async {
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

      final result =
          await runMetaflac(['inspect', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('streamInfo'));
      expect(json['streamInfo']['sampleRate'], equals(48000));
      expect(json['streamInfo']['bitsPerSample'], equals(24));
      expect(json, contains('vorbisComment'));
      expect(json['vorbisComment']['tags']['TITLE'], equals('Test'));
    });

    test('with no file gives exit code 2', () async {
      final result = await runMetaflac(['inspect']);
      expect(result.exitCode, equals(2));
    });
  });

  group('blocks list', () {
    test('lists block types', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'T')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result =
          await runMetaflac(['blocks', 'list', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));
      final out = result.stdout as String;
      expect(out, contains('streamInfo'));
      expect(out, contains('vorbisComment'));
      expect(out, contains('padding'));
    });

    test('--json produces JSON array of blocks', () async {
      final flac = buildFlac();
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['blocks', 'list', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('blocks'));
      final blocks = json['blocks'] as List;
      expect(blocks, isNotEmpty);
      expect(blocks.first['type'], equals('streamInfo'));
      expect(blocks.first, contains('payloadSize'));
    });
  });

  group('tags list', () {
    test('shows KEY=VALUE pairs', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'My Song'),
              VorbisCommentEntry(key: 'ARTIST', value: 'Test Artist'),
            ],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result =
          await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));
      final out = result.stdout as String;
      expect(out, contains('TITLE=My Song'));
      expect(out, contains('ARTIST=Test Artist'));
    });

    test('--json produces JSON with tags', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'test-vendor',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Song'),
              VorbisCommentEntry(key: 'ARTIST', value: 'Band'),
            ],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['tags', 'list', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json, contains('tags'));
      expect(json['tags']['TITLE'], equals('Song'));
      expect(json['tags']['ARTIST'], equals('Band'));
      expect(json['vendorString'], equals('test-vendor'));
    });

    test('with no file gives exit code 2', () async {
      final result = await runMetaflac(['tags', 'list']);
      expect(result.exitCode, equals(2));
    });
  });
}
