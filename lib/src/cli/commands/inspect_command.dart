import 'dart:io';

import 'package:dart_metaflac/dart_metaflac.dart';

import '../base_command.dart';
import '../formatters.dart';

/// Lists all metadata blocks (equivalent to --list).
class InspectCommand extends BaseFlacCommand {
  @override
  String get name => 'inspect';

  @override
  String get description => 'List all metadata blocks (equivalent to --list)';

  @override
  Future<int> run() async {
    final files = filePaths;
    var anyError = false;

    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(filePath, 'File not found: $filePath',
              'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        final bytes = file.readAsBytesSync();
        final doc = FlacParser.parseBytes(bytes);
        final prefix = withFilename(files) ? '$filePath: ' : '';

        if (useJson) {
          writeJson(metadataToJson(doc, filePath));
        } else {
          if (!quiet) printMetadata(doc, prefix);
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
