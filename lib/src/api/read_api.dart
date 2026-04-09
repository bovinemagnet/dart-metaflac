import 'dart:typed_data';
import '../binary/flac_parser.dart';
import '../model/flac_metadata_document.dart';

Future<FlacMetadataDocument> readFlacMetadata(Stream<List<int>> stream) =>
    FlacParser.parse(stream);

FlacMetadataDocument readFlacMetadataFromBytes(Uint8List bytes) =>
    FlacParser.parseBytes(bytes);
