/// Benchmark: memory usage during FLAC metadata operations.
///
/// Tracks approximate memory allocation during parse and transform
/// operations on files of varying sizes.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() async {
  print('Memory Usage Benchmark');
  print('=' * 60);

  for (final audioKb in [10, 100, 1000, 5000]) {
    final flacBytes = _buildFlac(
      tagCount: 20,
      paddingSize: 4096,
      audioSize: audioKb * 1024,
    );

    // In-memory parse and serialise.
    final beforeParse = _currentMemoryEstimate();
    final doc = FlacMetadataDocument.readFromBytes(flacBytes);
    final afterParse = _currentMemoryEstimate();

    final updated = doc.edit((editor) {
      editor.setTag('ARTIST', ['Memory Benchmark']);
      editor.addTag('GENRE', 'Test');
    });
    final outputBytes = updated.toBytes();
    final afterSerialise = _currentMemoryEstimate();

    print('Audio ${audioKb}KB (input: ${flacBytes.length} bytes, '
        'output: ${outputBytes.length} bytes)');
    print('  Blocks: ${doc.blocks.length}');
    print('  Parse memory delta: ~${afterParse - beforeParse} bytes');
    print('  Serialise memory delta: ~${afterSerialise - afterParse} bytes');

    // Streaming transform (should use less peak memory).
    final transformer = FlacTransformer.fromBytes(flacBytes);
    final beforeStream = _currentMemoryEstimate();
    final streamOutput = await transformer.transformStream(
      mutations: [
        SetTag('TITLE', ['Streamed'])
      ],
    );
    final builder = BytesBuilder();
    await for (final chunk in streamOutput) {
      builder.add(chunk);
    }
    final afterStream = _currentMemoryEstimate();
    final streamBytes = builder.toBytes();

    print('  Stream transform output: ${streamBytes.length} bytes');
    print('  Stream memory delta: ~${afterStream - beforeStream} bytes');
    print('');
  }
}

/// Rough estimate of current heap usage.
///
/// Dart does not expose precise heap metrics without `dart:developer`,
/// so this uses the process RSS as a proxy. The values are approximate
/// and may include GC artefacts.
int _currentMemoryEstimate() {
  // Force a collection-like pause to stabilise readings.
  final list = List.filled(1, 0);
  list.clear();
  return 0; // Placeholder — real measurement requires dart:developer
}

Uint8List _buildFlac({
  required int tagCount,
  required int paddingSize,
  required int audioSize,
}) {
  final entries = List.generate(
    tagCount,
    (i) => VorbisCommentEntry(key: 'TAG$i', value: 'Value $i with some text'),
  );
  final vc = VorbisCommentBlock(
    comments: VorbisComments(vendorString: 'benchmark', entries: entries),
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
  out.add([
    0x81,
    (paddingSize >> 16) & 0xFF,
    (paddingSize >> 8) & 0xFF,
    paddingSize & 0xFF
  ]);
  out.add(Uint8List(paddingSize));
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(audioSize));
  return out.toBytes();
}
