/// Enumeration of FLAC metadata block types as defined by the FLAC
/// specification.
///
/// Each value corresponds to a numeric type code (0–6) stored in the
/// block header. Unrecognised codes are mapped to [unknown].
enum FlacBlockType {
  /// STREAMINFO block (type 0) — mandatory; contains sample rate, channels,
  /// bit depth, total samples, and MD5 signature.
  streamInfo,

  /// PADDING block (type 1) — reserved space that may be used for future
  /// metadata edits without rewriting the entire file.
  padding,

  /// APPLICATION block (type 2) — third-party application data identified
  /// by a 4-byte application ID.
  application,

  /// SEEKTABLE block (type 3) — optional seek points for faster random
  /// access within the audio stream.
  seekTable,

  /// VORBIS_COMMENT block (type 4) — human-readable tags using the Vorbis
  /// comment format (e.g. ARTIST, TITLE).
  vorbisComment,

  /// CUESHEET block (type 5) — CD table-of-contents information including
  /// track offsets and ISRC codes.
  cueSheet,

  /// PICTURE block (type 6) — embedded image such as album art, with
  /// associated MIME type and dimensions.
  picture,

  /// Placeholder for any block type code not recognised by this library.
  ///
  /// Unknown blocks are preserved as raw bytes during round-trip
  /// serialisation.
  unknown;

  /// Return the [FlacBlockType] corresponding to the given numeric [code].
  ///
  /// Codes 0–6 map to the standard FLAC block types. Any other value
  /// returns [unknown].
  static FlacBlockType fromCode(int code) {
    switch (code) {
      case 0:
        return FlacBlockType.streamInfo;
      case 1:
        return FlacBlockType.padding;
      case 2:
        return FlacBlockType.application;
      case 3:
        return FlacBlockType.seekTable;
      case 4:
        return FlacBlockType.vorbisComment;
      case 5:
        return FlacBlockType.cueSheet;
      case 6:
        return FlacBlockType.picture;
      default:
        return FlacBlockType.unknown;
    }
  }

  /// The numeric type code for this block type as stored in the FLAC
  /// block header.
  ///
  /// Returns 127 for [unknown], which is the maximum reserved value in
  /// the FLAC specification.
  int get code {
    switch (this) {
      case FlacBlockType.streamInfo:
        return 0;
      case FlacBlockType.padding:
        return 1;
      case FlacBlockType.application:
        return 2;
      case FlacBlockType.seekTable:
        return 3;
      case FlacBlockType.vorbisComment:
        return 4;
      case FlacBlockType.cueSheet:
        return 5;
      case FlacBlockType.picture:
        return 6;
      case FlacBlockType.unknown:
        return 127;
    }
  }
}
