/// Example: full in-memory round-trip suitable for Flutter Web and WASM.
///
/// The core `dart_metaflac` library has **no `dart:io` dependency**, so it
/// works in any Dart runtime — including Flutter Web, WASM, and browser
/// isolates where file APIs are unavailable. This example demonstrates the
/// canonical read → edit → write flow using only `Uint8List` and
/// `package:dart_metaflac/dart_metaflac.dart`.
///
/// In a real Flutter Web app, the input bytes would typically come from:
///   * `package:http` (downloading a FLAC from a server),
///   * `FilePickerResult` (user-selected file via `file_picker` or a
///     `<input type="file">` element),
///   * `rootBundle.load()` (asset shipped with the app), or
///   * IndexedDB / an in-memory store.
///
/// The output `Uint8List` can then be offered back to the user via a
/// download link (`createObjectUrlFromBlob`) or re-uploaded.
///
/// Note: this file deliberately does NOT import
/// `package:dart_metaflac/io.dart` — that library pulls in `dart:io`, which
/// is not available on web targets. Keeping the core/io split explicit is
/// the reason the library has two public entry points.
library;

import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  // Step 1: Obtain the FLAC bytes. In this example we build a tiny synthetic
  // FLAC in memory; in a Flutter Web app, these would come from the network,
  // a file picker, or an asset bundle.
  final inputBytes = _buildSyntheticFlac();
  print('Loaded ${inputBytes.length} bytes of FLAC metadata.');

  // Step 2: Parse the FLAC metadata into an immutable document.
  final doc = FlacMetadataDocument.readFromBytes(inputBytes);

  // Step 3: Read existing tags.
  final vc = doc.vorbisComment;
  if (vc != null) {
    print('\nExisting tags:');
    for (final entry in vc.comments.entries) {
      print('  ${entry.key} = ${entry.value}');
    }
  } else {
    print('No VORBIS_COMMENT block present.');
  }

  // Step 4: Edit the metadata. `document.edit(...)` returns a new
  // document; the original is untouched.
  final updated = doc.edit((editor) {
    editor.setTag('ARTIST', ['New Artist']);
    editor.setTag('TITLE', ['Edited In Browser']);
    editor.addTag('GENRE', 'Electronic');
  });

  // Step 5: Serialise back to bytes. The result is a fully valid FLAC
  // file that can be downloaded, re-uploaded, or handed to a `<audio>`
  // element via a blob URL.
  final outputBytes = updated.toBytes();
  print('\nProduced ${outputBytes.length} bytes of updated FLAC.');

  // Step 6: Verify the round-trip by re-reading the output.
  final reparsed = FlacMetadataDocument.readFromBytes(outputBytes);
  print('\nUpdated tags:');
  for (final entry in reparsed.vorbisComment!.comments.entries) {
    print('  ${entry.key} = ${entry.value}');
  }
}

/// Builds a minimal FLAC byte sequence with a STREAMINFO block, a
/// VORBIS_COMMENT block, and a single (dummy) frame. Production code would
/// never hand-roll FLAC bytes — this helper exists purely so the example
/// is self-contained and does not depend on any file or network I/O.
Uint8List _buildSyntheticFlac() {
  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac example',
      entries: [
        VorbisCommentEntry(key: 'ARTIST', value: 'Original Artist'),
        VorbisCommentEntry(key: 'TITLE', value: 'Original Title'),
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
  out.add([0x66, 0x4C, 0x61, 0x43]); // "fLaC" magic
  out.add([0x00, 0x00, 0x00, 34]); // STREAMINFO header (not last)
  out.add(siData);
  out.add([
    0x84, // VORBIS_COMMENT, last metadata block
    (vcData.length >> 16) & 0xFF,
    (vcData.length >> 8) & 0xFF,
    vcData.length & 0xFF,
  ]);
  out.add(vcData);
  out.add([0xFF, 0xF8]); // frame sync
  out.add(Uint8List(200));
  return out.toBytes();
}
