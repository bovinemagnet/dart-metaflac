import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

/// Base class for metaflac subcommands with shared options and helpers.
abstract class BaseFlacCommand extends Command<int> {
  BaseFlacCommand() {
    argParser
      ..addFlag('json', help: 'Output in JSON format', negatable: false)
      ..addFlag('quiet',
          abbr: 'q', help: 'Suppress normal output', negatable: false)
      ..addFlag('dry-run',
          help: 'Show what would change without writing', negatable: false)
      ..addFlag('preserve-modtime', help: 'Preserve file modification time')
      ..addFlag('continue-on-error',
          help: 'Continue on error', negatable: false)
      ..addFlag('with-filename', help: 'Print filename with output');
  }

  /// Whether the `--json` flag was supplied; controls machine-readable output.
  bool get useJson => argResults!['json'] as bool;

  /// Whether the `--quiet` / `-q` flag was supplied; suppresses normal output.
  bool get quiet => argResults!['quiet'] as bool;

  /// Whether the `--dry-run` flag was supplied; no files are written when true.
  bool get dryRun => argResults!['dry-run'] as bool;

  /// Whether the `--preserve-modtime` flag was supplied.
  bool get preserveModtime => argResults!['preserve-modtime'] as bool;

  /// Whether the `--continue-on-error` flag was supplied.
  bool get continueOnError => argResults!['continue-on-error'] as bool;

  /// Returns the trailing positional file paths from the parsed arguments.
  ///
  /// Throws [UsageException] if no file paths were provided.
  List<String> get filePaths {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No input files specified.', usage);
    }
    return rest;
  }

  /// Returns true when filenames should be prefixed to output lines.
  ///
  /// Always true when processing more than one file, or when `--with-filename`
  /// was explicitly passed.
  bool withFilename(List<String> files) =>
      argResults!['with-filename'] as bool || files.length > 1;

  /// Writes [message] to stdout, unless [quiet] is true.
  void writeLine(String message) {
    if (!quiet) stdout.writeln(message);
  }

  /// Encodes [json] and writes it to stdout, unless [quiet] is true.
  void writeJson(Object json) {
    if (!quiet) stdout.writeln(jsonEncode(json));
  }

  /// Writes an error for [filePath] to stderr, using JSON or plain text format.
  void writeError(String filePath, String message, String type) {
    if (useJson) {
      stderr.writeln(
          jsonEncode({'file': filePath, 'error': message, 'type': type}));
    } else {
      stderr.writeln('Error processing $filePath: $message');
    }
  }

  /// Returns the appropriate exit code for a FLAC exception.
  int exitCodeFor(Exception e) {
    final typeName = e.runtimeType.toString();
    if (typeName.contains('InvalidFlac') ||
        typeName.contains('MalformedMetadata')) {
      return 3;
    }
    if (typeName.contains('FlacIo') || typeName.contains('FileSystem')) {
      return 4;
    }
    return 1;
  }
}
