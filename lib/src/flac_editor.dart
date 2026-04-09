import 'dart:async';
import 'dart:typed_data';
import 'models.dart';
import 'flac_parser.dart';
import 'vorbis_comment_processor.dart';
import 'picture_block_processor.dart';

class FlacEditor {
  final Stream<List<int>> source;

  FlacEditor(this.source);

  Future<FlacMetadata> readMetadata() async {
    return FlacParser.parse(source);
  }

  Stream<List<int>> updateMetadata({
    Map<String, List<String>>? vorbisComments,
    String? vendorString,
    List<PictureBlock>? pictures,
  }) async* {
    final bytes = await FlacParser.collectBytes(source);
    final result = _buildUpdatedFlac(
      bytes,
      vorbisComments: vorbisComments,
      vendorString: vendorString,
      pictures: pictures,
    );
    yield result;
  }

  static Uint8List _buildUpdatedFlac(
    Uint8List original, {
    Map<String, List<String>>? vorbisComments,
    String? vendorString,
    List<PictureBlock>? pictures,
  }) {
    final metadata = FlacParser.parseBytes(original);

    Uint8List? newVorbisData;
    if (vorbisComments != null || vendorString != null) {
      final existing = metadata.vorbisComment;
      final newBlock = VorbisCommentBlock(
        vendorString: vendorString ?? existing?.vendorString ?? 'dart_metaflac',
        comments: vorbisComments ?? existing?.comments ?? {},
      );
      newVorbisData = VorbisCommentProcessor.encode(newBlock);
    }

    List<Uint8List>? newPictureDataList;
    if (pictures != null) {
      newPictureDataList = pictures.map(PictureBlockProcessor.encode).toList();
    }

    final audioStart = _findAudioStart(original, metadata);

    var existingPaddingTotal = 0;
    for (final block in metadata.allBlocks) {
      if (block.header.type == MetadataBlockType.padding) {
        existingPaddingTotal += 4 + block.header.length;
      }
    }

    var oldVorbisSize = 0;
    var oldPictureSize = 0;
    for (final block in metadata.allBlocks) {
      if (block.header.type == MetadataBlockType.vorbisComment) {
        oldVorbisSize = 4 + block.header.length;
      } else if (block.header.type == MetadataBlockType.picture) {
        oldPictureSize += 4 + block.header.length;
      }
    }

    final newVorbisSize = newVorbisData != null ? 4 + newVorbisData.length : oldVorbisSize;
    final newPictureSize = newPictureDataList != null
        ? newPictureDataList.fold<int>(0, (s, d) => s + 4 + d.length)
        : oldPictureSize;

    final sizeDelta = (newVorbisSize - oldVorbisSize) + (newPictureSize - oldPictureSize);
    final availablePadding = existingPaddingTotal;
    final remainingPadding = availablePadding - sizeDelta;

    final newBlocks = <_BlockEntry>[];

    for (final block in metadata.allBlocks) {
      final t = block.header.type;
      if (t == MetadataBlockType.vorbisComment && newVorbisData != null) continue;
      if (t == MetadataBlockType.picture && newPictureDataList != null) continue;
      if (t == MetadataBlockType.padding) continue;
      newBlocks.add(_BlockEntry(t, block.data));
    }

    if (newVorbisData != null) {
      newBlocks.add(_BlockEntry(MetadataBlockType.vorbisComment, newVorbisData));
    } else {
      for (final block in metadata.allBlocks) {
        if (block.header.type == MetadataBlockType.vorbisComment) {
          newBlocks.add(_BlockEntry(MetadataBlockType.vorbisComment, block.data));
        }
      }
    }

    if (newPictureDataList != null) {
      for (final pd in newPictureDataList) {
        newBlocks.add(_BlockEntry(MetadataBlockType.picture, pd));
      }
    } else {
      for (final block in metadata.allBlocks) {
        if (block.header.type == MetadataBlockType.picture) {
          newBlocks.add(_BlockEntry(MetadataBlockType.picture, block.data));
        }
      }
    }

    Uint8List? paddingData;
    if (remainingPadding >= 4) {
      final paddingContentSize = remainingPadding - 4;
      paddingData = Uint8List(paddingContentSize);
    } else if (remainingPadding > 0 && remainingPadding < 4) {
      paddingData = Uint8List(0);
    }

    var metaSize = 4;
    for (final b in newBlocks) {
      metaSize += 4 + b.data.length;
    }
    if (paddingData != null) {
      metaSize += 4 + paddingData.length;
    }

    final audioData = original.sublist(audioStart);
    final out = Uint8List(metaSize + audioData.length);
    var offset = 0;

    out[0] = 0x66; out[1] = 0x4C; out[2] = 0x61; out[3] = 0x43;
    offset = 4;

    for (var i = 0; i < newBlocks.length; i++) {
      final b = newBlocks[i];
      final isLast = (i == newBlocks.length - 1) && paddingData == null;
      _writeBlockHeader(out, offset, b.type, isLast, b.data.length);
      offset += 4;
      out.setRange(offset, offset + b.data.length, b.data);
      offset += b.data.length;
    }

    if (paddingData != null) {
      _writeBlockHeader(out, offset, MetadataBlockType.padding, true, paddingData.length);
      offset += 4;
      out.setRange(offset, offset + paddingData.length, paddingData);
      offset += paddingData.length;
    }

    out.setRange(offset, offset + audioData.length, audioData);

    return out;
  }

  static void _writeBlockHeader(
    Uint8List out,
    int offset,
    MetadataBlockType type,
    bool isLast,
    int length,
  ) {
    final typeByte = type.toInt() & 0x7F;
    out[offset] = isLast ? (0x80 | typeByte) : typeByte;
    out[offset + 1] = (length >> 16) & 0xFF;
    out[offset + 2] = (length >> 8) & 0xFF;
    out[offset + 3] = length & 0xFF;
  }

  static int _findAudioStart(Uint8List bytes, FlacMetadata metadata) {
    var offset = 4;
    for (final block in metadata.allBlocks) {
      offset += 4 + block.header.length;
    }
    return offset;
  }
}

class _BlockEntry {
  final MetadataBlockType type;
  final Uint8List data;
  _BlockEntry(this.type, this.data);
}
