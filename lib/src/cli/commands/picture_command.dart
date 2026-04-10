import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';

import '../base_command.dart';
import '../formatters.dart';

/// Parent command for picture operations.
class PictureCommand extends Command<int> {
  PictureCommand() {
    addSubcommand(PictureAddCommand());
    addSubcommand(PictureRemoveCommand());
    addSubcommand(PictureExportCommand());
  }

  @override
  String get name => 'picture';

  @override
  String get description => 'Picture operations';
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Parses a CLI picture type string (e.g. 'front-cover') to [PictureType].
PictureType _parsePictureType(String value) {
  switch (value) {
    case 'other':
      return PictureType.other;
    case 'file-icon-32x32':
      return PictureType.fileIcon32x32;
    case 'other-file-icon':
      return PictureType.otherFileIcon;
    case 'front-cover':
      return PictureType.frontCover;
    case 'back-cover':
      return PictureType.backCover;
    case 'leaflet-page':
      return PictureType.leafletPage;
    case 'media':
      return PictureType.media;
    case 'lead-artist':
      return PictureType.leadArtist;
    case 'artist':
      return PictureType.artist;
    case 'conductor':
      return PictureType.conductor;
    case 'band':
      return PictureType.band;
    case 'composer':
      return PictureType.composer;
    case 'lyricist':
      return PictureType.lyricist;
    case 'recording-location':
      return PictureType.recordingLocation;
    case 'during-recording':
      return PictureType.duringRecording;
    case 'during-performance':
      return PictureType.duringPerformance;
    case 'movie-screen-capture':
      return PictureType.movieScreenCapture;
    case 'bright-colored-fish':
      return PictureType.brightColoredFish;
    case 'illustration':
      return PictureType.illustration;
    case 'band-logo':
      return PictureType.bandLogo;
    case 'publisher-logo':
      return PictureType.publisherLogo;
    default:
      throw UsageException(
        'Unknown picture type: "$value"',
        'Valid types: other, front-cover, back-cover, leaflet-page, '
            'media, lead-artist, artist, conductor, band, composer, '
            'lyricist, recording-location, during-recording, '
            'during-performance, movie-screen-capture, illustration, '
            'band-logo, publisher-logo',
      );
  }
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

// ─── Add ────────────────────────────────────────────────────────────────────

/// Adds a picture to a FLAC file.
class PictureAddCommand extends BaseFlacCommand {
  PictureAddCommand() {
    argParser
      ..addOption('file',
          help: 'Path to image file to embed', valueHelp: 'IMAGE')
      ..addOption('type',
          help: 'Picture type (e.g. front-cover, back-cover, other)',
          defaultsTo: 'front-cover')
      ..addOption('description',
          help: 'Picture description text', defaultsTo: '');
  }

  @override
  String get name => 'add';

  @override
  String get description => 'Add a picture to the FLAC file';

  /// Embeds the image supplied via `--file` into the FLAC as a [PictureBlock].
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;
    final imagePath = argResults!['file'] as String?;
    if (imagePath == null) {
      throw UsageException('--file is required.', usage);
    }

    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      writeError(
          imagePath, 'Image file not found: $imagePath', 'FileSystemException');
      return 4;
    }

    final typeStr = argResults!['type'] as String;
    final pictureType = _parsePictureType(typeStr);
    final desc = argResults!['description'] as String;

    final ext = imagePath.toLowerCase().split('.').last;
    final mimeType = mimeTypeFromExtension(ext);
    final imageData = imageFile.readAsBytesSync();

    final picture = PictureBlock(
      pictureType: pictureType,
      mimeType: mimeType,
      description: desc,
      width: 0,
      height: 0,
      colorDepth: 0,
      indexedColors: 0,
      data: imageData,
    );

    return _applyMutations(this, filePath, [AddPicture(picture)]);
  }
}

// ─── Remove ─────────────────────────────────────────────────────────────────

/// Removes pictures from a FLAC file.
class PictureRemoveCommand extends BaseFlacCommand {
  PictureRemoveCommand() {
    argParser
      ..addFlag('all', help: 'Remove all pictures', negatable: false)
      ..addOption('type',
          help: 'Remove pictures of this type (e.g. front-cover)');
  }

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove pictures from the FLAC file';

  /// Removes pictures matching `--type`, or all pictures when no type is given.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;

    final typeStr = argResults!['type'] as String?;

    final MetadataMutation mutation;
    if (typeStr != null) {
      mutation = RemovePictureByType(_parsePictureType(typeStr));
    } else {
      // Default to removing all pictures.
      mutation = const RemoveAllPictures();
    }

    return _applyMutations(this, filePath, [mutation]);
  }
}

// ─── Export ─────────────────────────────────────────────────────────────────

/// Exports a picture from a FLAC file.
class PictureExportCommand extends BaseFlacCommand {
  PictureExportCommand() {
    argParser
      ..addOption('output',
          abbr: 'o', help: 'Output file path', valueHelp: 'FILE')
      ..addOption('type',
          help: 'Export picture of this type (e.g. front-cover)');
  }

  @override
  String get name => 'export';

  @override
  String get description => 'Export a picture from the FLAC file';

  /// Writes picture data to `--output`, deriving the filename from the FLAC path when omitted.
  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final filePath = rest.first;

    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        writeError(
            filePath, 'File not found: $filePath', 'FileSystemException');
        return 4;
      }

      final bytes = file.readAsBytesSync();
      final doc = FlacParser.parseBytes(bytes);

      final typeStr = argResults!['type'] as String?;
      PictureBlock? picture;

      if (typeStr != null) {
        final pictureType = _parsePictureType(typeStr);
        for (final pic in doc.pictures) {
          if (pic.pictureType == pictureType) {
            picture = pic;
            break;
          }
        }
      } else if (doc.pictures.isNotEmpty) {
        picture = doc.pictures.first;
      }

      if (picture == null) {
        writeError(filePath, 'No picture found', 'FlacMetadataException');
        return 1;
      }

      var outputPath = argResults!['output'] as String?;
      if (outputPath == null) {
        // Derive output filename from FLAC file and MIME type.
        final baseName = filePath.replaceAll(RegExp(r'\.[^.]+$'), '');
        final ext = _extensionFromMimeType(picture.mimeType);
        outputPath = '$baseName.$ext';
      }

      File(outputPath).writeAsBytesSync(picture.data);

      if (useJson) {
        writeJson({
          'file': filePath,
          'exportedTo': outputPath,
          'mimeType': picture.mimeType,
          'dataLength': picture.data.length,
        });
      } else {
        writeLine('Exported picture to $outputPath');
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

/// Maps a MIME type to a file extension.
String _extensionFromMimeType(String mimeType) {
  switch (mimeType) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/gif':
      return 'gif';
    case 'image/bmp':
      return 'bmp';
    case 'image/webp':
      return 'webp';
    default:
      return 'bin';
  }
}
