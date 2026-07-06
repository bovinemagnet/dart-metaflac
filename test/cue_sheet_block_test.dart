import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Builds a spec-exact CUESHEET payload (RFC 9639 §8.7) for [tracks].
///
/// Each entry of [tracks] is `(offset, number, isrc, indexPointCount)`.
Uint8List buildCueSheetPayload(
  List<(int offset, int number, String isrc, int indexPoints)> tracks, {
  bool isCd = true,
}) {
  final out = BytesBuilder();
  out.add(Uint8List(128)); // media catalogue number
  out.add(Uint8List(8)); // lead-in samples
  out.addByte(isCd ? 0x80 : 0x00); // flags
  out.add(Uint8List(258)); // reserved
  out.addByte(tracks.length); // track count
  for (final (offset, number, isrc, indexPoints) in tracks) {
    final off = ByteData(8)..setUint64(0, offset);
    out.add(off.buffer.asUint8List());
    out.addByte(number);
    final isrcBytes = Uint8List(12);
    for (var i = 0; i < isrc.length && i < 12; i++) {
      isrcBytes[i] = isrc.codeUnitAt(i);
    }
    out.add(isrcBytes);
    out.add(Uint8List(14)); // track type / pre-emphasis / reserved
    out.addByte(indexPoints);
    for (var i = 0; i < indexPoints; i++) {
      out.add(Uint8List(8)); // index point offset
      out.addByte(i + 1); // index point number
      out.add(Uint8List(3)); // index point reserved
    }
  }
  return out.toBytes();
}

Uint8List buildFlacWithCueSheet(Uint8List cuePayload) {
  final streamInfo = Uint8List(34);
  streamInfo[1] = 16;
  streamInfo[2] = 1;

  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
  out.add([0x00, 0x00, 0x00, 34]); // STREAMINFO header (not last)
  out.add(streamInfo);
  // CUESHEET block (last)
  out.addByte(0x80 | 0x05);
  out.addByte((cuePayload.length >> 16) & 0xFF);
  out.addByte((cuePayload.length >> 8) & 0xFF);
  out.addByte(cuePayload.length & 0xFF);
  out.add(cuePayload);
  return out.toBytes();
}

void main() {
  group('CueSheetBlock parsing', () {
    test('parses every track in a multi-track cue sheet', () {
      final payload = buildCueSheetPayload([
        (1000, 1, 'AAAA0000000A', 1),
        (2000, 2, 'BBBB0000000B', 1),
        (3000, 3, 'CCCC0000000C', 2),
      ]);
      final doc =
          FlacMetadataDocument.readFromBytes(buildFlacWithCueSheet(payload));
      final cue = doc.blocks.whereType<CueSheetBlock>().single;

      expect(cue.tracks.map((t) => t.number), equals([1, 2, 3]));
      expect(cue.tracks.map((t) => t.offset), equals([1000, 2000, 3000]));
      expect(
        cue.tracks.map((t) => t.isrc),
        equals(['AAAA0000000A', 'BBBB0000000B', 'CCCC0000000C']),
      );
    });
  });
}
