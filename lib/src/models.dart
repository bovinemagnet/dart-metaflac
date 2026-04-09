import 'dart:typed_data';

enum MetadataBlockType {
  streamInfo,
  padding,
  application,
  seekTable,
  vorbisComment,
  cueSheet,
  picture,
  unknown;

  static MetadataBlockType fromInt(int value) {
    switch (value) {
      case 0: return MetadataBlockType.streamInfo;
      case 1: return MetadataBlockType.padding;
      case 2: return MetadataBlockType.application;
      case 3: return MetadataBlockType.seekTable;
      case 4: return MetadataBlockType.vorbisComment;
      case 5: return MetadataBlockType.cueSheet;
      case 6: return MetadataBlockType.picture;
      default: return MetadataBlockType.unknown;
    }
  }

  int toInt() {
    switch (this) {
      case MetadataBlockType.streamInfo: return 0;
      case MetadataBlockType.padding: return 1;
      case MetadataBlockType.application: return 2;
      case MetadataBlockType.seekTable: return 3;
      case MetadataBlockType.vorbisComment: return 4;
      case MetadataBlockType.cueSheet: return 5;
      case MetadataBlockType.picture: return 6;
      case MetadataBlockType.unknown: return 127;
    }
  }
}

class MetadataBlockHeader {
  final MetadataBlockType type;
  final bool isLast;
  final int length;

  const MetadataBlockHeader({
    required this.type,
    required this.isLast,
    required this.length,
  });
}

class RawMetadataBlock {
  final MetadataBlockHeader header;
  final Uint8List data;

  const RawMetadataBlock({required this.header, required this.data});
}

class StreamInfoBlock {
  final int minBlockSize;
  final int maxBlockSize;
  final int minFrameSize;
  final int maxFrameSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int totalSamples;
  final Uint8List md5Signature;

  const StreamInfoBlock({
    required this.minBlockSize,
    required this.maxBlockSize,
    required this.minFrameSize,
    required this.maxFrameSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.md5Signature,
  });
}

class VorbisCommentBlock {
  final String vendorString;
  final Map<String, List<String>> comments;

  const VorbisCommentBlock({
    required this.vendorString,
    required this.comments,
  });
}

class PictureBlock {
  final int pictureType;
  final String mimeType;
  final String description;
  final int width;
  final int height;
  final int colorDepth;
  final int indexedColorCount;
  final Uint8List data;

  const PictureBlock({
    required this.pictureType,
    required this.mimeType,
    required this.description,
    required this.width,
    required this.height,
    required this.colorDepth,
    required this.indexedColorCount,
    required this.data,
  });
}

class FlacMetadata {
  final StreamInfoBlock streamInfo;
  final VorbisCommentBlock? vorbisComment;
  final List<PictureBlock> pictures;
  final List<RawMetadataBlock> allBlocks;

  const FlacMetadata({
    required this.streamInfo,
    this.vorbisComment,
    required this.pictures,
    required this.allBlocks,
  });
}
