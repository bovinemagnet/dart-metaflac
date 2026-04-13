import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import '../base_command.dart';

/// Parent command for block operations.
class BlocksCommand extends Command<int> {
  BlocksCommand() {
    addSubcommand(BlocksListCommand());
  }

  @override
  String get name => 'blocks';

  @override
  String get description => 'Block operations';
}

/// Lists all metadata blocks with their types and sizes.
class BlocksListCommand extends BaseFlacCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'List all metadata blocks with types and sizes';

  /// Lists all metadata blocks with their type names, codes, and payload sizes.
  @override
  Future<int> run() async {
    final files = filePaths;
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

        if (useJson) {
          final blockList = doc.blocks
              .map((block) => {
                    'type': block.type.name,
                    'typeCode': block.type.code,
                    'payloadSize': block.payloadLength,
                  })
              .toList();
          writeJson({'file': filePath, 'blocks': blockList});
        } else {
          for (var i = 0; i < doc.blocks.length; i++) {
            final block = doc.blocks[i];
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
