import '../model/flac_block_type.dart';

/// Parses a comma-separated list of block type names (case-insensitive)
/// into a [Set] of [FlacBlockType].
///
/// Accepted names: `STREAMINFO`, `PADDING`, `APPLICATION`, `SEEKTABLE`,
/// `VORBIS_COMMENT`, `PICTURE`. Matches the names that upstream metaflac
/// uses on the command line.
///
/// Throws [ArgumentError] if [input] contains an unknown name. Empty
/// entries and surrounding whitespace are ignored.
Set<FlacBlockType> parseBlockTypes(String input) {
  final result = <FlacBlockType>{};
  for (final raw in input.split(',')) {
    final name = raw.trim().toUpperCase();
    if (name.isEmpty) continue;
    final type = _blockTypeFromName(name);
    if (type == null) {
      throw ArgumentError.value(
        raw,
        'block type',
        'Unknown block type. Valid: STREAMINFO, PADDING, APPLICATION, '
            'SEEKTABLE, VORBIS_COMMENT, PICTURE.',
      );
    }
    result.add(type);
  }
  return result;
}

/// Parses a comma-separated list of non-negative integers into a [Set].
///
/// Throws [ArgumentError] on non-integer or negative entries.
Set<int> parseBlockNumbers(String input) {
  final result = <int>{};
  for (final raw in input.split(',')) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    final n = int.tryParse(text);
    if (n == null) {
      throw ArgumentError.value(raw, 'block number', 'Not an integer.');
    }
    if (n < 0) {
      throw ArgumentError.value(raw, 'block number', 'Must be >= 0.');
    }
    result.add(n);
  }
  return result;
}

FlacBlockType? _blockTypeFromName(String name) {
  switch (name) {
    case 'STREAMINFO':
      return FlacBlockType.streamInfo;
    case 'PADDING':
      return FlacBlockType.padding;
    case 'APPLICATION':
      return FlacBlockType.application;
    case 'SEEKTABLE':
      return FlacBlockType.seekTable;
    case 'VORBIS_COMMENT':
      return FlacBlockType.vorbisComment;
    case 'PICTURE':
      return FlacBlockType.picture;
    default:
      return null;
  }
}
