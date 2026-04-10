# overview #

Below is a repo-ready skeleton and API draft for the three-package layout. I’m keeping the core package `dart:io`-free and byte/stream-oriented, because your uploaded PRD explicitly calls for a pure Dart, I/O-agnostic core built around `Stream`, `Sink`, and `Uint8List`, with the CLI as a separate platform-specific frontend.  

I’m also baking in first-class support for:

* Vorbis comments
* picture blocks
* padding-aware updates
* safe full rewrites when padding is insufficient
* `metaflac`-style CLI parity for the key workflows in your PRD. 

---

# 1. Recommended repo layout

```text
dart-metaflac/
  melos.yaml
  analysis_options.yaml
  README.md
  docs/
    architecture.md
    api-examples.md
    cli-compatibility.md
  fixtures/
    README.md
    minimal.flac
    with_tags.flac
    with_picture.flac
    with_padding.flac
    malformed/
      bad_magic.flac
      truncated_block.flac

  packages/
    dart_metaflac/
      pubspec.yaml
      README.md
      lib/
        dart_metaflac.dart
        src/
          api/
            document_api.dart
            read_api.dart
            transform_api.dart
          binary/
            byte_reader.dart
            byte_writer.dart
            flac_block_header.dart
            flac_constants.dart
            flac_parser.dart
            flac_serializer.dart
          edit/
            flac_metadata_editor.dart
            mutation_ops.dart
            normalization.dart
            padding_strategy.dart
          error/
            exceptions.dart
          model/
            flac_block_type.dart
            flac_metadata_block.dart
            flac_metadata_document.dart
            stream_info_block.dart
            vorbis_comment_block.dart
            vorbis_comments.dart
            picture_block.dart
            padding_block.dart
            application_block.dart
            seek_table_block.dart
            cue_sheet_block.dart
            unknown_block.dart
            picture_type.dart
          transform/
            flac_transform_options.dart
            flac_transform_plan.dart
            flac_transform_result.dart
            flac_transformer.dart
            stream_rewriter.dart
          util/
            validators.dart
            utf8_utils.dart
      test/
        parser/
        model/
        transform/
      example/
        in_memory_update.dart
        stream_transform.dart

    dart_metaflac_io/
      pubspec.yaml
      README.md
      lib/
        dart_metaflac_io.dart
        src/
          file_api.dart
          flac_file_editor.dart
          atomic_writer.dart
          temp_file_manager.dart
          write_mode.dart
      test/
        file_update_test.dart
        atomic_writer_test.dart
      example/
        update_file.dart

    dart_metaflac_cli/
      pubspec.yaml
      README.md
      bin/
        dart_metaflac.dart
      lib/
        src/
          cli_runner.dart
          command_context.dart
          compat/
            metaflac_alias_parser.dart
          commands/
            inspect_command.dart
            blocks_command.dart
            tags_command.dart
            picture_command.dart
            padding_command.dart
          output/
            human_output.dart
            json_output.dart
            exit_codes.dart
      test/
        cli_smoke_test.dart
        compat_alias_test.dart
```

---

# 2. Workspace files

## `melos.yaml`

```yaml
name: dart-metaflac

packages:
  - packages/**
```

## root `analysis_options.yaml`

```yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - always_declare_return_types
    - avoid_dynamic_calls
    - cancel_subscriptions
    - directives_ordering
    - prefer_final_fields
    - prefer_final_locals
    - sort_pub_dependencies
    - unawaited_futures
```

---

# 3. Package pubspec drafts

## `packages/dart_metaflac/pubspec.yaml`

```yaml
name: dart_metaflac
description: Pure Dart FLAC metadata transformation library.
version: 0.0.1-dev.1
environment:
  sdk: ^3.5.0

dependencies:
  meta: ^1.12.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

## `packages/dart_metaflac_io/pubspec.yaml`

```yaml
name: dart_metaflac_io
description: File-system adapters and safe persistence helpers for dart_metaflac.
version: 0.0.1-dev.1
environment:
  sdk: ^3.5.0

dependencies:
  dart_metaflac:
    path: ../dart_metaflac

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

## `packages/dart_metaflac_cli/pubspec.yaml`

```yaml
name: dart_metaflac_cli
description: CLI for dart_metaflac with metaflac-compatible aliases.
version: 0.0.1-dev.1
environment:
  sdk: ^3.5.0

executables:
  dart-metaflac: dart_metaflac

dependencies:
  args: ^2.5.0
  dart_metaflac:
    path: ../dart_metaflac
  dart_metaflac_io:
    path: ../dart_metaflac_io

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
```

---

# 4. Public export surfaces

This is the part that matters most long term.

## `packages/dart_metaflac/lib/dart_metaflac.dart`

```dart
library dart_metaflac;

export 'src/error/exceptions.dart';

export 'src/model/flac_block_type.dart';
export 'src/model/flac_metadata_block.dart';
export 'src/model/flac_metadata_document.dart';
export 'src/model/stream_info_block.dart';
export 'src/model/vorbis_comment_block.dart';
export 'src/model/vorbis_comments.dart';
export 'src/model/vorbis_comment_block.dart';
export 'src/model/picture_block.dart';
export 'src/model/padding_block.dart';
export 'src/model/application_block.dart';
export 'src/model/seek_table_block.dart';
export 'src/model/cue_sheet_block.dart';
export 'src/model/unknown_block.dart';
export 'src/model/picture_type.dart';

export 'src/edit/mutation_ops.dart';
export 'src/edit/flac_metadata_editor.dart';

export 'src/transform/flac_transform_options.dart';
export 'src/transform/flac_transform_plan.dart';
export 'src/transform/flac_transform_result.dart';
export 'src/transform/flac_transformer.dart';

export 'src/binary/flac_parser.dart';
export 'src/binary/flac_serializer.dart';

export 'src/api/document_api.dart';
export 'src/api/read_api.dart';
export 'src/api/transform_api.dart';
```

## `packages/dart_metaflac_io/lib/dart_metaflac_io.dart`

```dart
library dart_metaflac_io;

export 'package:dart_metaflac/dart_metaflac.dart';

export 'src/write_mode.dart';
export 'src/file_api.dart';
export 'src/flac_file_editor.dart';
export 'src/atomic_writer.dart';
```

I would re-export the core package here. It makes the file adapter package pleasant to use.

---

# 5. Core package starter interfaces

## `lib/src/error/exceptions.dart`

```dart
class FlacMetadataException implements Exception {
  FlacMetadataException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

class InvalidFlacException extends FlacMetadataException {
  InvalidFlacException(super.message, {super.cause});
}

class MalformedMetadataException extends FlacMetadataException {
  MalformedMetadataException(super.message, {super.cause});
}

class UnsupportedBlockException extends FlacMetadataException {
  UnsupportedBlockException(super.message, {super.cause});
}

class FlacInsufficientPaddingException extends FlacMetadataException {
  FlacInsufficientPaddingException(super.message, {super.cause});
}

class WriteConflictException extends FlacMetadataException {
  WriteConflictException(super.message, {super.cause});
}

class FlacIoException extends FlacMetadataException {
  FlacIoException(super.message, {super.cause});
}
```

---

## `lib/src/model/flac_block_type.dart`

```dart
enum FlacBlockType {
  streamInfo,
  padding,
  application,
  seekTable,
  vorbisComment,
  cueSheet,
  picture,
  unknown,
}
```

---

## `lib/src/model/picture_type.dart`

```dart
enum PictureType {
  other(0),
  fileIcon32x32(1),
  otherFileIcon(2),
  frontCover(3),
  backCover(4),
  leafletPage(5),
  media(6),
  leadArtist(7),
  artist(8),
  conductor(9),
  band(10),
  composer(11),
  lyricist(12),
  recordingLocation(13),
  duringRecording(14),
  duringPerformance(15),
  movieScreenCapture(16),
  brightColoredFish(17),
  illustration(18),
  bandLogo(19),
  publisherLogo(20);

  const PictureType(this.code);
  final int code;
}
```

---

## `lib/src/model/flac_metadata_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';

abstract class FlacMetadataBlock {
  const FlacMetadataBlock();

  FlacBlockType get type;

  /// Serialized payload length, excluding the 4-byte FLAC metadata block header.
  int get payloadLength;

  /// Serialize only the block payload.
  Uint8List toPayloadBytes();
}
```

---

## `lib/src/model/stream_info_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class StreamInfoBlock extends FlacMetadataBlock {
  const StreamInfoBlock({
    required this.minBlockSize,
    required this.maxBlockSize,
    required this.minFrameSize,
    required this.maxFrameSize,
    required this.sampleRate,
    required this.channelCount,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.md5Signature,
  });

  final int minBlockSize;
  final int maxBlockSize;
  final int minFrameSize;
  final int maxFrameSize;
  final int sampleRate;
  final int channelCount;
  final int bitsPerSample;
  final int totalSamples;
  final Uint8List md5Signature;

  @override
  FlacBlockType get type => FlacBlockType.streamInfo;

  @override
  int get payloadLength => 34;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('STREAMINFO serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/vorbis_comments.dart`

```dart
final class VorbisCommentEntry {
  const VorbisCommentEntry({
    required this.key,
    required this.value,
  });

  final String key;
  final String value;

  String get canonicalKey => key.toUpperCase();
}

final class VorbisComments {
  const VorbisComments({
    required this.vendorString,
    required this.entries,
  });

  final String vendorString;
  final List<VorbisCommentEntry> entries;

  List<String> valuesOf(String key) {
    final canonical = key.toUpperCase();
    return entries
        .where((entry) => entry.canonicalKey == canonical)
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  Map<String, List<String>> asMultiMap() {
    final map = <String, List<String>>{};
    for (final entry in entries) {
      map.putIfAbsent(entry.canonicalKey, () => <String>[]).add(entry.value);
    }
    return map;
  }

  VorbisComments set(String key, List<String> values) {
    final canonical = key.toUpperCase();
    final retained =
        entries.where((entry) => entry.canonicalKey != canonical).toList();
    retained.addAll(values.map((v) => VorbisCommentEntry(key: key, value: v)));
    return VorbisComments(vendorString: vendorString, entries: retained);
  }

  VorbisComments add(String key, String value) {
    return VorbisComments(
      vendorString: vendorString,
      entries: [...entries, VorbisCommentEntry(key: key, value: value)],
    );
  }

  VorbisComments removeKey(String key) {
    final canonical = key.toUpperCase();
    return VorbisComments(
      vendorString: vendorString,
      entries:
          entries.where((entry) => entry.canonicalKey != canonical).toList(),
    );
  }

  VorbisComments removeExact(String key, String value) {
    final canonical = key.toUpperCase();
    return VorbisComments(
      vendorString: vendorString,
      entries: entries
          .where((entry) =>
              !(entry.canonicalKey == canonical && entry.value == value))
          .toList(),
    );
  }

  VorbisComments clear() {
    return VorbisComments(vendorString: vendorString, entries: const []);
  }
}
```

---

## `lib/src/model/vorbis_comment_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';
import 'vorbis_comments.dart';

final class VorbisCommentBlock extends FlacMetadataBlock {
  const VorbisCommentBlock({
    required this.comments,
  });

  final VorbisComments comments;

  @override
  FlacBlockType get type => FlacBlockType.vorbisComment;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('Vorbis comment serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/picture_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';
import 'picture_type.dart';

final class PictureBlock extends FlacMetadataBlock {
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

  final PictureType pictureType;
  final String mimeType;
  final String description;
  final int width;
  final int height;
  final int colorDepth;
  final int indexedColors;
  final Uint8List data;

  @override
  FlacBlockType get type => FlacBlockType.picture;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('Picture serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/padding_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class PaddingBlock extends FlacMetadataBlock {
  const PaddingBlock(this.size);

  final int size;

  @override
  FlacBlockType get type => FlacBlockType.padding;

  @override
  int get payloadLength => size;

  @override
  Uint8List toPayloadBytes() => Uint8List(size);
}
```

---

## `lib/src/model/application_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class ApplicationBlock extends FlacMetadataBlock {
  const ApplicationBlock({
    required this.applicationId,
    required this.data,
  });

  final Uint8List applicationId; // 4 bytes
  final Uint8List data;

  @override
  FlacBlockType get type => FlacBlockType.application;

  @override
  int get payloadLength => 4 + data.length;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('Application block serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/seek_table_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class SeekPoint {
  const SeekPoint({
    required this.sampleNumber,
    required this.offset,
    required this.frameSamples,
  });

  final int sampleNumber;
  final int offset;
  final int frameSamples;
}

final class SeekTableBlock extends FlacMetadataBlock {
  const SeekTableBlock({
    required this.points,
  });

  final List<SeekPoint> points;

  @override
  FlacBlockType get type => FlacBlockType.seekTable;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('Seek table serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/cue_sheet_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class CueSheetTrack {
  const CueSheetTrack({
    required this.offset,
    required this.number,
    required this.isrc,
  });

  final int offset;
  final int number;
  final String isrc;
}

final class CueSheetBlock extends FlacMetadataBlock {
  const CueSheetBlock({
    required this.mediaCatalogNumber,
    required this.leadInSamples,
    required this.isCd,
    required this.tracks,
  });

  final String mediaCatalogNumber;
  final int leadInSamples;
  final bool isCd;
  final List<CueSheetTrack> tracks;

  @override
  FlacBlockType get type => FlacBlockType.cueSheet;

  @override
  int get payloadLength => toPayloadBytes().length;

  @override
  Uint8List toPayloadBytes() {
    throw UnimplementedError('Cue sheet serialization not yet implemented.');
  }
}
```

---

## `lib/src/model/unknown_block.dart`

```dart
import 'dart:typed_data';

import 'flac_block_type.dart';
import 'flac_metadata_block.dart';

final class UnknownBlock extends FlacMetadataBlock {
  const UnknownBlock({
    required this.rawTypeCode,
    required this.rawPayload,
  });

  final int rawTypeCode;
  final Uint8List rawPayload;

  @override
  FlacBlockType get type => FlacBlockType.unknown;

  @override
  int get payloadLength => rawPayload.length;

  @override
  Uint8List toPayloadBytes() => Uint8List.fromList(rawPayload);
}
```

---

## `lib/src/model/flac_metadata_document.dart`

```dart
import 'dart:typed_data';

import '../edit/flac_metadata_editor.dart';
import 'flac_metadata_block.dart';
import 'picture_block.dart';
import 'stream_info_block.dart';
import 'vorbis_comment_block.dart';

final class FlacMetadataDocument {
  const FlacMetadataDocument({
    required this.blocks,
    required this.audioDataOffset,
    required this.sourceMetadataRegionLength,
  });

  final List<FlacMetadataBlock> blocks;

  /// Absolute byte offset where FLAC audio frames begin.
  final int audioDataOffset;

  /// Size in bytes of marker + metadata region from original source.
  final int sourceMetadataRegionLength;

  StreamInfoBlock get streamInfo =>
      blocks.whereType<StreamInfoBlock>().single;

  VorbisCommentBlock? get vorbisComment =>
      blocks.whereType<VorbisCommentBlock>().cast<VorbisCommentBlock?>().firstWhere(
            (b) => b != null,
            orElse: () => null,
          );

  List<PictureBlock> get pictures =>
      blocks.whereType<PictureBlock>().toList(growable: false);

  FlacMetadataDocument edit(void Function(FlacMetadataEditor editor) updates) {
    final editor = FlacMetadataEditor.fromDocument(this);
    updates(editor);
    return editor.build();
  }

  Future<Uint8List> toBytes() async {
    throw UnimplementedError('Document serialization not yet implemented.');
  }
}
```

I would likely tighten that `vorbisComment` getter later, but this is enough to start.

---

# 6. Mutation model

## `lib/src/edit/mutation_ops.dart`

```dart
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
```

---

## `lib/src/edit/flac_metadata_editor.dart`

```dart
import '../model/flac_metadata_document.dart';
import '../model/padding_block.dart';
import '../model/picture_block.dart';
import '../model/picture_type.dart';
import 'mutation_ops.dart';

final class FlacMetadataEditor {
  FlacMetadataEditor._(this._source);

  factory FlacMetadataEditor.fromDocument(FlacMetadataDocument source) {
    return FlacMetadataEditor._(source);
  }

  final FlacMetadataDocument _source;
  final List<MetadataMutation> _mutations = <MetadataMutation>[];

  List<MetadataMutation> get mutations => List.unmodifiable(_mutations);

  void setTag(String key, List<String> values) {
    _mutations.add(SetTag(key, values));
  }

  void addTag(String key, String value) {
    _mutations.add(AddTag(key, value));
  }

  void removeTag(String key) {
    _mutations.add(RemoveTag(key));
  }

  void removeExactTagValue(String key, String value) {
    _mutations.add(RemoveExactTagValue(key, value));
  }

  void clearTags() {
    _mutations.add(const ClearTags());
  }

  void addPicture(PictureBlock picture) {
    _mutations.add(AddPicture(picture));
  }

  void replacePictureByType(PictureType type, PictureBlock replacement) {
    _mutations.add(ReplacePictureByType(
      pictureType: type,
      replacement: replacement,
    ));
  }

  void removePictureByType(PictureType type) {
    _mutations.add(RemovePictureByType(type));
  }

  void removeAllPictures() {
    _mutations.add(const RemoveAllPictures());
  }

  void setPadding(int size) {
    _mutations.add(SetPadding(size));
  }

  FlacMetadataDocument build() {
    throw UnimplementedError('Mutation application not yet implemented.');
  }
}
```

---

# 7. Binary parsing and serialization

## `lib/src/binary/flac_block_header.dart`

```dart
final class FlacBlockHeader {
  const FlacBlockHeader({
    required this.isLast,
    required this.typeCode,
    required this.payloadLength,
  });

  final bool isLast;
  final int typeCode;
  final int payloadLength;
}
```

---

## `lib/src/binary/flac_constants.dart`

```dart
const String flacMagic = 'fLaC';
const int flacMetadataHeaderSize = 4;
const int streamInfoPayloadLength = 34;
```

---

## `lib/src/binary/byte_reader.dart`

```dart
import 'dart:typed_data';

import '../error/exceptions.dart';

final class ByteReader {
  ByteReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;

  int readUint8() {
    _ensureAvailable(1);
    return _bytes[_offset++];
  }

  int readUint24() {
    _ensureAvailable(3);
    final value =
        (_bytes[_offset] << 16) |
        (_bytes[_offset + 1] << 8) |
        _bytes[_offset + 2];
    _offset += 3;
    return value;
  }

  int readUint32LE() {
    _ensureAvailable(4);
    final b0 = _bytes[_offset];
    final b1 = _bytes[_offset + 1];
    final b2 = _bytes[_offset + 2];
    final b3 = _bytes[_offset + 3];
    _offset += 4;
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(result);
  }

  void _ensureAvailable(int length) {
    if (remaining < length) {
      throw MalformedMetadataException(
        'Unexpected end of data: needed $length bytes, only $remaining available.',
      );
    }
  }
}
```

---

## `lib/src/binary/byte_writer.dart`

```dart
import 'dart:typed_data';

final class ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeUint8(int value) {
    _builder.add([value & 0xFF]);
  }

  void writeUint24(int value) {
    _builder.add([
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  void writeUint32LE(int value) {
    _builder.add([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  void writeBytes(List<int> bytes) {
    _builder.add(bytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
```

---

## `lib/src/binary/flac_parser.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../error/exceptions.dart';
import '../model/flac_metadata_document.dart';

final class FlacParser {
  const FlacParser();

  Future<FlacMetadataDocument> parseBytes(Uint8List bytes) async {
    final magic = ascii.decode(bytes.sublist(0, 4), allowInvalid: false);
    if (magic != 'fLaC') {
      throw InvalidFlacException('Missing FLAC magic header.');
    }

    throw UnimplementedError('FLAC metadata parsing not yet implemented.');
  }

  Future<FlacMetadataDocument> parseStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return parseBytes(builder.takeBytes());
  }
}
```

This is intentionally simple for the starter draft. Later you can optimize `parseStream` to buffer only the metadata region.

---

## `lib/src/binary/flac_serializer.dart`

```dart
import 'dart:typed_data';

import '../model/flac_metadata_block.dart';
import '../model/flac_metadata_document.dart';

final class FlacSerializer {
  const FlacSerializer();

  Uint8List serializeDocument(FlacMetadataDocument document) {
    throw UnimplementedError('Document serialization not yet implemented.');
  }

  Uint8List serializeBlocks(List<FlacMetadataBlock> blocks) {
    throw UnimplementedError('Block serialization not yet implemented.');
  }
}
```

---

# 8. Transform layer

## `lib/src/transform/flac_transform_options.dart`

```dart
final class FlacTransformOptions {
  const FlacTransformOptions({
    this.preferredPaddingBytes,
    this.allowFullRewrite = true,
  });

  final int? preferredPaddingBytes;
  final bool allowFullRewrite;
}
```

---

## `lib/src/transform/flac_transform_plan.dart`

```dart
import '../model/flac_metadata_block.dart';

final class FlacTransformPlan {
  const FlacTransformPlan({
    required this.originalBlocks,
    required this.transformedBlocks,
    required this.originalMetadataRegionSize,
    required this.transformedMetadataRegionSize,
    required this.fitsExistingRegion,
    required this.requiresFullRewrite,
  });

  final List<FlacMetadataBlock> originalBlocks;
  final List<FlacMetadataBlock> transformedBlocks;
  final int originalMetadataRegionSize;
  final int transformedMetadataRegionSize;
  final bool fitsExistingRegion;
  final bool requiresFullRewrite;
}
```

---

## `lib/src/transform/flac_transform_result.dart`

```dart
import 'dart:async';

import 'flac_transform_plan.dart';

final class FlacTransformResult {
  const FlacTransformResult({
    required this.plan,
    required this.output,
  });

  final FlacTransformPlan plan;
  final Stream<List<int>> output;
}
```

---

## `lib/src/transform/flac_transformer.dart`

```dart
import 'dart:async';
import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../edit/mutation_ops.dart';
import '../model/flac_metadata_document.dart';
import 'flac_transform_options.dart';
import 'flac_transform_plan.dart';
import 'flac_transform_result.dart';

final class FlacTransformer {
  FlacTransformer._({
    required this._sourceFactory,
    required FlacParser parser,
  }) : _parser = parser;

  factory FlacTransformer.fromBytes(Uint8List bytes) {
    return FlacTransformer._(
      parser: const FlacParser(),
      _sourceFactory: () async* {
        yield bytes;
      },
    );
  }

  factory FlacTransformer.fromStream(Stream<List<int>> stream) {
    return FlacTransformer._(
      parser: const FlacParser(),
      _sourceFactory: () => stream,
    );
  }

  final FlacParser _parser;
  final Stream<List<int>> Function() _sourceFactory;

  Future<FlacMetadataDocument> readMetadata() async {
    return _parser.parseStream(_sourceFactory());
  }

  Future<FlacTransformPlan> plan({
    required List<MetadataMutation> mutations,
    FlacTransformOptions options = const FlacTransformOptions(),
  }) async {
    final document = await readMetadata();
    throw UnimplementedError('Transform planning not yet implemented.');
  }

  Future<FlacTransformResult> transform({
    required List<MetadataMutation> mutations,
    FlacTransformOptions options = const FlacTransformOptions(),
  }) async {
    throw UnimplementedError('Stream transformation not yet implemented.');
  }
}
```

---

## `lib/src/transform/stream_rewriter.dart`

```dart
import 'dart:async';

final class StreamRewriter {
  const StreamRewriter();

  Stream<List<int>> rewrite({
    required Stream<List<int>> original,
    required List<int> replacementPrefix,
    required int bytesToSkipFromOriginalStart,
  }) async* {
    yield replacementPrefix;

    var skipped = 0;
    await for (final chunk in original) {
      if (skipped >= bytesToSkipFromOriginalStart) {
        yield chunk;
        continue;
      }

      if (skipped + chunk.length <= bytesToSkipFromOriginalStart) {
        skipped += chunk.length;
        continue;
      }

      final start = bytesToSkipFromOriginalStart - skipped;
      skipped = bytesToSkipFromOriginalStart;
      yield chunk.sublist(start);
    }
  }
}
```

---

# 9. API entry-point helpers

## `lib/src/api/read_api.dart`

```dart
import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../model/flac_metadata_document.dart';

final class FlacReadApi {
  const FlacReadApi._();

  static Future<FlacMetadataDocument> readFromBytes(Uint8List bytes) {
    return const FlacParser().parseBytes(bytes);
  }

  static Future<FlacMetadataDocument> readFromStream(Stream<List<int>> stream) {
    return const FlacParser().parseStream(stream);
  }
}
```

---

## `lib/src/api/document_api.dart`

```dart
import 'dart:typed_data';

import '../binary/flac_parser.dart';
import '../model/flac_metadata_document.dart';

extension FlacDocumentFactory on FlacMetadataDocument {
  static Future<FlacMetadataDocument> readFromBytes(Uint8List bytes) {
    return const FlacParser().parseBytes(bytes);
  }

  static Future<FlacMetadataDocument> readFromStream(
    Stream<List<int>> stream,
  ) {
    return const FlacParser().parseStream(stream);
  }
}
```

If you dislike static extensions, move these into `FlacMetadataDocument` directly. I probably would.

---

## `lib/src/api/transform_api.dart`

```dart
import 'dart:typed_data';

import '../transform/flac_transformer.dart';

final class FlacTransformApi {
  const FlacTransformApi._();

  static FlacTransformer fromBytes(Uint8List bytes) {
    return FlacTransformer.fromBytes(bytes);
  }

  static FlacTransformer fromStream(Stream<List<int>> stream) {
    return FlacTransformer.fromStream(stream);
  }
}
```

---

# 10. IO adapter package

Your uploaded PRD explicitly separates the platform-specific CLI/file handling from the pure core. This package is where all path and persistence concerns live. 

## `packages/dart_metaflac_io/lib/src/write_mode.dart`

```dart
enum WriteMode {
  safeAtomic,
  auto,
  inPlaceIfPossible,
  outputToNewFile,
}
```

---

## `packages/dart_metaflac_io/lib/src/file_api.dart`

```dart
import 'write_mode.dart';

final class FlacWriteOptions {
  const FlacWriteOptions({
    this.mode = WriteMode.safeAtomic,
    this.preserveModTime = false,
    this.outputPath,
  });

  final WriteMode mode;
  final bool preserveModTime;
  final String? outputPath;
}
```

---

## `packages/dart_metaflac_io/lib/src/temp_file_manager.dart`

```dart
import 'dart:io';

final class TempFileManager {
  const TempFileManager();

  Future<File> createSiblingTempFile(File source) async {
    final directory = source.parent;
    final tempName = '.${source.uri.pathSegments.last}.tmp';
    final file = File('${directory.path}${Platform.pathSeparator}$tempName');
    if (await file.exists()) {
      await file.delete();
    }
    return file;
  }
}
```

---

## `packages/dart_metaflac_io/lib/src/atomic_writer.dart`

```dart
import 'dart:io';

import 'package:dart_metaflac/dart_metaflac.dart';

import 'temp_file_manager.dart';

final class AtomicWriter {
  AtomicWriter({
    TempFileManager? tempFileManager,
  }) : _tempFileManager = tempFileManager ?? const TempFileManager();

  final TempFileManager _tempFileManager;

  Future<void> replaceFileAtomically({
    required File source,
    required Stream<List<int>> transformedOutput,
    bool preserveModTime = false,
  }) async {
    final stat = preserveModTime ? await source.stat() : null;
    final tempFile = await _tempFileManager.createSiblingTempFile(source);

    IOSink? sink;
    try {
      sink = tempFile.openWrite();
      await transformedOutput.pipe(sink);
      await sink.flush();
      await sink.close();

      await tempFile.rename(source.path);

      if (preserveModTime && stat != null) {
        await File(source.path).setLastModified(stat.modified);
      }
    } on Object catch (e) {
      throw FlacIoException('Atomic replace failed.', cause: e);
    } finally {
      await sink?.close();
    }
  }
}
```

On some platforms, rename semantics are not perfectly atomic in every edge case, but this is still the right default abstraction.

---

## `packages/dart_metaflac_io/lib/src/flac_file_editor.dart`

```dart
import 'dart:io';

import 'package:dart_metaflac/dart_metaflac.dart';

import 'atomic_writer.dart';
import 'file_api.dart';
import 'write_mode.dart';

final class FlacFileEditor {
  FlacFileEditor({
    AtomicWriter? atomicWriter,
  }) : _atomicWriter = atomicWriter ?? AtomicWriter();

  final AtomicWriter _atomicWriter;

  Future<FlacMetadataDocument> readFile(String path) {
    return const FlacParser().parseStream(File(path).openRead());
  }

  Future<void> updateFile(
    String path, {
    required List<MetadataMutation> mutations,
    FlacWriteOptions options = const FlacWriteOptions(),
  }) async {
    final source = File(path);
    final transformer = FlacTransformer.fromStream(source.openRead());
    final result = await transformer.transform(mutations: mutations);

    switch (options.mode) {
      case WriteMode.safeAtomic:
      case WriteMode.auto:
        await _atomicWriter.replaceFileAtomically(
          source: source,
          transformedOutput: result.output,
          preserveModTime: options.preserveModTime,
        );
      case WriteMode.outputToNewFile:
        final outPath = options.outputPath;
        if (outPath == null || outPath.isEmpty) {
          throw WriteConflictException(
            'outputPath is required when mode=outputToNewFile.',
          );
        }
        final sink = File(outPath).openWrite();
        await result.output.pipe(sink);
        await sink.flush();
        await sink.close();
      case WriteMode.inPlaceIfPossible:
        if (!result.plan.fitsExistingRegion) {
          throw WriteConflictException(
            'In-place update is not possible for this transform.',
          );
        }
        // Later: implement exact in-place overwrite path.
        throw UnimplementedError('In-place update not yet implemented.');
    }
  }
}
```

---

# 11. CLI package

## `packages/dart_metaflac_cli/bin/dart_metaflac.dart`

```dart
import 'dart:io';

import 'package:dart_metaflac_cli/src/cli_runner.dart';

Future<void> main(List<String> args) async {
  final exitCodeValue = await CliRunner().run(args);
  exitCode = exitCodeValue;
}
```

---

## `packages/dart_metaflac_cli/lib/src/command_context.dart`

```dart
import 'package:dart_metaflac_io/dart_metaflac_io.dart';

final class CommandContext {
  CommandContext({
    FlacFileEditor? fileEditor,
  }) : fileEditor = fileEditor ?? FlacFileEditor();

  final FlacFileEditor fileEditor;
}
```

---

## `packages/dart_metaflac_cli/lib/src/output/exit_codes.dart`

```dart
abstract final class ExitCodes {
  static const int success = 0;
  static const int usage = 64;
  static const int dataError = 65;
  static const int ioError = 74;
  static const int softwareError = 70;
}
```

---

## `packages/dart_metaflac_cli/lib/src/output/human_output.dart`

```dart
void printInfo(String message) {
  // ignore: avoid_print
  print(message);
}

void printError(String message) {
  // ignore: avoid_print
  print(message);
}
```

Later, move `printError` to `stderr.writeln`.

---

## `packages/dart_metaflac_cli/lib/src/output/json_output.dart`

```dart
import 'dart:convert';

String toJsonOutput(Map<String, Object?> payload) {
  return const JsonEncoder.withIndent('  ').convert(payload);
}
```

---

## `packages/dart_metaflac_cli/lib/src/compat/metaflac_alias_parser.dart`

```dart
final class MetaflacAliasParseResult {
  const MetaflacAliasParseResult({
    required this.rewrittenArgs,
    required this.wasCompatibilityAlias,
  });

  final List<String> rewrittenArgs;
  final bool wasCompatibilityAlias;
}

final class MetaflacAliasParser {
  const MetaflacAliasParser();

  MetaflacAliasParseResult rewrite(List<String> args) {
    if (args.isEmpty) {
      return const MetaflacAliasParseResult(
        rewrittenArgs: <String>[],
        wasCompatibilityAlias: false,
      );
    }

    final first = args.first;

    if (first == '--list' && args.length >= 2) {
      return MetaflacAliasParseResult(
        rewrittenArgs: ['blocks', 'list', ...args.skip(1)],
        wasCompatibilityAlias: true,
      );
    }

    if (first.startsWith('--set-tag=')) {
      final kv = first.substring('--set-tag='.length);
      return MetaflacAliasParseResult(
        rewrittenArgs: ['tags', 'set', ...args.skip(1), kv],
        wasCompatibilityAlias: true,
      );
    }

    if (first.startsWith('--remove-tag=')) {
      final key = first.substring('--remove-tag='.length);
      return MetaflacAliasParseResult(
        rewrittenArgs: ['tags', 'remove', ...args.skip(1), key],
        wasCompatibilityAlias: true,
      );
    }

    if (first == '--remove-all-tags') {
      return MetaflacAliasParseResult(
        rewrittenArgs: ['tags', 'clear', ...args.skip(1)],
        wasCompatibilityAlias: true,
      );
    }

    return MetaflacAliasParseResult(
      rewrittenArgs: args,
      wasCompatibilityAlias: false,
    );
  }
}
```

---

## `packages/dart_metaflac_cli/lib/src/cli_runner.dart`

```dart
import 'package:args/args.dart';
import 'package:dart_metaflac/dart_metaflac.dart';

import 'command_context.dart';
import 'compat/metaflac_alias_parser.dart';
import 'output/exit_codes.dart';

final class CliRunner {
  CliRunner({
    CommandContext? context,
    MetaflacAliasParser? aliasParser,
  })  : _context = context ?? CommandContext(),
        _aliasParser = aliasParser ?? const MetaflacAliasParser();

  final CommandContext _context;
  final MetaflacAliasParser _aliasParser;

  Future<int> run(List<String> args) async {
    try {
      final rewritten = _aliasParser.rewrite(args).rewrittenArgs;
      if (rewritten.isEmpty) {
        return ExitCodes.usage;
      }

      final command = rewritten.first;
      switch (command) {
        case 'inspect':
          return ExitCodes.success;
        case 'blocks':
          return ExitCodes.success;
        case 'tags':
          return ExitCodes.success;
        case 'picture':
          return ExitCodes.success;
        case 'padding':
          return ExitCodes.success;
        default:
          return ExitCodes.usage;
      }
    } on FlacIoException {
      return ExitCodes.ioError;
    } on FlacMetadataException {
      return ExitCodes.dataError;
    } catch (_) {
      return ExitCodes.softwareError;
    }
  }
}
```

This is intentionally just a shell. The command files should own actual parsing and execution.

---

# 12. Example command starter

## `packages/dart_metaflac_cli/lib/src/commands/tags_command.dart`

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

import '../command_context.dart';

final class TagsCommand {
  const TagsCommand();

  Future<void> setTag({
    required CommandContext context,
    required String path,
    required String key,
    required String value,
  }) async {
    await context.fileEditor.updateFile(
      path,
      mutations: [SetTag(key, [value])],
    );
  }

  Future<void> removeTag({
    required CommandContext context,
    required String path,
    required String key,
  }) async {
    await context.fileEditor.updateFile(
      path,
      mutations: [RemoveTag(key)],
    );
  }

  Future<void> clearTags({
    required CommandContext context,
    required String path,
  }) async {
    await context.fileEditor.updateFile(
      path,
      mutations: const [ClearTags()],
    );
  }
}
```

---

# 13. Placeholder files I would keep but implement later

These deserve files now even if they start nearly empty:

## `lib/src/edit/normalization.dart`

```dart
import '../model/flac_metadata_block.dart';

final class BlockNormalization {
  const BlockNormalization();

  List<FlacMetadataBlock> normalize(List<FlacMetadataBlock> blocks) {
    // Later:
    // - STREAMINFO first
    // - preserve unknown blocks
    // - place padding near end
    return List<FlacMetadataBlock>.from(blocks);
  }
}
```

## `lib/src/edit/padding_strategy.dart`

```dart
final class PaddingStrategy {
  const PaddingStrategy();

  int remainingPadding({
    required int originalRegionSize,
    required int transformedRegionSize,
  }) {
    return originalRegionSize - transformedRegionSize;
  }
}
```

## `lib/src/util/validators.dart`

```dart
import '../error/exceptions.dart';

void validateVorbisKey(String key) {
  if (key.isEmpty) {
    throw MalformedMetadataException('Vorbis key must not be empty.');
  }
  if (key.contains('=')) {
    throw MalformedMetadataException('Vorbis key must not contain "=".');
  }
}
```

## `lib/src/util/utf8_utils.dart`

```dart
import 'dart:convert';
import 'dart:typed_data';

String decodeUtf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: false);

Uint8List encodeUtf8(String value) => Uint8List.fromList(utf8.encode(value));
```

---

# 14. Example usage after wiring

## In-memory use

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

Future<void> updateBytes(List<int> input, List<int> coverBytes) async {
  final doc = await FlacMetadataDocument.readFromBytes(input as dynamic);
  final updated = doc.edit((e) {
    e.setTag('ARTIST', ['New Artist']);
    e.setTag('ALBUM', ['New Album']);
  });

  final out = await updated.toBytes();
  print(out.length);
}
```

I would eventually avoid the static-extension factory and place `readFromBytes` directly on `FlacMetadataDocument`.

## File-based use

```dart
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac_io/dart_metaflac_io.dart';

Future<void> main() async {
  final editor = FlacFileEditor();

  await editor.updateFile(
    'song.flac',
    mutations: const [
      SetTag('ARTIST', ['Miles Davis']),
      SetTag('ALBUM', ['Kind of Blue']),
      SetPadding(8192),
    ],
    options: const FlacWriteOptions(
      mode: WriteMode.safeAtomic,
      preserveModTime: true,
    ),
  );
}
```

That lines up directly with your requirement for safe file manipulation, padding-aware updates, and a CLI/frontend layered on a pure core.   

---

# 15. My opinion on a couple of choices

Two decisions here are worth locking in early.

First, I would keep **three packages**, not two:

* `dart_metaflac`
* `dart_metaflac_io`
* `dart_metaflac_cli`

That keeps the core truly portable and prevents accidental `dart:io` leakage.

Second, I would keep **mutation objects** like `SetTag`, `RemoveTag`, and `SetPadding` instead of only exposing mutable models. They make the CLI layer cleaner, simplify dry-run planning, and make tests much easier to write.
