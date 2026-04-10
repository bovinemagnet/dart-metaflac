import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// A FLAC metadata block with an unrecognised type code.
///
/// Unknown blocks are preserved as raw bytes during parsing and
/// round-trip serialisation, ensuring that future or proprietary block
/// types are not silently discarded.
///
/// See also:
/// - [FlacBlockType.unknown] for the sentinel block type value.
final class UnknownBlock extends FlacMetadataBlock {
  /// Create an [UnknownBlock] with the given [rawTypeCode] and
  /// [rawPayload].
  const UnknownBlock({required this.rawTypeCode, required this.rawPayload});

  /// The numeric block type code as read from the FLAC stream.
  ///
  /// This value does not correspond to any standard [FlacBlockType] and is
  /// retained so that the block can be written back with its original type.
  final int rawTypeCode;

  /// The uninterpreted payload bytes of this block.
  final Uint8List rawPayload;

  @override
  FlacBlockType get type => FlacBlockType.unknown;

  @override
  int get payloadLength => rawPayload.length;

  @override
  Uint8List toPayloadBytes() => Uint8List.fromList(rawPayload);
}
