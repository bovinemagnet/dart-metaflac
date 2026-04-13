/// Example: streaming FLAC transform using FlacTransformer.
///
/// The streaming API avoids buffering the entire audio data in memory,
/// making it suitable for large files.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

Future<void> main() async {
  final flacBytes = _buildFlacWithTags();

  // Create a transformer from bytes.
  // In production, use FlacTransformer.fromStream() with a file stream.
  final transformer = FlacTransformer.fromBytes(flacBytes);

  // Read metadata without transforming.
  final doc = await transformer.readMetadata();
  print('Original artist: ${doc.vorbisComment?.comments.valuesOf('ARTIST')}');

  // Transform in memory (small files).
  final transformer2 = FlacTransformer.fromBytes(flacBytes);
  final result = await transformer2.transform(
    mutations: [
      SetTag('ARTIST', ['Streamed Artist']),
      SetTag('ALBUM', ['Streamed Album']),
      AddTag('GENRE', 'Ambient'),
    ],
  );

  print('Transform plan:');
  print('  Original metadata size: ${result.plan.originalMetadataRegionSize}');
  print('  New metadata size: ${result.plan.transformedMetadataRegionSize}');
  print('  Fits existing region: ${result.plan.fitsExistingRegion}');
  print('  Output size: ${result.bytes.length} bytes');

  // Streaming transform (large files).
  final transformer3 = FlacTransformer.fromBytes(flacBytes);
  final outputStream = await transformer3.transformStream(
    mutations: [
      SetTag('TITLE', ['Streamed Title']),
    ],
  );

  // Collect the stream output.
  final outputBuilder = BytesBuilder();
  await for (final chunk in outputStream) {
    outputBuilder.add(chunk);
  }
  final streamedOutput = outputBuilder.toBytes();
  print('Streamed output size: ${streamedOutput.length} bytes');

  // Verify the streamed output.
  final verified = FlacMetadataDocument.readFromBytes(
    Uint8List.fromList(streamedOutput),
  );
  print(
      'Verified title: ${verified.vorbisComment?.comments.valuesOf('TITLE')}');
}

Uint8List _buildFlacWithTags() {
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
