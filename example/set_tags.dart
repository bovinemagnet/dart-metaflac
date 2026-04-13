/// Example: setting, adding, and removing Vorbis comment tags.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  final flacBytes = _buildFlacWithTags();
  final doc = FlacMetadataDocument.readFromBytes(flacBytes);

  print('=== Before editing ===');
  _printTags(doc);

  // Edit tags using the immutable document model.
  // Each call to edit() returns a new document; the original is unchanged.
  final updated = doc.edit((editor) {
    // Set replaces all values for the key (takes a List<String>).
    editor.setTag('ARTIST', ['New Artist']);

    // Add appends a value, preserving existing entries.
    editor.addTag('GENRE', 'Electronic');

    // Remove deletes all entries for the key.
    editor.removeTag('COMMENT');

    // Remove a specific key=value pair (useful for multi-valued tags).
    editor.removeExactTagValue('GENRE', 'Rock');
  });

  print('\n=== After editing ===');
  _printTags(updated);

  // Serialise and verify round-trip.
  final outputBytes = updated.toBytes();
  final verified = FlacMetadataDocument.readFromBytes(outputBytes);
  print('\n=== After round-trip ===');
  _printTags(verified);
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
        VorbisCommentEntry(key: 'GENRE', value: 'Rock'),
        VorbisCommentEntry(key: 'GENRE', value: 'Pop'),
        VorbisCommentEntry(key: 'COMMENT', value: 'A sample comment'),
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
  out.add([
    0x04,
    (vcData.length >> 16) & 0xFF,
    (vcData.length >> 8) & 0xFF,
    vcData.length & 0xFF
  ]);
  out.add(vcData);
  out.add([0x81, 0x00, 0x04, 0x00]);
  out.add(Uint8List(1024));
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(200));
  return out.toBytes();
}
