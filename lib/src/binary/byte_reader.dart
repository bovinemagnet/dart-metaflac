import 'dart:typed_data';
import '../error/exceptions.dart';

final class ByteReader {
  ByteReader(this._bytes);
  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;

  int readUint8() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  int readUint16BE() {
    _ensureAvailable(2);
    final value = (_bytes[_offset] << 8) | _bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  int readUint24() {
    _ensureAvailable(3);
    final value = (_bytes[_offset] << 16) |
        (_bytes[_offset + 1] << 8) |
        _bytes[_offset + 2];
    _offset += 3;
    return value;
  }

  int readUint32BE() {
    _ensureAvailable(4);
    final value = (_bytes[_offset] << 24) |
        (_bytes[_offset + 1] << 16) |
        (_bytes[_offset + 2] << 8) |
        _bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  int readUint32LE() {
    _ensureAvailable(4);
    final b0 = _bytes[_offset];
    final b1 = _bytes[_offset + 1];
    final b2 = _bytes[_offset + 2];
    final b3 = _bytes[_offset + 3];
    _offset += 4;
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final result =
        Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return result;
  }

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
