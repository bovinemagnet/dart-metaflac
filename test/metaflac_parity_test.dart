/// Integration tests for the metaflac-compatible legacy flags added in
/// Tier 1 and Tier 2 of the parity effort.
///
/// Each test runs `bin/metaflac.dart` as a subprocess (matching the
/// pattern used by `cli_test.dart`) against a synthetic fixture with
/// known STREAMINFO values, tags, and optional picture. The assertions
/// cover every new legacy flag end-to-end and confirm the output
/// matches what upstream `metaflac` would produce.
///
/// Tier 1 covers the show-ops and global flags; Tier 2 covers the three
/// new vorbis-comment mutations. Tier 3–6 flags are deferred (see the
/// metaflac-parity tracking issues).
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

String tmpFile(String name) => '${tmpDir.path}/$name';

void main() {
  projectRoot = Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    projectRoot = '/home/paul/gitHUB/dart-metaflac';
  }

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('metaflac_parity_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // Fixture built with specific streaminfo values so scalar show-ops
  // produce predictable output. Uses the shared `buildFlac` helper from
  // test/test_fixtures.dart.
  String buildFixture() {
    final bytes = buildFlac(
      sampleRate: 48000,
      channels: 2,
      bitsPerSample: 24,
      totalSamples: 144000,
      paddingSize: 512,
      // Include a VORBIS_COMMENT block with four tags and a couple of
      // REPLAYGAIN entries so --remove-replay-gain has something to do.
      vorbisComment: _vc([
        ('ARTIST', 'Parity Artist'),
        ('TITLE', 'Parity Title'),
        ('ALBUM', 'Parity Album'),
        ('DATE', '2026'),
        ('REPLAYGAIN_TRACK_GAIN', '-6.51 dB'),
        ('REPLAYGAIN_TRACK_PEAK', '0.998046'),
        ('REPLAYGAIN_ALBUM_GAIN', '-6.23 dB'),
      ]),
    );
    final path = tmpFile('parity.flac');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  group('Tier 1: STREAMINFO scalar show-ops', () {
    test('--show-sample-rate prints the raw sample rate', () async {
      final path = buildFixture();
      final r = await runCli(['--show-sample-rate', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '48000');
    });

    test('--show-channels prints the channel count', () async {
      final path = buildFixture();
      final r = await runCli(['--show-channels', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '2');
    });

    test('--show-bps prints bits per sample', () async {
      final path = buildFixture();
      final r = await runCli(['--show-bps', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '24');
    });

    test('--show-total-samples prints the total sample count', () async {
      final path = buildFixture();
      final r = await runCli(['--show-total-samples', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '144000');
    });

    test('--show-min-blocksize and --show-max-blocksize return integers',
        () async {
      final path = buildFixture();
      final minR = await runCli(['--show-min-blocksize', path]);
      expect(minR.exitCode, 0);
      expect(int.tryParse(minR.stdout.toString().trim()), isNotNull);

      final maxR = await runCli(['--show-max-blocksize', path]);
      expect(maxR.exitCode, 0);
      expect(int.tryParse(maxR.stdout.toString().trim()), isNotNull);
    });

    test('--show-min-framesize and --show-max-framesize return integers',
        () async {
      final path = buildFixture();
      final minR = await runCli(['--show-min-framesize', path]);
      expect(minR.exitCode, 0);
      expect(int.tryParse(minR.stdout.toString().trim()), isNotNull);

      final maxR = await runCli(['--show-max-framesize', path]);
      expect(maxR.exitCode, 0);
      expect(int.tryParse(maxR.stdout.toString().trim()), isNotNull);
    });

    test('--show-md5sum is a working alias for --show-md5', () async {
      final path = buildFixture();
      final r1 = await runCli(['--show-md5', path]);
      final r2 = await runCli(['--show-md5sum', path]);
      expect(r1.exitCode, 0);
      expect(r2.exitCode, 0);
      expect(r1.stdout.toString().trim(), equals(r2.stdout.toString().trim()));
    });

    test('scalar show-ops emit JSON when --json is set', () async {
      final path = buildFixture();
      final r = await runCli(['--show-sample-rate', '--json', path]);
      expect(r.exitCode, 0);
      final json = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
      expect(json['sampleRate'], 48000);
      expect(json['file'], path);
    });
  });

  group('Tier 1: Vorbis comment show-ops', () {
    test('--show-vendor-tag prints the vendor string', () async {
      final path = buildFixture();
      final r = await runCli(['--show-vendor-tag', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), isNotEmpty);
    });

    test('--show-tag=NAME prints only matching entries', () async {
      final path = buildFixture();
      final r = await runCli(['--show-tag=ARTIST', path]);
      expect(r.exitCode, 0);
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, contains('ARTIST=Parity Artist'));
      expect(lines.where((l) => l.startsWith('TITLE')), isEmpty);
    });

    test('--show-tag=NAME with --json returns values array', () async {
      final path = buildFixture();
      final r = await runCli(['--show-tag=TITLE', '--json', path]);
      expect(r.exitCode, 0);
      final json = jsonDecode(r.stdout.toString()) as Map<String, dynamic>;
      expect(json['tag'], 'TITLE');
      expect(json['values'], ['Parity Title']);
    });

    test('--show-all-tags prints every entry', () async {
      final path = buildFixture();
      final r = await runCli(['--show-all-tags', path]);
      expect(r.exitCode, 0);
      final out = r.stdout.toString();
      expect(out, contains('ARTIST=Parity Artist'));
      expect(out, contains('TITLE=Parity Title'));
      expect(out, contains('ALBUM=Parity Album'));
      expect(out, contains('DATE=2026'));
    });
  });

  group('Tier 1: global options and output redirection', () {
    test('--no-filename strips the filename prefix even with multiple files',
        () async {
      final path = buildFixture();
      final path2 = tmpFile('parity2.flac');
      File(path2).writeAsBytesSync(File(path).readAsBytesSync());
      final r =
          await runCli(['--show-sample-rate', '--no-filename', path, path2]);
      expect(r.exitCode, 0);
      // With --no-filename we expect just '48000\n48000' and no path
      // prefix on either line.
      final lines = r.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, equals(['48000', '48000']));
    });

    test('-o writes to the output file and leaves the input intact', () async {
      final path = buildFixture();
      final outPath = tmpFile('parity-out.flac');
      final originalBytes = File(path).readAsBytesSync();

      final r =
          await runCli(['--set-tag=ARTIST=Output Artist', '-o', outPath, path]);
      expect(r.exitCode, 0);
      expect(File(outPath).existsSync(), isTrue);

      // Input untouched.
      expect(File(path).readAsBytesSync(), equals(originalBytes));

      // Output has the new tag.
      final showOut = await runCli(['--show-tag=ARTIST', outPath]);
      expect(showOut.exitCode, 0);
      expect(
          showOut.stdout.toString().trim(), contains('ARTIST=Output Artist'));
    });

    test('--no-utf8-convert is accepted as a no-op', () async {
      final path = buildFixture();
      final r = await runCli(['--show-sample-rate', '--no-utf8-convert', path]);
      expect(r.exitCode, 0);
      expect(r.stdout.toString().trim(), '48000');
    });

    test('--dont-use-padding is accepted and triggers a full rewrite',
        () async {
      final path = buildFixture();
      final r = await runCli([
        '--set-tag=COMMENT=forces rewrite',
        '--dont-use-padding',
        '--dry-run',
        path,
      ]);
      expect(r.exitCode, 0);
      // With explicitPaddingSize=0 any metadata growth forces a full
      // rewrite rather than reusing padding.
      expect(r.stdout.toString(), contains('requires full rewrite: true'));
    });
  });

  group('Tier 1: ReplayGain removal', () {
    test('--remove-replay-gain drops all REPLAYGAIN_* tags', () async {
      final path = buildFixture();

      final before = await runCli(['--show-all-tags', path]);
      expect(before.stdout.toString(), contains('REPLAYGAIN_TRACK_GAIN'));

      final rm = await runCli(['--remove-replay-gain', path]);
      expect(rm.exitCode, 0);

      final after = await runCli(['--show-all-tags', path]);
      expect(after.stdout.toString(), isNot(contains('REPLAYGAIN_TRACK_GAIN')));
      expect(after.stdout.toString(), isNot(contains('REPLAYGAIN_TRACK_PEAK')));
      expect(after.stdout.toString(), isNot(contains('REPLAYGAIN_ALBUM_GAIN')));
      // Non-RG tags survive.
      expect(after.stdout.toString(), contains('ARTIST=Parity Artist'));
    });
  });

  group('Tier 2: new tag mutations', () {
    test('--remove-first-tag drops only the first matching entry', () async {
      // Build a fixture with TWO ARTIST entries so we can verify only
      // the first is removed.
      final bytes = buildFlac(
        paddingSize: -1,
        vorbisComment: _vc([
          ('ARTIST', 'First'),
          ('ARTIST', 'Second'),
          ('TITLE', 'Only Title'),
        ]),
      );
      final path = tmpFile('two_artists.flac');
      File(path).writeAsBytesSync(bytes);

      final r = await runCli(['--remove-first-tag=ARTIST', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-tag=ARTIST', path]);
      expect(after.exitCode, 0);
      final lines = after.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines, equals(['ARTIST=Second']));
    });

    test('--remove-all-tags-except retains only the named fields', () async {
      final path = buildFixture();
      final r = await runCli(['--remove-all-tags-except=TITLE=DATE', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-all-tags', path]);
      expect(after.exitCode, 0);
      final out = after.stdout.toString();
      expect(out, contains('TITLE=Parity Title'));
      expect(out, contains('DATE=2026'));
      expect(out, isNot(contains('ARTIST')));
      expect(out, isNot(contains('ALBUM')));
      expect(out, isNot(contains('REPLAYGAIN_')));
    });

    test('--set-tag-from-file reads VALUE from a file', () async {
      final path = buildFixture();
      final valuePath = tmpFile('notes.txt');
      File(valuePath).writeAsStringSync('Multi-line\nCOMMENT from a file');

      final r = await runCli(['--set-tag-from-file=COMMENT=$valuePath', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-tag=COMMENT', path]);
      expect(after.exitCode, 0);
      // The file contents are written as a single multi-line value;
      // display is one line per --show-tag hit.
      expect(after.stdout.toString(), contains('Multi-line'));
      expect(after.stdout.toString(), contains('COMMENT from a file'));
    });
  });

  // These tests specifically exercise the `bin/metaflac.dart` legacy
  // router's flag → operation wiring. The underlying behaviour is
  // already covered by the modern subcommand tests in
  // `test/cli_subcommands_test.dart`, but those tests never drive the
  // legacy router, so a regression in the router glue would not be
  // caught without these.
  group('Legacy router flag wiring', () {
    test('--remove-tag drops every matching entry', () async {
      final path = buildFixture();
      final r =
          await runCli(['--remove-tag=ARTIST', '--remove-tag=DATE', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-all-tags', path]);
      expect(after.exitCode, 0);
      final out = after.stdout.toString();
      expect(out, isNot(contains('ARTIST')));
      expect(out, isNot(contains('DATE')));
      expect(out, contains('TITLE=Parity Title'));
      expect(out, contains('ALBUM=Parity Album'));
    });

    test('--remove-all-tags strips every entry', () async {
      final path = buildFixture();
      final r = await runCli(['--remove-all-tags', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-all-tags', path]);
      expect(after.exitCode, 0);
      // Every user tag gone; --show-all-tags emits nothing on the
      // happy path (the block may still exist with just the vendor
      // string, but no entries print).
      expect(after.stdout.toString().trim(), isEmpty);
    });

    test('--import-tags-from reads NAME=VALUE lines from a file', () async {
      // Start from a minimal fixture with no tags so we can tell exactly
      // what got imported.
      final bytes = buildFlac(paddingSize: -1);
      final path = tmpFile('empty.flac');
      File(path).writeAsBytesSync(bytes);

      final tagsFile = tmpFile('tags.txt');
      File(tagsFile).writeAsStringSync(
        'ARTIST=Imported Artist\n'
        'TITLE=Imported Title\n'
        'GENRE=Imported Genre\n',
      );

      final r = await runCli(['--import-tags-from=$tagsFile', path]);
      expect(r.exitCode, 0);

      final after = await runCli(['--show-all-tags', path]);
      expect(after.exitCode, 0);
      final out = after.stdout.toString();
      expect(out, contains('ARTIST=Imported Artist'));
      expect(out, contains('TITLE=Imported Title'));
      expect(out, contains('GENRE=Imported Genre'));
    });

    test('--import-picture-from attaches a PICTURE block', () async {
      final bytes = buildFlac(paddingSize: -1);
      final path = tmpFile('nopicture.flac');
      File(path).writeAsBytesSync(bytes);

      // Tiny valid JPEG-ish payload; the library only needs the bytes,
      // it does not decode them.
      final picPath = tmpFile('cover.jpg');
      File(picPath).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);

      final r = await runCli(['--import-picture-from=$picPath', path]);
      expect(r.exitCode, 0);

      // Use --list to confirm the picture block now exists.
      final after = await runCli(['--list', '--json', path]);
      expect(after.exitCode, 0);
      final json = jsonDecode(after.stdout.toString()) as Map<String, dynamic>;
      expect(json['pictures'], isNotNull);
      expect(json['pictures'] as List, hasLength(1));
    });

    test('--export-picture-to writes the embedded picture to disc', () async {
      final path = buildFixture();
      // First attach a picture so there is something to export.
      final picPath = tmpFile('in.jpg');
      final picBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0xDE, 0xAD, 0xBE, 0xEF];
      File(picPath).writeAsBytesSync(picBytes);
      final attach = await runCli(['--import-picture-from=$picPath', path]);
      expect(attach.exitCode, 0);

      // Now export it back out to a different path.
      final outPath = tmpFile('out.jpg');
      final exp = await runCli(['--export-picture-to=$outPath', path]);
      expect(exp.exitCode, 0);
      expect(File(outPath).existsSync(), isTrue);
      expect(File(outPath).readAsBytesSync(), equals(picBytes));
    });

    test('--output-name long form writes to a new file', () async {
      final path = buildFixture();
      final outPath = tmpFile('via-long-form.flac');
      final originalBytes = File(path).readAsBytesSync();

      final r = await runCli([
        '--set-tag=ARTIST=Long Form Artist',
        '--output-name=$outPath',
        path,
      ]);
      expect(r.exitCode, 0);
      expect(File(outPath).existsSync(), isTrue);

      // Input untouched.
      expect(File(path).readAsBytesSync(), equals(originalBytes));

      // Output carries the new tag.
      final show = await runCli(['--show-tag=ARTIST', outPath]);
      expect(show.exitCode, 0);
      expect(
          show.stdout.toString().trim(), contains('ARTIST=Long Form Artist'));
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

VorbisCommentBlock _vc(List<(String, String)> entries) {
  return VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac parity test',
      entries: entries
          .map((e) => VorbisCommentEntry(key: e.$1, value: e.$2))
          .toList(),
    ),
  );
}
