final class VorbisCommentEntry {
  const VorbisCommentEntry({required this.key, required this.value});
  final String key;
  final String value;
  String get canonicalKey => key.toUpperCase();
}

final class VorbisComments {
  const VorbisComments({required this.vendorString, required this.entries});
  final String vendorString;
  final List<VorbisCommentEntry> entries;

  List<String> valuesOf(String key) {
    final canonical = key.toUpperCase();
    return entries
        .where((e) => e.canonicalKey == canonical)
        .map((e) => e.value)
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
        entries.where((e) => e.canonicalKey != canonical).toList();
    retained
        .addAll(values.map((v) => VorbisCommentEntry(key: key, value: v)));
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
          entries.where((e) => e.canonicalKey != canonical).toList(),
    );
  }

  VorbisComments removeExact(String key, String value) {
    final canonical = key.toUpperCase();
    return VorbisComments(
      vendorString: vendorString,
      entries: entries
          .where(
              (e) => !(e.canonicalKey == canonical && e.value == value))
          .toList(),
    );
  }

  VorbisComments clear() {
    return VorbisComments(vendorString: vendorString, entries: const []);
  }
}
