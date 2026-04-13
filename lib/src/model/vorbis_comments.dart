/// A single key–value entry in a Vorbis comment block.
///
/// Keys are case-insensitive per the Vorbis specification; use
/// [canonicalKey] for case-normalised comparisons.
final class VorbisCommentEntry {
  /// Create a [VorbisCommentEntry] with the given [key] and [value].
  const VorbisCommentEntry({required this.key, required this.value});

  /// The field name as originally stored (case preserved).
  final String key;

  /// The field value as a UTF-8 string.
  final String value;

  /// The upper-case form of [key], used for case-insensitive matching.
  String get canonicalKey => key.toUpperCase();
}

/// An ordered collection of Vorbis comment entries with a vendor string.
///
/// **Important:** [VorbisComments] is _not_ a map. It preserves insertion
/// order and permits duplicate keys, which is valid and common in the
/// Vorbis comment specification (e.g. multiple ARTIST entries).
///
/// All lookup and mutation methods perform case-insensitive key matching.
/// Mutation methods return a new [VorbisComments] instance; this class is
/// immutable.
///
/// See also:
/// - [VorbisCommentBlock] which wraps this model as a [FlacMetadataBlock].
/// - [VorbisCommentEntry] for individual entries.
final class VorbisComments {
  /// Create a [VorbisComments] with the given [vendorString] and [entries].
  const VorbisComments({required this.vendorString, required this.entries});

  /// The encoder or software vendor identification string.
  final String vendorString;

  /// The ordered list of comment entries.
  ///
  /// Duplicate keys are permitted and their relative order is significant.
  final List<VorbisCommentEntry> entries;

  /// Return all values associated with [key] (case-insensitive).
  ///
  /// Returns an empty list if no entries match.
  List<String> valuesOf(String key) {
    final canonical = key.toUpperCase();
    return entries
        .where((e) => e.canonicalKey == canonical)
        .map((e) => e.value)
        .toList(growable: false);
  }

  /// Convert the entries to a multi-map keyed by upper-case field name.
  ///
  /// Each key maps to a list of values in the order they appear in
  /// [entries].
  Map<String, List<String>> asMultiMap() {
    final map = <String, List<String>>{};
    for (final entry in entries) {
      map.putIfAbsent(entry.canonicalKey, () => <String>[]).add(entry.value);
    }
    return map;
  }

  /// Return a new [VorbisComments] with all entries for [key] replaced by
  /// [values].
  ///
  /// Existing entries whose key matches [key] (case-insensitive) are
  /// removed, and the new values are appended at the end.
  VorbisComments set(String key, List<String> values) {
    final canonical = key.toUpperCase();
    final retained = entries.where((e) => e.canonicalKey != canonical).toList();
    retained.addAll(values.map((v) => VorbisCommentEntry(key: key, value: v)));
    return VorbisComments(vendorString: vendorString, entries: retained);
  }

  /// Return a new [VorbisComments] with an additional entry for [key] and
  /// [value] appended at the end.
  ///
  /// Does not remove any existing entries, even those with the same key.
  VorbisComments add(String key, String value) {
    return VorbisComments(
      vendorString: vendorString,
      entries: [...entries, VorbisCommentEntry(key: key, value: value)],
    );
  }

  /// Return a new [VorbisComments] with all entries for [key] removed
  /// (case-insensitive).
  VorbisComments removeKey(String key) {
    final canonical = key.toUpperCase();
    return VorbisComments(
      vendorString: vendorString,
      entries: entries.where((e) => e.canonicalKey != canonical).toList(),
    );
  }

  /// Return a new [VorbisComments] with the specific entry matching both
  /// [key] (case-insensitive) and [value] (exact match) removed.
  ///
  /// If multiple entries match, all of them are removed.
  VorbisComments removeExact(String key, String value) {
    final canonical = key.toUpperCase();
    return VorbisComments(
      vendorString: vendorString,
      entries: entries
          .where((e) => !(e.canonicalKey == canonical && e.value == value))
          .toList(),
    );
  }

  /// Return a new [VorbisComments] with only the **first** entry matching
  /// [key] (case-insensitive) removed.
  ///
  /// Subsequent entries with the same key are preserved. If no entry
  /// matches, the result is byte-identical to the original.
  ///
  /// See also: [removeKey], which removes every matching entry.
  VorbisComments removeFirst(String key) {
    final canonical = key.toUpperCase();
    final result = <VorbisCommentEntry>[];
    var removed = false;
    for (final entry in entries) {
      if (!removed && entry.canonicalKey == canonical) {
        removed = true;
        continue;
      }
      result.add(entry);
    }
    return VorbisComments(vendorString: vendorString, entries: result);
  }

  /// Return a new [VorbisComments] with every entry removed except those
  /// whose key (case-insensitive) is in [keepKeys].
  ///
  /// The [vendorString] is always retained. This mirrors the reference
  /// `metaflac --remove-all-tags-except=NAME1=NAME2=…` operation.
  VorbisComments clearExcept(Set<String> keepKeys) {
    final canonicalKeep = keepKeys.map((k) => k.toUpperCase()).toSet();
    return VorbisComments(
      vendorString: vendorString,
      entries:
          entries.where((e) => canonicalKeep.contains(e.canonicalKey)).toList(),
    );
  }

  /// Return a new [VorbisComments] with all entries removed, retaining
  /// only the [vendorString].
  VorbisComments clear() {
    return VorbisComments(vendorString: vendorString, entries: const []);
  }
}
