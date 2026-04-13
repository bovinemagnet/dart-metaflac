import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';

import '../base_command.dart';

/// Parent command for tag operations.
class TagsCommand extends Command<int> {
  TagsCommand() {
    addSubcommand(TagsListCommand());
    addSubcommand(TagsSetCommand());
    addSubcommand(TagsAddCommand());
    addSubcommand(TagsRemoveCommand());
    addSubcommand(TagsClearCommand());
    addSubcommand(TagsImportCommand());
    addSubcommand(TagsExportCommand());
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

  /// Prints all Vorbis comment entries for each input file.
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

// ─── Mutation helpers ────────────────────────────────────────────────────────

/// Parses a KEY=VALUE string, returning the key and value.
/// Throws [UsageException] if the format is invalid.
(String, String) _parseKeyValue(String arg, String usage) {
  final idx = arg.indexOf('=');
  if (idx < 1) {
    throw UsageException('Invalid KEY=VALUE format: "$arg"', usage);
  }
  return (arg.substring(0, idx), arg.substring(idx + 1));
}

/// Applies mutations to a single file, handling dry-run and JSON output.
Future<int> _applyMutations(
  BaseFlacCommand cmd,
  String filePath,
  List<MetadataMutation> mutations,
) async {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      cmd.writeError(
          filePath, 'File not found: $filePath', 'FileSystemException');
      return 4;
    }

    if (cmd.dryRun) {
      final bytes = file.readAsBytesSync();
      final result = await transformFlac(bytes, mutations);
      if (cmd.useJson) {
        cmd.writeJson({
          'file': filePath,
          'dryRun': true,
          'mutationsApplied': mutations.length,
          'fitsExistingRegion': result.plan.fitsExistingRegion,
        });
      } else {
        cmd.writeLine(
          'Dry run: ${mutations.length} mutation(s) would be applied '
          'to $filePath',
        );
      }
    } else {
      await FlacFileEditor.updateFile(
        filePath,
        mutations: mutations,
        options: FlacWriteOptions(preserveModTime: cmd.preserveModtime),
      );
      if (cmd.useJson) {
        cmd.writeJson({
          'file': filePath,
          'success': true,
          'mutationsApplied': mutations.length,
        });
      } else {
        cmd.writeLine(
          'Applied ${mutations.length} mutation(s) to $filePath',
        );
      }
    }
    return 0;
  } on FlacMetadataException catch (e) {
    cmd.writeError(filePath, e.message, e.runtimeType.toString());
    return cmd.exitCodeFor(e);
  } on FileSystemException catch (e) {
    cmd.writeError(filePath, e.message, 'FileSystemException');
    return 4;
  }
}

// ─── Set ─────────────────────────────────────────────────────────────────────

/// Sets tags (replaces existing values for each key).
class TagsSetCommand extends BaseFlacCommand {
  @override
  String get name => 'set';

  @override
  String get description => 'Set tags (KEY=VALUE)';

  /// Replaces all existing values for each supplied key with the new value(s).
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final commandArgs = rest.skip(1).toList();
    if (commandArgs.isEmpty) {
      throw UsageException('No KEY=VALUE pairs specified.', usage);
    }

    final mutations = <MetadataMutation>[];
    // Group values by key so SetTag gets all values for each key.
    final grouped = <String, List<String>>{};
    for (final arg in commandArgs) {
      final (key, value) = _parseKeyValue(arg, usage);
      grouped.putIfAbsent(key, () => []).add(value);
    }
    for (final entry in grouped.entries) {
      mutations.add(SetTag(entry.key, entry.value));
    }

    return _applyMutations(this, filePath, mutations);
  }
}

// ─── Add ─────────────────────────────────────────────────────────────────────

/// Adds a tag value (preserves existing values for that key).
class TagsAddCommand extends BaseFlacCommand {
  @override
  String get name => 'add';

  @override
  String get description => 'Add a tag value (preserves existing)';

  /// Appends each KEY=VALUE pair without removing pre-existing values.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final commandArgs = rest.skip(1).toList();
    if (commandArgs.isEmpty) {
      throw UsageException('No KEY=VALUE specified.', usage);
    }

    final mutations = <MetadataMutation>[];
    for (final arg in commandArgs) {
      final (key, value) = _parseKeyValue(arg, usage);
      mutations.add(AddTag(key, value));
    }

    return _applyMutations(this, filePath, mutations);
  }
}

// ─── Remove ──────────────────────────────────────────────────────────────────

/// Removes all values for the given key.
class TagsRemoveCommand extends BaseFlacCommand {
  @override
  String get name => 'remove';

  @override
  String get description => 'Remove all values for a tag key';

  /// Deletes every occurrence of each named tag key.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final commandArgs = rest.skip(1).toList();
    if (commandArgs.isEmpty) {
      throw UsageException('No tag key specified.', usage);
    }

    final mutations = <MetadataMutation>[];
    for (final key in commandArgs) {
      mutations.add(RemoveTag(key));
    }

    return _applyMutations(this, filePath, mutations);
  }
}

// ─── Clear ───────────────────────────────────────────────────────────────────

/// Removes all Vorbis comments.
class TagsClearCommand extends BaseFlacCommand {
  @override
  String get name => 'clear';

  @override
  String get description => 'Remove all Vorbis comment tags';

  /// Drops the entire Vorbis comment block from the file.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;

    return _applyMutations(this, filePath, [const ClearTags()]);
  }
}

// ─── Import ──────────────────────────────────────────────────────────────────

/// Imports tags from a text file (KEY=VALUE per line).
class TagsImportCommand extends BaseFlacCommand {
  TagsImportCommand() {
    argParser.addOption('from',
        help: 'Path to tag file to import', valueHelp: 'FILE');
  }

  @override
  String get name => 'import';

  @override
  String get description => 'Import tags from a text file';

  /// Reads KEY=VALUE lines from `--from` and adds them to the FLAC file.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final fromPath = argResults!['from'] as String?;
    if (fromPath == null) {
      throw UsageException('--from is required.', usage);
    }

    final tagFile = File(fromPath);
    if (!tagFile.existsSync()) {
      writeError(
          fromPath, 'Tag file not found: $fromPath', 'FileSystemException');
      return 4;
    }

    final lines = tagFile
        .readAsStringSync()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'));

    final mutations = <MetadataMutation>[];
    for (final line in lines) {
      final (key, value) = _parseKeyValue(line, usage);
      mutations.add(AddTag(key, value));
    }

    if (mutations.isEmpty) {
      writeLine('No tags found in $fromPath');
      return 0;
    }

    return _applyMutations(this, filePath, mutations);
  }
}

// ─── Export ──────────────────────────────────────────────────────────────────

/// Exports tags to file or stdout.
class TagsExportCommand extends BaseFlacCommand {
  TagsExportCommand() {
    argParser.addOption('output',
        abbr: 'o', help: 'Output file path', valueHelp: 'FILE');
  }

  @override
  String get name => 'export';

  @override
  String get description => 'Export tags to file or stdout';

  /// Writes Vorbis comments as KEY=VALUE lines to `--output` or stdout.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final outputPath = argResults!['output'] as String?;

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        writeError(
            filePath, 'File not found: $filePath', 'FileSystemException');
        return 4;
      }

      final bytes = file.readAsBytesSync();
      final doc = FlacParser.parseBytes(bytes);
      final vc = doc.vorbisComment;

      final buffer = StringBuffer();
      if (vc != null) {
        for (final entry in vc.comments.entries) {
          buffer.writeln('${entry.key}=${entry.value}');
        }
      }

      if (outputPath != null) {
        File(outputPath).writeAsStringSync(buffer.toString());
        if (!quiet) {
          if (useJson) {
            writeJson({
              'file': filePath,
              'exportedTo': outputPath,
              'tagCount': vc?.comments.entries.length ?? 0,
            });
          } else {
            writeLine('Exported tags to $outputPath');
          }
        }
      } else {
        // Write to stdout
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
            'tags': tags,
          });
        } else {
          stdout.write(buffer.toString());
        }
      }
      return 0;
    } on FlacMetadataException catch (e) {
      writeError(filePath, e.message, e.runtimeType.toString());
      return exitCodeFor(e);
    } on FileSystemException catch (e) {
      writeError(filePath, e.message, 'FileSystemException');
      return 4;
    }
  }
}
