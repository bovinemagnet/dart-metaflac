import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

/// A FLAC application metadata block (type 2).
///
/// Application blocks carry third-party data identified by a registered
/// 4-byte [applicationId]. The format and semantics of [data] are defined
/// by the application that registered the ID.
///
/// See also:
/// - [FlacBlockType.application] for the block type code.
final class ApplicationBlock extends FlacMetadataBlock {
  /// Create an [ApplicationBlock] with the given [applicationId] and [data].
  const ApplicationBlock({required this.applicationId, required this.data});

  /// The 4-byte registered application identifier.
  final Uint8List applicationId;

  /// The application-specific data payload.
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
