# dart_metaflac

A pure Dart library for reading and writing FLAC audio metadata. No `dart:io` dependency in the core — works with Dart, Flutter, and web applications.

## Features

- **Parse** FLAC metadata from bytes or streams
- **Read** Vorbis comments, stream info, pictures, padding, and all block types
- **Edit** tags, pictures, and padding with an immutable document model
- **Transform** FLAC files in-memory or via memory-efficient streaming
- **File I/O** with atomic writes (temp file + rename) for safe updates
- **CLI tool** with modern subcommands and `metaflac`-compatible flags
- **Round-trip safe** — unknown block types are preserved as-is

## Installation

```bash
dart pub add dart_metaflac
```

Or add to your `pubspec.yaml`:

```yaml
dependencies:
  dart_metaflac: ^0.1.0
```

## Quick Start

### Reading Metadata

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

// From bytes (works everywhere, including Flutter Web)
final doc = FlacMetadataDocument.readFromBytes(flacBytes);

// Stream info
final info = doc.streamInfo;
print('Sample rate: ${info.sampleRate}');
print('Channels: ${info.channelCount}');

// Vorbis comments
final comments = doc.vorbisComment?.comments;
print('Artist: ${comments?.valuesOf('ARTIST')}');
print('Title: ${comments?.valuesOf('TITLE')}');
```

### Editing Tags

```dart
final updated = doc.edit((editor) {
  editor.setTag('ARTIST', ['New Artist']);
  editor.setTag('ALBUM', ['New Album']);
  editor.addTag('GENRE', 'Rock');
  editor.removeTag('COMMENT');
});
final newBytes = updated.toBytes();
```

### Adding a Picture

```dart
import 'dart:typed_data';

final updated = doc.edit((editor) {
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

### Streaming Transform

```dart
final transformer = FlacTransformer.fromBytes(flacBytes);
final result = await transformer.transform(
  mutations: [SetTag('ARTIST', ['Streamed Artist'])],
);
print('Bytes changed: ${result.bytes.length}');
```

### File-Based Editing (dart:io)

```dart
import 'package:dart_metaflac/dart_metaflac.dart';

final doc = await FlacFileEditor.readFile('song.flac');
await FlacFileEditor.updateFile(
  'song.flac',
  mutations: [SetTag('TITLE', ['Updated'])],
);
```

## CLI Usage

The CLI supports both modern subcommands and `metaflac`-compatible flags.

```bash
# Run via dart
dart run bin/metaflac.dart <command> [options] <file.flac>
```

### Modern Subcommands

| Command | Description |
|---------|-------------|
| `inspect` | Display FLAC metadata summary |
| `blocks list` | List all metadata blocks |
| `tags list` | List all Vorbis comments |
| `tags set --tag KEY=VALUE` | Set a tag value |
| `tags add --tag KEY=VALUE` | Add a tag (allows duplicates) |
| `tags remove --tag KEY` | Remove a tag by key |
| `tags clear` | Remove all tags |
| `tags import --file tags.txt` | Import tags from file |
| `tags export --file tags.txt` | Export tags to file |
| `picture add --file cover.jpg` | Add a picture |
| `picture remove --type front-cover` | Remove pictures by type |
| `picture export --file cover.jpg` | Export a picture |
| `padding set --size 4096` | Set padding size |
| `padding remove` | Remove all padding |

### Compatibility Flags

| Flag | Equivalent Subcommand |
|------|----------------------|
| `--list` | `blocks list` |
| `--show-md5` | `inspect` (MD5 field) |
| `--set-tag=KEY=VALUE` | `tags set --tag KEY=VALUE` |
| `--remove-tag=KEY` | `tags remove --tag KEY` |
| `--remove-all-tags` | `tags clear` |
| `--export-tags-to=FILE` | `tags export --file FILE` |
| `--import-tags-from=FILE` | `tags import --file FILE` |
| `--export-picture-to=FILE` | `picture export --file FILE` |
| `--import-picture-from=FILE` | `picture add --file FILE` |

### Global Options

| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format |
| `--dry-run` | Show changes without writing |
| `--continue-on-error` | Continue processing on error |
| `--quiet`, `-q` | Suppress normal output |
| `--preserve-modtime` | Preserve file modification time |
| `--with-filename` | Print filename with output |

**Exit codes:** 0 (success), 1 (general error), 2 (invalid arguments), 3 (invalid FLAC), 4 (I/O error).

## Architecture

The library is organised into layered modules:

- **model** — Immutable domain objects (`FlacMetadataDocument`, `VorbisComments`, `StreamInfoBlock`, `PictureBlock`, etc.)
- **binary** — Low-level parsing and serialisation (`FlacParser`, `FlacSerializer`)
- **edit** — Mutation operations (`FlacMetadataEditor`, `MetadataMutation`)
- **transform** — Transform planning and streaming (`FlacTransformer`)
- **api** — High-level convenience functions (`readFlacMetadata`, `applyMutations`, `transformFlac`)
- **io** — File persistence with `dart:io` (`FlacFileEditor`, `AtomicWriter`)

See [doc/MIGRATION.md](doc/MIGRATION.md) for a guide on migrating from the reference `metaflac` tool.

## Licence

See [LICENCE](LICENCE) for details.
