/// Tests that Vorbis comment keys keep their original casing.
///
/// Vorbis comment field names are case-insensitive for matching, but the
/// reference metaflac preserves the stored casing byte-for-byte. Taggers
/// in the wild write mixed-case keys (e.g. `AccurateRipResult=...`), so
/// uppercasing on parse breaks byte-exact round-trips on real files.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

VorbisCommentBlock _mixedCaseComment() => VorbisCommentBlock(
      comments: const VorbisComments(
        vendorString: 'test',
        entries: [
          VorbisCommentEntry(key: 'AccurateRipResult', value: 'AccurateRip'),
          VorbisCommentEntry(key: 'artist', value: 'Cappella'),
          VorbisCommentEntry(key: 'TITLE', value: 'U Got to Know'),
        ],
      ),
    );

void main() {
  group('Vorbis comment key casing', () {
    test('parseBytes preserves original key casing', () {
      final bytes = buildFlac(vorbisComment: _mixedCaseComment());

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      final keys = doc.vorbisComment!.comments.entries.map((e) => e.key);
      expect(keys, ['AccurateRipResult', 'artist', 'TITLE']);
    });

    test('mixed-case keys round-trip byte-for-byte', () {
      final bytes = buildFlac(vorbisComment: _mixedCaseComment());

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      expect(doc.toBytes(), bytes);
    });

    test('lookups stay case-insensitive after parse', () {
      final bytes = buildFlac(vorbisComment: _mixedCaseComment());

      final comments =
          FlacMetadataDocument.readFromBytes(bytes).vorbisComment!.comments;

      expect(comments.valuesOf('ARTIST'), ['Cappella']);
      expect(comments.valuesOf('accurateripresult'), ['AccurateRip']);
      expect(comments.valuesOf('title'), ['U Got to Know']);
    });

    test('mutations match parsed mixed-case keys case-insensitively', () {
      final bytes = buildFlac(vorbisComment: _mixedCaseComment());
      final doc = FlacMetadataDocument.readFromBytes(bytes);

      final updated = doc.edit((e) {
        e.setTag('ARTIST', ['New Artist']);
        e.removeTag('ACCURATERIPRESULT');
      });

      final comments = updated.vorbisComment!.comments;
      expect(comments.valuesOf('artist'), ['New Artist']);
      expect(comments.valuesOf('AccurateRipResult'), isEmpty);
      // Untouched entries keep their original casing.
      expect(comments.entries.map((e) => e.key), contains('TITLE'));
    });
  });
}
