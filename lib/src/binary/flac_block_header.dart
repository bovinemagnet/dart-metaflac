/// Parsed header of a FLAC metadata block.
///
/// Every metadata block in a FLAC stream is preceded by a four-byte header
/// containing a last-block flag, a block type code, and the payload length.
/// This class captures those three fields after they have been read from the
/// binary stream by [FlacParser].
final class FlacBlockHeader {
  /// Create a [FlacBlockHeader] with the given [isLast] flag, [typeCode],
  /// and [payloadLength].
  const FlacBlockHeader({
    required this.isLast,
    required this.typeCode,
    required this.payloadLength,
  });

  /// Whether this is the last metadata block before the audio frames.
  ///
  /// When `true`, the parser stops reading metadata after this block.
  final bool isLast;

  /// Numeric type code identifying the kind of metadata block.
  ///
  /// Standard codes are 0 (STREAMINFO), 1 (PADDING), 2 (APPLICATION),
  /// 3 (SEEKTABLE), 4 (VORBIS_COMMENT), 5 (CUESHEET), and 6 (PICTURE).
  /// Codes 7--126 are reserved; 127 is invalid.
  final int typeCode;

  /// Length of the block payload in bytes, excluding the four-byte header.
  final int payloadLength;
}
