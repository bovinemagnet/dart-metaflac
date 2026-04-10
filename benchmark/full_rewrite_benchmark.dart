/// Benchmark: full FLAC file rewrite throughput.
///
/// Measures the time to parse, transform, and serialise FLAC files of
/// varying sizes when the transform requires a full rewrite (metadata
/// exceeds the original region).
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() async {
  print('Full Rewrite Benchmark');
  print('=' * 60);

  // Test with different simulated audio data sizes.
  for (final audioKb in [10, 100, 1000]) {
    final flacBytes = _buildFlac(
      tagCount: 5,
      paddingSize: 0, // No padding forces full rewrite.
      audioSize: audioKb * 1024,
    );

    await _benchmark(
      'Audio ${audioKb}KB (${flacBytes.length} bytes total)',
      flacBytes,
    );
  }
}

Future<void> _benchmark(String label, Uint8List flacBytes) async {
  const warmup = 50;
  const iterations = 500;

  final mutations = [
    SetTag('ARTIST', ['Benchmark Artist']),
    SetTag('ALBUM', ['Benchmark Album']),
    SetTag('TITLE', ['Benchmark Title']),
    AddTag('GENRE', 'Electronic'),
    AddTag('GENRE', 'Ambient'),
  ];

  // Warm up.
  for (var i = 0; i < warmup; i++) {
    final transformer = FlacTransformer.fromBytes(flacBytes);
    await transformer.transform(mutations: mutations);
  }

  // Measure.
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final transformer = FlacTransformer.fromBytes(flacBytes);
    await transformer.transform(mutations: mutations);
  }
  sw.stop();

  final totalUs = sw.elapsedMicroseconds;
  final avgUs = totalUs / iterations;
  final throughputMBs = (flacBytes.length / 1024 / 1024) / (avgUs / 1e6);
  print('$label: ${avgUs.toStringAsFixed(1)} µs/op, '
      '${throughputMBs.toStringAsFixed(1)} MB/s');
}

Uint8List _buildFlac({
  required int tagCount,
  required int paddingSize,
  required int audioSize,
}) {
  final entries = List.generate(
    tagCount,
    (i) => VorbisCommentEntry(key: 'TAG$i', value: 'Value $i'),
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

  final vcIsLast = paddingSize <= 0;
  out.add([(vcIsLast ? 0x84 : 0x04), (vcData.length >> 16) & 0xFF, (vcData.length >> 8) & 0xFF, vcData.length & 0xFF]);
  out.add(vcData);

  if (paddingSize > 0) {
    out.add([0x81, (paddingSize >> 16) & 0xFF, (paddingSize >> 8) & 0xFF, paddingSize & 0xFF]);
    out.add(Uint8List(paddingSize));
  }

  // Simulated audio data.
  out.add([0xFF, 0xF8]);
  out.add(Uint8List(audioSize));
  return out.toBytes();
}
