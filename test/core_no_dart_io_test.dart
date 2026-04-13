/// Guard test: the core library entry point (`lib/dart_metaflac.dart`)
/// must never transitively depend on `dart:io`.
///
/// The file/IO adapters live in a separate public entry point at
/// `package:dart_metaflac/io.dart`. The core library is meant to be safe
/// for Flutter Web, WASM, and any other target where `dart:io` is
/// unavailable. This test walks every Dart source file reachable from the
/// core entry point and fails if any of them `import 'dart:io'`.
///
/// If this test fails, either:
///   1. You added a `dart:io` import to a file under `lib/src/` that is
///      reachable from `lib/dart_metaflac.dart`. Move the offending code
///      into `lib/src/io/` and export it from `lib/io.dart` instead.
///   2. You added a new `export 'src/io/...'` line to
///      `lib/dart_metaflac.dart`. Remove it — the IO layer belongs in
///      `lib/io.dart`.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('core library has no transitive dart:io dependency', () {
    final projectRoot = _findProjectRoot();
    final coreEntry = File('${projectRoot.path}/lib/dart_metaflac.dart');
    expect(coreEntry.existsSync(), isTrue,
        reason: 'core library entry point is missing');

    final visited = <String>{};
    final offenders = <String>[];
    final queue = <File>[coreEntry];

    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!file.existsSync()) continue;

      // Canonicalise before visited-check so `a/../b.dart` and `b.dart`
      // collapse to the same entry. Without this, relative imports can
      // create cycles that blow up memory and time.
      final canonical = file.resolveSymbolicLinksSync();
      if (!visited.add(canonical)) continue;

      final source = File(canonical).readAsStringSync();

      if (_containsDartIoImport(source)) {
        offenders.add(_relative(canonical, projectRoot));
      }

      for (final importUri in _extractLocalImports(source)) {
        final resolved = _resolveImport(canonical, importUri, projectRoot);
        if (resolved != null) queue.add(resolved);
      }
    }

    expect(offenders, isEmpty,
        reason: 'Files reachable from lib/dart_metaflac.dart must not import '
            "dart:io. Offenders: $offenders");
  });
}

bool _containsDartIoImport(String source) {
  final pattern = RegExp(
    r'''^\s*import\s+['"]dart:io['"]''',
    multiLine: true,
  );
  return pattern.hasMatch(source);
}

Iterable<String> _extractLocalImports(String source) sync* {
  final pattern = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (uri.startsWith('dart:')) continue;
    if (uri.startsWith('package:') &&
        !uri.startsWith('package:dart_metaflac/')) {
      continue;
    }
    yield uri;
  }
}

File? _resolveImport(String fromCanonical, String importUri, Directory root) {
  if (importUri.startsWith('package:dart_metaflac/')) {
    final tail = importUri.substring('package:dart_metaflac/'.length);
    return File('${root.path}/lib/$tail');
  }
  final fromDir = Directory(fromCanonical).parent.path;
  return File('$fromDir/$importUri');
}

String _relative(String canonical, Directory root) {
  final rootPath = root.absolute.path;
  if (canonical.startsWith(rootPath)) {
    return canonical.substring(rootPath.length + 1);
  }
  return canonical;
}

Directory _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'could not locate pubspec.yaml from ${Directory.current}');
    }
    dir = parent;
  }
}
