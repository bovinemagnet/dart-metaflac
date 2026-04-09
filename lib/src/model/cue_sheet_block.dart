import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class CueSheetTrack {
  const CueSheetTrack({
    required this.offset,
    required this.number,
    required this.isrc,
  });
  final int offset;
  final int number;
  final String isrc;
}

final class CueSheetBlock extends FlacMetadataBlock {
  const CueSheetBlock({
    required this.mediaCatalogNumber,
    required this.leadInSamples,
    required this.isCd,
    required this.tracks,
    required this.rawPayload,
  });

  final String mediaCatalogNumber;
  final int leadInSamples;
  final bool isCd;
  final List<CueSheetTrack> tracks;

  /// Original bytes preserved for round-trip fidelity.
  final Uint8List rawPayload;

  @override
  FlacBlockType get type => FlacBlockType.cueSheet;

  @override
  int get payloadLength => rawPayload.length;

  @override
  Uint8List toPayloadBytes() => Uint8List.fromList(rawPayload);
}
