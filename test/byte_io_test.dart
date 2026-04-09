import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  group('ByteReader', () {
    test('readUint8 reads single byte', () {
      final r = ByteReader(Uint8List.fromList([0xAB]));
      expect(r.readUint8(), equals(0xAB));
      expect(r.remaining, equals(0));
      expect(r.offset, equals(1));
    });

    test('readUint16BE reads big-endian 16-bit value', () {
      final r = ByteReader(Uint8List.fromList([0x12, 0x34]));
      expect(r.readUint16BE(), equals(0x1234));
    });

    test('readUint24 reads big-endian 24-bit value', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02, 0x03]));
      expect(r.readUint24(), equals(0x010203));
    });

    test('readUint32BE reads big-endian 32-bit value', () {
      final r = ByteReader(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));
      expect(r.readUint32BE(), equals(0xDEADBEEF));
    });

    test('readUint32LE reads little-endian 32-bit value', () {
      final r = ByteReader(Uint8List.fromList([0x78, 0x56, 0x34, 0x12]));
      expect(r.readUint32LE(), equals(0x12345678));
    });

    test('readBytes reads slice of bytes', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02, 0x03, 0x04]));
      final slice = r.readBytes(3);
      expect(slice, equals([0x01, 0x02, 0x03]));
      expect(r.remaining, equals(1));
    });

    test('skip advances offset without reading', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02, 0x03]));
      r.skip(2);
      expect(r.offset, equals(2));
      expect(r.readUint8(), equals(0x03));
    });

    test('sequential reads advance offset correctly', () {
      final r = ByteReader(Uint8List.fromList([0xFF, 0x01, 0x00, 0x00, 0x02]));
      expect(r.readUint8(), equals(0xFF));
      expect(r.readUint32BE(), equals(0x01000002));
      expect(r.remaining, equals(0));
    });

    test('throws MalformedMetadataException when reading beyond end', () {
      final r = ByteReader(Uint8List.fromList([0x01]));
      r.readUint8();
      expect(
        () => r.readUint8(),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test('throws MalformedMetadataException on readBytes beyond end', () {
      final r = ByteReader(Uint8List.fromList([0x01, 0x02]));
      expect(
        () => r.readBytes(3),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test('throws MalformedMetadataException on skip beyond end', () {
      final r = ByteReader(Uint8List.fromList([0x01]));
      expect(
        () => r.skip(2),
        throwsA(isA<MalformedMetadataException>()),
      );
    });

    test('remaining is correct after reads', () {
      final r = ByteReader(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(r.remaining, equals(5));
      r.skip(2);
      expect(r.remaining, equals(3));
      r.readBytes(3);
      expect(r.remaining, equals(0));
    });
  });

  group('ByteWriter', () {
    test('writeUint8 produces single byte', () {
      final w = ByteWriter();
      w.writeUint8(0xAB);
      expect(w.toBytes(), equals([0xAB]));
    });

    test('writeUint8 masks to 8 bits', () {
      final w = ByteWriter();
      w.writeUint8(0x1FF); // should mask to 0xFF
      expect(w.toBytes(), equals([0xFF]));
    });

    test('writeUint16BE produces big-endian bytes', () {
      final w = ByteWriter();
      w.writeUint16BE(0x1234);
      expect(w.toBytes(), equals([0x12, 0x34]));
    });

    test('writeUint24 produces big-endian 3-byte sequence', () {
      final w = ByteWriter();
      w.writeUint24(0x010203);
      expect(w.toBytes(), equals([0x01, 0x02, 0x03]));
    });

    test('writeUint32BE produces big-endian bytes', () {
      final w = ByteWriter();
      w.writeUint32BE(0xDEADBEEF);
      expect(w.toBytes(), equals([0xDE, 0xAD, 0xBE, 0xEF]));
    });

    test('writeUint32LE produces little-endian bytes', () {
      final w = ByteWriter();
      w.writeUint32LE(0x12345678);
      expect(w.toBytes(), equals([0x78, 0x56, 0x34, 0x12]));
    });

    test('writeBytes appends raw bytes', () {
      final w = ByteWriter();
      w.writeBytes([0x01, 0x02, 0x03]);
      expect(w.toBytes(), equals([0x01, 0x02, 0x03]));
    });

    test('multiple writes accumulate correctly', () {
      final w = ByteWriter();
      w.writeUint8(0xAA);
      w.writeUint16BE(0xBBCC);
      w.writeUint8(0xDD);
      expect(w.toBytes(), equals([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('ByteReader and ByteWriter round-trip uint32 LE', () {
      const value = 0x01020304;
      final w = ByteWriter();
      w.writeUint32LE(value);
      final r = ByteReader(w.toBytes());
      expect(r.readUint32LE(), equals(value));
    });

    test('ByteReader and ByteWriter round-trip uint32 BE', () {
      const value = 0xDEADBEEF;
      final w = ByteWriter();
      w.writeUint32BE(value);
      final r = ByteReader(w.toBytes());
      expect(r.readUint32BE(), equals(value));
    });
  });
}
