import 'dart:typed_data';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/mutation_ops.dart';

/// Apply a list of metadata mutations to a FLAC byte stream.
///
/// Read the entire [input] stream, parse it as a FLAC file, apply each
/// [MetadataMutation] in [mutations] in order, then serialise the
/// modified document back to bytes.
///
/// The returned [Uint8List] contains the complete FLAC file including
/// the updated metadata blocks and the original audio data.
///
/// Throws [InvalidFlacException] if the input does not contain valid
/// FLAC data.
///
/// Throws [MalformedMetadataException] if any metadata block is
/// structurally invalid.
Future<Uint8List> applyMutations(
  Stream<List<int>> input,
  List<MetadataMutation> mutations,
) async {
  final bytes = await _collectBytes(input);
  final doc = FlacParser.parseBytes(bytes);
  final updated = doc.edit((e) {
    for (final m in mutations) {
      e.applyMutation(m);
    }
  });
  final audioData = bytes.sublist(doc.audioDataOffset);
  return FlacSerializer.serialize(updated.blocks, audioData);
}

Future<Uint8List> _collectBytes(Stream<List<int>> stream) async {
  final chunks = <List<int>>[];
  await for (final chunk in stream) {
    chunks.add(chunk);
  }
  final total = chunks.fold<int>(0, (s, c) => s + c.length);
  final result = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}
