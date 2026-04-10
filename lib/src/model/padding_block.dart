import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// A FLAC padding metadata block (type 1).
///
/// Padding blocks consist entirely of zero bytes and serve as reserved
/// space within the metadata region. When metadata is edited, padding can
/// be consumed to avoid rewriting the entire FLAC file.
///
/// See also:
/// - [FlacBlockType.padding] for the block type code.
/// - [FlacInsufficientPaddingException] thrown when there is not enough
///   padding for an in-place update.
final class PaddingBlock extends FlacMetadataBlock {
  /// Create a [PaddingBlock] with the given [size] in bytes.
  const PaddingBlock(this.size);

  /// The number of zero-filled bytes in this padding block's payload.
  final int size;

  @override
  FlacBlockType get type => FlacBlockType.padding;

  @override
  int get payloadLength => size;

  @override
  Uint8List toPayloadBytes() => Uint8List(size);
}
