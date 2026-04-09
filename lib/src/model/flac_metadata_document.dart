import '../edit/flac_metadata_editor.dart';
import 'flac_metadata_block.dart';
import 'picture_block.dart';
import 'stream_info_block.dart';
import 'vorbis_comment_block.dart';

final class FlacMetadataDocument {
  const FlacMetadataDocument({
    required this.blocks,
    required this.audioDataOffset,
    required this.sourceMetadataRegionLength,
  });

  final List<FlacMetadataBlock> blocks;
  final int audioDataOffset;
  final int sourceMetadataRegionLength;

  StreamInfoBlock get streamInfo =>
      blocks.whereType<StreamInfoBlock>().single;

  VorbisCommentBlock? get vorbisComment =>
      blocks.whereType<VorbisCommentBlock>().firstOrNull;

  List<PictureBlock> get pictures =>
      blocks.whereType<PictureBlock>().toList(growable: false);

  FlacMetadataDocument edit(
      void Function(FlacMetadataEditor editor) updates) {
    final editor = FlacMetadataEditor.fromDocument(this);
    updates(editor);
    return editor.build();
  }
}
