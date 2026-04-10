import 'dart:convert';
import 'dart:typed_data';
import 'flac_block_type.dart';
import 'flac_metadata_block.dart';
import 'picture_type.dart';

/// A FLAC metadata block containing an embedded picture (type 6).
///
/// A FLAC file may contain multiple [PictureBlock] instances, each holding
/// a single image with its associated metadata (MIME type, dimensions,
/// colour depth, and description). Common uses include album cover art
/// and artist photos.
///
/// See also:
/// - [PictureType] for the enumeration of picture categories.
/// - [FlacMetadataDocument.pictures] for convenient access to all pictures.
final class PictureBlock extends FlacMetadataBlock {
  /// Create a [PictureBlock] with the given image data and metadata.
  const PictureBlock({
    required this.pictureType,
    required this.mimeType,
    required this.description,
    required this.width,
    required this.height,
    required this.colorDepth,
    required this.indexedColors,
    required this.data,
  });

  /// The category of this picture (e.g. front cover, artist photo).
  final PictureType pictureType;

  /// The MIME type of the image data (e.g. `image/png`, `image/jpeg`).
  final String mimeType;

  /// A UTF-8 description of the picture, which may be empty.
  final String description;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Colour depth of the image in bits per pixel.
  final int colorDepth;

  /// Number of colours used for indexed-colour images (e.g. GIF), or 0
  /// for non-indexed formats.
  final int indexedColors;

  /// The raw image data bytes.
  final Uint8List data;

  @override
  FlacBlockType get type => FlacBlockType.picture;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    final mimeBytes = utf8.encode(mimeType);
    final descBytes = utf8.encode(description);
    final totalSize = 4 +
        4 +
        mimeBytes.length +
        4 +
        descBytes.length +
        4 +
        4 +
        4 +
        4 +
        4 +
        data.length;
    final out = Uint8List(totalSize);
    final bd = ByteData.sublistView(out);
    var offset = 0;
    bd.setUint32(offset, pictureType.code, Endian.big);
    offset += 4;
    bd.setUint32(offset, mimeBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;
    bd.setUint32(offset, descBytes.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + descBytes.length, descBytes);
    offset += descBytes.length;
    bd.setUint32(offset, width, Endian.big);
    offset += 4;
    bd.setUint32(offset, height, Endian.big);
    offset += 4;
    bd.setUint32(offset, colorDepth, Endian.big);
    offset += 4;
    bd.setUint32(offset, indexedColors, Endian.big);
    offset += 4;
    bd.setUint32(offset, data.length, Endian.big);
    offset += 4;
    out.setRange(offset, offset + data.length, data);
    return out;
  }
}
