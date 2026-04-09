import 'dart:convert';
import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';
import 'vorbis_comments.dart';

final class VorbisCommentBlock extends FlacMetadataBlock {
  const VorbisCommentBlock({required this.comments});
  final VorbisComments comments;

  @override
  FlacBlockType get type => FlacBlockType.vorbisComment;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    final vendorBytes = utf8.encode(comments.vendorString);
    final commentPairs = <List<int>>[];
    for (final entry in comments.entries) {
      commentPairs.add(utf8.encode('${entry.key}=${entry.value}'));
    }
    var totalSize = 4 + vendorBytes.length + 4;
    for (final cp in commentPairs) {
      totalSize += 4 + cp.length;
    }
    final out = Uint8List(totalSize);
    var offset = 0;
    void writeLE32(int v) {
      out[offset] = v & 0xFF;
      out[offset + 1] = (v >> 8) & 0xFF;
      out[offset + 2] = (v >> 16) & 0xFF;
      out[offset + 3] = (v >> 24) & 0xFF;
      offset += 4;
    }

    writeLE32(vendorBytes.length);
    out.setRange(offset, offset + vendorBytes.length, vendorBytes);
    offset += vendorBytes.length;
    writeLE32(commentPairs.length);
    for (final cp in commentPairs) {
      writeLE32(cp.length);
      out.setRange(offset, offset + cp.length, cp);
      offset += cp.length;
    }
    return out;
  }
}
