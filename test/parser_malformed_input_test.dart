import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Wraps [blocks] (already including their 4-byte headers) in a minimal
/// FLAC container: fLaC magic + a not-last STREAMINFO + the given blocks.
Uint8List flacWithBlocks(List<int> blocks) {
  final streamInfo = Uint8List(34);
  streamInfo[1] = 16;
  streamInfo[2] = 1;
  final out = BytesBuilder();
  out.add([0x66, 0x4C, 0x61, 0x43]); // fLaC
  out.add([0x00, 0x00, 0x00, 34]); // STREAMINFO header (not last)
  out.add(streamInfo);
  out.add(blocks);
  return out.toBytes();
}

void main() {
  group('parser exception contract on malformed input', () {
    test(
        'APPLICATION block with declared length < 4 throws '
        'MalformedMetadataException, not RangeError', () {
      final bytes = flacWithBlocks([
        0x02, 0x00, 0x00, 0x02, 0x41, 0x42, // APPLICATION, length 2 (< 4)
        0x81, 0x00, 0x00, 0x00, // valid last PADDING so data remains
      ]);
      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test(
        'invalid UTF-8 in Vorbis comment vendor string throws '
        'MalformedMetadataException, not FormatException', () {
      final bytes = flacWithBlocks([
        0x84, 0x00, 0x00, 0x09, // VORBIS_COMMENT (last), length 9
        0x01, 0x00, 0x00, 0x00, // vendor length 1 (LE)
        0xFF, // invalid UTF-8 byte
        0x00, 0x00, 0x00, 0x00, // comment count 0
      ]);
      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test(
        'invalid UTF-8 in a Vorbis comment entry throws '
        'MalformedMetadataException, not FormatException', () {
      final bytes = flacWithBlocks([
        0x84, 0x00, 0x00, 0x0D, // VORBIS_COMMENT (last), length 13
        0x00, 0x00, 0x00, 0x00, // vendor length 0
        0x01, 0x00, 0x00, 0x00, // comment count 1
        0x01, 0x00, 0x00, 0x00, // comment length 1
        0xC0, // invalid UTF-8 lead byte
      ]);
      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test(
        'invalid UTF-8 in a PICTURE MIME type throws '
        'MalformedMetadataException, not FormatException', () {
      final bytes = flacWithBlocks([
        0x86, 0x00, 0x00, 0x21, // PICTURE (last), length 33
        0x00, 0x00, 0x00, 0x03, // picture type 3
        0x00, 0x00, 0x00, 0x01, // MIME length 1
        0xFF, // invalid UTF-8 byte
        0x00, 0x00, 0x00, 0x00, // description length 0
        0x00, 0x00, 0x00, 0x00, // width
        0x00, 0x00, 0x00, 0x00, // height
        0x00, 0x00, 0x00, 0x00, // colour depth
        0x00, 0x00, 0x00, 0x00, // indexed colours
        0x00, 0x00, 0x00, 0x00, // data length 0
      ]);
      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test(
        'block whose inner fields overrun its declared payload length '
        'throws MalformedMetadataException instead of misparsing', () {
      // PICTURE block declares 32 payload bytes but its data-length field
      // says 10, so the parser would read 42 bytes — silently consuming
      // the start of whatever follows.
      final bytes = flacWithBlocks([
        0x86, 0x00, 0x00, 0x20, // PICTURE (last), declared length 32
        0x00, 0x00, 0x00, 0x03, // picture type 3
        0x00, 0x00, 0x00, 0x00, // MIME length 0
        0x00, 0x00, 0x00, 0x00, // description length 0
        0x00, 0x00, 0x00, 0x00, // width
        0x00, 0x00, 0x00, 0x00, // height
        0x00, 0x00, 0x00, 0x00, // colour depth
        0x00, 0x00, 0x00, 0x00, // indexed colours
        0x00, 0x00, 0x00, 0x0A, // data length 10 — overruns the block
        // 10 bytes that are really audio, not picture data.
        0xFF, 0xF8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      ]);
      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<MalformedMetadataException>()),
      );
    });
  });

  group('malformed Vorbis comment entries', () {
    test('an entry without = is preserved and round-trips byte-for-byte', () {
      final bytes = flacWithBlocks([
        0x84, 0x00, 0x00, 0x17, // VORBIS_COMMENT (last), length 23
        0x04, 0x00, 0x00, 0x00, // vendor length 4 (LE)
        0x74, 0x65, 0x73, 0x74, // 'test'
        0x01, 0x00, 0x00, 0x00, // comment count 1
        0x07, 0x00, 0x00, 0x00, // comment length 7
        0x4E, 0x4F, 0x45, 0x51, 0x55, 0x41, 0x4C, // 'NOEQUAL' — no '='
      ]);

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      final entries = doc.vorbisComment!.comments.entries;
      expect(entries, hasLength(1));
      expect(entries.single.key, 'NOEQUAL');
      expect(entries.single.value, '');
      expect(entries.single.hasSeparator, isFalse);
      expect(doc.toBytes(), bytes);
    });

    test('well-formed entries report hasSeparator true', () {
      final bytes = flacWithBlocks([
        0x84, 0x00, 0x00, 0x18, // VORBIS_COMMENT (last), length 24
        0x04, 0x00, 0x00, 0x00, // vendor length 4 (LE)
        0x74, 0x65, 0x73, 0x74, // 'test'
        0x01, 0x00, 0x00, 0x00, // comment count 1
        0x08, 0x00, 0x00, 0x00, // comment length 8
        0x41, 0x52, 0x54, 0x49, 0x53, 0x54, 0x3D, 0x41, // 'ARTIST=A'
      ]);

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      final entry = doc.vorbisComment!.comments.entries.single;
      expect(entry.hasSeparator, isTrue);
      expect(doc.toBytes(), bytes);
    });
  });
}
