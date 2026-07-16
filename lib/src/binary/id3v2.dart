import 'dart:typed_data';

/// Returns the total byte length of a leading ID3v2 tag, or 0 when
/// [bytes] does not start with one.
///
/// An ID3v2 tag is a 10-byte header ('ID3', two version bytes, one
/// flags byte, four syncsafe size bytes), the payload of the declared
/// size, and — when the footer flag (0x10) is set — a 10-byte footer.
/// Size bytes with the high bit set are not valid syncsafe integers,
/// so such data is not treated as an ID3 tag at all.
int leadingId3v2Length(Uint8List bytes) {
  const headerLength = 10;
  if (bytes.length < headerLength) return 0;
  if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return 0;
  if (bytes[6] >= 0x80 ||
      bytes[7] >= 0x80 ||
      bytes[8] >= 0x80 ||
      bytes[9] >= 0x80) {
    return 0;
  }
  final payloadLength =
      (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
  final hasFooter = (bytes[5] & 0x10) != 0;
  return headerLength + payloadLength + (hasFooter ? headerLength : 0);
}
