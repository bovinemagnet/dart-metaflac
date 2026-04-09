import 'dart:io';
import 'package:args/args.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', help: 'List all metadata blocks')
    ..addFlag('show-md5', help: 'Show MD5 from STREAMINFO')
    ..addOption('export-tags-to', help: 'Export Vorbis comments to file (use - for stdout)')
    ..addOption('export-picture-to', help: 'Export picture to file')
    ..addMultiOption('remove-tag', help: 'Remove tag by name')
    ..addFlag('remove-all-tags', help: 'Remove all Vorbis comments')
    ..addMultiOption('set-tag', help: 'Set a tag (KEY=VALUE)')
    ..addOption('import-tags-from', help: 'Import tags from file')
    ..addOption('import-picture-from', help: 'Import picture from file')
    ..addFlag('preserve-modtime', help: 'Preserve file modification time')
    ..addFlag('with-filename', help: 'Print filename with output')
    ..addFlag('no-utf8-convert', help: 'Do not convert tags to UTF-8');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    exit(1);
  }

  final files = results.rest;
  if (files.isEmpty) {
    stderr.writeln('No input files specified.');
    stderr.writeln(parser.usage);
    exit(1);
  }

  for (final filePath in files) {
    final file = File(filePath);
    if (!file.existsSync()) {
      stderr.writeln('File not found: $filePath');
      continue;
    }

    final withFilename = results['with-filename'] as bool || files.length > 1;
    final prefix = withFilename ? '$filePath: ' : '';

    final preserveModtime = results['preserve-modtime'] as bool;
    final originalModTime = preserveModtime ? file.lastModifiedSync() : null;

    final editor = FlacEditor(file.openRead());

    if (results['list'] as bool) {
      final meta = await editor.readMetadata();
      _printMetadata(meta, prefix);
      continue;
    }

    if (results['show-md5'] as bool) {
      final meta = await editor.readMetadata();
      final md5Hex = meta.streamInfo.md5Signature
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      stdout.writeln('$prefix$md5Hex');
      continue;
    }

    final exportTagsTo = results['export-tags-to'] as String?;
    if (exportTagsTo != null) {
      final meta = await editor.readMetadata();
      final lines = StringBuffer();
      meta.vorbisComment?.comments.forEach((key, values) {
        for (final v in values) {
          lines.writeln('$key=$v');
        }
      });
      if (exportTagsTo == '-') {
        stdout.write(lines);
      } else {
        File(exportTagsTo).writeAsStringSync(lines.toString());
      }
      continue;
    }

    final exportPictureTo = results['export-picture-to'] as String?;
    if (exportPictureTo != null) {
      final meta = await editor.readMetadata();
      if (meta.pictures.isNotEmpty) {
        File(exportPictureTo).writeAsBytesSync(meta.pictures.first.data);
      } else {
        stderr.writeln('${prefix}No picture found.');
      }
      continue;
    }

    final removeTags = results['remove-tag'] as List<String>;
    final removeAllTags = results['remove-all-tags'] as bool;
    final setTags = results['set-tag'] as List<String>;
    final importTagsFrom = results['import-tags-from'] as String?;
    final importPictureFrom = results['import-picture-from'] as String?;

    final hasWriteOp = removeTags.isNotEmpty ||
        removeAllTags ||
        setTags.isNotEmpty ||
        importTagsFrom != null ||
        importPictureFrom != null;

    if (!hasWriteOp) {
      stderr.writeln('No operation specified. Use --help for usage.');
      continue;
    }

    final meta = await FlacEditor(file.openRead()).readMetadata();
    var comments = Map<String, List<String>>.from(
      meta.vorbisComment?.comments.map(
            (k, v) => MapEntry(k, List<String>.from(v)),
          ) ??
          {},
    );
    final vendorString = meta.vorbisComment?.vendorString ?? 'dart_metaflac';
    var pictures = List<PictureBlock>.from(meta.pictures);

    if (removeAllTags) {
      comments = {};
    }

    for (final tag in removeTags) {
      comments.remove(tag.toUpperCase());
    }

    for (final tag in setTags) {
      final eqIdx = tag.indexOf('=');
      if (eqIdx < 0) {
        stderr.writeln('Invalid tag format (expected KEY=VALUE): $tag');
        continue;
      }
      final key = tag.substring(0, eqIdx).toUpperCase();
      final value = tag.substring(eqIdx + 1);
      comments.putIfAbsent(key, () => []).add(value);
    }

    if (importTagsFrom != null) {
      final lines = File(importTagsFrom).readAsLinesSync();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final eqIdx = line.indexOf('=');
        if (eqIdx < 0) continue;
        final key = line.substring(0, eqIdx).toUpperCase();
        final value = line.substring(eqIdx + 1);
        comments.putIfAbsent(key, () => []).add(value);
      }
    }

    if (importPictureFrom != null) {
      final picFile = File(importPictureFrom);
      final ext = importPictureFrom.toLowerCase().split('.').last;
      final mimeType = _mimeTypeFromExtension(ext);
      pictures.add(PictureBlock(
        pictureType: 3,
        mimeType: mimeType,
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColorCount: 0,
        data: picFile.readAsBytesSync(),
      ));
    }

    final updatedStream = FlacEditor(file.openRead()).updateMetadata(
      vorbisComments: comments,
      vendorString: vendorString,
      pictures: pictures,
    );

    final chunks = <List<int>>[];
    await for (final chunk in updatedStream) {
      chunks.add(chunk);
    }
    final totalLen = chunks.fold<int>(0, (s, c) => s + c.length);
    final outBytes = List<int>.filled(totalLen, 0);
    var off = 0;
    for (final c in chunks) {
      for (final b in c) {
        outBytes[off++] = b;
      }
    }
    file.writeAsBytesSync(outBytes);

    if (preserveModtime && originalModTime != null) {
      if (!Platform.isWindows) {
        final ts = originalModTime.toIso8601String().replaceAll('T', ' ').substring(0, 19);
        await Process.run('touch', ['-d', ts, filePath]);
      }
    }
  }
}

void _printMetadata(FlacMetadata meta, String prefix) {
  final si = meta.streamInfo;
  stdout.writeln('${prefix}STREAMINFO:');
  stdout.writeln('$prefix  min_blocksize: ${si.minBlockSize}');
  stdout.writeln('$prefix  max_blocksize: ${si.maxBlockSize}');
  stdout.writeln('$prefix  min_framesize: ${si.minFrameSize}');
  stdout.writeln('$prefix  max_framesize: ${si.maxFrameSize}');
  stdout.writeln('$prefix  sample_rate: ${si.sampleRate}');
  stdout.writeln('$prefix  channels: ${si.channels}');
  stdout.writeln('$prefix  bits_per_sample: ${si.bitsPerSample}');
  stdout.writeln('$prefix  total_samples: ${si.totalSamples}');
  final md5Hex = si.md5Signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  stdout.writeln('$prefix  md5sum: $md5Hex');

  final vc = meta.vorbisComment;
  if (vc != null) {
    stdout.writeln('${prefix}VORBIS_COMMENT:');
    stdout.writeln('$prefix  vendor_string: ${vc.vendorString}');
    vc.comments.forEach((key, values) {
      for (final v in values) {
        stdout.writeln('$prefix  $key=$v');
      }
    });
  }

  for (var i = 0; i < meta.pictures.length; i++) {
    final pic = meta.pictures[i];
    stdout.writeln('${prefix}PICTURE[$i]:');
    stdout.writeln('$prefix  type: ${pic.pictureType}');
    stdout.writeln('$prefix  mime_type: ${pic.mimeType}');
    stdout.writeln('$prefix  description: ${pic.description}');
    stdout.writeln('$prefix  width: ${pic.width}');
    stdout.writeln('$prefix  height: ${pic.height}');
    stdout.writeln('$prefix  color_depth: ${pic.colorDepth}');
    stdout.writeln('$prefix  data_length: ${pic.data.length}');
  }
}

String _mimeTypeFromExtension(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}
