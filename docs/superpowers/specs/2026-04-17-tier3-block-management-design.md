# Tier 3 metaflac parity: block remove/append and block-selection filters

**Status:** approved, ready for implementation plan
**Issue:** [#15](https://github.com/bovinemagnet/dart-metaflac/issues/15)
**Date:** 2026-04-17

## Summary

Add generic block management to `dart_metaflac` matching the third tier of upstream `metaflac` parity: removal of metadata blocks by type or index, removal of all non-STREAMINFO blocks, and appending raw metadata blocks from a file. Adds three block-selection filter flags (`--block-number`, `--block-type`, `--except-block-type`) that apply to both listing and removing blocks.

## Goals

- Users can remove specific metadata blocks from a FLAC file without editing individual tag or picture APIs.
- Users can strip a FLAC down to STREAMINFO only.
- Users can inject a pre-serialised metadata block (e.g. a binary seek table produced by another tool).
- Block-selection filters work uniformly on `blocks list` output and `blocks remove`.
- STREAMINFO (block 0) is never removable, matching the FLAC specification.

## Non-goals

- Parsing or validating the contents of an appended raw block — it travels through the existing `UnknownBlock` carrier regardless of declared type.
- Supporting block selection on write commands other than `blocks remove` in this milestone (tags/picture/padding remain targeted operations).
- Interactive or wildcard selectors beyond comma-separated lists.

## Mutation types

New entries in `lib/src/edit/mutation_ops.dart`:

```dart
final class RemoveBlocksByType extends MetadataMutation {
  const RemoveBlocksByType(this.types);
  final Set<FlacBlockType> types;
}

final class RemoveBlocksByNumber extends MetadataMutation {
  const RemoveBlocksByNumber(this.indices);
  final Set<int> indices;  // 0-based; index 0 (STREAMINFO) silently skipped
}

final class RemoveAllNonStreamInfo extends MetadataMutation {
  const RemoveAllNonStreamInfo();
}

final class AppendRawBlock extends MetadataMutation {
  const AppendRawBlock({
    required this.type,
    required this.payload,
    this.afterIndex,
  });
  final FlacBlockType type;
  final Uint8List payload;
  final int? afterIndex;  // null -> append at end (before any trailing PADDING)
}
```

### STREAMINFO handling

- `RemoveBlocksByType` — throws `FlacMetadataException` at editor build time if `FlacBlockType.streamInfo` is included. This is a user error: naming the mandatory block explicitly.
- `RemoveBlocksByNumber` — silently skips index 0. Upstream metaflac does not fail when a selection happens to include STREAMINFO.
- `RemoveAllNonStreamInfo` — by definition retains STREAMINFO.

### `AppendRawBlock` carrier

The incoming bytes are wrapped in an `UnknownBlock` with `rawTypeCode = type.code` and `rawPayload = payload`. The existing serialiser writes `UnknownBlock` using its `rawTypeCode`, so a known type code is preserved byte-for-byte. Consumers who later read the file will re-parse the block according to its type code — if the bytes are well-formed they get a typed block, otherwise they get an `UnknownBlock`.

`afterIndex` semantics:
- `null` — append at the tail, before any trailing `PaddingBlock`. If no padding, at the very end.
- `0` — insert immediately after STREAMINFO.
- `n > 0` — insert after the block currently at index `n`. If `n >= blocks.length`, append at the tail.

## Editor API

Thin wrappers on `FlacMetadataEditor`:

```dart
void removeBlocksByType(Set<FlacBlockType> types);
void removeBlocksByNumber(Set<int> indices);
void removeAllNonStreamInfo();
void appendRawBlock(FlacBlockType type, Uint8List payload, {int? afterIndex});
```

## CLI

### New subcommands

In `lib/src/cli/commands/blocks_command.dart`:

- `blocks remove` — requires at least one of `--block-type`, `--block-number`, `--except-block-type`. Supports `--dont-use-padding` (forces full rewrite). Multiple files supported via positional args.
- `blocks remove-all` — strips every non-STREAMINFO block. No selection flags. Accepts `--dont-use-padding`.
- `blocks append` — `--type=NAME` (required), `--from-file=PATH` (required), optional `--after=N`. Mirrors `picture add` for path handling.

### `blocks list` filters

The same three selection flags become display filters on `blocks list`:
- `--block-type=NAME[,NAME…]`
- `--except-block-type=NAME[,NAME…]`
- `--block-number=N[,N…]`

Block indices in `blocks list` output remain the original 0-based indices in the document (not renumbered after filtering), so users can feed them back into `--block-number`.

### Selection flag parsing

- Comma-separated, case-insensitive for type names: `STREAMINFO`, `PADDING`, `APPLICATION`, `SEEKTABLE`, `VORBIS_COMMENT`, `PICTURE`.
- Unknown type names raise `UsageException` with the accepted list.
- Conflicting `--block-type` and `--except-block-type` on the same invocation is an error.
- `--block-number` may be combined with either `--block-type` or `--except-block-type`; the union of their matches is the selection set.

### Decision D1 — per-command, not global

The selection flags are scoped to `blocks list` and `blocks remove`, where they make sense. Adding them to `BaseFlacCommand` would expose them on `tags`, `picture`, `padding`, `inspect`, where they are meaningless. This matches the current codebase style (each command owns its options).

### Decision D3 — empty selection is an error

`blocks remove` with no selector flags emits a `UsageException` (exit 2). Upstream metaflac requires a selector; silently doing nothing is a worse default than a loud error.

## Legacy flags in `bin/metaflac.dart`

Add to the top-level `ArgParser`:
- `--remove` (flag) — enables remove mode; combine with selection flags below.
- `--remove-all` (flag) — shortcut for `blocks remove-all`.
- `--append` (option, takes a path) — reads a binary block from the given file.
- `--block-number=#[,#…]`
- `--block-type=TYPE[,TYPE…]`
- `--except-block-type=TYPE[,TYPE…]`

When `--list` is combined with selection flags, output is filtered identically to `blocks list`. When `--remove` is set, selection flags determine the target. `--dont-use-padding` already exists and applies naturally.

## Tests

New test file `test/tier3_blocks_test.dart`:
- Each mutation type exercised with the existing `buildFlacFixture()`.
- `RemoveBlocksByType({streamInfo})` throws.
- `RemoveBlocksByNumber({0})` is a no-op (silent skip) — not an error.
- `RemoveAllNonStreamInfo` leaves only STREAMINFO.
- `AppendRawBlock` round-trips byte-for-byte through the serialiser/parser.
- `AppendRawBlock(afterIndex: null)` inserts before trailing padding, not after.

Additions to existing tests:
- `cli_subcommands_test.dart` — `blocks remove --block-type=PICTURE`, `blocks remove-all`, `blocks append`, and filter behaviour on `blocks list`.
- `metaflac_parity_test.dart` — legacy `--remove`, `--remove-all`, `--append`, `--list --block-type`.

## Risks

- **Selection flag parsing divergence.** Upstream metaflac accepts `STREAMINFO` etc. case-sensitively in some versions. We normalise to upper-case to be forgiving. Worth a comment.
- **`afterIndex` interacting with padding-aware writes.** Inserting after a PADDING block produces an odd layout. The implementation always inserts before any trailing PADDING when `afterIndex` is null; an explicit `afterIndex` that lands after padding is respected (user's call).
- **Legacy `--list` filter semantics.** Combining `--list` with `--block-type` is new behaviour that previously was a silent no-op. Covered by tests.

## Out of scope (future tiers)

- `--add-seekpoint`, `--add-replay-gain`, `--scan-replay-gain`.
- Rich APPLICATION block handling (currently round-trips as-is).
- CUESHEET-specific editing commands.
