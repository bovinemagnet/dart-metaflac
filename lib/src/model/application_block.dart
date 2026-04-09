import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class ApplicationBlock extends FlacMetadataBlock {
  const ApplicationBlock({required this.applicationId, required this.data});

  /// 4-byte application ID.
  final Uint8List applicationId;
  final Uint8List data;

  @override
  FlacBlockType get type => FlacBlockType.application;

  @override
  int get payloadLength => 4 + data.length;

  @override
  Uint8List toPayloadBytes() {
    final out = Uint8List(4 + data.length);
    out.setRange(0, 4, applicationId);
    out.setRange(4, 4 + data.length, data);
    return out;
  }
}
