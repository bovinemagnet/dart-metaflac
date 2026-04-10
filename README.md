# dart_metaflac

A pure Dart library for reading and writing FLAC audio metadata.

The core has **no `dart:io` dependency**, so it works anywhere Dart runs —
standalone VM, Flutter mobile/desktop, **Flutter Web**, WASM, and server
isolates. File-based APIs live in a separate entry point for targets
where `dart:io` is available.

## Features

- **Parse** FLAC metadata from `Uint8List` or `Stream<List<int>>`
- **Read** Vorbis comments, stream info, pictures, padding, seek table,
  cue sheet, application, and unknown blocks
- **Edit** tags, pictures, and padding via an immutable document model
- **Transform** in memory or via memory-efficient streaming (audio data
  is never buffered)
- **File I/O** with atomic writes (temp file + rename) and optional
  modification-time preservation
- **CLI tool** with modern subcommands and `metaflac`-compatible flags
- **Round-trip safe** — unknown block types are preserved byte-for-byte

## Installation

```sh
dart pub add dart_metaflac
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_metaflac: ^0.0.2
```

## Public entry points

The library has two public libraries. Import whichever you need:

```dart
// Pure-Dart core. Safe on every target, including Flutter Web.
import 'package:dart_metaflac/dart_metaflac.dart';

// File/IO adapters. Requires dart:io (native / Flutter mobile / desktop).
import 'package:dart_metaflac/io.dart';
```

On Flutter Web or any other target without `dart:io`, import **only**
the core library and work entirely in `Uint8List`s.

## Quick start

### Read metadata (works everywhere)

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

final doc = FlacMetadataDocument.readFromBytes(flacBytes);

print('Sample rate: ${doc.streamInfo?.sampleRate}');
print('Channels:    ${doc.streamInfo?.channelCount}');

final comments = doc.vorbisComment?.comments;
print('Artist: ${comments?.valuesOf('ARTIST')}');
print('Title:  ${comments?.valuesOf('TITLE')}');
```

### Edit tags

```dart
final updated = doc.edit((editor) {
  editor.setTag('ARTIST', ['New Artist']);
  editor.setTag('ALBUM', ['New Album']);
  editor.addTag('GENRE', 'Rock');
  editor.removeTag('COMMENT');
});

final newBytes = updated.toBytes();
```

`VorbisComments` preserves insertion order and allows duplicate keys, so
it is **not** a `Map` — use `valuesOf(key)` to access values.

### Add a picture

```dart
final withCover = doc.edit((editor) {
  editor.addPicture(PictureBlock(
    pictureType: PictureType.frontCover,
    mimeType: 'image/jpeg',
    description: 'Front cover',
    width: 500,
    height: 500,
    colorDepth: 24,
    indexedColors: 0,
    data: jpegBytes,
  ));
});
```

### Edit a file on disc (native only)

```dart
import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:dart_metaflac/io.dart';

final doc = await FlacFileEditor.readFile('song.flac');

await FlacFileEditor.updateFile(
  'song.flac',
  mutations: [
    SetTag('ARTIST', ['New Artist']),
    SetTag('TITLE', ['Updated']),
    RemoveTag('COMMENT'),
  ],
  options: const FlacWriteOptions(preserveModTime: true),
);
```

`FlacFileEditor.updateFile` takes a list of `MetadataMutation` values
(`SetTag`, `AddTag`, `RemoveTag`, `ClearTags`, `AddPicture`,
`RemovePictureByType`, `SetPadding`, …). Use the `doc.edit((editor) => …)`
callback form when working with an in-memory `FlacMetadataDocument`
instead.

`FlacFileEditor` uses atomic writes (temp file + rename) by default, so
an interrupted write cannot leave a half-written file on disc.

### Stream-based transform for large files

```dart
final transformer = FlacTransformer.fromBytes(flacBytes);
final result = await transformer.transform(
  mutations: [SetTag('ARTIST', ['Streamed Artist'])],
);
```

When reading from a `Stream<List<int>>`, only the metadata region is
buffered — audio frames pass through without ever being loaded into
memory, so multi-gigabyte FLACs edit in constant memory.

## CLI

A `metaflac`-compatible CLI ships with the package. It supports modern
subcommand style **and** the classic `metaflac` `--flag` aliases, so
existing scripts can drop it in as a replacement.

```sh
# Activate globally
dart pub global activate dart_metaflac

# Or run from a checkout
dart run bin/metaflac.dart <command> [options] <file.flac>
```

### Modern subcommands

| Command | Description |
| --- | --- |
| `inspect <file>` | Display a FLAC metadata summary |
| `blocks list <file>` | List every metadata block in order |
| `tags list <file>` | List all Vorbis comment entries |
| `tags set <file> KEY=VALUE` | Set a tag (replaces existing values) |
| `tags add <file> KEY=VALUE` | Add a tag (allows duplicates) |
| `tags remove <file> KEY` | Remove all entries for a key |
| `tags clear <file>` | Remove every tag |
| `tags import <file> --from=tags.txt` | Import tags from a text file |
| `tags export <file> --output=tags.txt` | Export tags to a text file |
| `picture add <file> --file=cover.jpg` | Embed a picture |
| `picture remove <file> --all` | Remove every embedded picture |
| `picture export <file> --output=cover.jpg` | Extract a picture to disc |
| `padding set <file> 4096` | Rewrite with a padding block of N bytes |
| `padding remove <file>` | Strip all padding blocks |

### Compatibility flags

| Classic flag | Equivalent subcommand |
| --- | --- |
| `--list` | `blocks list` |
| `--show-md5` | `inspect` (MD5 field only) |
| `--set-tag=KEY=VALUE` | `tags set <file> KEY=VALUE` |
| `--remove-tag=KEY` | `tags remove <file> KEY` |
| `--remove-all-tags` | `tags clear` |
| `--export-tags-to=FILE` | `tags export --output=FILE` |
| `--import-tags-from=FILE` | `tags import --from=FILE` |
| `--export-picture-to=FILE` | `picture export --output=FILE` |
| `--import-picture-from=FILE` | `picture add --file=FILE` |

### Global options

| Option | Description |
| --- | --- |
| `--json` | Emit JSON output instead of human-readable text |
| `--dry-run` | Plan the write without touching the file |
| `--continue-on-error` | Skip broken files when processing multiple inputs |
| `--quiet`, `-q` | Suppress normal output |
| `--preserve-modtime` | Keep the original file modification time after a write |
| `--with-filename` | Prefix each line of output with its filename |

**Exit codes:** `0` success, `1` general error, `2` invalid arguments,
`3` invalid FLAC, `4` I/O error.

See the [CLI reference](src/docs/modules/ROOT/pages/cli-reference.adoc)
for the authoritative, always-up-to-date command matrix.

## Platform support

| Platform                  | `dart_metaflac.dart` | `io.dart` |
| ------------------------- | :------------------: | :-------: |
| Dart VM (standalone)      | yes                  | yes       |
| Flutter mobile (iOS / Android) | yes             | yes       |
| Flutter desktop           | yes                  | yes       |
| Flutter Web               | yes                  | no        |
| WASM / browser isolates   | yes                  | no        |

## Documentation

Full documentation lives in the Antora-based docs site under
[`src/docs/`](src/docs/). The canonical pages are written in AsciiDoc
and render on GitHub automatically:

- [Overview](src/docs/modules/ROOT/pages/index.adoc) — project overview, features, and platform support
- [Getting started](src/docs/modules/ROOT/pages/getting-started.adoc) — installation and first examples
- [Library guide](src/docs/modules/ROOT/pages/library-guide.adoc) — in-depth API usage
- [Architecture](src/docs/modules/ROOT/pages/architecture.adoc) — module structure and design decisions
- [CLI reference](src/docs/modules/ROOT/pages/cli-reference.adoc) — complete command reference
- [Audio integrity](src/docs/modules/ROOT/pages/audio-integrity.adoc) — how the library guarantees metadata edits never corrupt audio
- [Migration from `metaflac`](src/docs/modules/ROOT/pages/migration.adoc) — mapping reference `metaflac` commands to this library

To build the docs site locally:

```sh
npx antora local-antora-playbook.yml
# Output: target/public/
```

## Examples

Runnable examples are in [`example/`](example/):

- [`read_tags.dart`](example/read_tags.dart) — parse bytes and read tags
- [`set_tags.dart`](example/set_tags.dart) — edit tags in memory
- [`pictures.dart`](example/pictures.dart) — add and remove pictures
- [`streaming.dart`](example/streaming.dart) — stream-based transforms for large files
- [`web_in_memory.dart`](example/web_in_memory.dart) — full round-trip for Flutter Web / WASM
- [`file_rewrite.dart`](example/file_rewrite.dart) — file-based editing with `FlacFileEditor`
- [`flutter_example/`](example/flutter_example/) — minimal Flutter app using an asset bundle

## Licence

See [LICENCE](LICENCE) for details.
