# Migration Guide: metaflac → dart_metaflac

This guide maps commands from the reference `metaflac` CLI tool to their equivalents in `dart_metaflac`.

## CLI Flag Mapping

| metaflac Flag | dart_metaflac Subcommand | dart_metaflac Legacy Flag |
|---|---|---|
| `--list` | `blocks list` | `--list` |
| `--show-md5sum` | `inspect` | `--show-md5` |
| `--show-tag=FIELD` | `tags list --tag FIELD` | N/A |
| `--set-tag=FIELD=VALUE` | `tags set --tag FIELD=VALUE` | `--set-tag=FIELD=VALUE` |
| `--remove-tag=FIELD` | `tags remove --tag FIELD` | `--remove-tag=FIELD` |
| `--remove-all-tags` | `tags clear` | `--remove-all-tags` |
| `--export-tags-to=FILE` | `tags export --file FILE` | `--export-tags-to=FILE` |
| `--import-tags-from=FILE` | `tags import --file FILE` | `--import-tags-from=FILE` |
| `--export-picture-to=FILE` | `picture export --file FILE` | `--export-picture-to=FILE` |
| `--import-picture-from=FILE` | `picture add --file FILE` | `--import-picture-from=FILE` |
| `--preserve-modtime` | (global option) | `--preserve-modtime` |
| `--with-filename` | (global option) | `--with-filename` |
| `--no-utf8-convert` | (global option) | `--no-utf8-convert` |

## Dart API Equivalents

| metaflac Operation | Dart API |
|---|---|
| Show metadata blocks | `FlacMetadataDocument.readFromBytes(bytes).blocks` |
| Show MD5 | `doc.streamInfo.md5Signature` |
| Read a tag | `doc.vorbisComment?.comments.valuesOf('ARTIST')` |
| Set a tag | `doc.edit((e) => e.setTag('ARTIST', ['value']))` |
| Add a tag (multi-value) | `doc.edit((e) => e.addTag('GENRE', 'Rock'))` |
| Remove a tag | `doc.edit((e) => e.removeTag('COMMENT'))` |
| Remove specific value | `doc.edit((e) => e.removeExactTagValue('GENRE', 'Rock'))` |
| Clear all tags | `doc.edit((e) => e.clearTags())` |
| Export tags | Iterate `doc.vorbisComment?.comments.entries` |
| Import tags | Parse file, then `editor.setTag()`/`editor.addTag()` |
| Add picture | `doc.edit((e) => e.addPicture(pictureBlock))` |
| Remove picture by type | `doc.edit((e) => e.removePictureByType(PictureType.frontCover))` |
| Remove all pictures | `doc.edit((e) => e.removeAllPictures())` |
| File read/write | `FlacFileEditor.readFile(path)` / `FlacFileEditor.updateFile(path, mutations: [...])` |

## Usage Examples

### Reading tags

**metaflac:**
```bash
metaflac --show-tag=ARTIST song.flac
```

**dart_metaflac CLI:**
```bash
dart run bin/metaflac.dart tags list --tag ARTIST song.flac
```

**dart_metaflac Dart API:**
```dart
final doc = FlacMetadataDocument.readFromBytes(bytes);
final artists = doc.vorbisComment?.comments.valuesOf('ARTIST');
print(artists); // ['Artist Name']
```

### Setting tags

**metaflac:**
```bash
metaflac --set-tag=ARTIST=NewArtist song.flac
```

**dart_metaflac CLI:**
```bash
dart run bin/metaflac.dart tags set --tag ARTIST=NewArtist song.flac
```

**dart_metaflac Dart API:**
```dart
final updated = doc.edit((editor) {
  editor.setTag('ARTIST', ['NewArtist']);
});
final newBytes = updated.toBytes();
```

### Exporting tags

**metaflac:**
```bash
metaflac --export-tags-to=tags.txt song.flac
```

**dart_metaflac CLI:**
```bash
dart run bin/metaflac.dart tags export --file tags.txt song.flac
```

### Adding a picture

**metaflac:**
```bash
metaflac --import-picture-from=cover.jpg song.flac
```

**dart_metaflac CLI:**
```bash
dart run bin/metaflac.dart picture add --file cover.jpg song.flac
```

## Known Differences

1. **Vorbis comment keys** — `dart_metaflac` preserves the original case of keys when stored, but all lookups are case-insensitive (per the Vorbis specification). The reference `metaflac` also follows this behaviour.

2. **Multiple values** — `setTag` in `dart_metaflac` replaces *all* values for a key. Use `addTag` to append without removing existing values. The reference `metaflac` `--set-tag` appends by default.

3. **Picture import** — `dart_metaflac` uses `picture add --file` rather than the `--import-picture-from` specification format that encodes type, MIME, description, and dimensions in the filename. When using the legacy `--import-picture-from` flag, the behaviour matches the reference tool.

4. **Output format** — `dart_metaflac` supports `--json` for structured output, which the reference `metaflac` does not.

5. **Batch processing** — `dart_metaflac` supports `--continue-on-error` for processing multiple files, continuing even if one file fails.

6. **Dry run** — `dart_metaflac` supports `--dry-run` to preview changes without writing, which the reference `metaflac` does not.

7. **Padding** — `dart_metaflac` provides explicit padding management via `padding set` and `padding remove` subcommands. The reference `metaflac` has `--add-padding` and `--remove` but with different semantics.
