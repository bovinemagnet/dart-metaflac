# dart_metaflac Flutter example

A minimal Flutter application demonstrating how to use `dart_metaflac` in
a cross-platform Flutter app. Reads FLAC metadata from an asset bundle
and displays the Vorbis comment tags in a list view.

## Platform support

| Platform          | Read (core) | Write (file) |
| ----------------- | :---------: | :----------: |
| Flutter Mobile    | yes         | yes          |
| Flutter Desktop   | yes         | yes          |
| Flutter Web       | yes         | no¹          |

¹ On Flutter Web the file-based APIs are not available because they
depend on `dart:io`. Use the in-memory APIs
([`FlacMetadataDocument.readFromBytes`] and
[`FlacMetadataDocument.toBytes`]) and hand the resulting `Uint8List`
back to the browser via a blob URL if you need to "save" the file.

## Getting started

1. Drop a real `.flac` file into `assets/sample.flac`. The repository's
   top-level `assets/wav/siren.flac` is a good candidate — copy it into
   place with:

   ```sh
   mkdir -p assets
   cp ../../assets/wav/siren.flac assets/sample.flac
   ```

2. Run the app on your preferred target:

   ```sh
   flutter run -d chrome        # web
   flutter run -d macos         # desktop
   flutter run -d <device-id>   # mobile
   ```

## How it works

The app loads the FLAC bytes from the asset bundle using
`rootBundle.load()`, which works identically on every Flutter target.
It then parses the bytes with `FlacMetadataDocument.readFromBytes` —
a pure-Dart API that has no dependency on `dart:io`:

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

final data = await rootBundle.load('assets/sample.flac');
final bytes = data.buffer.asUint8List();
final doc = FlacMetadataDocument.readFromBytes(bytes);

for (final entry in doc.vorbisComment!.comments.entries) {
  print('${entry.key} = ${entry.value}');
}
```

To **edit** and persist changes on a native (non-web) target, add a
second import and use `FlacFileEditor`:

```dart
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';  // adds dart:io-backed APIs

await FlacFileEditor.updateFile(
  '/path/to/song.flac',
  mutations: [SetTag('ARTIST', ['New Artist'])],
);
```

Do **not** add `import 'package:dart_metaflac/io.dart'` on Flutter Web —
it imports `dart:io`, which the browser runtime cannot provide.

## This is a documentation example

This project is intentionally minimal. It is not a published package and
is not run by the library's test suite. Its purpose is to demonstrate
idiomatic usage patterns for Flutter app developers who want to
integrate `dart_metaflac`.
