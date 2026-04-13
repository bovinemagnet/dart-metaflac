/// Benchmark: in-place metadata update when changes fit within existing padding.
///
/// Measures the time to edit tags when the new metadata fits within the
/// original metadata region (no full rewrite required).
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  print('Padding Hit Benchmark (in-place update)');
  print('=' * 60);

  final flacBytes = _buildFlac(tagCount: 10, paddingSize: 4096);
  print('Input: ${flacBytes.length} bytes, 10 tags, 4096 bytes padding');
  print('');

  _benchmark('Set single tag', flacBytes, [
    SetTag('TAG0', ['Updated Value']),
  ]);

  _benchmark('Set 5 tags', flacBytes, [
    for (var i = 0; i < 5; i++) SetTag('TAG$i', ['Updated Value $i']),
  ]);

  _benchmark('Add + remove tags', flacBytes, [
    AddTag('NEWTAG', 'New Value'),
    RemoveTag('TAG0'),
  ]);
}

void _benchmark(
    String label, Uint8List flacBytes, List<MetadataMutation> mutations) {
  const warmup = 100;
  const iterations = 1000;

  // Warm up.
  for (var i = 0; i < warmup; i++) {
    final doc = FlacMetadataDocument.readFromBytes(flacBytes);
    doc.edit((editor) {
      for (final m in mutations) {
        editor.applyMutation(m);
      }
    }).toBytes();
  }

  // Measure.
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final doc = FlacMetadataDocument.readFromBytes(flacBytes);
    doc.edit((editor) {
      for (final m in mutations) {
        editor.applyMutation(m);
      }
    }).toBytes();
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
