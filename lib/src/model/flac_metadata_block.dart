import 'dart:typed_data';
import 'flac_block_type.dart';

abstract class FlacMetadataBlock {
  const FlacMetadataBlock();
  FlacBlockType get type;
  int get payloadLength;
  Uint8List toPayloadBytes();
}
