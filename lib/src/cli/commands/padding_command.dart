import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import '../base_command.dart';

/// Parent command for padding operations.
class PaddingCommand extends Command<int> {
  PaddingCommand() {
    addSubcommand(PaddingSetCommand());
    addSubcommand(PaddingRemoveCommand());
  }

  @override
  String get name => 'padding';

  @override
  String get description => 'Padding operations';
}

// ─── Helpers ────────────────────────────────────────────────────────────────

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

// ─── Set ────────────────────────────────────────────────────────────────────

/// Sets the padding block to a specific size in bytes.
class PaddingSetCommand extends BaseFlacCommand {
  @override
  String get name => 'set';

  @override
  String get description => 'Set padding size in bytes';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;

    if (rest.length < 2) {
      throw UsageException('No padding size specified.', usage);
    }

    final size = int.tryParse(rest[1]);
    if (size == null || size < 0) {
      throw UsageException(
          'Invalid padding size: "${rest[1]}". Must be a non-negative integer.',
          usage);
    }

    return _applyMutations(this, filePath, [SetPadding(size)]);
  }
}

// ─── Remove ─────────────────────────────────────────────────────────────────

/// Removes all padding (sets padding to 0).
class PaddingRemoveCommand extends BaseFlacCommand {
  @override
  String get name => 'remove';

  @override
  String get description => 'Remove all padding';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;

    return _applyMutations(this, filePath, [const SetPadding(0)]);
  }
}
