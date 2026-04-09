import 'dart:typed_data';
import '../binary/flac_parser.dart';
import '../binary/flac_serializer.dart';
import '../edit/mutation_ops.dart';

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
