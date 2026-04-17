import 'dart:typed_data';

import '../model/flac_block_type.dart';
import '../model/picture_block.dart';
import '../model/picture_type.dart';

/// Base type for all metadata mutation operations.
///
/// Each concrete subclass represents a single, atomic change that can be
/// applied to a [FlacMetadataDocument] via [FlacMetadataEditor]. Mutations
/// are accumulated and then executed in order when [FlacMetadataEditor.build]
/// is called.
///
/// This is a sealed class hierarchy, so exhaustive pattern matching is
/// available in `switch` expressions.
sealed class MetadataMutation {
  /// Create a metadata mutation.
  const MetadataMutation();
}

/// Replace all values for a Vorbis comment tag with a new list of values.
///
/// If the tag does not yet exist, it is created. Any previous values
/// associated with [key] are discarded.
///
/// See also: [AddTag], which appends a single value without removing
/// existing ones.
final class SetTag extends MetadataMutation {
  /// Create a mutation that sets [key] to the given [values].
  const SetTag(this.key, this.values);

  /// The case-insensitive Vorbis comment field name.
  final String key;

  /// The replacement list of values for [key].
  final List<String> values;
}

/// Append a single value to a Vorbis comment tag.
///
/// If the tag does not yet exist, it is created with a single entry.
/// Existing values for [key] are preserved.
///
/// See also: [SetTag], which replaces all values for a key.
final class AddTag extends MetadataMutation {
  /// Create a mutation that appends [value] to [key].
  const AddTag(this.key, this.value);

  /// The case-insensitive Vorbis comment field name.
  final String key;

  /// The value to append.
  final String value;
}

/// Remove all values for a Vorbis comment tag.
///
/// Every entry whose field name matches [key] (case-insensitively) is
/// removed. If the tag does not exist, this is a no-op.
///
/// See also: [RemoveExactTagValue], which removes only a specific
/// key/value pair.
final class RemoveTag extends MetadataMutation {
  /// Create a mutation that removes all entries for [key].
  const RemoveTag(this.key);

  /// The case-insensitive Vorbis comment field name to remove.
  final String key;
}

/// Remove a single, exact key/value pair from the Vorbis comments.
///
/// Only entries matching both [key] (case-insensitively) and [value]
/// (exactly) are removed. Other entries with the same key but different
/// values are preserved.
///
/// See also: [RemoveTag], which removes all values for a key.
final class RemoveExactTagValue extends MetadataMutation {
  /// Create a mutation that removes entries matching [key] and [value].
  const RemoveExactTagValue(this.key, this.value);

  /// The case-insensitive Vorbis comment field name.
  final String key;

  /// The exact value to match for removal.
  final String value;
}

/// Remove only the **first** Vorbis comment entry matching a key.
///
/// Subsequent entries with the same key are preserved. If no entry
/// matches, the mutation is a no-op. This mirrors the reference
/// `metaflac --remove-first-tag=FIELD` operation.
///
/// See also: [RemoveTag], which removes every matching entry.
final class RemoveFirstTag extends MetadataMutation {
  /// Create a mutation that removes the first entry for [key].
  const RemoveFirstTag(this.key);

  /// The case-insensitive Vorbis comment field name.
  final String key;
}

/// Remove all Vorbis comment entries.
///
/// After this mutation is applied, the Vorbis comment block will contain
/// no user tags (the vendor string is preserved).
final class ClearTags extends MetadataMutation {
  /// Create a mutation that clears all Vorbis comment entries.
  const ClearTags();
}

/// Remove every Vorbis comment entry except those whose key is in
/// [keepKeys].
///
/// Key matching is case-insensitive. The vendor string is always
/// preserved. This mirrors the reference
/// `metaflac --remove-all-tags-except=NAME1=NAME2=…` operation.
///
/// See also: [ClearTags], which removes every entry unconditionally.
final class ClearTagsExcept extends MetadataMutation {
  /// Create a mutation that retains only the entries whose key is in
  /// [keepKeys].
  const ClearTagsExcept(this.keepKeys);

  /// The set of case-insensitive field names to retain.
  final Set<String> keepKeys;
}

/// Append a [PictureBlock] to the metadata.
///
/// The picture is added after all existing metadata blocks. No existing
/// pictures are removed.
///
/// See also: [ReplacePictureByType], [RemovePictureByType],
/// [RemoveAllPictures].
final class AddPicture extends MetadataMutation {
  /// Create a mutation that appends [picture] to the metadata blocks.
  const AddPicture(this.picture);

  /// The picture block to add.
  final PictureBlock picture;
}

/// Replace all pictures of a given [PictureType] with a single replacement.
///
/// Every existing [PictureBlock] whose [PictureBlock.pictureType] matches
/// [pictureType] is replaced in-place by [replacement].
///
/// See also: [AddPicture], [RemovePictureByType].
final class ReplacePictureByType extends MetadataMutation {
  /// Create a mutation that replaces pictures of [pictureType] with
  /// [replacement].
  const ReplacePictureByType({
    required this.pictureType,
    required this.replacement,
  });

  /// The type of picture to match for replacement.
  final PictureType pictureType;

  /// The picture block that replaces each matched picture.
  final PictureBlock replacement;
}

/// Remove all pictures of a given [PictureType].
///
/// Every existing [PictureBlock] whose [PictureBlock.pictureType] matches
/// [pictureType] is removed from the metadata.
///
/// See also: [RemoveAllPictures], [ReplacePictureByType].
final class RemovePictureByType extends MetadataMutation {
  /// Create a mutation that removes pictures of [pictureType].
  const RemovePictureByType(this.pictureType);

  /// The type of picture to remove.
  final PictureType pictureType;
}

/// Remove every [PictureBlock] from the metadata.
///
/// See also: [RemovePictureByType], which targets a specific
/// [PictureType].
final class RemoveAllPictures extends MetadataMutation {
  /// Create a mutation that removes all picture blocks.
  const RemoveAllPictures();
}

/// Set the padding block to an explicit size in bytes.
///
/// Any existing padding blocks are first removed, then a single
/// [PaddingBlock] of [size] bytes is appended (if [size] is greater
/// than zero).
final class SetPadding extends MetadataMutation {
  /// Create a mutation that sets the padding to [size] bytes.
  const SetPadding(this.size);

  /// The desired padding size in bytes. A value of zero removes all
  /// padding.
  final int size;
}

/// Remove every metadata block whose [FlacBlockType] is in [types].
///
/// STREAMINFO (type 0) is mandatory per the FLAC specification. Including
/// [FlacBlockType.streamInfo] in [types] is a programmer error: the editor
/// throws [FlacMetadataException] at build time.
///
/// Unknown types (type code outside 0–6) may be targeted by including
/// [FlacBlockType.unknown], which removes all blocks that the parser could
/// not classify.
final class RemoveBlocksByType extends MetadataMutation {
  /// Create a mutation that removes blocks whose type is in [types].
  const RemoveBlocksByType(this.types);

  /// The set of block types to remove.
  final Set<FlacBlockType> types;
}
