/// Primary example demonstrating the core read/edit/write workflow.
///
/// This example builds a synthetic FLAC file in memory, reads its metadata,
/// edits tags, and serialises the result back to bytes.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  // Build a minimal FLAC file in memory with some tags.
  final flacBytes = _buildSampleFlac();

  // 1. Read metadata from bytes.
  final doc = FlacMetadataDocument.readFromBytes(flacBytes);

  // 2. Inspect stream info.
  final info = doc.streamInfo;
  print('Sample rate: ${info.sampleRate} Hz');
  print('Channels: ${info.channelCount}');
  print('Bits per sample: ${info.bitsPerSample}');

  // 3. Read existing tags.
  final comments = doc.vorbisComment?.comments;
  if (comments != null) {
    print('Artist: ${comments.valuesOf('ARTIST')}');
    print('Title: ${comments.valuesOf('TITLE')}');
  }

  // 4. Edit tags using the immutable document model.
  final updated = doc.edit((editor) {
    editor.setTag('ARTIST', ['Updated Artist']);
    editor.setTag('ALBUM', ['New Album']);
    editor.addTag('GENRE', 'Electronic');
    editor.removeTag('COMMENT');
  });

  // 5. Serialise back to bytes.
  final outputBytes = updated.toBytes();
  print('Output size: ${outputBytes.length} bytes');

  // 6. Verify the edit round-tripped correctly.
  final verified = FlacMetadataDocument.readFromBytes(outputBytes);
  final updatedComments = verified.vorbisComment!.comments;
  print('Updated artist: ${updatedComments.valuesOf('ARTIST')}');
  print('New album: ${updatedComments.valuesOf('ALBUM')}');
  print('Genre: ${updatedComments.valuesOf('GENRE')}');
}

/// Build a minimal synthetic FLAC file with sample tags.
Uint8List _buildSampleFlac() {
  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'dart_metaflac example',
      entries: [
        VorbisCommentEntry(key: 'ARTIST', value: 'Test Artist'),
        VorbisCommentEntry(key: 'TITLE', value: 'Test Title'),
        VorbisCommentEntry(key: 'COMMENT', value: 'A test comment'),
      ],
    ),
  );

  final siData = _buildStreamInfoPayload(
    sampleRate: 44100,
    channels: 2,
    bitsPerSample: 16,
    totalSamples: 88200,
  );

  final vcData = vc.toPayloadBytes();
  const paddingSize = 1024;

  final out = BytesBuilder();
  // FLAC stream marker
  out.add([0x66, 0x4C, 0x61, 0x43]);
  // STREAMINFO block header (not last)
  out.add([0x00, 0x00, 0x00, 34]);
  out.add(siData);
  // Vorbis comment block header (not last)
  out.add([0x04, (vcData.length >> 16) & 0xFF, (vcData.length >> 8) & 0xFF, vcData.length & 0xFF]);
  out.add(vcData);
  // Padding block header (last)
  out.add([0x81, (paddingSize >> 16) & 0xFF, (paddingSize >> 8) & 0xFF, paddingSize & 0xFF]);
  out.add(Uint8List(paddingSize));
  // Fake audio frame
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(200));

  return out.toBytes();
}

Uint8List _buildStreamInfoPayload({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int totalSamples,
}) {
  final data = Uint8List(34);
  data[0] = 0;
  data[1] = 16;
  data[2] = 1;
  data[3] = 0;
  data[10] = (sampleRate >> 12) & 0xFF;
  data[11] = (sampleRate >> 4) & 0xFF;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  data[12] = ((sampleRate & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  data[13] = ((bps & 0xF) << 4) | ((totalSamples >> 32) & 0xF);
  data[14] = (totalSamples >> 24) & 0xFF;
  data[15] = (totalSamples >> 16) & 0xFF;
  data[16] = (totalSamples >> 8) & 0xFF;
  data[17] = totalSamples & 0xFF;
  return data;
}
