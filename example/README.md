# dart_metaflac examples

Runnable examples demonstrating how to use `dart_metaflac`.

## Core (pure-Dart, no `dart:io`)

These examples use only `package:dart_metaflac/dart_metaflac.dart` and
therefore work on **every** Dart target — standalone VM, Flutter (mobile,
desktop, **web**, WASM), and server isolates.

| File | Description |
| ---- | ----------- |
| [`dart_metaflac_example.dart`](dart_metaflac_example.dart) | Headline example used as the pub.dev example snippet. |
| [`read_tags.dart`](read_tags.dart) | Parse a FLAC byte buffer and read Vorbis comment tags. |
| [`set_tags.dart`](set_tags.dart) | Edit tags via `document.edit(...)` and re-serialise to bytes. |
| [`pictures.dart`](pictures.dart) | Add and remove embedded pictures. |
| [`streaming.dart`](streaming.dart) | Stream-based transforms for large files where audio data cannot fit in memory. |
| [`web_in_memory.dart`](web_in_memory.dart) | Full read → edit → write round-trip in a single `Uint8List`, suitable for **Flutter Web / WASM**. |

Run any of these with:

```sh
dart run example/<file>.dart
```

## File-based (`dart:io`-backed)

These examples import `package:dart_metaflac/io.dart` in addition to the
core library. They require `dart:io` and therefore work on the standalone
Dart VM and Flutter mobile/desktop, **but not on Flutter Web**.

| File | Description |
| ---- | ----------- |
| [`file_rewrite.dart`](file_rewrite.dart) | Read, edit, and safely atomically rewrite a `.flac` file on disk via `FlacFileEditor`. |

## Flutter

| Directory | Description |
| --------- | ----------- |
| [`flutter_example/`](flutter_example/) | Minimal Flutter app showing asset-based FLAC tag reading; works on mobile, desktop, and web. |

See [`flutter_example/README.md`](flutter_example/README.md) for setup
instructions.
