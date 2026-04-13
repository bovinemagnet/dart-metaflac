import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/src/io/atomic_writer.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('atomic_writer_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AtomicWriter.writeAtomic', () {
    test('writes correct bytes to target path', () async {
      final path = '${tempDir.path}/output.flac';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      // Create file first (writeAtomic replaces existing)
      File(path).writeAsBytesSync(Uint8List.fromList([0]));
      await AtomicWriter.writeAtomic(path, bytes);
      expect(File(path).readAsBytesSync(), equals(bytes));
    });

    test('creates file if it does not exist', () async {
      final path = '${tempDir.path}/new_file.dat';
      final bytes = Uint8List.fromList([10, 20, 30]);
      await AtomicWriter.writeAtomic(path, bytes);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), equals(bytes));
    });

    test('no temp files left after successful write', () async {
      final path = '${tempDir.path}/clean.dat';
      await AtomicWriter.writeAtomic(path, Uint8List.fromList([1]));
      final remaining = tempDir.listSync().whereType<File>().toList();
      expect(remaining.length, equals(1));
      expect(FileSystemEntity.identicalSync(remaining.first.path, path), isTrue);
    });

    test('original file survives if target directory does not exist', () async {
      final badPath = '${tempDir.path}/nonexistent_dir/file.dat';
      expect(
        () => AtomicWriter.writeAtomic(badPath, Uint8List.fromList([1])),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('AtomicWriter.writeToNew', () {
    test('writes bytes to specified path', () async {
      final path = '${tempDir.path}/new_output.dat';
      final bytes = Uint8List.fromList([7, 8, 9]);
      await AtomicWriter.writeToNew(path, bytes);
      expect(File(path).readAsBytesSync(), equals(bytes));
    });
  });
}
