/// Tests that publicly exposed lists on the immutable models cannot be
/// mutated in place.
///
/// `FlacMetadataDocument` and friends advertise immutability, but their
/// list fields were plain growable lists — `doc.blocks.clear()` compiled
/// and silently corrupted the document before `toBytes()`. All public
/// list fields must reject in-place mutation.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  group('public lists are unmodifiable', () {
    test('FlacMetadataDocument.blocks rejects mutation', () {
      final doc = FlacMetadataDocument.readFromBytes(buildFlac());

      expect(() => doc.blocks.clear(), throwsUnsupportedError);
      expect(() => doc.blocks.removeAt(0), throwsUnsupportedError);
    });

    test('directly constructed document blocks reject mutation', () {
      final parsed = FlacMetadataDocument.readFromBytes(buildFlac());
      final doc = FlacMetadataDocument(
        blocks: [...parsed.blocks],
        audioDataOffset: parsed.audioDataOffset,
        sourceMetadataRegionLength: parsed.sourceMetadataRegionLength,
      );

      expect(() => doc.blocks.clear(), throwsUnsupportedError);
    });

    test('FlacTransformPlan block lists reject mutation', () async {
      final result = await transformFlac(buildFlac(), []);

      expect(() => result.plan.originalBlocks.clear(), throwsUnsupportedError);
      expect(
          () => result.plan.transformedBlocks.clear(), throwsUnsupportedError);
    });

    test('VorbisComments.entries rejects mutation', () {
      final comments = VorbisComments(
        vendorString: 'test',
        entries: [const VorbisCommentEntry(key: 'ARTIST', value: 'A')],
      );

      expect(() => comments.entries.clear(), throwsUnsupportedError);
    });

    test('SeekTableBlock.points rejects mutation', () {
      final block = SeekTableBlock(points: [
        const SeekPoint(sampleNumber: 0, offset: 0, frameSamples: 4096),
      ]);

      expect(() => block.points.clear(), throwsUnsupportedError);
    });

    test('CueSheetBlock.tracks rejects mutation', () {
      final block = CueSheetBlock(
        mediaCatalogNumber: '',
        leadInSamples: 0,
        isCd: false,
        tracks: [const CueSheetTrack(offset: 0, number: 1, isrc: '')],
        rawPayload: Uint8List(0),
      );

      expect(() => block.tracks.clear(), throwsUnsupportedError);
    });
  });
}
