import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  group('Exception hierarchy', () {
    test('FlacMetadataException implements Exception', () {
      final e = FlacMetadataException('test message');
      expect(e, isA<Exception>());
      expect(e.toString(), contains('test message'));
    });

    test('InvalidFlacException extends FlacMetadataException', () {
      final e = InvalidFlacException('bad file');
      expect(e, isA<FlacMetadataException>());
      expect(e.toString(), contains('bad file'));
    });

    test('MalformedMetadataException extends FlacMetadataException', () {
      final e = MalformedMetadataException('truncated block');
      expect(e, isA<FlacMetadataException>());
    });

    test('UnsupportedBlockException extends FlacMetadataException', () {
      final e = UnsupportedBlockException('write not supported');
      expect(e, isA<FlacMetadataException>());
    });

    test('FlacInsufficientPaddingException extends FlacMetadataException', () {
      final e = FlacInsufficientPaddingException('no room');
      expect(e, isA<FlacMetadataException>());
    });

    test('WriteConflictException extends FlacMetadataException', () {
      final e = WriteConflictException('in-place impossible');
      expect(e, isA<FlacMetadataException>());
    });

    test('FlacIoException extends FlacMetadataException', () {
      final e = FlacIoException('disk error');
      expect(e, isA<FlacMetadataException>());
    });

    test('FlacCorruptHeaderException extends InvalidFlacException', () {
      final e = FlacCorruptHeaderException('invalid marker');
      expect(e, isA<InvalidFlacException>());
      expect(e, isA<FlacMetadataException>());
    });

    test('exception cause is stored', () {
      final cause = Exception('underlying IO error');
      final e = FlacIoException('wrapped', cause: cause);
      expect(e.cause, same(cause));
    });

    test('exception toString includes class name and message', () {
      final e = InvalidFlacException('missing fLaC');
      expect(e.toString(), contains('InvalidFlacException'));
      expect(e.toString(), contains('missing fLaC'));
    });
  });

  group('FlacBlockType', () {
    test('fromCode returns correct types for all known codes', () {
      expect(FlacBlockType.fromCode(0), equals(FlacBlockType.streamInfo));
      expect(FlacBlockType.fromCode(1), equals(FlacBlockType.padding));
      expect(FlacBlockType.fromCode(2), equals(FlacBlockType.application));
      expect(FlacBlockType.fromCode(3), equals(FlacBlockType.seekTable));
      expect(FlacBlockType.fromCode(4), equals(FlacBlockType.vorbisComment));
      expect(FlacBlockType.fromCode(5), equals(FlacBlockType.cueSheet));
      expect(FlacBlockType.fromCode(6), equals(FlacBlockType.picture));
    });

    test('fromCode returns unknown for unrecognized codes', () {
      expect(FlacBlockType.fromCode(7), equals(FlacBlockType.unknown));
      expect(FlacBlockType.fromCode(127), equals(FlacBlockType.unknown));
    });

    test('code returns correct integer for each type', () {
      expect(FlacBlockType.streamInfo.code, equals(0));
      expect(FlacBlockType.padding.code, equals(1));
      expect(FlacBlockType.application.code, equals(2));
      expect(FlacBlockType.seekTable.code, equals(3));
      expect(FlacBlockType.vorbisComment.code, equals(4));
      expect(FlacBlockType.cueSheet.code, equals(5));
      expect(FlacBlockType.picture.code, equals(6));
      expect(FlacBlockType.unknown.code, equals(127));
    });

    test('fromCode and code are inverses for known types', () {
      const knownCodes = [0, 1, 2, 3, 4, 5, 6];
      for (final code in knownCodes) {
        expect(FlacBlockType.fromCode(code).code, equals(code));
      }
    });
  });

  group('PictureType', () {
    test('fromCode returns correct enum for known codes', () {
      expect(PictureType.fromCode(0), equals(PictureType.other));
      expect(PictureType.fromCode(3), equals(PictureType.frontCover));
      expect(PictureType.fromCode(4), equals(PictureType.backCover));
      expect(PictureType.fromCode(20), equals(PictureType.publisherLogo));
    });

    test('fromCode returns other for unknown code', () {
      expect(PictureType.fromCode(99), equals(PictureType.other));
    });

    test('all 21 picture types have unique codes from 0 to 20', () {
      final codes = PictureType.values.map((t) => t.code).toSet();
      expect(codes.length, equals(21));
      for (var i = 0; i <= 20; i++) {
        expect(codes.contains(i), isTrue, reason: 'Missing code $i');
      }
    });

    test('fromCode and code are inverses for all defined types', () {
      for (final t in PictureType.values) {
        expect(PictureType.fromCode(t.code), equals(t));
      }
    });
  });

  group('PaddingStrategy', () {
    test('computeRemainingPadding returns difference', () {
      expect(
        PaddingStrategy.computeRemainingPadding(
          originalMetadataRegionSize: 1000,
          newMetadataContentSize: 800,
        ),
        equals(200),
      );
    });

    test('computeRemainingPadding can be negative (overflow)', () {
      expect(
        PaddingStrategy.computeRemainingPadding(
          originalMetadataRegionSize: 500,
          newMetadataContentSize: 600,
        ),
        equals(-100),
      );
    });

    test('fitsExistingRegion returns true when new size fits', () {
      expect(
        PaddingStrategy.fitsExistingRegion(
          originalMetadataRegionSize: 1000,
          newMetadataContentSize: 999,
        ),
        isTrue,
      );
    });

    test('fitsExistingRegion returns true when sizes are equal', () {
      expect(
        PaddingStrategy.fitsExistingRegion(
          originalMetadataRegionSize: 500,
          newMetadataContentSize: 500,
        ),
        isTrue,
      );
    });

    test('fitsExistingRegion returns false when new size exceeds', () {
      expect(
        PaddingStrategy.fitsExistingRegion(
          originalMetadataRegionSize: 400,
          newMetadataContentSize: 401,
        ),
        isFalse,
      );
    });
  });
}
