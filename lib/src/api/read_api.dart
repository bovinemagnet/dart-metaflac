import 'dart:typed_data';
import '../binary/flac_parser.dart';
import '../model/flac_metadata_document.dart';

/// Parse FLAC metadata from a byte stream.
///
/// Read the entire [stream] and parse its contents as a FLAC file,
/// returning a [FlacMetadataDocument] containing all metadata blocks
/// and the audio data offset.
///
/// This is the streaming counterpart to [readFlacMetadataFromBytes].
/// The stream is fully consumed before parsing begins.
///
/// Throws [InvalidFlacException] if the stream does not contain valid
/// FLAC data.
///
/// Throws [MalformedMetadataException] if any metadata block is
/// structurally invalid.
Future<FlacMetadataDocument> readFlacMetadata(Stream<List<int>> stream) =>
    FlacParser.parse(stream);

/// Parse FLAC metadata from an in-memory byte buffer.
///
/// Synchronously parse [bytes] as a FLAC file and return a
/// [FlacMetadataDocument] containing all metadata blocks and the
/// audio data offset.
///
/// This is the in-memory counterpart to [readFlacMetadata].
///
/// Throws [InvalidFlacException] if [bytes] does not contain valid
/// FLAC data.
///
/// Throws [MalformedMetadataException] if any metadata block is
/// structurally invalid.
FlacMetadataDocument readFlacMetadataFromBytes(Uint8List bytes) =>
    FlacParser.parseBytes(bytes);
