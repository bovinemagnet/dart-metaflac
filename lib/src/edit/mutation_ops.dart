import '../model/picture_block.dart';
import '../model/picture_type.dart';

sealed class MetadataMutation {
  const MetadataMutation();
}

final class SetTag extends MetadataMutation {
  const SetTag(this.key, this.values);
  final String key;
  final List<String> values;
}

final class AddTag extends MetadataMutation {
  const AddTag(this.key, this.value);
  final String key;
  final String value;
}

final class RemoveTag extends MetadataMutation {
  const RemoveTag(this.key);
  final String key;
}

final class RemoveExactTagValue extends MetadataMutation {
  const RemoveExactTagValue(this.key, this.value);
  final String key;
  final String value;
}

final class ClearTags extends MetadataMutation {
  const ClearTags();
}

final class AddPicture extends MetadataMutation {
  const AddPicture(this.picture);
  final PictureBlock picture;
}

final class ReplacePictureByType extends MetadataMutation {
  const ReplacePictureByType({
    required this.pictureType,
    required this.replacement,
  });
  final PictureType pictureType;
  final PictureBlock replacement;
}

final class RemovePictureByType extends MetadataMutation {
  const RemovePictureByType(this.pictureType);
  final PictureType pictureType;
}

final class RemoveAllPictures extends MetadataMutation {
  const RemoveAllPictures();
}

final class SetPadding extends MetadataMutation {
  const SetPadding(this.size);
  final int size;
}
