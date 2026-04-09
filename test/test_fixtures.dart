/// Shared test fixtures for building in-memory FLAC files.
library;

import 'dart:typed_data';
import 'package:dart_metaflac/dart_metaflac.dart';

// ─── FLAC Fixture Builder ─────────────────────────────────────────────────────

/// Builds an in-memory FLAC file with optional blocks.
///
/// [paddingSize] < 0 means no padding block.
Uint8List buildFlac({
  int sampleRate = 44100,
  int channels = 2,
  int bitsPerSample = 16,
  int totalSamples = 88200,
  int paddingSize = 1024,
  VorbisCommentBlock? vorbisComment,
  List<PictureBlock> pictures = const [],
}) {
  final siData = Uint8List(34);
  final sr = sampleRate;
  final ch = channels - 1;
  final bps = bitsPerSample - 1;
  final ts = totalSamples;
  siData[0] = 0;
  siData[1] = 16;
  siData[2] = 1;
  siData[3] = 0;
  siData[10] = (sr >> 12) & 0xFF;
  siData[11] = (sr >> 4) & 0xFF;
  siData[12] =
      ((sr & 0xF) << 4) | ((ch & 0x7) << 1) | ((bps >> 4) & 0x1);
  siData[13] = ((bps & 0xF) << 4) | ((ts >> 32) & 0xF);
  siData[14] = (ts >> 24) & 0xFF;
  siData[15] = (ts >> 16) & 0xFF;
  siData[16] = (ts >> 8) & 0xFF;
  siData[17] = ts & 0xFF;

  Uint8List? vcData;
  if (vorbisComment != null) {
    vcData = vorbisComment.toPayloadBytes();
  }
  final picDataList = pictures.map((p) => p.toPayloadBytes()).toList();

  final hasVC = vcData != null;
  final hasPics = picDataList.isNotEmpty;
  final hasPadding = paddingSize >= 0;

  final out = BytesBuilder();
  out.addByte(0x66);
  out.addByte(0x4C);
  out.addByte(0x61);
  out.addByte(0x43);

  final siIsLast = !hasVC && !hasPics && !hasPadding;
  out.addByte(siIsLast ? 0x80 : 0x00);
  out.addByte(0);
  out.addByte(0);
  out.addByte(34);
  out.add(siData);

  if (hasVC) {
    final vcIsLast = !hasPics && !hasPadding;
    out.addByte((vcIsLast ? 0x80 : 0x00) | 0x04);
    out.addByte((vcData.length >> 16) & 0xFF);
    out.addByte((vcData.length >> 8) & 0xFF);
    out.addByte(vcData.length & 0xFF);
    out.add(vcData);
  }

  for (var i = 0; i < picDataList.length; i++) {
    final pd = picDataList[i];
    final picIsLast = (i == picDataList.length - 1) && !hasPadding;
    out.addByte((picIsLast ? 0x80 : 0x00) | 0x06);
    out.addByte((pd.length >> 16) & 0xFF);
    out.addByte((pd.length >> 8) & 0xFF);
    out.addByte(pd.length & 0xFF);
    out.add(pd);
  }

  if (hasPadding) {
    out.addByte(0x80 | 0x01);
    out.addByte((paddingSize >> 16) & 0xFF);
    out.addByte((paddingSize >> 8) & 0xFF);
    out.addByte(paddingSize & 0xFF);
    out.add(Uint8List(paddingSize));
  }

  // Fake audio sync bytes + payload
  out.addByte(0xFF);
  out.addByte(0xF8);
  out.add(Uint8List(200));

  return out.toBytes();
}

// ─── Picture Fixture ────────────────────────────────────────────────────────

PictureBlock makeJpeg({
  PictureType type = PictureType.frontCover,
  String description = '',
  int width = 500,
  int height = 500,
}) =>
    PictureBlock(
      pictureType: type,
      mimeType: 'image/jpeg',
      description: description,
      width: width,
      height: height,
      colorDepth: 24,
      indexedColors: 0,
      data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
    );

// ─── Stream Helpers ─────────────────────────────────────────────────────────

/// Collects a [Stream<List<int>>] into a single [Uint8List].
Future<Uint8List> collectStream(Stream<List<int>> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}
