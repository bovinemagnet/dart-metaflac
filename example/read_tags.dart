/// Example: reading Vorbis comment tags from a FLAC byte buffer.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  // In a real application, these bytes would come from a file or network.
  final flacBytes = _buildFlacWithTags();

  // Parse the FLAC metadata.
  final doc = FlacMetadataDocument.readFromBytes(flacBytes);

  // Access the Vorbis comment block.
  final vc = doc.vorbisComment;
  if (vc == null) {
    print('No Vorbis comments found.');
    return;
  }

  final comments = vc.comments;

  // Get all values for a specific key.
  // Note: VorbisComments is NOT a map — it preserves insertion order
  // and allows duplicate keys.
  print('ARTIST: ${comments.valuesOf('ARTIST')}');
  print('TITLE: ${comments.valuesOf('TITLE')}');

  // Iterate over all entries.
  print('\nAll tags:');
  for (final entry in comments.entries) {
    print('  ${entry.key}=${entry.value}');
  }

  // Get as a multi-map (Map<String, List<String>>).
  final map = comments.asMultiMap();
  print('\nAs multi-map: $map');
}

Uint8List _buildFlacWithTags() {
  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac example',
      entries: [
        VorbisCommentEntry(key: 'ARTIST', value: 'The Example Band'),
        VorbisCommentEntry(key: 'TITLE', value: 'Example Song'),
        VorbisCommentEntry(key: 'GENRE', value: 'Rock'),
        VorbisCommentEntry(key: 'GENRE', value: 'Alternative'),
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
    0x84,
    (vcData.length >> 16) & 0xFF,
    (vcData.length >> 8) & 0xFF,
    vcData.length & 0xFF
  ]);
  out.add(vcData);
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(200));
  return out.toBytes();
}
