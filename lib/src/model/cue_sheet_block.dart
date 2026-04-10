import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// A single track entry within a [CueSheetBlock].
///
/// Each track has a sample offset, a track number, and an optional ISRC
/// (International Standard Recording Code).
final class CueSheetTrack {
  /// Create a [CueSheetTrack] with the given [offset], [number], and [isrc].
  const CueSheetTrack({
    required this.offset,
    required this.number,
    required this.isrc,
  });

  /// The sample offset of this track from the beginning of the audio stream.
  final int offset;

  /// The track number (1–99 for regular tracks, 170 for lead-out).
  final int number;

  /// The track's ISRC code, or an empty string if not set.
  final String isrc;
}

/// A FLAC cue sheet metadata block (type 5).
///
/// Contains CD table-of-contents information including the media catalogue
/// number, lead-in sample count, and an ordered list of [CueSheetTrack]
/// entries. The original raw payload is preserved for round-trip fidelity.
///
/// See also:
/// - [CueSheetTrack] for individual track entries.
/// - [FlacBlockType.cueSheet] for the block type code.
final class CueSheetBlock extends FlacMetadataBlock {
  /// Create a [CueSheetBlock] with the given fields.
  ///
  /// The [rawPayload] must contain the complete original cue sheet bytes
  /// for faithful round-trip serialisation.
  const CueSheetBlock({
    required this.mediaCatalogNumber,
    required this.leadInSamples,
    required this.isCd,
    required this.tracks,
    required this.rawPayload,
  });

  /// The media catalogue number (UPC/EAN), up to 128 bytes, NUL-padded.
  final String mediaCatalogNumber;

  /// The number of lead-in samples (must be non-zero for CD-DA cue sheets).
  final int leadInSamples;

  /// Whether this cue sheet corresponds to a Compact Disc.
  final bool isCd;

  /// The ordered list of tracks in this cue sheet.
  final List<CueSheetTrack> tracks;

  /// Original bytes preserved for round-trip fidelity.
  ///
  /// Because the cue sheet format contains reserved fields and index-point
  /// data that this model does not fully decompose, the raw payload is
  /// stored to ensure lossless re-serialisation.
  final Uint8List rawPayload;

  @override
  FlacBlockType get type => FlacBlockType.cueSheet;

  @override
  int get payloadLength => rawPayload.length;

  @override
  Uint8List toPayloadBytes() => Uint8List.fromList(rawPayload);
}
