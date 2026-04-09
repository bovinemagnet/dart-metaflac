import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class UnknownBlock extends FlacMetadataBlock {
  const UnknownBlock({required this.rawTypeCode, required this.rawPayload});
  final int rawTypeCode;
  final Uint8List rawPayload;

  @override
  FlacBlockType get type => FlacBlockType.unknown;

  @override
  int get payloadLength => rawPayload.length;

  @override
  Uint8List toPayloadBytes() => Uint8List.fromList(rawPayload);
}
