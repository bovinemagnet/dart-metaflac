import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  group('VorbisCommentProcessor', () {
    test('encodes and decodes empty comments', () {
      final block = VorbisCommentBlock(
        vendorString: 'test_vendor',
        comments: {},
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.vendorString, equals('test_vendor'));
      expect(decoded.comments, isEmpty);
    });

    test('round-trips single tag', () {
      final block = VorbisCommentBlock(
        vendorString: 'vendor',
        comments: {
          'TITLE': ['My Song'],
        },
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.comments['TITLE'], equals(['My Song']));
    });

    test('round-trips multi-value tags', () {
      final block = VorbisCommentBlock(
        vendorString: 'v',
        comments: {
          'ARTIST': ['Artist A', 'Artist B'],
        },
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.comments['ARTIST'], containsAll(['Artist A', 'Artist B']));
      expect(decoded.comments['ARTIST']!.length, equals(2));
    });

    test('round-trips multiple different tags', () {
      final block = VorbisCommentBlock(
        vendorString: 'vendor',
        comments: {
          'TITLE': ['Test'],
          'ALBUM': ['My Album'],
          'TRACKNUMBER': ['5'],
        },
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.comments['TITLE'], equals(['Test']));
      expect(decoded.comments['ALBUM'], equals(['My Album']));
      expect(decoded.comments['TRACKNUMBER'], equals(['5']));
    });

    test('keys are uppercased on decode', () {
      final block = VorbisCommentBlock(
        vendorString: 'v',
        comments: {'title': ['hello']},
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.comments.containsKey('TITLE'), isTrue);
    });

    test('handles unicode in vendor and values', () {
      final block = VorbisCommentBlock(
        vendorString: 'vendor 日本語',
        comments: {'TITLE': ['曲名']},
      );
      final encoded = VorbisCommentProcessor.encode(block);
      final decoded = VorbisCommentProcessor.decode(encoded);
      expect(decoded.vendorString, equals('vendor 日本語'));
      expect(decoded.comments['TITLE'], equals(['曲名']));
    });
  });
}
