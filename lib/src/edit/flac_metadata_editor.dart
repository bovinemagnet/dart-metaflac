import '../model/flac_metadata_block.dart';
import '../model/flac_metadata_document.dart';
import '../model/padding_block.dart';
import '../model/picture_block.dart';
import '../model/picture_type.dart';
import '../model/stream_info_block.dart';
import '../model/vorbis_comment_block.dart';
import '../model/vorbis_comments.dart';
import 'mutation_ops.dart';

/// Accumulate [MetadataMutation] operations and produce an updated
/// [FlacMetadataDocument].
///
/// Mutations are recorded in order and applied sequentially when [build]
/// is called. The editor never modifies the source document; instead it
/// returns a new, immutable [FlacMetadataDocument].
///
/// ```dart
/// final updated = FlacMetadataEditor.fromDocument(doc)
///   ..setTag('ARTIST', ['Ada Lovelace'])
///   ..addTag('GENRE', 'Electronic')
///   ..build();
/// ```
///
/// See also: [MetadataMutation] for the full list of supported operations.
class FlacMetadataEditor {
  /// Create an editor seeded with the blocks from [_source].
  FlacMetadataEditor.fromDocument(this._source) : _mutations = [];

  final FlacMetadataDocument _source;
  final List<MetadataMutation> _mutations;

  /// Replace all values for [key] with [values] in the Vorbis comments.
  ///
  /// Enqueues a [SetTag] mutation.
  void setTag(String key, List<String> values) =>
      _mutations.add(SetTag(key, values));

  /// Append a single [value] to [key] in the Vorbis comments.
  ///
  /// Enqueues an [AddTag] mutation. Existing values for [key] are
  /// preserved.
  void addTag(String key, String value) => _mutations.add(AddTag(key, value));

  /// Remove all entries for [key] from the Vorbis comments.
  ///
  /// Enqueues a [RemoveTag] mutation.
  void removeTag(String key) => _mutations.add(RemoveTag(key));

  /// Remove a single entry matching both [key] and [value] from the
  /// Vorbis comments.
  ///
  /// Enqueues a [RemoveExactTagValue] mutation.
  void removeExactTagValue(String key, String value) =>
      _mutations.add(RemoveExactTagValue(key, value));

  /// Remove all Vorbis comment entries.
  ///
  /// Enqueues a [ClearTags] mutation. The vendor string is preserved.
  void clearTags() => _mutations.add(const ClearTags());

  /// Append a [PictureBlock] to the metadata.
  ///
  /// Enqueues an [AddPicture] mutation.
  void addPicture(PictureBlock picture) => _mutations.add(AddPicture(picture));

  /// Replace all pictures of [pictureType] with [replacement].
  ///
  /// Enqueues a [ReplacePictureByType] mutation.
  void replacePictureByType(
          PictureType pictureType, PictureBlock replacement) =>
      _mutations.add(ReplacePictureByType(
          pictureType: pictureType, replacement: replacement));

  /// Remove all pictures of [pictureType].
  ///
  /// Enqueues a [RemovePictureByType] mutation.
  void removePictureByType(PictureType pictureType) =>
      _mutations.add(RemovePictureByType(pictureType));

  /// Remove every [PictureBlock] from the metadata.
  ///
  /// Enqueues a [RemoveAllPictures] mutation.
  void removeAllPictures() => _mutations.add(const RemoveAllPictures());

  /// Set the padding to [size] bytes.
  ///
  /// Enqueues a [SetPadding] mutation. Existing padding blocks are
  /// replaced by a single block of the given size (or removed entirely
  /// if [size] is zero).
  void setPadding(int size) => _mutations.add(SetPadding(size));

  /// Apply a single [MetadataMutation] immediately.
  void applyMutation(MetadataMutation mutation) => _mutations.add(mutation);

  /// Apply all enqueued mutations and return a new [FlacMetadataDocument].
  ///
  /// Mutations are applied in the order they were enqueued. The source
  /// document is not modified.
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
      case RemoveFirstTag m:
        return _updateVorbisComments(blocks, (vc) => vc.removeFirst(m.key));
      case ClearTags _:
        return _updateVorbisComments(blocks, (vc) => vc.clear());
      case ClearTagsExcept m:
        return _updateVorbisComments(
            blocks, (vc) => vc.clearExcept(m.keepKeys));
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
        final withoutPadding = blocks.where((b) => b is! PaddingBlock).toList();
        if (m.size > 0) return [...withoutPadding, PaddingBlock(m.size)];
        return withoutPadding;
    }
  }

  List<FlacMetadataBlock> _updateVorbisComments(
    List<FlacMetadataBlock> blocks,
    VorbisComments Function(VorbisComments) update,
  ) {
    final existing = blocks.whereType<VorbisCommentBlock>().firstOrNull;
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
      return blocks.map((b) => b is VorbisCommentBlock ? newBlock : b).toList();
    }
  }
}
