import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';

import '../base_command.dart';
import '../block_selection.dart';

/// Parent command for block operations.
class BlocksCommand extends Command<int> {
  BlocksCommand() {
    addSubcommand(BlocksListCommand());
    addSubcommand(BlocksRemoveCommand());
    addSubcommand(BlocksRemoveAllCommand());
  }

  @override
  String get name => 'blocks';

  @override
  String get description => 'Block operations';
}

/// Lists metadata blocks with optional block-selection filters.
class BlocksListCommand extends BaseFlacCommand {
  BlocksListCommand() {
    argParser
      ..addOption('block-type',
          help: 'Comma-separated block types to show')
      ..addOption('except-block-type',
          help: 'Comma-separated block types to hide')
      ..addOption('block-number',
          help: 'Comma-separated 0-based indices to show');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all metadata blocks with types and sizes';

  @override
  Future<int> run() async {
    final files = filePaths;
    final blockType = argResults!['block-type'] as String?;
    final exceptBlockType = argResults!['except-block-type'] as String?;
    final blockNumber = argResults!['block-number'] as String?;

    if (blockType != null && exceptBlockType != null) {
      throw UsageException(
        'Cannot combine --block-type and --except-block-type.',
        usage,
      );
    }

    Set<FlacBlockType>? showTypes;
    Set<FlacBlockType>? hideTypes;
    Set<int>? showIndices;
    try {
      if (blockType != null) showTypes = parseBlockTypes(blockType);
      if (exceptBlockType != null) {
        hideTypes = parseBlockTypes(exceptBlockType);
      }
      if (blockNumber != null) {
        showIndices = parseBlockNumbers(blockNumber);
      }
    } on ArgumentError catch (e) {
      throw UsageException(e.message.toString(), usage);
    }

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(
              filePath, 'File not found: $filePath', 'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        final bytes = file.readAsBytesSync();
        final doc = FlacParser.parseBytes(bytes);
        final prefix = withFilename(files) ? '$filePath: ' : '';

        bool keep(int i, FlacMetadataBlock b) {
          if (showTypes != null && !showTypes!.contains(b.type)) return false;
          if (hideTypes != null && hideTypes!.contains(b.type)) return false;
          if (showIndices != null && !showIndices!.contains(i)) return false;
          return true;
        }

        if (useJson) {
          final blockList = <Map<String, Object?>>[];
          for (var i = 0; i < doc.blocks.length; i++) {
            final block = doc.blocks[i];
            if (!keep(i, block)) continue;
            blockList.add({
              'index': i,
              'type': block.type.name,
              'typeCode': block.type.code,
              'payloadSize': block.payloadLength,
            });
          }
          writeJson({'file': filePath, 'blocks': blockList});
        } else {
          for (var i = 0; i < doc.blocks.length; i++) {
            final block = doc.blocks[i];
            if (!keep(i, block)) continue;
            writeLine('${prefix}BLOCK $i: type=${block.type.name} '
                '(${block.type.code}), size=${block.payloadLength}');
          }
        }
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}

/// Removes metadata blocks selected by type, except-type, or number.
class BlocksRemoveCommand extends BaseFlacCommand {
  BlocksRemoveCommand() {
    argParser
      ..addOption('block-type',
          help: 'Comma-separated block types to remove '
              '(STREAMINFO, PADDING, APPLICATION, SEEKTABLE, '
              'VORBIS_COMMENT, PICTURE)')
      ..addOption('except-block-type',
          help: 'Comma-separated block types to keep (others are removed)')
      ..addOption('block-number',
          help: 'Comma-separated 0-based block indices to remove')
      ..addFlag('dont-use-padding',
          help: 'Do not reuse padding; force full rewrite',
          negatable: false);
  }

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove metadata blocks by type or number';

  @override
  Future<int> run() async {
    final files = filePaths;
    final blockType = argResults!['block-type'] as String?;
    final exceptBlockType = argResults!['except-block-type'] as String?;
    final blockNumber = argResults!['block-number'] as String?;

    if (blockType != null && exceptBlockType != null) {
      throw UsageException(
        'Cannot combine --block-type and --except-block-type.',
        usage,
      );
    }
    if (blockType == null && exceptBlockType == null && blockNumber == null) {
      throw UsageException(
        'At least one of --block-type, --except-block-type, or '
        '--block-number is required.',
        usage,
      );
    }

    final dontUsePadding = argResults!['dont-use-padding'] as bool;

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(
              filePath, 'File not found: $filePath', 'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        final mutations = <MetadataMutation>[];

        if (blockType != null) {
          final types = parseBlockTypes(blockType);
          mutations.add(RemoveBlocksByType(types));
        } else if (exceptBlockType != null) {
          final keep = parseBlockTypes(exceptBlockType);
          final bytes = file.readAsBytesSync();
          final doc = FlacParser.parseBytes(bytes);
          final toRemove = <FlacBlockType>{};
          for (final b in doc.blocks) {
            if (b.type == FlacBlockType.streamInfo) continue;
            if (!keep.contains(b.type)) toRemove.add(b.type);
          }
          mutations.add(RemoveBlocksByType(toRemove));
        }

        if (blockNumber != null) {
          mutations
              .add(RemoveBlocksByNumber(parseBlockNumbers(blockNumber)));
        }

        await FlacFileEditor.updateFile(
          filePath,
          mutations: mutations,
          options: FlacWriteOptions(
            preserveModTime: preserveModtime,
            explicitPaddingSize: dontUsePadding ? 0 : null,
          ),
        );

        if (useJson) {
          writeJson({
            'file': filePath,
            'success': true,
            'mutationsApplied': mutations.length,
          });
        } else {
          writeLine('Applied ${mutations.length} mutation(s) to $filePath');
        }
      } on ArgumentError catch (e) {
        throw UsageException(e.message.toString(), usage);
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}

/// Removes every metadata block except STREAMINFO.
class BlocksRemoveAllCommand extends BaseFlacCommand {
  BlocksRemoveAllCommand() {
    argParser.addFlag('dont-use-padding',
        help: 'Do not reuse padding; force full rewrite', negatable: false);
  }

  @override
  String get name => 'remove-all';

  @override
  String get description =>
      'Remove all metadata blocks except STREAMINFO';

  @override
  Future<int> run() async {
    final files = filePaths;
    final dontUsePadding = argResults!['dont-use-padding'] as bool;

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(
              filePath, 'File not found: $filePath', 'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        await FlacFileEditor.updateFile(
          filePath,
          mutations: const [RemoveAllNonStreamInfo()],
          options: FlacWriteOptions(
            preserveModTime: preserveModtime,
            explicitPaddingSize: dontUsePadding ? 0 : null,
          ),
        );

        if (useJson) {
          writeJson({'file': filePath, 'success': true});
        } else {
          writeLine('Removed all non-STREAMINFO blocks from $filePath');
        }
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}
