import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';
import 'package:dart_metaflac/src/cli/block_selection.dart';
import 'package:dart_metaflac/src/cli/command_runner.dart';

// ─── Exit codes ───────────────────────────────────────────────────────────────
const _exitSuccess = 0;
const _exitGeneralError = 1;
const _exitInvalidArgs = 2;
const _exitInvalidFlac = 3;
const _exitIoError = 4;

Future<void> main(List<String> args) async {
  // Route to subcommand runner if the first argument is a known subcommand.
  const subcommands = {'inspect', 'blocks', 'tags', 'picture', 'padding'};
  if (args.isNotEmpty && subcommands.contains(args.first)) {
    final runner = MetaflacCommandRunner();
    try {
      final exitCode = await runner.run(args) ?? 0;
      exit(exitCode);
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      stderr.writeln(e.usage);
      exit(_exitInvalidArgs);
    }
  }

  final parser = ArgParser()
    // ── List / inspect ──────────────────────────────────────────────────
    ..addFlag('list', help: 'List all metadata blocks')
    // ── STREAMINFO scalar show-ops (one raw value per invocation) ───────
    ..addFlag('show-md5', help: 'Show MD5 from STREAMINFO')
    ..addFlag('show-md5sum',
        help: 'Show MD5 from STREAMINFO (metaflac-compatible alias)')
    ..addFlag('show-min-blocksize', help: 'Show STREAMINFO minimum block size')
    ..addFlag('show-max-blocksize', help: 'Show STREAMINFO maximum block size')
    ..addFlag('show-min-framesize', help: 'Show STREAMINFO minimum frame size')
    ..addFlag('show-max-framesize', help: 'Show STREAMINFO maximum frame size')
    ..addFlag('show-sample-rate', help: 'Show STREAMINFO sample rate')
    ..addFlag('show-channels', help: 'Show STREAMINFO channel count')
    ..addFlag('show-bps', help: 'Show STREAMINFO bits per sample')
    ..addFlag('show-total-samples', help: 'Show STREAMINFO total sample count')
    // ── Vorbis comment show-ops ─────────────────────────────────────────
    ..addFlag('show-vendor-tag', help: 'Show the VORBIS_COMMENT vendor string')
    ..addOption('show-tag', help: 'Show all values for a specific tag (NAME)')
    ..addFlag('show-all-tags',
        help: 'Show all Vorbis comment tags (alias for export to stdout)')
    // ── Existing read/write ops ─────────────────────────────────────────
    ..addOption('export-tags-to',
        help: 'Export Vorbis comments to file (use - for stdout)')
    ..addOption('export-picture-to', help: 'Export picture to file')
    ..addMultiOption('remove-tag', help: 'Remove tag by name')
    ..addOption('remove-first-tag',
        help: 'Remove the first tag entry matching FIELD')
    ..addFlag('remove-all-tags', help: 'Remove all Vorbis comments')
    ..addOption('remove-all-tags-except',
        help:
            'Remove all tags except NAME1[=NAME2[=…]] (metaflac "=" separator)')
    ..addFlag('remove-replay-gain',
        help: 'Remove all REPLAYGAIN_* tags', negatable: false)
    ..addMultiOption('set-tag', help: 'Set a tag (KEY=VALUE)')
    ..addMultiOption('set-tag-from-file',
        help: 'Set a tag where VALUE is read from a file (KEY=FILE)')
    ..addOption('import-tags-from', help: 'Import tags from file')
    ..addOption('import-picture-from', help: 'Import picture from file')
    // ── Tier 3: block management ────────────────────────────────────────
    ..addFlag('remove',
        help: 'Remove blocks matching --block-type/--except-block-type/'
            '--block-number',
        negatable: false)
    ..addFlag('remove-all',
        help: 'Remove all metadata blocks except STREAMINFO', negatable: false)
    ..addOption('append',
        help: 'Append a raw metadata block from FILE (use with --block-type)',
        valueHelp: 'FILE')
    ..addOption('block-type',
        help: 'Block types (comma-separated), e.g. PICTURE,PADDING')
    ..addOption('except-block-type',
        help: 'Block types to keep (comma-separated)')
    ..addOption('block-number', help: '0-based block indices (comma-separated)')
    // ── Global options ──────────────────────────────────────────────────
    ..addOption('output-name',
        abbr: 'o',
        help: 'Write output to FILE instead of modifying input in place')
    ..addFlag('preserve-modtime', help: 'Preserve file modification time')
    ..addFlag('with-filename', help: 'Print filename with output')
    ..addFlag('no-filename',
        help: 'Never print filename with output', negatable: false)
    ..addFlag('no-utf8-convert',
        help: 'Skip UTF-8 conversion (no-op: Dart strings are always UTF-8)')
    ..addFlag('dont-use-padding',
        help: 'Do not reuse existing padding; force full rewrite',
        negatable: false)
    ..addFlag('json', help: 'Output in JSON format', negatable: false)
    ..addFlag('dry-run',
        help: 'Show what would change without writing', negatable: false)
    ..addFlag('continue-on-error',
        help: 'Continue processing remaining files on error', negatable: false)
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
      _reportError(filePath, 'File not found: $filePath', 'FileSystemException',
          useJson);
      return _exitIoError;
    }

    // --no-filename beats --with-filename and defaults to on for a
    // single input, off for multiple (matching metaflac).
    final noFilename = results['no-filename'] as bool;
    final withFilename =
        !noFilename && (results['with-filename'] as bool || files.length > 1);
    final prefix = withFilename ? '$filePath: ' : '';

    final preserveModtime = results['preserve-modtime'] as bool;
    final dontUsePadding = results['dont-use-padding'] as bool;
    final outputName = results['output-name'] as String?;

    final bytes = file.readAsBytesSync();
    final doc = FlacParser.parseBytes(bytes);

    // Tier 3 block-selection options (used by both --list and --remove).
    final removeFlag = results['remove'] as bool;
    final removeAll = results['remove-all'] as bool;
    final appendPath = results['append'] as String?;
    final blockTypeOpt = results['block-type'] as String?;
    final exceptBlockTypeOpt = results['except-block-type'] as String?;
    final blockNumberOpt = results['block-number'] as String?;

    // ── Read operations ─────────────────────────────────────────────────

    if (results['list'] as bool) {
      Set<FlacBlockType>? showTypes;
      Set<FlacBlockType>? hideTypes;
      Set<int>? showIndices;
      try {
        if (blockTypeOpt != null) showTypes = parseBlockTypes(blockTypeOpt);
        if (exceptBlockTypeOpt != null) {
          hideTypes = parseBlockTypes(exceptBlockTypeOpt);
        }
        if (blockNumberOpt != null) {
          showIndices = parseBlockNumbers(blockNumberOpt);
        }
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }

      final hasFilter =
          showTypes != null || hideTypes != null || showIndices != null;

      if (useJson) {
        final json = _metadataToJson(doc, filePath);
        _write(jsonEncode(json), quiet);
      } else if (hasFilter) {
        for (var i = 0; i < doc.blocks.length; i++) {
          final b = doc.blocks[i];
          if (showTypes != null && !showTypes.contains(b.type)) continue;
          if (hideTypes != null && hideTypes.contains(b.type)) continue;
          if (showIndices != null && !showIndices.contains(i)) continue;
          _write(
            '${prefix}BLOCK $i: type=${b.type.name} '
            '(${b.type.code}), size=${b.payloadLength}',
            quiet,
          );
        }
      } else {
        if (!quiet) _printMetadata(doc, prefix);
      }
      return _exitSuccess;
    }

    if ((results['show-md5'] as bool) || (results['show-md5sum'] as bool)) {
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

    // STREAMINFO scalar show-ops. Each prints exactly one raw value so
    // shell scripts can consume them directly. If JSON mode is on, wrap
    // the value in a small object.
    int? scalarValue;
    String? scalarKey;
    if (results['show-min-blocksize'] as bool) {
      scalarKey = 'minBlockSize';
      scalarValue = doc.streamInfo.minBlockSize;
    } else if (results['show-max-blocksize'] as bool) {
      scalarKey = 'maxBlockSize';
      scalarValue = doc.streamInfo.maxBlockSize;
    } else if (results['show-min-framesize'] as bool) {
      scalarKey = 'minFrameSize';
      scalarValue = doc.streamInfo.minFrameSize;
    } else if (results['show-max-framesize'] as bool) {
      scalarKey = 'maxFrameSize';
      scalarValue = doc.streamInfo.maxFrameSize;
    } else if (results['show-sample-rate'] as bool) {
      scalarKey = 'sampleRate';
      scalarValue = doc.streamInfo.sampleRate;
    } else if (results['show-channels'] as bool) {
      scalarKey = 'channels';
      scalarValue = doc.streamInfo.channelCount;
    } else if (results['show-bps'] as bool) {
      scalarKey = 'bitsPerSample';
      scalarValue = doc.streamInfo.bitsPerSample;
    } else if (results['show-total-samples'] as bool) {
      scalarKey = 'totalSamples';
      scalarValue = doc.streamInfo.totalSamples;
    }
    if (scalarKey != null) {
      if (useJson) {
        _write(jsonEncode({'file': filePath, scalarKey: scalarValue}), quiet);
      } else {
        _write('$prefix$scalarValue', quiet);
      }
      return _exitSuccess;
    }

    if (results['show-vendor-tag'] as bool) {
      final vendor = doc.vorbisComment?.comments.vendorString ?? '';
      if (useJson) {
        _write(jsonEncode({'file': filePath, 'vendorString': vendor}), quiet);
      } else {
        _write('$prefix$vendor', quiet);
      }
      return _exitSuccess;
    }

    final showTag = results['show-tag'] as String?;
    if (showTag != null) {
      final values =
          doc.vorbisComment?.comments.valuesOf(showTag) ?? const <String>[];
      if (useJson) {
        _write(jsonEncode({'file': filePath, 'tag': showTag, 'values': values}),
            quiet);
      } else {
        for (final v in values) {
          _write('$prefix${showTag.toUpperCase()}=$v', quiet);
        }
      }
      return _exitSuccess;
    }

    if (results['show-all-tags'] as bool) {
      final vc = doc.vorbisComment;
      if (useJson) {
        final tags =
            vc?.comments.asMultiMap() ?? const <String, List<String>>{};
        _write(jsonEncode({'file': filePath, 'tags': tags}), quiet);
      } else if (vc != null) {
        for (final entry in vc.comments.entries) {
          _write('$prefix${entry.key}=${entry.value}', quiet);
        }
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
    final removeFirstTag = results['remove-first-tag'] as String?;
    final removeAllTags = results['remove-all-tags'] as bool;
    final removeAllTagsExcept = results['remove-all-tags-except'] as String?;
    final removeReplayGain = results['remove-replay-gain'] as bool;
    final setTags = results['set-tag'] as List<String>;
    final setTagFromFile = results['set-tag-from-file'] as List<String>;
    final importTagsFrom = results['import-tags-from'] as String?;
    final importPictureFrom = results['import-picture-from'] as String?;

    final hasWriteOp = removeTags.isNotEmpty ||
        removeFirstTag != null ||
        removeAllTags ||
        removeAllTagsExcept != null ||
        removeReplayGain ||
        setTags.isNotEmpty ||
        setTagFromFile.isNotEmpty ||
        importTagsFrom != null ||
        importPictureFrom != null ||
        removeFlag ||
        removeAll ||
        appendPath != null;

    if (!hasWriteOp) {
      stderr.writeln('No operation specified. Use --help for usage.');
      return _exitSuccess;
    }

    final mutations = <MetadataMutation>[];

    if (removeAllTags) {
      mutations.add(const ClearTags());
    }

    if (removeAllTagsExcept != null) {
      // metaflac uses `=` as the separator inside the value, e.g.
      // --remove-all-tags-except=TITLE=ARTIST=ALBUM
      final keep =
          removeAllTagsExcept.split('=').where((s) => s.isNotEmpty).toSet();
      mutations.add(ClearTagsExcept(keep));
    }

    if (removeReplayGain) {
      // Matches the standard ReplayGain 2.0 field names.
      const replayGainFields = [
        'REPLAYGAIN_REFERENCE_LOUDNESS',
        'REPLAYGAIN_TRACK_GAIN',
        'REPLAYGAIN_TRACK_PEAK',
        'REPLAYGAIN_ALBUM_GAIN',
        'REPLAYGAIN_ALBUM_PEAK',
      ];
      for (final field in replayGainFields) {
        mutations.add(RemoveTag(field));
      }
    }

    for (final tag in removeTags) {
      mutations.add(RemoveTag(tag.toUpperCase()));
    }

    if (removeFirstTag != null) {
      mutations.add(RemoveFirstTag(removeFirstTag.toUpperCase()));
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

    for (final spec in setTagFromFile) {
      final eqIdx = spec.indexOf('=');
      if (eqIdx < 0) {
        stderr.writeln(
            'Invalid --set-tag-from-file format (expected KEY=FILE): $spec');
        continue;
      }
      final key = spec.substring(0, eqIdx).toUpperCase();
      final path = spec.substring(eqIdx + 1);
      final contents = File(path).readAsStringSync().trimRight();
      mutations.add(SetTag(key, [contents]));
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

    // Tier 3 block operations.
    if (removeAll) {
      mutations.add(const RemoveAllNonStreamInfo());
    } else if (removeFlag) {
      if (blockTypeOpt == null &&
          exceptBlockTypeOpt == null &&
          blockNumberOpt == null) {
        stderr.writeln('--remove requires --block-type, '
            '--except-block-type, or --block-number');
        return _exitInvalidArgs;
      }
      if (blockTypeOpt != null && exceptBlockTypeOpt != null) {
        stderr.writeln('Cannot combine --block-type and --except-block-type');
        return _exitInvalidArgs;
      }
      try {
        if (blockTypeOpt != null) {
          mutations.add(RemoveBlocksByType(parseBlockTypes(blockTypeOpt)));
        } else if (exceptBlockTypeOpt != null) {
          final keep = parseBlockTypes(exceptBlockTypeOpt);
          final toRemove = <FlacBlockType>{};
          for (final b in doc.blocks) {
            if (b.type == FlacBlockType.streamInfo) continue;
            if (!keep.contains(b.type)) toRemove.add(b.type);
          }
          mutations.add(RemoveBlocksByType(toRemove));
        }
        if (blockNumberOpt != null) {
          mutations
              .add(RemoveBlocksByNumber(parseBlockNumbers(blockNumberOpt)));
        }
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }
    }

    if (appendPath != null) {
      if (blockTypeOpt == null) {
        stderr.writeln('--append requires --block-type');
        return _exitInvalidArgs;
      }
      final Set<FlacBlockType> types;
      try {
        types = parseBlockTypes(blockTypeOpt);
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }
      if (types.length != 1) {
        stderr.writeln('--block-type must name exactly one type for --append');
        return _exitInvalidArgs;
      }
      final blockFile = File(appendPath);
      if (!blockFile.existsSync()) {
        _reportError(appendPath, 'Block file not found: $appendPath',
            'FileSystemException', useJson);
        return _exitIoError;
      }
      mutations.add(AppendRawBlock(
        type: types.single,
        payload: blockFile.readAsBytesSync(),
      ));
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

    // --output-name (-o) switches to outputToNewFile mode.
    // --dont-use-padding forces a full rewrite by setting explicit
    // padding to zero and using safeAtomic (no in-place overwrite).
    final writeMode =
        outputName != null ? WriteMode.outputToNewFile : WriteMode.safeAtomic;
    await FlacFileEditor.updateFile(
      filePath,
      mutations: mutations,
      options: FlacWriteOptions(
        preserveModTime: preserveModtime,
        writeMode: writeMode,
        outputPath: outputName,
        explicitPaddingSize: dontUsePadding ? 0 : null,
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
    _reportError(filePath, e.message, 'MalformedMetadataException', useJson);
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

void _reportError(String filePath, String message, String type, bool useJson) {
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
  final md5Hex =
      si.md5Signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
  final md5Hex =
      si.md5Signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  stdout.writeln('$prefix  md5sum: $md5Hex');

  final vc = doc.vorbisComment;
  if (vc != null) {
    stdout.writeln('${prefix}VORBIS_COMMENT:');
    stdout.writeln('$prefix  vendor_string: ${vc.comments.vendorString}');
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
