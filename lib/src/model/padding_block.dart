import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class PaddingBlock extends FlacMetadataBlock {
  const PaddingBlock(this.size);
  final int size;

  @override
  FlacBlockType get type => FlacBlockType.padding;

  @override
  int get payloadLength => size;

  @override
  Uint8List toPayloadBytes() => Uint8List(size);
}
