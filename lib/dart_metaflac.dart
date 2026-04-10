/// A pure Dart library for reading and writing FLAC audio metadata.
///
/// This library provides complete support for FLAC metadata operations
/// **without depending on `dart:io`**, making it suitable for Dart, Flutter
/// (including Flutter Web and WASM), server isolates, and browser use cases.
///
/// File-based APIs that need `dart:io` live in a separate entry point:
/// `package:dart_metaflac/io.dart`. Import both libraries on targets where
/// `dart:io` is available.
///
/// ## Modules
///
/// * **model** — Immutable domain objects representing FLAC metadata blocks,
///   including [FlacMetadataDocument], [VorbisComments], [StreamInfoBlock],
///   [PictureBlock], and more.
/// * **binary** — Low-level parsing and serialisation via [FlacParser] and
///   [FlacSerializer].
/// * **edit** — Mutation operations through [FlacMetadataEditor] and the
///   [MetadataMutation] sealed class hierarchy.
/// * **transform** — Transform planning and streaming via [FlacTransformer].
/// * **api** — High-level convenience functions: [readFlacMetadata],
///   [readFlacMetadataFromBytes], [applyMutations], and [transformFlac].
///
/// See also: `package:dart_metaflac/io.dart` for file persistence adapters
/// (`FlacFileEditor`, `AtomicWriter`, `FlacWriteOptions`, `ModTimePreserver`).
///
/// ## Quick Start
///
/// ```dart
/// import 'package:dart_metaflac/dart_metaflac.dart';
///
/// // Read metadata from bytes
/// final doc = FlacMetadataDocument.readFromBytes(flacBytes);
/// print(doc.vorbisComment?.comments.valuesOf('ARTIST'));
///
/// // Edit metadata
/// final updated = doc.edit((editor) {
///   editor.setTag('ARTIST', ['New Artist']);
///   editor.setTag('TITLE', ['New Title']);
/// });
/// final newBytes = updated.toBytes();
/// ```
library;

// Error types
export 'src/error/exceptions.dart';

// Model
export 'src/model/flac_block_type.dart';
export 'src/model/flac_metadata_block.dart';
export 'src/model/flac_metadata_document.dart';
export 'src/model/picture_type.dart';
export 'src/model/vorbis_comments.dart';
export 'src/model/stream_info_block.dart';
export 'src/model/vorbis_comment_block.dart';
export 'src/model/picture_block.dart';
export 'src/model/padding_block.dart';
export 'src/model/application_block.dart';
export 'src/model/seek_table_block.dart';
export 'src/model/cue_sheet_block.dart';
export 'src/model/unknown_block.dart';

// Binary
export 'src/binary/flac_constants.dart';
export 'src/binary/flac_block_header.dart';
export 'src/binary/byte_reader.dart';
export 'src/binary/byte_writer.dart';
export 'src/binary/flac_parser.dart';
export 'src/binary/flac_serializer.dart';

// Edit
export 'src/edit/mutation_ops.dart';
export 'src/edit/padding_strategy.dart';
export 'src/edit/flac_metadata_editor.dart';

// Transform
export 'src/transform/flac_transform_options.dart';
export 'src/transform/flac_transform_plan.dart';
export 'src/transform/flac_transform_result.dart';
export 'src/transform/flac_transformer.dart';

// API
export 'src/api/read_api.dart';
export 'src/api/document_api.dart';
export 'src/api/transform_api.dart';

// Note: file/IO adapters (FlacFileEditor, AtomicWriter, FlacWriteOptions,
// ModTimePreserver) are deliberately NOT exported here. They depend on
// `dart:io` and live in `package:dart_metaflac/io.dart`.
