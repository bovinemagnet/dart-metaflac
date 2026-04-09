enum FlacBlockType {
  streamInfo,
  padding,
  application,
  seekTable,
  vorbisComment,
  cueSheet,
  picture,
  unknown;

  static FlacBlockType fromCode(int code) {
    switch (code) {
      case 0:
        return FlacBlockType.streamInfo;
      case 1:
        return FlacBlockType.padding;
      case 2:
        return FlacBlockType.application;
      case 3:
        return FlacBlockType.seekTable;
      case 4:
        return FlacBlockType.vorbisComment;
      case 5:
        return FlacBlockType.cueSheet;
      case 6:
        return FlacBlockType.picture;
      default:
        return FlacBlockType.unknown;
    }
  }

  int get code {
    switch (this) {
      case FlacBlockType.streamInfo:
        return 0;
      case FlacBlockType.padding:
        return 1;
      case FlacBlockType.application:
        return 2;
      case FlacBlockType.seekTable:
        return 3;
      case FlacBlockType.vorbisComment:
        return 4;
      case FlacBlockType.cueSheet:
        return 5;
      case FlacBlockType.picture:
        return 6;
      case FlacBlockType.unknown:
        return 127;
    }
  }
}
