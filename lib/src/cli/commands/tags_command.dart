import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import '../base_command.dart';

/// Parent command for tag operations.
class TagsCommand extends Command<int> {
  TagsCommand() {
    addSubcommand(TagsListCommand());
  }

  @override
  String get name => 'tags';

  @override
  String get description => 'Tag operations';
}

/// Lists Vorbis comment tags.
class TagsListCommand extends BaseFlacCommand {
  @override
  String get name => 'list';

  @override
  String get description => 'List Vorbis comment tags';

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
        final vc = doc.vorbisComment;

        if (useJson) {
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
          writeJson({
            'file': filePath,
            'vendorString': vc?.comments.vendorString,
            'tags': tags,
          });
        } else {
          if (vc != null) {
            for (final entry in vc.comments.entries) {
              writeLine('$prefix${entry.key}=${entry.value}');
            }
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
