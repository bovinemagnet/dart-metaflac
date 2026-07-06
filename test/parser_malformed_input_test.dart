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
  });
}
