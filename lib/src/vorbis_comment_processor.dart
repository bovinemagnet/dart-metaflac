import 'dart:convert';
import 'dart:typed_data';
import 'models.dart';

class VorbisCommentProcessor {
  static VorbisCommentBlock decode(Uint8List data) {
    var offset = 0;

    int readLE32() {
      final v = data[offset] |
          (data[offset + 1] << 8) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 24);
      offset += 4;
      return v;
    }

    final vendorLength = readLE32();
    final vendorString = utf8.decode(data.sublist(offset, offset + vendorLength));
    offset += vendorLength;

    final commentCount = readLE32();
    final comments = <String, List<String>>{};

    for (var i = 0; i < commentCount; i++) {
      final commentLength = readLE32();
      final commentStr = utf8.decode(data.sublist(offset, offset + commentLength));
      offset += commentLength;

      final eqIdx = commentStr.indexOf('=');
      if (eqIdx >= 0) {
        final key = commentStr.substring(0, eqIdx).toUpperCase();
        final value = commentStr.substring(eqIdx + 1);
        comments.putIfAbsent(key, () => []).add(value);
      }
    }

    return VorbisCommentBlock(vendorString: vendorString, comments: comments);
  }

  static Uint8List encode(VorbisCommentBlock block) {
    final vendorBytes = utf8.encode(block.vendorString);

    final commentPairs = <List<int>>[];
    block.comments.forEach((key, values) {
      for (final value in values) {
        commentPairs.add(utf8.encode('$key=$value'));
      }
    });

    var totalSize = 4 + vendorBytes.length + 4;
    for (final cp in commentPairs) {
      totalSize += 4 + cp.length;
    }

    final out = Uint8List(totalSize);
    var offset = 0;

    void writeLE32(int v) {
      out[offset] = v & 0xFF;
      out[offset + 1] = (v >> 8) & 0xFF;
      out[offset + 2] = (v >> 16) & 0xFF;
      out[offset + 3] = (v >> 24) & 0xFF;
      offset += 4;
    }

    writeLE32(vendorBytes.length);
    out.setRange(offset, offset + vendorBytes.length, vendorBytes);
    offset += vendorBytes.length;

    writeLE32(commentPairs.length);
    for (final cp in commentPairs) {
      writeLE32(cp.length);
      out.setRange(offset, offset + cp.length, cp);
      offset += cp.length;
    }

    return out;
  }
}
