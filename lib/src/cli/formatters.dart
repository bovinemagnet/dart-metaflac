import 'dart:io';

import 'package:dart_metaflac/dart_metaflac.dart';

/// Formats metadata as human-readable text and writes to stdout.
void printMetadata(FlacMetadataDocument doc, String prefix) {
  final si = doc.streamInfo;
  stdout.writeln('${prefix}STREAMINFO:');
  stdout.writeln('$prefix  min_blocksize: ${si.minBlockSize}');
  stdout.writeln('$prefix  max_blocksize: ${si.maxBlockSize}');
  stdout.writeln('$prefix  min_framesize: ${si.minFrameSize}');
  stdout.writeln('$prefix  max_framesize: ${si.maxFrameSize}');
  stdout.writeln('$prefix  sample_rate: ${si.sampleRate}');
  stdout.writeln('$prefix  channels: ${si.channelCount}');
  stdout.writeln('$prefix  bits_per_sample: ${si.bitsPerSample}');
  stdout.writeln('$prefix  total_samples: ${si.totalSamples}');
  final md5Hex =
      si.md5Signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  stdout.writeln('$prefix  md5sum: $md5Hex');

  final vc = doc.vorbisComment;
  if (vc != null) {
    stdout.writeln('${prefix}VORBIS_COMMENT:');
    stdout.writeln('$prefix  vendor_string: ${vc.comments.vendorString}');
    for (final entry in vc.comments.entries) {
      stdout.writeln('$prefix  ${entry.key}=${entry.value}');
    }
  }

  final pictures = doc.pictures;
  for (var i = 0; i < pictures.length; i++) {
    final pic = pictures[i];
    stdout.writeln('${prefix}PICTURE[$i]:');
    stdout.writeln('$prefix  type: ${pic.pictureType.code}');
    stdout.writeln('$prefix  mime_type: ${pic.mimeType}');
    stdout.writeln('$prefix  description: ${pic.description}');
    stdout.writeln('$prefix  width: ${pic.width}');
    stdout.writeln('$prefix  height: ${pic.height}');
    stdout.writeln('$prefix  color_depth: ${pic.colorDepth}');
    stdout.writeln('$prefix  data_length: ${pic.data.length}');
  }
}

/// Converts metadata to a JSON-serialisable map.
Map<String, dynamic> metadataToJson(FlacMetadataDocument doc, String filePath) {
  final si = doc.streamInfo;
  final md5Hex =
      si.md5Signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  final result = <String, dynamic>{
    'file': filePath,
    'streamInfo': {
      'minBlockSize': si.minBlockSize,
      'maxBlockSize': si.maxBlockSize,
      'minFrameSize': si.minFrameSize,
      'maxFrameSize': si.maxFrameSize,
      'sampleRate': si.sampleRate,
      'channelCount': si.channelCount,
      'bitsPerSample': si.bitsPerSample,
      'totalSamples': si.totalSamples,
      'md5Signature': md5Hex,
    },
  };

  final vc = doc.vorbisComment;
  if (vc != null) {
    final tags = <String, dynamic>{};
    for (final entry in vc.comments.entries) {
      final key = entry.key;
      if (tags.containsKey(key)) {
        final existing = tags[key];
        if (existing is List) {
          existing.add(entry.value);
        } else {
          tags[key] = [existing, entry.value];
        }
      } else {
        tags[key] = entry.value;
      }
    }
    result['vorbisComment'] = {
      'vendorString': vc.comments.vendorString,
      'tags': tags,
    };
  }

  final pictures = doc.pictures;
  if (pictures.isNotEmpty) {
    result['pictures'] = pictures
        .map((pic) => {
              'pictureType': pic.pictureType.code,
              'mimeType': pic.mimeType,
              'description': pic.description,
              'width': pic.width,
              'height': pic.height,
              'colorDepth': pic.colorDepth,
              'indexedColors': pic.indexedColors,
              'dataLength': pic.data.length,
            })
        .toList();
  }

  return result;
}

/// Maps a file extension to a MIME type for picture imports.
String mimeTypeFromExtension(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'webp':
      return 'image/webp';
    default:
      return 'application/octet-stream';
  }
}
