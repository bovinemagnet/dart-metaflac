/// Example: file-based FLAC editing using FlacFileEditor.
///
/// This example uses `dart:io` and is intended for Dart CLI or server
/// applications. It is not compatible with Flutter Web.
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';

Future<void> main() async {
  // Create a temporary FLAC file to work with.
  final tempDir = await Directory.systemTemp.createTemp('dart_metaflac_');
  final filePath = '${tempDir.path}/example.flac';

  try {
    // Write a synthetic FLAC file.
    await File(filePath).writeAsBytes(_buildFlacWithTags());
    print('Created temporary FLAC: $filePath');

    // Read the file.
    final doc = await FlacFileEditor.readFile(filePath);
    print('Original tags:');
    _printTags(doc);

    // Update the file with new tags (safe atomic write by default).
    await FlacFileEditor.updateFile(
      filePath,
      mutations: [
        SetTag('ARTIST', ['File-Edited Artist']),
        SetTag('ALBUM', ['File-Edited Album']),
        RemoveTag('COMMENT'),
      ],
    );
    print('\nAfter atomic update:');
    final updated = await FlacFileEditor.readFile(filePath);
    _printTags(updated);

    // Update with modification time preservation.
    await FlacFileEditor.updateFile(
      filePath,
      mutations: [
        SetTag('YEAR', ['2024']),
      ],
      options: const FlacWriteOptions(preserveModTime: true),
    );
    print('\nAfter update with preserved mod time:');
    final preserved = await FlacFileEditor.readFile(filePath);
    _printTags(preserved);

    // Write to a new file.
    final newPath = '${tempDir.path}/output.flac';
    await FlacFileEditor.updateFile(
      filePath,
      mutations: [
        SetTag('TITLE', ['Output Copy']),
      ],
      options: FlacWriteOptions(
        writeMode: WriteMode.outputToNewFile,
        outputPath: newPath,
      ),
    );
    print('\nNew file written to: $newPath');
    final newDoc = await FlacFileEditor.readFile(newPath);
    _printTags(newDoc);
  } finally {
    // Clean up temporary files.
    await tempDir.delete(recursive: true);
    print('\nCleaned up temporary directory.');
  }
}

void _printTags(FlacMetadataDocument doc) {
  final comments = doc.vorbisComment?.comments;
  if (comments == null) {
    print('  (no tags)');
    return;
  }
  for (final entry in comments.entries) {
    print('  ${entry.key}=${entry.value}');
  }
}

Uint8List _buildFlacWithTags() {
  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac example',
      entries: [
        VorbisCommentEntry(key: 'ARTIST', value: 'Original Artist'),
        VorbisCommentEntry(key: 'TITLE', value: 'Original Title'),
        VorbisCommentEntry(key: 'COMMENT', value: 'Will be removed'),
      ],
    ),
  );

  final siData = Uint8List(34);
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | ((1 & 0x7) << 1) | ((15 >> 4) & 0x1);
  siData[13] = ((15 & 0xF) << 4);

  final vcData = vc.toPayloadBytes();
  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]);
  out.add([0x00, 0x00, 0x00, 34]);
  out.add(siData);
  out.add([0x04, (vcData.length >> 16) & 0xFF, (vcData.length >> 8) & 0xFF, vcData.length & 0xFF]);
  out.add(vcData);
  out.add([0x81, 0x00, 0x04, 0x00]);
  out.add(Uint8List(1024));
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(200));
  return out.toBytes();
}
