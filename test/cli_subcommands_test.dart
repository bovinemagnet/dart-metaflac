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

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
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

      final result =
          await runMetaflac(['blocks', 'list', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
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

      final result = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
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

      final result =
          await runMetaflac(['tags', 'list', '--json', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
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

  group('tags set', () {
    test('sets a tag value', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['tags', 'set', tmpFile('test.flac'), 'ARTIST=Test']);
      expect(result.exitCode, equals(0));

      // Verify by re-reading
      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      expect(verify.stdout as String, contains('ARTIST=Test'));
      expect(verify.stdout as String, contains('TITLE=Old'));
    });

    test('replaces existing tag value', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Old')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result =
          await runMetaflac(['tags', 'set', tmpFile('test.flac'), 'TITLE=New']);
      expect(result.exitCode, equals(0));

      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      final out = verify.stdout as String;
      expect(out, contains('TITLE=New'));
      expect(out, isNot(contains('TITLE=Old')));
    });

    test('--dry-run does not modify file', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'Original')],
          ),
        ),
      );
      writeFlac('test.flac', flac);
      final originalBytes = File(tmpFile('test.flac')).readAsBytesSync();

      final result = await runMetaflac(
          ['tags', 'set', '--dry-run', tmpFile('test.flac'), 'ARTIST=Test']);
      expect(result.exitCode, equals(0));
      expect(result.stdout as String, contains('Dry run'));

      final afterBytes = File(tmpFile('test.flac')).readAsBytesSync();
      expect(afterBytes, equals(originalBytes));
    });

    test('--json produces JSON success output', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'TITLE', value: 'T')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['tags', 'set', '--json', tmpFile('test.flac'), 'ARTIST=Test']);
      expect(result.exitCode, equals(0));

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['mutationsApplied'], equals(1));
    });
  });

  group('tags add', () {
    test('adds a tag value preserving existing', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [VorbisCommentEntry(key: 'GENRE', value: 'Rock')],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['tags', 'add', tmpFile('test.flac'), 'GENRE=Jazz']);
      expect(result.exitCode, equals(0));

      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      final out = verify.stdout as String;
      expect(out, contains('GENRE=Rock'));
      expect(out, contains('GENRE=Jazz'));
    });
  });

  group('tags remove', () {
    test('removes all values for a key', () async {
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

      final result =
          await runMetaflac(['tags', 'remove', tmpFile('test.flac'), 'TITLE']);
      expect(result.exitCode, equals(0));

      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      final out = verify.stdout as String;
      expect(out, isNot(contains('TITLE')));
      expect(out, contains('ARTIST=Band'));
    });
  });

  group('tags clear', () {
    test('removes all tags', () async {
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

      final result = await runMetaflac(['tags', 'clear', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      final out = (verify.stdout as String).trim();
      expect(out, isEmpty);
    });
  });

  group('tags export', () {
    test('exports KEY=VALUE output to stdout', () async {
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
          await runMetaflac(['tags', 'export', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));
      final out = result.stdout as String;
      expect(out, contains('TITLE=My Song'));
      expect(out, contains('ARTIST=Test Artist'));
    });

    test('exports to file with --output', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [
              VorbisCommentEntry(key: 'TITLE', value: 'Song'),
            ],
          ),
        ),
      );
      writeFlac('test.flac', flac);
      final outPath = tmpFile('tags.txt');

      final result = await runMetaflac(
          ['tags', 'export', '--output=$outPath', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final content = File(outPath).readAsStringSync();
      expect(content, contains('TITLE=Song'));
    });
  });

  group('tags import', () {
    test('imports tags from a text file', () async {
      final flac = buildFlac(
        vorbisComment: VorbisCommentBlock(
          comments: VorbisComments(
            vendorString: 'v',
            entries: [],
          ),
        ),
      );
      writeFlac('test.flac', flac);

      final tagFilePath = tmpFile('tags.txt');
      File(tagFilePath).writeAsStringSync('TITLE=Imported\nARTIST=Someone\n');

      final result = await runMetaflac(
          ['tags', 'import', '--from=$tagFilePath', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      final verify = await runMetaflac(['tags', 'list', tmpFile('test.flac')]);
      final out = verify.stdout as String;
      expect(out, contains('TITLE=Imported'));
      expect(out, contains('ARTIST=Someone'));
    });
  });

  group('picture add', () {
    test('adds a picture from an image file', () async {
      final flac = buildFlac();
      writeFlac('test.flac', flac);

      // Write a minimal PNG file (magic bytes).
      final pngBytes =
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      File(tmpFile('cover.png')).writeAsBytesSync(pngBytes);

      final result = await runMetaflac([
        'picture',
        'add',
        '--file=${tmpFile('cover.png')}',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));

      // Verify picture exists by inspecting with JSON.
      final verify =
          await runMetaflac(['inspect', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(verify.stdout as String) as Map<String, dynamic>;
      expect(json, contains('pictures'));
      final pics = json['pictures'] as List;
      expect(pics, isNotEmpty);
      expect(pics.first['mimeType'], equals('image/png'));
    });
  });

  group('picture remove', () {
    test('--all removes all pictures', () async {
      final picData = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final flac = buildFlac(
        pictures: [
          PictureBlock(
            pictureType: PictureType.frontCover,
            mimeType: 'image/png',
            description: '',
            width: 0,
            height: 0,
            colorDepth: 0,
            indexedColors: 0,
            data: picData,
          ),
        ],
      );
      writeFlac('test.flac', flac);

      final result = await runMetaflac(
          ['picture', 'remove', '--all', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      // Verify no pictures remain.
      final verify =
          await runMetaflac(['inspect', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(verify.stdout as String) as Map<String, dynamic>;
      expect(json.containsKey('pictures'), isFalse);
    });
  });

  group('picture export', () {
    test('exports picture data to file', () async {
      final picData =
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final flac = buildFlac(
        pictures: [
          PictureBlock(
            pictureType: PictureType.frontCover,
            mimeType: 'image/png',
            description: '',
            width: 0,
            height: 0,
            colorDepth: 0,
            indexedColors: 0,
            data: picData,
          ),
        ],
      );
      writeFlac('test.flac', flac);

      final outPath = tmpFile('exported.png');
      final result = await runMetaflac([
        'picture',
        'export',
        '--output=$outPath',
        tmpFile('test.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final exported = File(outPath).readAsBytesSync();
      expect(exported, equals(picData));
    });
  });

  group('padding set', () {
    test('sets padding to a specific size', () async {
      final flac = buildFlac(paddingSize: 512);
      writeFlac('test.flac', flac);

      final result =
          await runMetaflac(['padding', 'set', tmpFile('test.flac'), '4096']);
      expect(result.exitCode, equals(0));

      // Verify padding block size.
      final verify =
          await runMetaflac(['blocks', 'list', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(verify.stdout as String) as Map<String, dynamic>;
      final blocks = json['blocks'] as List;
      final paddingBlocks =
          blocks.where((b) => b['type'] == 'padding').toList();
      expect(paddingBlocks, isNotEmpty);
      expect(paddingBlocks.first['payloadSize'], equals(4096));
    });
  });

  group('padding remove', () {
    test('removes all padding', () async {
      final flac = buildFlac(paddingSize: 1024);
      writeFlac('test.flac', flac);

      final result =
          await runMetaflac(['padding', 'remove', tmpFile('test.flac')]);
      expect(result.exitCode, equals(0));

      // Verify no padding blocks remain.
      final verify =
          await runMetaflac(['blocks', 'list', '--json', tmpFile('test.flac')]);
      final json = jsonDecode(verify.stdout as String) as Map<String, dynamic>;
      final blocks = json['blocks'] as List;
      final paddingBlocks =
          blocks.where((b) => b['type'] == 'padding').toList();
      expect(paddingBlocks, isEmpty);
    });
  });

  group('blocks remove', () {
    Uint8List flacWithPictureAndPadding() => buildFlac(
          vorbisComment: VorbisCommentBlock(
            comments: VorbisComments(
              vendorString: 'v',
              entries: [VorbisCommentEntry(key: 'TITLE', value: 'T')],
            ),
          ),
          pictures: [
            PictureBlock(
              pictureType: PictureType.frontCover,
              mimeType: 'image/jpeg',
              description: '',
              width: 0,
              height: 0,
              colorDepth: 0,
              indexedColors: 0,
              data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
            ),
          ],
        );

    test('removes blocks by type', () async {
      writeFlac('remove.flac', flacWithPictureAndPadding());
      final result = await runMetaflac([
        'blocks',
        'remove',
        '--block-type=PICTURE',
        tmpFile('remove.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final doc = FlacMetadataDocument.readFromBytes(
          File(tmpFile('remove.flac')).readAsBytesSync());
      expect(doc.pictures, isEmpty);
    });

    test('removes blocks by number', () async {
      writeFlac('remove-num.flac', flacWithPictureAndPadding());
      // Layout: 0=STREAMINFO 1=VORBIS_COMMENT 2=PICTURE 3=PADDING
      final result = await runMetaflac([
        'blocks',
        'remove',
        '--block-number=2',
        tmpFile('remove-num.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final doc = FlacMetadataDocument.readFromBytes(
          File(tmpFile('remove-num.flac')).readAsBytesSync());
      expect(doc.pictures, isEmpty);
      expect(doc.vorbisComment, isNotNull);
    });

    test('fails without any selector flag', () async {
      writeFlac('no-sel.flac', flacWithPictureAndPadding());
      final result = await runMetaflac([
        'blocks',
        'remove',
        tmpFile('no-sel.flac'),
      ]);
      expect(result.exitCode, equals(2));
    });

    test('rejects combining --block-type and --except-block-type', () async {
      writeFlac('conflict.flac', flacWithPictureAndPadding());
      final result = await runMetaflac([
        'blocks',
        'remove',
        '--block-type=PICTURE',
        '--except-block-type=PADDING',
        tmpFile('conflict.flac'),
      ]);
      expect(result.exitCode, equals(2));
    });

    test('--except-block-type keeps only listed types plus STREAMINFO',
        () async {
      writeFlac('except.flac', flacWithPictureAndPadding());
      final result = await runMetaflac([
        'blocks',
        'remove',
        '--except-block-type=VORBIS_COMMENT',
        tmpFile('except.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final doc = FlacMetadataDocument.readFromBytes(
          File(tmpFile('except.flac')).readAsBytesSync());
      for (final b in doc.blocks) {
        expect(
          b.type == FlacBlockType.streamInfo ||
              b.type == FlacBlockType.vorbisComment,
          isTrue,
          reason: 'unexpected block: ${b.type}',
        );
      }
    });
  });

  group('blocks append', () {
    test('appends a raw block from a file', () async {
      writeFlac('append.flac', buildFlac());
      final blockPath = tmpFile('raw.bin');
      File(blockPath).writeAsBytesSync([0x41, 0x42, 0x43, 0x44, 0x00, 0x00]);

      final result = await runMetaflac([
        'blocks',
        'append',
        '--type=APPLICATION',
        '--from-file=$blockPath',
        tmpFile('append.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final doc = FlacMetadataDocument.readFromBytes(
          File(tmpFile('append.flac')).readAsBytesSync());
      final app = doc.blocks.whereType<ApplicationBlock>().singleOrNull;
      expect(app, isNotNull);
    });

    test('requires --type and --from-file', () async {
      writeFlac('append-missing.flac', buildFlac());
      final result = await runMetaflac(
          ['blocks', 'append', tmpFile('append-missing.flac')]);
      expect(result.exitCode, equals(2));
    });
  });

  group('blocks remove-all', () {
    test('leaves only STREAMINFO', () async {
      writeFlac(
        'remove-all.flac',
        buildFlac(
          vorbisComment: VorbisCommentBlock(
            comments: VorbisComments(
              vendorString: 'v',
              entries: [VorbisCommentEntry(key: 'T', value: 'x')],
            ),
          ),
        ),
      );
      final result = await runMetaflac([
        'blocks',
        'remove-all',
        tmpFile('remove-all.flac'),
      ]);
      expect(result.exitCode, equals(0));

      final doc = FlacMetadataDocument.readFromBytes(
          File(tmpFile('remove-all.flac')).readAsBytesSync());
      expect(doc.blocks.length, equals(1));
      expect(doc.blocks.single, isA<StreamInfoBlock>());
    });
  });
}
