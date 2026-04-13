/// CLI subprocess tests using the real siren.flac fixture.
///
/// These tests run the CLI as a subprocess against a real libFLAC-encoded
/// file, verifying read operations, write operations, audio integrity,
/// and CLI options.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'test_fixtures.dart';

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

String copySiren({String name = 'siren.flac'}) {
  return copySirenTo(tmpDir, name: name);
}

void main() {
  projectRoot = Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    projectRoot = '/home/paul/gitHUB/dart-metaflac';
  }

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('real_flac_cli_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  // ─── Group 1: Read operations ────────────────────────────────────────────

  group('CLI read operations on real FLAC', () {
    test('inspect --json returns correct STREAMINFO', () async {
      final path = copySiren();
      final result = await runMetaflac(['inspect', '--json', path]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final si = json['streamInfo'] as Map<String, dynamic>;
      expect(si['sampleRate'], equals(48000));
      expect(si['channelCount'], equals(1));
      expect(si['bitsPerSample'], equals(32));
      expect(si['totalSamples'], equals(240000));
    });

    test('--show-md5 --json returns expected MD5', () async {
      final path = copySiren();
      final result = await runMetaflac(['--show-md5', '--json', path]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['md5'], equals('09bffcd26cb9701e61558be6695a7680'));
    });

    test('tags list shows existing tag', () async {
      final path = copySiren();
      final result = await runMetaflac(['tags', 'list', path]);
      expect(result.exitCode, equals(0));
      expect(
        result.stdout as String,
        contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK=0x0004'),
      );
    });

    test('tags list --json has correct key/value', () async {
      final path = copySiren();
      final result = await runMetaflac(['tags', 'list', '--json', path]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final tags = json['tags'] as Map<String, dynamic>;
      expect(tags['WAVEFORMATEXTENSIBLE_CHANNEL_MASK'], equals('0x0004'));
    });

    test('blocks list --json shows all block types', () async {
      final path = copySiren();
      final result = await runMetaflac(['blocks', 'list', '--json', path]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final blocks = json['blocks'] as List<dynamic>;
      final types =
          blocks.map((b) => (b as Map<String, dynamic>)['type']).toSet();
      expect(
          types,
          containsAll([
            'streamInfo',
            'seekTable',
            'vorbisComment',
            'application',
            'padding',
          ]));
    });

    test('tags export outputs KEY=VALUE format', () async {
      final path = copySiren();
      final result = await runMetaflac(['tags', 'export', path]);
      expect(result.exitCode, equals(0));
      expect(
        result.stdout as String,
        contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK=0x0004'),
      );
    });
  });

  // ─── Group 2: Write operations ───────────────────────────────────────────

  group('CLI write operations on real FLAC', () {
    test('tags set adds a new tag, original tag preserved', () async {
      final path = copySiren();
      var result = await runMetaflac([
        'tags',
        'set',
        path,
        'ARTIST=Test Artist',
      ]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['tags', 'list', path]);
      final output = result.stdout as String;
      expect(output, contains('ARTIST=Test Artist'));
      expect(output, contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK=0x0004'));
    });

    test('tags add appends without replacing', () async {
      final path = copySiren();
      var result = await runMetaflac([
        'tags',
        'add',
        path,
        'GENRE=Electronic',
      ]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['tags', 'list', path]);
      final output = result.stdout as String;
      expect(output, contains('GENRE=Electronic'));
      expect(output, contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK=0x0004'));
    });

    test('tags remove deletes a specific tag', () async {
      final path = copySiren();
      var result = await runMetaflac([
        'tags',
        'remove',
        path,
        'WAVEFORMATEXTENSIBLE_CHANNEL_MASK',
      ]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['tags', 'list', path]);
      expect(
        result.stdout as String,
        isNot(contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK')),
      );
    });

    test('tags clear removes all tags', () async {
      final path = copySiren();
      var result = await runMetaflac(['tags', 'clear', path]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['tags', 'list', path]);
      final output = (result.stdout as String).trim();
      expect(output, isEmpty);
    });

    test('tags import from file', () async {
      final path = copySiren();
      final tagFile = '${tmpDir.path}/tags.txt';
      File(tagFile).writeAsStringSync(
        'ARTIST=Imported Artist\nALBUM=Imported Album\n',
      );

      var result = await runMetaflac([
        'tags',
        'import',
        '--from=$tagFile',
        path,
      ]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['tags', 'list', path]);
      final output = result.stdout as String;
      expect(output, contains('ARTIST=Imported Artist'));
      expect(output, contains('ALBUM=Imported Album'));
    });

    test('tags export then clear then import round-trip', () async {
      final path = copySiren();
      final exportFile = '${tmpDir.path}/exported.txt';

      // Add some tags first
      await runMetaflac([
        'tags',
        'set',
        path,
        'ARTIST=Round Trip',
      ]);

      // Export
      var result = await runMetaflac([
        'tags',
        'export',
        '--output=$exportFile',
        path,
      ]);
      expect(result.exitCode, equals(0));

      // Clear
      result = await runMetaflac(['tags', 'clear', path]);
      expect(result.exitCode, equals(0));

      // Verify cleared
      result = await runMetaflac(['tags', 'list', path]);
      expect((result.stdout as String).trim(), isEmpty);

      // Import
      result = await runMetaflac([
        'tags',
        'import',
        '--from=$exportFile',
        path,
      ]);
      expect(result.exitCode, equals(0));

      // Verify restored
      result = await runMetaflac(['tags', 'list', path]);
      final output = result.stdout as String;
      expect(output, contains('ARTIST=Round Trip'));
      expect(output, contains('WAVEFORMATEXTENSIBLE_CHANNEL_MASK=0x0004'));
    });

    test('picture add then picture export round-trip', () async {
      final path = copySiren();

      // Create a minimal PNG file (8-byte signature + IHDR + IEND)
      final pngBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, // IHDR length
        0x49, 0x48, 0x44, 0x52, // "IHDR"
        0x00, 0x00, 0x00, 0x01, // width: 1
        0x00, 0x00, 0x00, 0x01, // height: 1
        0x08, 0x02, // bit depth: 8, colour type: 2 (RGB)
        0x00, 0x00, 0x00, // compression, filter, interlace
        0x90, 0x77, 0x53, 0xDE, // CRC
        0x00, 0x00, 0x00, 0x0C, // IDAT length
        0x49, 0x44, 0x41, 0x54, // "IDAT"
        0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, // deflated data
        0x00, 0x02, 0x00, 0x01, // adler32
        0xE2, 0x21, 0xBC, 0x33, // CRC
        0x00, 0x00, 0x00, 0x00, // IEND length
        0x49, 0x45, 0x4E, 0x44, // "IEND"
        0xAE, 0x42, 0x60, 0x82, // CRC
      ]);
      final pngPath = '${tmpDir.path}/cover.png';
      File(pngPath).writeAsBytesSync(pngBytes);

      // Add picture
      var result = await runMetaflac([
        'picture',
        'add',
        '--file=$pngPath',
        path,
      ]);
      expect(result.exitCode, equals(0));

      // Export picture
      final exportPath = '${tmpDir.path}/exported.png';
      result = await runMetaflac([
        'picture',
        'export',
        '--output=$exportPath',
        path,
      ]);
      expect(result.exitCode, equals(0));

      // Verify exported bytes match original
      final exported = File(exportPath).readAsBytesSync();
      expect(exported, equals(pngBytes));
    });

    test('picture remove --all', () async {
      final path = copySiren();
      final pngPath = '${tmpDir.path}/cover.png';
      File(pngPath).writeAsBytesSync(Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x02,
        0x00,
        0x00,
        0x00,
        0x90,
        0x77,
        0x53,
        0xDE,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]));

      // Add then remove
      await runMetaflac(['picture', 'add', '--file=$pngPath', path]);
      var result = await runMetaflac(['picture', 'remove', '--all', path]);
      expect(result.exitCode, equals(0));

      // Verify no pictures via inspect
      result = await runMetaflac(['inspect', '--json', path]);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json.containsKey('pictures'), isFalse);
    });

    test('padding set to specific size', () async {
      final path = copySiren();
      var result = await runMetaflac(['padding', 'set', path, '4096']);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['blocks', 'list', '--json', path]);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final blocks = json['blocks'] as List<dynamic>;
      final padding = blocks.firstWhere(
        (b) => (b as Map<String, dynamic>)['type'] == 'padding',
      ) as Map<String, dynamic>;
      expect(padding['payloadSize'], equals(4096));
    });

    test('padding remove', () async {
      final path = copySiren();
      var result = await runMetaflac(['padding', 'remove', path]);
      expect(result.exitCode, equals(0));

      result = await runMetaflac(['blocks', 'list', '--json', path]);
      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final blocks = json['blocks'] as List<dynamic>;
      final paddingBlocks = blocks.where(
        (b) => (b as Map<String, dynamic>)['type'] == 'padding',
      );
      expect(paddingBlocks, isEmpty);
    });
  });

  // ─── Group 3: Audio integrity via CLI ────────────────────────────────────

  group('CLI audio data integrity', () {
    test('file remains valid FLAC after tag mutations', () async {
      final path = copySiren();

      // Apply multiple mutations
      await runMetaflac(['tags', 'set', path, 'ARTIST=Test']);
      await runMetaflac(['tags', 'add', path, 'ALBUM=Album']);
      await runMetaflac(['tags', 'add', path, 'GENRE=Rock']);

      // Re-inspect should succeed with same STREAMINFO
      final result = await runMetaflac(['inspect', '--json', path]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final si = json['streamInfo'] as Map<String, dynamic>;
      expect(si['sampleRate'], equals(48000));
      expect(si['channelCount'], equals(1));
      expect(si['totalSamples'], equals(240000));
    });

    test('MD5 signature unchanged after metadata-only edits', () async {
      final path = copySiren();

      // Get original MD5
      var result = await runMetaflac(['--show-md5', '--json', path]);
      final originalMd5 = (jsonDecode(result.stdout as String)
          as Map<String, dynamic>)['md5'] as String;

      // Apply edits
      await runMetaflac(['tags', 'set', path, 'TITLE=Modified']);
      await runMetaflac(['padding', 'set', path, '2048']);

      // Check MD5 unchanged
      result = await runMetaflac(['--show-md5', '--json', path]);
      final newMd5 = (jsonDecode(result.stdout as String)
          as Map<String, dynamic>)['md5'] as String;
      expect(newMd5, equals(originalMd5));
    });
  });

  // ─── Group 4: CLI options ────────────────────────────────────────────────

  group('CLI options with real FLAC', () {
    test('--dry-run does not modify file', () async {
      final path = copySiren();
      final beforeBytes = File(path).readAsBytesSync();

      final result = await runMetaflac([
        'tags',
        'set',
        '--dry-run',
        path,
        'ARTIST=Dry',
      ]);
      expect(result.exitCode, equals(0));

      final afterBytes = File(path).readAsBytesSync();
      expect(afterBytes, equals(beforeBytes));
    });

    test('--dry-run --json reports planned mutations', () async {
      final path = copySiren();
      final result = await runMetaflac([
        'tags',
        'set',
        '--dry-run',
        '--json',
        path,
        'ARTIST=Dry',
      ]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['dryRun'], isTrue);
    });

    test('--quiet suppresses stdout on write', () async {
      final path = copySiren();
      final result = await runMetaflac([
        'tags',
        'set',
        '--quiet',
        path,
        'ARTIST=Quiet',
      ]);
      expect(result.exitCode, equals(0));
      expect((result.stdout as String).trim(), isEmpty);
    });

    test('--preserve-modtime preserves modification time', () async {
      final path = copySiren();
      final oldTime = DateTime(2020, 6, 15);
      File(path).setLastModifiedSync(oldTime);

      final result = await runMetaflac([
        'tags',
        'set',
        '--preserve-modtime',
        path,
        'ARTIST=Preserved',
      ]);
      expect(result.exitCode, equals(0));

      final modTime = File(path).lastModifiedSync();
      expect(modTime.difference(oldTime).inSeconds.abs(), lessThanOrEqualTo(2));
    });

    test('--with-filename includes filename in output', () async {
      final path = copySiren();
      final result = await runMetaflac([
        'inspect',
        '--with-filename',
        path,
      ]);
      expect(result.exitCode, equals(0));
      expect(result.stdout as String, contains('siren.flac'));
    });
  });

  // ─── Group 5: Multi-file and error handling ──────────────────────────────

  group('CLI multi-file operations', () {
    test('processes multiple copies of real FLAC', () async {
      final path1 = copySirenTo(tmpDir, name: 'copy1.flac');
      final path2 = copySirenTo(tmpDir, name: 'copy2.flac');

      final result = await runMetaflac([
        'inspect',
        '--json',
        path1,
        path2,
      ]);
      expect(result.exitCode, equals(0));
    });

    test('--continue-on-error with mixed real and bad files', () async {
      final goodPath = copySiren();
      final badPath = '${tmpDir.path}/bad.flac';
      File(badPath).writeAsBytesSync(Uint8List.fromList([0, 1, 2, 3]));

      final result = await runMetaflac([
        'inspect',
        '--json',
        '--continue-on-error',
        goodPath,
        badPath,
      ]);
      // Should process the good file even though the bad one fails
      final output = result.stdout as String;
      expect(output, contains('48000'));
    });
  });
}
