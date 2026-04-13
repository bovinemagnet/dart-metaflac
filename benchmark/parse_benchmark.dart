/// Benchmark: FLAC metadata parsing latency.
///
/// Measures parse time for synthetic FLAC files with varying metadata sizes.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  print('FLAC Parse Benchmark');
  print('=' * 60);

  final small = _buildFlac(tagCount: 5, paddingSize: 1024);
  final medium = _buildFlac(tagCount: 50, paddingSize: 4096);
  final large = _buildFlac(tagCount: 500, paddingSize: 8192);

  _benchmark('Small  (5 tags, ${small.length} bytes)', small);
  _benchmark('Medium (50 tags, ${medium.length} bytes)', medium);
  _benchmark('Large  (500 tags, ${large.length} bytes)', large);
}

void _benchmark(String label, Uint8List flacBytes) {
  const warmup = 100;
  const iterations = 1000;

  // Warm up.
  for (var i = 0; i < warmup; i++) {
    FlacMetadataDocument.readFromBytes(flacBytes);
  }

  // Measure.
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    FlacMetadataDocument.readFromBytes(flacBytes);
  }
  sw.stop();

  final totalUs = sw.elapsedMicroseconds;
  final avgUs = totalUs / iterations;
  print('$label: ${avgUs.toStringAsFixed(1)} µs/op '
      '($iterations iterations, ${totalUs / 1000} ms total)');
}

Uint8List _buildFlac({required int tagCount, required int paddingSize}) {
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
  out.add(Uint8List(200));
  return out.toBytes();
}
