import 'dart:typed_data';
import '../error/exceptions.dart';

/// Sequential big-endian byte reader over a [Uint8List].
///
/// Provides methods for reading unsigned integers of various widths and raw
/// byte sequences from a fixed buffer. An internal offset advances
/// automatically after each read. All multi-byte reads use big-endian byte
/// order unless explicitly noted otherwise (see [readUint32LE]).
///
/// Throws [MalformedMetadataException] if a read would exceed the available
/// data.
final class ByteReader {
  /// Create a [ByteReader] that reads from [_bytes] starting at offset zero.
  ByteReader(this._bytes);
  final Uint8List _bytes;
  int _offset = 0;

  /// Current read position within the underlying byte buffer.
  int get offset => _offset;

  /// Number of bytes remaining between the current [offset] and the end of
  /// the buffer.
  int get remaining => _bytes.length - _offset;

  /// Read a single unsigned 8-bit integer and advance by one byte.
  ///
  /// Throws [MalformedMetadataException] if fewer than 1 byte remains.
  int readUint8() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  /// Read an unsigned 16-bit integer in big-endian byte order and advance by
  /// two bytes.
  ///
  /// Throws [MalformedMetadataException] if fewer than 2 bytes remain.
  int readUint16BE() {
    _ensureAvailable(2);
    final value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  /// Read an unsigned 24-bit integer in big-endian byte order and advance by
  /// three bytes.
  ///
  /// Throws [MalformedMetadataException] if fewer than 3 bytes remain.
  int readUint24() {
    _ensureAvailable(3);
    final value = (_bytes[_offset] << 16) |
        (_bytes[_offset + 1] << 8) |
        _bytes[_offset + 2];
    _offset += 3;
    return value;
  }

  /// Read an unsigned 32-bit integer in big-endian byte order and advance by
  /// four bytes.
  ///
  /// Throws [MalformedMetadataException] if fewer than 4 bytes remain.
  int readUint32BE() {
    _ensureAvailable(4);
    final value = (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  /// Read an unsigned 32-bit integer in little-endian byte order and advance
  /// by four bytes.
  ///
  /// This is used when parsing Vorbis comment headers, which store lengths in
  /// little-endian format.
  ///
  /// Throws [MalformedMetadataException] if fewer than 4 bytes remain.
  int readUint32LE() {
    _ensureAvailable(4);
    final b0 = _bytes[_offset];
    final b1 = _bytes[_offset + 1];
    final b2 = _bytes[_offset + 2];
    final b3 = _bytes[_offset + 3];
    _offset += 4;
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  /// Read [length] bytes as a new [Uint8List] and advance accordingly.
  ///
  /// The returned list is a copy and does not share memory with the
  /// underlying buffer.
  ///
  /// Throws [MalformedMetadataException] if fewer than [length] bytes remain.
  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final result =
        Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return result;
  }

  /// Skip forward by [length] bytes without returning any data.
  ///
  /// Throws [MalformedMetadataException] if fewer than [length] bytes remain.
  void skip(int length) {
    _ensureAvailable(length);
    _offset += length;
  }

  void _ensureAvailable(int length) {
    if (remaining < length) {
      throw MalformedMetadataException(
        'Unexpected end of data: needed $length bytes, '
        'only $remaining available.',
      );
    }
  }
}
