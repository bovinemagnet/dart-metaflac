import 'dart:typed_data';

final class ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
  }

  void writeUint16BE(int value) {
    _builder.add([(value >> 8) & 0xFF, value & 0xFF]);
  }

  void writeUint24(int value) {
    _builder.add([
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  void writeUint32BE(int value) {
    _builder.add([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  void writeUint32LE(int value) {
    _builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  Uint8List toBytes() => _builder.toBytes();
}
