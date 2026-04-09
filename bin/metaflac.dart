import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

// ─── Exit codes ───────────────────────────────────────────────────────────────
const _exitSuccess = 0;
const _exitGeneralError = 1;
const _exitInvalidArgs = 2;
const _exitInvalidFlac = 3;
const _exitIoError = 4;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', help: 'List all metadata blocks')
    ..addFlag('show-md5', help: 'Show MD5 from STREAMINFO')
    ..addOption('export-tags-to',
        help: 'Export Vorbis comments to file (use - for stdout)')
    ..addOption('export-picture-to', help: 'Export picture to file')
    ..addMultiOption('remove-tag', help: 'Remove tag by name')
    ..addFlag('remove-all-tags', help: 'Remove all Vorbis comments')
    ..addMultiOption('set-tag', help: 'Set a tag (KEY=VALUE)')
    ..addOption('import-tags-from', help: 'Import tags from file')
    ..addOption('import-picture-from', help: 'Import picture from file')
    ..addFlag('preserve-modtime', help: 'Preserve file modification time')
    ..addFlag('with-filename', help: 'Print filename with output')
    ..addFlag('no-utf8-convert', help: 'Do not convert tags to UTF-8')
    ..addFlag('json', help: 'Output in JSON format', negatable: false)
    ..addFlag('dry-run',
        help: 'Show what would change without writing', negatable: false)
    ..addFlag('continue-on-error',
        help: 'Continue processing remaining files on error',
        negatable: false)
    ..addFlag('quiet',
        abbr: 'q', help: 'Suppress normal output', negatable: false);

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    exit(_exitInvalidArgs);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(parser.usage);
    exit(_exitInvalidArgs);
  }

  final files = results.rest;
  if (files.isEmpty) {
    stderr.writeln('No input files specified.');
    stderr.writeln(parser.usage);
    exit(_exitInvalidArgs);
  }

  final useJson = results['json'] as bool;
  final dryRun = results['dry-run'] as bool;
  final continueOnError = results['continue-on-error'] as bool;
  final quiet = results['quiet'] as bool;

  var anyError = false;
  var lastExitCode = _exitSuccess;

  for (final filePath in files) {
    final code = await _processFile(
      filePath: filePath,
      results: results,
      files: files,
      useJson: useJson,
      dryRun: dryRun,
      quiet: quiet,
    );

    if (code != _exitSuccess) {
      anyError = true;
      lastExitCode = code;
      if (!continueOnError) {
        exit(code);
      }
    }
  }

  if (anyError) {
    exit(continueOnError ? _exitGeneralError : lastExitCode);
  }
}

Future<int> _processFile({
  required String filePath,
  required ArgResults results,
  required List<String> files,
  required bool useJson,
  required bool dryRun,
  required bool quiet,
}) async {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      _reportError(filePath, 'File not found: $filePath',
          'FileSystemException', useJson);
      return _exitIoError;
    }

    final withFilename =
        results['with-filename'] as bool || files.length > 1;
    final prefix = withFilename ? '$filePath: ' : '';

    final preserveModtime = results['preserve-modtime'] as bool;

    final bytes = file.readAsBytesSync();
    final doc = FlacParser.parseBytes(bytes);

    // ── Read operations ─────────────────────────────────────────────────

    if (results['list'] as bool) {
      if (useJson) {
        final json = _metadataToJson(doc, filePath);
        _write(jsonEncode(json), quiet);
      } else {
        if (!quiet) _printMetadata(doc, prefix);
      }
      return _exitSuccess;
    }

    if (results['show-md5'] as bool) {
      final md5Hex = doc.streamInfo.md5Signature
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (useJson) {
        _write(jsonEncode({'file': filePath, 'md5': md5Hex}), quiet);
      } else {
        _write('$prefix$md5Hex', quiet);
      }
      return _exitSuccess;
    }

    final exportTagsTo = results['export-tags-to'] as String?;
    if (exportTagsTo != null) {
      final vc = doc.vorbisComment;
      if (useJson && exportTagsTo == '-') {
        final tags = <String, dynamic>{};
        if (vc != null) {
          for (final entry in vc.comments.entries) {
            final key = entry.key;
            if (tags.containsKey(key)) {
              final existing = tags[key];
              if (existing is List) {
                existing.add(entry.value);
              } else {
                tags[key] = [existing, entry.value];
              }
            } else {
              tags[key] = entry.value;
            }
          }
        }
        _write(jsonEncode({'file': filePath, 'tags': tags}), quiet);
      } else {
        final lines = StringBuffer();
        if (vc != null) {
          for (final entry in vc.comments.entries) {
            lines.writeln('${entry.key}=${entry.value}');
          }
        }
        if (exportTagsTo == '-') {
          _write(lines.toString().trimRight(), quiet);
          if (!quiet) stdout.writeln();
        } else {
          File(exportTagsTo).writeAsStringSync(lines.toString());
        }
      }
      return _exitSuccess;
    }

    final exportPictureTo = results['export-picture-to'] as String?;
    if (exportPictureTo != null) {
      if (doc.pictures.isNotEmpty) {
        File(exportPictureTo).writeAsBytesSync(doc.pictures.first.data);
      } else {
        stderr.writeln('${prefix}No picture found.');
      }
      return _exitSuccess;
    }

    // ── Write operations ────────────────────────────────────────────────

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
      return _exitSuccess;
    }

    final mutations = <MetadataMutation>[];

    if (removeAllTags) {
      mutations.add(const ClearTags());
    }

    for (final tag in removeTags) {
      mutations.add(RemoveTag(tag.toUpperCase()));
    }

    for (final tag in setTags) {
      final eqIdx = tag.indexOf('=');
      if (eqIdx < 0) {
        stderr.writeln('Invalid tag format (expected KEY=VALUE): $tag');
        continue;
      }
      final key = tag.substring(0, eqIdx).toUpperCase();
      final value = tag.substring(eqIdx + 1);
      mutations.add(AddTag(key, value));
    }

    if (importTagsFrom != null) {
      final lines = File(importTagsFrom).readAsLinesSync();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final eqIdx = line.indexOf('=');
        if (eqIdx < 0) continue;
        final key = line.substring(0, eqIdx).toUpperCase();
        final value = line.substring(eqIdx + 1);
        mutations.add(AddTag(key, value));
      }
    }

    if (importPictureFrom != null) {
      final picFile = File(importPictureFrom);
      final ext = importPictureFrom.toLowerCase().split('.').last;
      final mimeType = _mimeTypeFromExtension(ext);
      mutations.add(AddPicture(PictureBlock(
        pictureType: PictureType.frontCover,
        mimeType: mimeType,
        description: '',
        width: 0,
        height: 0,
        colorDepth: 0,
        indexedColors: 0,
        data: picFile.readAsBytesSync(),
      )));
    }

    if (dryRun) {
      final result = await transformFlac(bytes, mutations);
      if (useJson) {
        _write(
          jsonEncode({
            'file': filePath,
            'dryRun': true,
            'success': true,
            'operation': 'write',
            'mutations': mutations.length,
            'originalMetadataSize': result.plan.originalMetadataRegionSize,
            'transformedMetadataSize':
                result.plan.transformedMetadataRegionSize,
            'fitsExistingRegion': result.plan.fitsExistingRegion,
            'requiresFullRewrite': result.plan.requiresFullRewrite,
          }),
          quiet,
        );
      } else {
        _write(
          '${prefix}Dry run: ${mutations.length} mutation(s), '
          'requires full rewrite: ${result.plan.requiresFullRewrite}',
          quiet,
        );
      }
      return _exitSuccess;
    }

    await FlacFileEditor.updateFile(
      filePath,
      mutations: mutations,
      options: FlacWriteOptions(
        preserveModTime: preserveModtime,
      ),
    );

    if (useJson) {
      final changes = <String, dynamic>{};
      final tagsSet = <String>[];
      final tagsRemoved = <String>[];
      var tagsCleared = false;
      var picturesAdded = 0;
      var picturesRemoved = 0;

      for (final m in mutations) {
        if (m is SetTag) tagsSet.add(m.key);
        if (m is AddTag) tagsSet.add(m.key);
        if (m is RemoveTag) tagsRemoved.add(m.key);
        if (m is RemoveExactTagValue) tagsRemoved.add(m.key);
        if (m is ClearTags) tagsCleared = true;
        if (m is AddPicture) picturesAdded++;
        if (m is ReplacePictureByType) {
          picturesAdded++;
          picturesRemoved++;
        }
        if (m is RemovePictureByType) picturesRemoved++;
        if (m is RemoveAllPictures) picturesRemoved++;
        if (m is SetPadding) changes['paddingSet'] = m.size;
      }

      if (tagsSet.isNotEmpty) changes['tagsSet'] = tagsSet;
      if (tagsRemoved.isNotEmpty) changes['tagsRemoved'] = tagsRemoved;
      if (tagsCleared) changes['tagsCleared'] = true;
      if (picturesAdded > 0) changes['picturesAdded'] = picturesAdded;
      if (picturesRemoved > 0) changes['picturesRemoved'] = picturesRemoved;

      _write(
        jsonEncode({
          'file': filePath,
          'success': true,
          'operation': 'write',
          'mutations': mutations.length,
          'changes': changes,
        }),
        quiet,
      );
    }

    return _exitSuccess;
  } on InvalidFlacException catch (e) {
    _reportError(filePath, e.message, 'InvalidFlacException', useJson);
    return _exitInvalidFlac;
  } on MalformedMetadataException catch (e) {
    _reportError(
        filePath, e.message, 'MalformedMetadataException', useJson);
    return _exitInvalidFlac;
  } on FlacIoException catch (e) {
    _reportError(filePath, e.message, 'FlacIoException', useJson);
    return _exitIoError;
  } on FileSystemException catch (e) {
    _reportError(filePath, e.message, 'FileSystemException', useJson);
    return _exitIoError;
  } on FlacMetadataException catch (e) {
    _reportError(filePath, e.message, 'FlacMetadataException', useJson);
    return _exitGeneralError;
  } catch (e) {
    _reportError(filePath, e.toString(), e.runtimeType.toString(), useJson);
    return _exitGeneralError;
  }
}

// ─── Output helpers ─────────────────────────────────────────────────────────

void _write(String message, bool quiet) {
  if (!quiet) {
    stdout.writeln(message);
  }
}

void _reportError(
    String filePath, String message, String type, bool useJson) {
  if (useJson) {
    stderr.writeln(jsonEncode({
      'file': filePath,
      'error': message,
      'type': type,
    }));
  } else {
    stderr.writeln('Error processing $filePath: $message');
  }
}

// ─── Metadata helpers ───────────────────────────────────────────────────────

Map<String, dynamic> _metadataToJson(
    FlacMetadataDocument doc, String filePath) {
  final si = doc.streamInfo;
  final md5Hex = si.md5Signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  final result = <String, dynamic>{
    'file': filePath,
    'streamInfo': {
      'minBlockSize': si.minBlockSize,
      'maxBlockSize': si.maxBlockSize,
      'minFrameSize': si.minFrameSize,
      'maxFrameSize': si.maxFrameSize,
      'sampleRate': si.sampleRate,
      'channelCount': si.channelCount,
      'bitsPerSample': si.bitsPerSample,
      'totalSamples': si.totalSamples,
      'md5Signature': md5Hex,
    },
  };

  final vc = doc.vorbisComment;
  if (vc != null) {
    final tags = <String, dynamic>{};
    for (final entry in vc.comments.entries) {
      final key = entry.key;
      if (tags.containsKey(key)) {
        final existing = tags[key];
        if (existing is List) {
          existing.add(entry.value);
        } else {
          tags[key] = [existing, entry.value];
        }
      } else {
        tags[key] = entry.value;
      }
    }
    result['vorbisComment'] = {
      'vendorString': vc.comments.vendorString,
      'tags': tags,
    };
  }

  final pictures = doc.pictures;
  if (pictures.isNotEmpty) {
    result['pictures'] = pictures
        .map((pic) => {
              'pictureType': pic.pictureType.code,
              'mimeType': pic.mimeType,
              'description': pic.description,
              'width': pic.width,
              'height': pic.height,
              'colorDepth': pic.colorDepth,
              'indexedColors': pic.indexedColors,
              'dataLength': pic.data.length,
            })
        .toList();
  }

  return result;
}

void _printMetadata(FlacMetadataDocument doc, String prefix) {
  final si = doc.streamInfo;
  stdout.writeln('${prefix}STREAMINFO:');
  stdout.writeln('$prefix  min_blocksize: ${si.minBlockSize}');
  stdout.writeln('$prefix  max_blocksize: ${si.maxBlockSize}');
  stdout.writeln('$prefix  min_framesize: ${si.minFrameSize}');
  stdout.writeln('$prefix  max_framesize: ${si.maxFrameSize}');
  stdout.writeln('$prefix  sample_rate: ${si.sampleRate}');
  stdout.writeln('$prefix  channels: ${si.channelCount}');
  stdout.writeln('$prefix  bits_per_sample: ${si.bitsPerSample}');
  stdout.writeln('$prefix  total_samples: ${si.totalSamples}');
  final md5Hex = si.md5Signature
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  stdout.writeln('$prefix  md5sum: $md5Hex');

  final vc = doc.vorbisComment;
  if (vc != null) {
    stdout.writeln('${prefix}VORBIS_COMMENT:');
    stdout
        .writeln('$prefix  vendor_string: ${vc.comments.vendorString}');
    for (final entry in vc.comments.entries) {
      stdout.writeln('$prefix  ${entry.key}=${entry.value}');
    }
  }

  final pictures = doc.pictures;
  for (var i = 0; i < pictures.length; i++) {
    final pic = pictures[i];
    stdout.writeln('${prefix}PICTURE[$i]:');
    stdout.writeln('$prefix  type: ${pic.pictureType.code}');
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
