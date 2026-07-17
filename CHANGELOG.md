## 0.0.3

### Library additions

- `FlacMetadataDocument.pictureByType(PictureType)` — look up the first
  picture of a given type, or `null` if none.
- `FlacMetadataDocument.frontCoverPicture` and `backCoverPicture` —
  convenience getters returning the first matching cover picture.
- `FlacMetadataEditor.setFrontCover(PictureBlock)` and
  `setBackCover(PictureBlock)` — upsert semantics: remove any existing
  cover of the same type, then append the new block.

### Fixed

- Parse FLAC files that carry a non-standard prepended ID3v2 tag,
  matching libFLAC: the tag is skipped when locating the `fLaC`
  marker and exposed as `FlacMetadataDocument.id3v2PrefixLength`.
  Every write path — `toBytes()`, `transformFlac`,
  `FlacTransformer.transform`/`transformStream`, `applyMutations`,
  and file/CLI writes — writes the prefix back byte-for-byte so
  round-trips never corrupt such files. Previously these files
  failed with `InvalidFlacException: Invalid FLAC marker`.
- Preserve the original casing of Vorbis comment keys when parsing,
  matching the reference metaflac. Keys are still matched
  case-insensitively, but mixed-case keys written by other taggers
  (e.g. `AccurateRipResult=...`) now round-trip byte-for-byte
  instead of being rewritten in upper case.
- Compat CLI failures no longer exit 0 (#28): `--export-picture-to`
  with no picture present exits 1, and a malformed `--set-tag` or
  `--set-tag-from-file` spec exits 2 before the file is touched. A
  write invocation that produces no mutations leaves the file alone
  instead of rewriting it unchanged.
- `--import-tags-from=-` (and `tags import --from -`) reads from
  stdin (#29), matching real metaflac and this tool's own export
  side, so `export | import` pipelines work.
- `--export-tags-to=-` no longer emits an extra trailing blank line,
  so stdout output is byte-identical to file output (#30).
- Vorbis comment entries without a `=` separator are preserved
  verbatim on round-trip instead of being silently dropped; they are
  exposed with `VorbisCommentEntry.hasSeparator == false` (#30).
- The parser rejects blocks whose inner length fields overrun the
  declared block length with `MalformedMetadataException` instead of
  silently misparsing subsequent data (#30).
- Public list fields (`FlacMetadataDocument.blocks`,
  `FlacTransformPlan.originalBlocks`/`transformedBlocks`,
  `VorbisComments.entries`, `SeekTableBlock.points`,
  `CueSheetBlock.tracks`) are now unmodifiable, so in-place mutation
  of an "immutable" document throws instead of corrupting it (#30).
  As a consequence these constructors are no longer `const`.
- Corrected the `WriteMode.inPlaceIfPossible` doc (it throws
  `WriteConflictException` when metadata does not fit, rather than
  falling back), fixed the non-compiling `lib/io.dart` usage example,
  and removed the dead `PaddingStrategy.defaultPadding` constant
  (#30).

## 0.0.2

metaflac CLI parity, Tiers 1 and 2 of the parity effort. Additive —
no existing public API is renamed or removed.

### New CLI flags (metaflac-compatible)

STREAMINFO scalar show-ops (one raw value per invocation, for shell
scripting):

- `--show-md5sum` (alias for `--show-md5`)
- `--show-min-blocksize`, `--show-max-blocksize`
- `--show-min-framesize`, `--show-max-framesize`
- `--show-sample-rate`, `--show-channels`, `--show-bps`
- `--show-total-samples`

Vorbis comment show-ops:

- `--show-vendor-tag`
- `--show-tag=NAME` (filter by field name)
- `--show-all-tags`

Global options and output redirection:

- `-o` / `--output-name=FILE` (write to a new file, leave input intact)
- `--no-filename` (suppress filename prefix even with multiple inputs)
- `--no-utf8-convert` (accepted as a no-op — Dart strings are always UTF-8)
- `--dont-use-padding` (force a full rewrite by disabling padding reuse)

Tag cleanup:

- `--remove-replay-gain` (drops the five standard REPLAYGAIN_* fields)
- `--remove-first-tag=FIELD` (new `RemoveFirstTag` mutation — drops only
  the first matching entry, preserves subsequent duplicates)
- `--remove-all-tags-except=NAME1[=NAME2[=…]]` (new `ClearTagsExcept`
  mutation — retains only the named fields, using metaflac's `=`
  separator convention)
- `--set-tag-from-file=FIELD=FILE` (reads the tag value from a file)

### Library additions

- `VorbisComments.removeFirst(String key)` — removes only the first
  matching entry (case-insensitive).
- `VorbisComments.clearExcept(Set<String> keepKeys)` — retains only
  the entries whose key is in the given set.
- `RemoveFirstTag` and `ClearTagsExcept` added to the sealed
  `MetadataMutation` hierarchy with corresponding `FlacMetadataEditor`
  switch arms.

### Intentional non-goals

`--add-replay-gain` and `--scan-replay-gain` remain permanently out of
scope: they require decoding PCM audio frames, which a metadata-only
library cannot and should not do. See the project's GitHub issue tracker
for the full reasoning.

### Tests

- New `test/metaflac_parity_test.dart` with 20 integration tests covering
  every new legacy flag end-to-end against subprocess CLI invocations.

## 0.0.1

Initial public release.

- Pure-Dart FLAC metadata parser with no `dart:io` dependency in the core
  library. Works on the standalone Dart VM, Flutter (including Flutter
  Web and WASM), server isolates, and browser targets.
- Two public library entry points:
  - `package:dart_metaflac/dart_metaflac.dart` — core, pure Dart.
  - `package:dart_metaflac/io.dart` — file/IO adapters, requires
    `dart:io` (not available on Flutter Web).
- Complete support for every standard FLAC metadata block type
  (STREAMINFO, PADDING, APPLICATION, SEEKTABLE, VORBIS_COMMENT,
  CUESHEET, PICTURE). Unknown block types are preserved byte-for-byte
  on round-trip.
- Immutable document model with an editor-callback API for in-memory
  edits (`doc.edit((editor) => ...)`) and a `MetadataMutation` list
  API for file-based edits (`FlacFileEditor.updateFile`).
- Streaming transform API that never buffers audio data, so multi-gigabyte
  FLAC files can be edited in constant memory.
- File persistence via `FlacFileEditor` with safe atomic writes
  (temp file + rename), multiple write modes (`safeAtomic`, `auto`,
  `inPlaceIfPossible`, `outputToNewFile`), and optional modification-time
  preservation.
- `metaflac`-compatible CLI tool at `bin/metaflac.dart` supporting both
  modern subcommands (`inspect`, `blocks list`, `tags`, `picture`,
  `padding`) and classic `--flag` aliases (`--list`, `--set-tag`,
  `--export-tags-to`, etc). Global options include `--json`, `--dry-run`,
  `--continue-on-error`, `--quiet`, `--preserve-modtime`, and
  `--with-filename`. Exit codes follow the metaflac convention.
- Typed exception hierarchy rooted at `FlacMetadataException`.
- Runnable examples for reading, editing, pictures, streaming, file
  rewriting, Flutter Web / WASM in-memory round-trips, and a minimal
  Flutter app.
- Antora documentation site under `src/docs/` with getting-started,
  library guide, architecture, CLI reference, audio integrity, and
  migration guide.
- 258 tests covering parsing, serialisation, editing, transforms,
  streaming, file IO, CLI, and both synthetic and on-disc fixtures.
