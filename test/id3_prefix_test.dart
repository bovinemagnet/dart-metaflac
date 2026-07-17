/// Tests for parsing FLAC files with a prepended ID3v2 tag.
///
/// The FLAC spec does not sanction ID3 tags, but taggers in the wild
/// prepend ID3v2 to .flac files anyway, and libFLAC tolerates this by
/// skipping the tag before looking for the `fLaC` marker. The parser
/// must do the same, and serialisation must preserve the prefix
/// byte-for-byte so a read/write round-trip never corrupts the file.
///
/// Author: Paul Snow
/// Since: 0.0.3
library;

import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

/// Wraps [flac] with a syntactically valid ID3v2.3 tag of [payloadSize]
/// junk bytes. When [withFooter] is set the footer-present flag is set
/// and a 10-byte footer is appended after the payload.
Uint8List withId3v2Prefix(
  Uint8List flac, {
  int payloadSize = 100,
  bool withFooter = false,
}) {
  final footerLength = withFooter ? 10 : 0;
  final prefix = Uint8List(10 + payloadSize + footerLength);
  prefix[0] = 0x49; // 'I'
  prefix[1] = 0x44; // 'D'
  prefix[2] = 0x33; // '3'
  prefix[3] = 3; // version 2.3
  prefix[4] = 0;
  prefix[5] = withFooter ? 0x10 : 0x00; // flags
  // Syncsafe 28-bit size of the payload (excludes header and footer).
  prefix[6] = (payloadSize >> 21) & 0x7F;
  prefix[7] = (payloadSize >> 14) & 0x7F;
  prefix[8] = (payloadSize >> 7) & 0x7F;
  prefix[9] = payloadSize & 0x7F;
  for (var i = 0; i < payloadSize; i++) {
    prefix[10 + i] = 0xAA; // junk payload
  }
  return Uint8List.fromList([...prefix, ...flac]);
}

VorbisCommentBlock _comment() => VorbisCommentBlock(
      comments: VorbisComments(
        vendorString: 'test',
        entries: [
          VorbisCommentEntry(key: 'ARTIST', value: 'Cappella'),
          VorbisCommentEntry(key: 'TITLE', value: 'U Got to Know'),
        ],
      ),
    );

void main() {
  group('ID3v2-prefixed FLAC', () {
    test('parseBytes skips the tag and reads all metadata', () {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      expect(doc.streamInfo.sampleRate, 44100);
      expect(doc.vorbisComment, isNotNull);
      final tags = doc.vorbisComment!.comments.entries;
      expect(tags.any((e) => e.value == 'Cappella'), isTrue);
      expect(doc.id3v2PrefixLength, 110);
    });

    test('parseBytes accounts for the ID3v2 footer when flagged', () {
      final bytes = withId3v2Prefix(
        buildFlac(vorbisComment: _comment()),
        payloadSize: 64,
        withFooter: true,
      );

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      expect(doc.id3v2PrefixLength, 10 + 64 + 10);
      expect(doc.streamInfo.sampleRate, 44100);
    });

    test('toBytes preserves the prefix byte-for-byte', () {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final doc = FlacMetadataDocument.readFromBytes(bytes);

      expect(doc.toBytes(), bytes);
    });

    test('unprefixed files report a zero prefix length', () {
      final doc = FlacMetadataDocument.readFromBytes(
          buildFlac(vorbisComment: _comment()));

      expect(doc.id3v2PrefixLength, 0);
    });

    test('junk starting with ID3 but no FLAC marker still throws', () {
      // Valid-looking ID3 header whose payload runs to the end of the
      // buffer — there is no fLaC marker after it.
      final junk = withId3v2Prefix(Uint8List(0), payloadSize: 16);

      expect(
        () => FlacMetadataDocument.readFromBytes(junk),
        throwsA(isA<InvalidFlacException>()),
      );
    });

    test('non-syncsafe size bytes are not treated as an ID3 tag', () {
      // 0xFF in a size byte is invalid for syncsafe integers, so this is
      // not a real ID3v2 tag and the ordinary invalid-marker error applies.
      final bytes = Uint8List.fromList(
          [0x49, 0x44, 0x33, 3, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3, 4]);

      expect(
        () => FlacMetadataDocument.readFromBytes(bytes),
        throwsA(isA<InvalidFlacException>()),
      );
    });
  });

  group('ID3v2-prefixed FLAC write paths', () {
    test('transformStream round-trips prefix and audio byte-for-byte',
        () async {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final out =
          await FlacTransformer.fromBytes(bytes).transformStream(mutations: []);
      final collected = await _collect(out);

      expect(collected, bytes);
    });

    test('transformStream handles a chunk boundary inside the ID3 prefix',
        () async {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));
      // Split mid-prefix and mid-metadata to exercise accumulation.
      final chunks = [
        bytes.sublist(0, 7),
        bytes.sublist(7, 60),
        bytes.sublist(60, 200),
        bytes.sublist(200),
      ];

      final out = await FlacTransformer.fromStream(Stream.fromIterable(chunks))
          .transformStream(mutations: []);
      final collected = await _collect(out);

      expect(collected, bytes);
    });

    test('transformStream applies mutations while keeping prefix and audio',
        () async {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final out = await FlacTransformer.fromBytes(bytes).transformStream(
        mutations: [
          const SetTag('ARTIST', ['New Artist'])
        ],
      );
      final collected = await _collect(out);

      final doc = FlacMetadataDocument.readFromBytes(collected);
      expect(doc.id3v2PrefixLength, 110);
      expect(doc.vorbisComment!.comments.valuesOf('ARTIST'), ['New Artist']);
      // Audio payload (0xFF 0xF8 sync + 200 zero bytes) survives.
      expect(collected.sublist(collected.length - 202, collected.length - 200),
          [0xFF, 0xF8]);
    });

    test('transformFlac preserves the prefix and reports prefix-free sizes',
        () async {
      final flac = buildFlac(vorbisComment: _comment());
      final bytes = withId3v2Prefix(flac);

      final result = await transformFlac(bytes, []);

      expect(result.bytes, bytes);
      // Plan sizes measure the metadata region only, never the prefix.
      final unprefixed = await transformFlac(flac, []);
      expect(result.plan.originalMetadataRegionSize,
          unprefixed.plan.originalMetadataRegionSize);
      expect(result.plan.transformedMetadataRegionSize,
          unprefixed.plan.transformedMetadataRegionSize);
    });

    test('FlacTransformer.transform preserves the prefix', () async {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final result = await FlacTransformer.fromBytes(bytes).transform(
        mutations: [
          const SetTag('ARTIST', ['New Artist'])
        ],
      );

      final doc = FlacMetadataDocument.readFromBytes(result.bytes);
      expect(doc.id3v2PrefixLength, 110);
      expect(doc.vorbisComment!.comments.valuesOf('ARTIST'), ['New Artist']);
    });

    test('applyMutations preserves the prefix', () async {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));

      final out = await applyMutations(Stream.fromIterable([bytes]), []);

      expect(out, bytes);
    });

    test('edit round-trip keeps the prefix on the updated document', () {
      final bytes = withId3v2Prefix(buildFlac(vorbisComment: _comment()));
      final doc = FlacMetadataDocument.readFromBytes(bytes);

      final updated = doc.edit((e) => e.setTag('ARTIST', ['New Artist']));

      expect(updated.id3v2PrefixLength, 110);
      final reread = FlacMetadataDocument.readFromBytes(updated.toBytes());
      expect(reread.id3v2PrefixLength, 110);
      expect(reread.vorbisComment!.comments.valuesOf('ARTIST'), ['New Artist']);
    });
  });
}

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}
