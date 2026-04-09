import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

/// Encodes a [VorbisCommentBlock] into a minimal FLAC, parses it back, and
/// returns the decoded [VorbisCommentBlock].
VorbisCommentBlock roundTrip(VorbisCommentBlock block) {
  final vcData = block.toPayloadBytes();
  final siData = Uint8List(34);
  final out = BytesBuilder();
  // fLaC marker
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);
  // STREAMINFO (not last)
  out.addByte(0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);
  // VORBIS_COMMENT (last)
  out.addByte(0x80 | 0x04);
  out.addByte((vcData.length >> 16) & 0xFF);
  out.addByte((vcData.length >> 8) & 0xFF);
  out.addByte(vcData.length & 0xFF);
  out.add(vcData);

  final doc = FlacParser.parseBytes(Uint8List.fromList(out.toBytes()));
  return doc.vorbisComment!;
}

void main() {
  group('VorbisCommentBlock', () {
    test('encodes and decodes empty comments', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'test_vendor',
          entries: [],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.vendorString, equals('test_vendor'));
      expect(decoded.comments.entries, isEmpty);
    });

    test('round-trips single tag', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'vendor',
          entries: [VorbisCommentEntry(key: 'TITLE', value: 'My Song')],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.valuesOf('TITLE'), equals(['My Song']));
    });

    test('round-trips multi-value tags', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'v',
          entries: [
            VorbisCommentEntry(key: 'ARTIST', value: 'Artist A'),
            VorbisCommentEntry(key: 'ARTIST', value: 'Artist B'),
          ],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.valuesOf('ARTIST'),
          containsAll(['Artist A', 'Artist B']));
      expect(decoded.comments.valuesOf('ARTIST').length, equals(2));
    });

    test('round-trips multiple different tags', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'vendor',
          entries: [
            VorbisCommentEntry(key: 'TITLE', value: 'Test'),
            VorbisCommentEntry(key: 'ALBUM', value: 'My Album'),
            VorbisCommentEntry(key: 'TRACKNUMBER', value: '5'),
          ],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.valuesOf('TITLE'), equals(['Test']));
      expect(decoded.comments.valuesOf('ALBUM'), equals(['My Album']));
      expect(decoded.comments.valuesOf('TRACKNUMBER'), equals(['5']));
    });

    test('keys are uppercased on decode', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'v',
          entries: [VorbisCommentEntry(key: 'title', value: 'hello')],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.valuesOf('TITLE'), equals(['hello']));
    });

    test('handles unicode in vendor and values', () {
      final block = VorbisCommentBlock(
        comments: VorbisComments(
          vendorString: 'vendor 日本語',
          entries: [VorbisCommentEntry(key: 'TITLE', value: '曲名')],
        ),
      );
      final decoded = roundTrip(block);
      expect(decoded.comments.vendorString, equals('vendor 日本語'));
      expect(decoded.comments.valuesOf('TITLE'), equals(['曲名']));
    });
  });

  group('VorbisComments', () {
    test('set replaces values for a key', () {
      final vc = VorbisComments(
        vendorString: 'v',
        entries: [
          VorbisCommentEntry(key: 'TITLE', value: 'Old'),
          VorbisCommentEntry(key: 'ARTIST', value: 'Someone'),
        ],
      );
      final updated = vc.set('TITLE', ['New1', 'New2']);
      expect(updated.valuesOf('TITLE'), equals(['New1', 'New2']));
      expect(updated.valuesOf('ARTIST'), equals(['Someone']));
    });

    test('removeKey removes all values for key', () {
      final vc = VorbisComments(
        vendorString: 'v',
        entries: [
          VorbisCommentEntry(key: 'TITLE', value: 'A'),
          VorbisCommentEntry(key: 'TITLE', value: 'B'),
          VorbisCommentEntry(key: 'ARTIST', value: 'C'),
        ],
      );
      final updated = vc.removeKey('TITLE');
      expect(updated.valuesOf('TITLE'), isEmpty);
      expect(updated.valuesOf('ARTIST'), equals(['C']));
    });

    test('clear removes all entries', () {
      final vc = VorbisComments(
        vendorString: 'v',
        entries: [VorbisCommentEntry(key: 'TITLE', value: 'A')],
      );
      final cleared = vc.clear();
      expect(cleared.entries, isEmpty);
      expect(cleared.vendorString, equals('v'));
    });
  });
}
