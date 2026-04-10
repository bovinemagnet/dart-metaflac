import 'dart:typed_data';
import 'flac_block_type.dart';

/// Abstract base class for all FLAC metadata blocks.
///
/// Each concrete subclass represents a specific block type defined by the
/// FLAC specification (e.g. [StreamInfoBlock], [VorbisCommentBlock],
/// [PictureBlock]). Implementations must provide their [type], the byte
/// length of their payload via [payloadLength], and serialisation via
/// [toPayloadBytes].
///
/// See also:
/// - [FlacBlockType] for the enumeration of block type codes.
/// - [FlacMetadataDocument] for the container that holds a list of blocks.
abstract class FlacMetadataBlock {
  /// Create a [FlacMetadataBlock].
  const FlacMetadataBlock();

  /// The [FlacBlockType] identifying this block's kind.
  FlacBlockType get type;

  /// The length of this block's payload in bytes, excluding the 4-byte
  /// block header.
  int get payloadLength;

  /// Serialise this block's payload to a [Uint8List].
  ///
  /// The returned bytes do not include the 4-byte block header; the caller
  /// is responsible for writing the header separately.
  Uint8List toPayloadBytes();
}
