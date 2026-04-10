import 'dart:typed_data';

/// Sequential byte writer that accumulates data into a [Uint8List].
///
/// Provides methods for writing unsigned integers of various widths and raw
/// byte sequences. All multi-byte writes use big-endian byte order unless
/// explicitly noted otherwise (see [writeUint32LE]).
///
/// Call [toBytes] to obtain the accumulated result.
final class ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Write a single unsigned 8-bit integer (one byte).
  ///
  /// Only the lowest 8 bits of [value] are written.
  void writeUint8(int value) {
    _builder.addByte(value & 0xFF);
  }

  /// Write an unsigned 16-bit integer in big-endian byte order (two bytes).
  void writeUint16BE(int value) {
    _builder.add([(value >> 8) & 0xFF, value & 0xFF]);
  }

  /// Write an unsigned 24-bit integer in big-endian byte order (three bytes).
  void writeUint24(int value) {
    _builder.add([
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Write an unsigned 32-bit integer in big-endian byte order (four bytes).
  void writeUint32BE(int value) {
    _builder.add([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  /// Write an unsigned 32-bit integer in little-endian byte order (four
  /// bytes).
  ///
  /// This is used when serialising Vorbis comment headers, which store
  /// lengths in little-endian format.
  void writeUint32LE(int value) {
    _builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  /// Write a sequence of raw bytes.
  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  /// Return all accumulated bytes as a single [Uint8List].
  ///
  /// After calling this method the writer should not be reused.
  Uint8List toBytes() => _builder.toBytes();
}
