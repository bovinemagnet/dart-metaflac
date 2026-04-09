import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/src/io/modtime.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('modtime_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ModTimePreserver', () {
    test('capture returns a DateTime', () async {
      final path = '${tempDir.path}/test.dat';
      File(path).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      final modTime = await ModTimePreserver.capture(path);
      expect(modTime, isA<DateTime>());
    });

    test('restore sets the modification time', () async {
      final path = '${tempDir.path}/test.dat';
      File(path).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      final pastTime = DateTime(2020, 1, 1, 12, 0, 0);
      await ModTimePreserver.restore(path, pastTime);

      final restored = await ModTimePreserver.capture(path);
      // Allow 1 second tolerance for filesystem precision
      expect(
          restored.difference(pastTime).inSeconds.abs(), lessThanOrEqualTo(1));
    });
  });
}
