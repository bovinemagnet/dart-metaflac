import '../model/flac_metadata_block.dart';
import '../model/flac_metadata_document.dart';
import '../model/padding_block.dart';
import '../model/picture_block.dart';
import '../model/picture_type.dart';
import '../model/stream_info_block.dart';
import '../model/vorbis_comment_block.dart';
import '../model/vorbis_comments.dart';
import 'mutation_ops.dart';

class FlacMetadataEditor {
  FlacMetadataEditor.fromDocument(this._source)
      : _mutations = [];

  final FlacMetadataDocument _source;
  final List<MetadataMutation> _mutations;

  void setTag(String key, List<String> values) =>
      _mutations.add(SetTag(key, values));

  void addTag(String key, String value) =>
      _mutations.add(AddTag(key, value));

  void removeTag(String key) => _mutations.add(RemoveTag(key));

  void removeExactTagValue(String key, String value) =>
      _mutations.add(RemoveExactTagValue(key, value));

  void clearTags() => _mutations.add(const ClearTags());

  void addPicture(PictureBlock picture) =>
      _mutations.add(AddPicture(picture));

  void replacePictureByType(PictureType pictureType, PictureBlock replacement) =>
      _mutations.add(ReplacePictureByType(
          pictureType: pictureType, replacement: replacement));

  void removePictureByType(PictureType pictureType) =>
      _mutations.add(RemovePictureByType(pictureType));

  void removeAllPictures() => _mutations.add(const RemoveAllPictures());

  void setPadding(int size) => _mutations.add(SetPadding(size));

  /// Apply a single [MetadataMutation] immediately.
  void applyMutation(MetadataMutation mutation) => _mutations.add(mutation);

  FlacMetadataDocument build() {
    var currentBlocks = List<FlacMetadataBlock>.from(_source.blocks);
    for (final mutation in _mutations) {
      currentBlocks = _applyToBlocks(currentBlocks, mutation);
    }
    return FlacMetadataDocument(
      blocks: currentBlocks,
      audioDataOffset: _source.audioDataOffset,
      sourceMetadataRegionLength: _source.sourceMetadataRegionLength,
    );
  }

  List<FlacMetadataBlock> _applyToBlocks(
    List<FlacMetadataBlock> blocks,
    MetadataMutation mutation,
  ) {
    switch (mutation) {
      case SetTag m:
        return _updateVorbisComments(blocks, (vc) => vc.set(m.key, m.values));
      case AddTag m:
        return _updateVorbisComments(blocks, (vc) => vc.add(m.key, m.value));
      case RemoveTag m:
        return _updateVorbisComments(blocks, (vc) => vc.removeKey(m.key));
      case RemoveExactTagValue m:
        return _updateVorbisComments(
            blocks, (vc) => vc.removeExact(m.key, m.value));
      case ClearTags _:
        return _updateVorbisComments(blocks, (vc) => vc.clear());
      case AddPicture m:
        return [...blocks, m.picture];
      case ReplacePictureByType m:
        return blocks.map((b) {
          if (b is PictureBlock && b.pictureType == m.pictureType) {
            return m.replacement;
          }
          return b;
        }).toList();
      case RemovePictureByType m:
        return blocks
            .where(
                (b) => !(b is PictureBlock && b.pictureType == m.pictureType))
            .toList();
      case RemoveAllPictures _:
        return blocks.where((b) => b is! PictureBlock).toList();
      case SetPadding m:
        final withoutPadding =
            blocks.where((b) => b is! PaddingBlock).toList();
        if (m.size > 0) return [...withoutPadding, PaddingBlock(m.size)];
        return withoutPadding;
    }
  }

  List<FlacMetadataBlock> _updateVorbisComments(
    List<FlacMetadataBlock> blocks,
    VorbisComments Function(VorbisComments) update,
  ) {
    final existing =
        blocks.whereType<VorbisCommentBlock>().firstOrNull;
    final existingComments = existing?.comments ??
        VorbisComments(vendorString: 'dart_metaflac', entries: []);
    final newComments = update(existingComments);
    final newBlock = VorbisCommentBlock(comments: newComments);

    if (existing == null) {
      // Insert after StreamInfo block.
      final result = <FlacMetadataBlock>[];
      var inserted = false;
      for (final b in blocks) {
        result.add(b);
        if (!inserted && b is StreamInfoBlock) {
          result.add(newBlock);
          inserted = true;
        }
      }
      if (!inserted) result.add(newBlock);
      return result;
    } else {
      return blocks
          .map((b) => b is VorbisCommentBlock ? newBlock : b)
          .toList();
    }
  }
}
