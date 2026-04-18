# Tier 3 Block Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add metaflac Tier 3 parity — generic block removal (`--remove`, `--remove-all`), block appending from a file (`--append`), and the three block-selection filter flags (`--block-type`, `--except-block-type`, `--block-number`) wired into both listing and removal.

**Architecture:** Four new sealed `MetadataMutation` subclasses drive all block-level editing. Thin `FlacMetadataEditor` wrappers expose them. Three new CLI subcommands (`blocks remove`, `blocks remove-all`, `blocks append`) and block-selection filter flags on `blocks list`. Legacy flags in `bin/metaflac.dart` mirror upstream metaflac.

**Tech Stack:** Dart 3, `package:args` (CommandRunner), `package:test`. No external dependencies added.

---

## File structure

**Modify:**
- `lib/src/binary/flac_serializer.dart` — preserve `UnknownBlock.rawTypeCode` on write (bug fix, prerequisite).
- `lib/src/edit/mutation_ops.dart` — add four mutation classes.
- `lib/src/edit/flac_metadata_editor.dart` — editor methods + `_applyToBlocks` branches.
- `lib/src/cli/commands/blocks_command.dart` — new subcommands + list filters.
- `bin/metaflac.dart` — legacy flag aliases.

**Create:**
- `test/tier3_blocks_test.dart` — mutation-level tests.

**Modify tests:**
- `test/cli_subcommands_test.dart` — subcommand tests.
- `test/metaflac_parity_test.dart` — legacy flag tests.

---

### Task 1: Fix `UnknownBlock` type-code round-trip (prerequisite)

The serialiser currently writes every `UnknownBlock` with header byte `0x7F` (`FlacBlockType.unknown.code`) rather than the preserved `rawTypeCode`. `AppendRawBlock` depends on this round-trip working.

**Files:**
- Modify: `lib/src/binary/flac_serializer.dart:50-57`
- Test: `test/tier3_blocks_test.dart` (new file — this task creates it)

- [ ] **Step 1: Write the failing test**

Create `test/tier3_blocks_test.dart` with:

```dart
import 'dart:typed_data';

import 'package:dart_metaflac/dart_metaflac.dart';
import 'package:test/test.dart';

/// Builds a minimal FLAC containing STREAMINFO + one raw SEEKTABLE-typed
/// block (carried as UnknownBlock-shaped raw bytes) + fake audio.
Uint8List _buildFlacWithRawBlock({
  required int typeCode,
  required Uint8List payload,
}) {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0;
  siData[13] = (15 << 4);

  final out = BytesBuilder()
    ..addByte(0x66)
    ..addByte(0x4C)
    ..addByte(0x61)
    ..addByte(0x43)
    // STREAMINFO
    ..addByte(0x00)
    ..addByte(0)
    ..addByte(0)
    ..addByte(34)
    ..add(siData)
    // Raw block with requested typeCode, last block
    ..addByte(0x80 | (typeCode & 0x7F))
    ..addByte((payload.length >> 16) & 0xFF)
    ..addByte((payload.length >> 8) & 0xFF)
    ..addByte(payload.length & 0xFF)
    ..add(payload)
    // Fake audio
    ..addByte(0xFF)
    ..addByte(0xF8)
    ..add(Uint8List(16));
  return out.toBytes();
}

void main() {
  group('UnknownBlock round-trip preserves rawTypeCode', () {
    test('type code 42 survives parse -> serialise -> parse', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final bytes = _buildFlacWithRawBlock(typeCode: 42, payload: payload);

      final doc = FlacParser.parseBytes(bytes);
      final unknown = doc.blocks.whereType<UnknownBlock>().single;
      expect(unknown.rawTypeCode, 42);

      final roundTripped = FlacSerializer.serialize(
        doc.blocks,
        bytes.sublist(doc.audioDataOffset),
      );
      final reparsed = FlacParser.parseBytes(roundTripped);
      final unknown2 = reparsed.blocks.whereType<UnknownBlock>().single;
      expect(unknown2.rawTypeCode, 42,
          reason: 'rawTypeCode must survive serialisation round-trip');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/tier3_blocks_test.dart`
Expected: FAIL on `expect(unknown2.rawTypeCode, 42)` — the reparsed value will be 127 because the serialiser writes `FlacBlockType.unknown.code`.

- [ ] **Step 3: Fix the serialiser**

In `lib/src/binary/flac_serializer.dart`, update `_serializeBlocks` to use `rawTypeCode` for `UnknownBlock` instances. Add the import at the top of the file:

```dart
import '../model/unknown_block.dart';
```

Then replace lines 49-57 (the inner loop) with:

```dart
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isLast = i == blocks.length - 1;
      final payload = block.toPayloadBytes();
      final rawCode = block is UnknownBlock ? block.rawTypeCode : block.type.code;
      final typeByte = rawCode & 0x7F;
      writer.writeUint8(isLast ? (0x80 | typeByte) : typeByte);
      writer.writeUint24(payload.length);
      writer.writeBytes(payload);
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/tier3_blocks_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full test suite to confirm no regressions**

Run: `dart test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/binary/flac_serializer.dart test/tier3_blocks_test.dart
git commit -m "fix: preserve UnknownBlock rawTypeCode through serialisation"
```

---

### Task 2: Add `RemoveBlocksByType` mutation

**Files:**
- Modify: `lib/src/edit/mutation_ops.dart` (add class at end)
- Modify: `lib/src/edit/flac_metadata_editor.dart` (add editor method + switch branch + imports)
- Test: `test/tier3_blocks_test.dart` (append tests)

- [ ] **Step 1: Write the failing tests**

Append to `test/tier3_blocks_test.dart`:

```dart
  group('RemoveBlocksByType', () {
    test('removes all PICTURE blocks', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) =>
          e.removeBlocksByType({FlacBlockType.picture}));
      expect(updated.blocks.whereType<PictureBlock>(), isEmpty);
      expect(updated.blocks.whereType<StreamInfoBlock>().length, 1);
    });

    test('removes multiple types at once', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) => e.removeBlocksByType(
            {FlacBlockType.picture, FlacBlockType.vorbisComment},
          ));
      expect(updated.blocks.whereType<PictureBlock>(), isEmpty);
      expect(updated.blocks.whereType<VorbisCommentBlock>(), isEmpty);
    });

    test('throws when STREAMINFO is included', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      expect(
        () => doc.edit((e) =>
            e.removeBlocksByType({FlacBlockType.streamInfo})),
        throwsA(isA<FlacMetadataException>()),
      );
    });

    test('empty set is a no-op', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final original = doc.blocks.length;
      final updated = doc.edit((e) => e.removeBlocksByType({}));
      expect(updated.blocks.length, original);
    });
  });
```

Add the shared fixture helper near the top of `test/tier3_blocks_test.dart`, below `_buildFlacWithRawBlock`:

```dart
Uint8List _fixture({int paddingSize = 512}) {
  final siData = Uint8List(34);
  siData[10] = (44100 >> 12) & 0xFF;
  siData[11] = (44100 >> 4) & 0xFF;
  siData[12] = ((44100 & 0xF) << 4) | (1 << 1) | 0;
  siData[13] = (15 << 4);

  final vc = VorbisCommentBlock(
    comments: VorbisComments(
      vendorString: 'fixture_vendor',
      entries: [
        VorbisCommentEntry(key: 'TITLE', value: 'Original Title'),
      ],
    ),
  );
  final vcData = vc.toPayloadBytes();

  final pic = PictureBlock(
    pictureType: PictureType.frontCover,
    mimeType: 'image/jpeg',
    description: 'Cover',
    width: 300,
    height: 300,
    colorDepth: 24,
    indexedColors: 0,
    data: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]),
  );
  final picData = pic.toPayloadBytes();

  final out = BytesBuilder()
    ..addByte(0x66)
    ..addByte(0x4C)
    ..addByte(0x61)
    ..addByte(0x43)
    // STREAMINFO
    ..addByte(0x00)
    ..addByte(0)
    ..addByte(0)
    ..addByte(34)
    ..add(siData)
    // VORBIS_COMMENT
    ..addByte(0x04)
    ..addByte((vcData.length >> 16) & 0xFF)
    ..addByte((vcData.length >> 8) & 0xFF)
    ..addByte(vcData.length & 0xFF)
    ..add(vcData)
    // PICTURE
    ..addByte(0x06)
    ..addByte((picData.length >> 16) & 0xFF)
    ..addByte((picData.length >> 8) & 0xFF)
    ..addByte(picData.length & 0xFF)
    ..add(picData)
    // PADDING (last)
    ..addByte(0x80 | 0x01)
    ..addByte((paddingSize >> 16) & 0xFF)
    ..addByte((paddingSize >> 8) & 0xFF)
    ..addByte(paddingSize & 0xFF)
    ..add(Uint8List(paddingSize))
    // Fake audio
    ..addByte(0xFF)
    ..addByte(0xF8)
    ..add(Uint8List(128));
  return out.toBytes();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/tier3_blocks_test.dart`
Expected: FAIL — `removeBlocksByType` does not exist on `FlacMetadataEditor`.

- [ ] **Step 3: Add the mutation class**

Append to `lib/src/edit/mutation_ops.dart`, after the existing imports add:

```dart
import 'flac_block_type.dart';
```

Wait — `FlacBlockType` lives in `../model/flac_block_type.dart`. Look at the existing imports at top of `mutation_ops.dart`:

```dart
import '../model/picture_block.dart';
import '../model/picture_type.dart';
```

Add:

```dart
import '../model/flac_block_type.dart';
```

Then append at the end of the file:

```dart
/// Remove every metadata block whose [FlacBlockType] is in [types].
///
/// STREAMINFO (type 0) is mandatory per the FLAC specification. Including
/// [FlacBlockType.streamInfo] in [types] is a programmer error: the editor
/// throws [FlacMetadataException] at build time.
///
/// Unknown types (type code outside 0–6) may be targeted by including
/// [FlacBlockType.unknown], which removes all blocks that the parser could
/// not classify.
final class RemoveBlocksByType extends MetadataMutation {
  /// Create a mutation that removes blocks whose type is in [types].
  const RemoveBlocksByType(this.types);

  /// The set of block types to remove.
  final Set<FlacBlockType> types;
}
```

- [ ] **Step 4: Add editor method + branch**

In `lib/src/edit/flac_metadata_editor.dart`, add to imports (top of file):

```dart
import '../error/exceptions.dart';
import '../model/flac_block_type.dart';
```

Then, before `void applyMutation(...)`, add:

```dart
  /// Remove all blocks whose type is in [types].
  ///
  /// Enqueues a [RemoveBlocksByType] mutation. STREAMINFO cannot be
  /// removed — passing [FlacBlockType.streamInfo] causes
  /// [FlacMetadataException] at [build] time.
  void removeBlocksByType(Set<FlacBlockType> types) =>
      _mutations.add(RemoveBlocksByType(types));
```

Add a case to the `switch (mutation)` in `_applyToBlocks`:

```dart
      case RemoveBlocksByType m:
        if (m.types.contains(FlacBlockType.streamInfo)) {
          throw FlacMetadataException(
            'Cannot remove STREAMINFO block — it is mandatory per the '
            'FLAC specification.',
          );
        }
        if (m.types.isEmpty) return blocks;
        return blocks.where((b) => !m.types.contains(b.type)).toList();
```

- [ ] **Step 5: Run the tests**

Run: `dart test test/tier3_blocks_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/edit/mutation_ops.dart lib/src/edit/flac_metadata_editor.dart test/tier3_blocks_test.dart
git commit -m "feat: add RemoveBlocksByType mutation (#15)"
```

---

### Task 3: Add `RemoveBlocksByNumber` mutation

**Files:**
- Modify: `lib/src/edit/mutation_ops.dart`
- Modify: `lib/src/edit/flac_metadata_editor.dart`
- Test: `test/tier3_blocks_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `test/tier3_blocks_test.dart`:

```dart
  group('RemoveBlocksByNumber', () {
    test('removes blocks at the given indices', () {
      // Fixture layout: 0=STREAMINFO, 1=VORBIS_COMMENT, 2=PICTURE, 3=PADDING
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) =>
          e.removeBlocksByNumber({2}));
      expect(updated.blocks.whereType<PictureBlock>(), isEmpty);
      expect(updated.blocks.whereType<VorbisCommentBlock>().length, 1);
    });

    test('index 0 (STREAMINFO) is silently skipped', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final originalLen = doc.blocks.length;
      final updated = doc.edit((e) =>
          e.removeBlocksByNumber({0}));
      expect(updated.blocks.length, originalLen);
      expect(updated.blocks.whereType<StreamInfoBlock>().length, 1);
    });

    test('out-of-range indices are ignored', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final originalLen = doc.blocks.length;
      final updated = doc.edit((e) =>
          e.removeBlocksByNumber({99}));
      expect(updated.blocks.length, originalLen);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/tier3_blocks_test.dart -n RemoveBlocksByNumber`
Expected: FAIL — `removeBlocksByNumber` not defined.

- [ ] **Step 3: Add the mutation class**

Append to `lib/src/edit/mutation_ops.dart`:

```dart
/// Remove metadata blocks at the given 0-based [indices].
///
/// Index 0 always refers to STREAMINFO which cannot be removed; if 0 is
/// present in [indices] it is silently skipped. Indices outside the range
/// of existing blocks are ignored.
final class RemoveBlocksByNumber extends MetadataMutation {
  /// Create a mutation that removes blocks at [indices].
  const RemoveBlocksByNumber(this.indices);

  /// The set of 0-based block indices to remove.
  final Set<int> indices;
}
```

- [ ] **Step 4: Add editor method + branch**

In `lib/src/edit/flac_metadata_editor.dart`, add before `applyMutation`:

```dart
  /// Remove blocks at the given 0-based [indices].
  ///
  /// Enqueues a [RemoveBlocksByNumber] mutation. Index 0 (STREAMINFO) is
  /// silently skipped; out-of-range indices are ignored.
  void removeBlocksByNumber(Set<int> indices) =>
      _mutations.add(RemoveBlocksByNumber(indices));
```

Add the switch branch:

```dart
      case RemoveBlocksByNumber m:
        final toKeep = <FlacMetadataBlock>[];
        for (var i = 0; i < blocks.length; i++) {
          if (i == 0 || !m.indices.contains(i)) {
            toKeep.add(blocks[i]);
          }
        }
        return toKeep;
```

- [ ] **Step 5: Run the tests**

Run: `dart test test/tier3_blocks_test.dart -n RemoveBlocksByNumber`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/edit/mutation_ops.dart lib/src/edit/flac_metadata_editor.dart test/tier3_blocks_test.dart
git commit -m "feat: add RemoveBlocksByNumber mutation (#15)"
```

---

### Task 4: Add `RemoveAllNonStreamInfo` mutation

**Files:**
- Modify: `lib/src/edit/mutation_ops.dart`
- Modify: `lib/src/edit/flac_metadata_editor.dart`
- Test: `test/tier3_blocks_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/tier3_blocks_test.dart`:

```dart
  group('RemoveAllNonStreamInfo', () {
    test('leaves only STREAMINFO', () {
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) => e.removeAllNonStreamInfo());
      expect(updated.blocks.length, 1);
      expect(updated.blocks.single, isA<StreamInfoBlock>());
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/tier3_blocks_test.dart -n RemoveAllNonStreamInfo`
Expected: FAIL — `removeAllNonStreamInfo` not defined.

- [ ] **Step 3: Add the mutation class**

Append to `lib/src/edit/mutation_ops.dart`:

```dart
/// Remove every metadata block except STREAMINFO.
///
/// Convenience for the upstream `metaflac --remove-all` flag.
final class RemoveAllNonStreamInfo extends MetadataMutation {
  /// Create a mutation that strips all non-STREAMINFO blocks.
  const RemoveAllNonStreamInfo();
}
```

- [ ] **Step 4: Add editor method + branch**

In `lib/src/edit/flac_metadata_editor.dart`, add before `applyMutation`:

```dart
  /// Remove every block except STREAMINFO.
  ///
  /// Enqueues a [RemoveAllNonStreamInfo] mutation.
  void removeAllNonStreamInfo() =>
      _mutations.add(const RemoveAllNonStreamInfo());
```

Add the switch branch:

```dart
      case RemoveAllNonStreamInfo _:
        return blocks.whereType<StreamInfoBlock>().toList();
```

- [ ] **Step 5: Run test**

Run: `dart test test/tier3_blocks_test.dart -n RemoveAllNonStreamInfo`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/edit/mutation_ops.dart lib/src/edit/flac_metadata_editor.dart test/tier3_blocks_test.dart
git commit -m "feat: add RemoveAllNonStreamInfo mutation (#15)"
```

---

### Task 5: Add `AppendRawBlock` mutation

**Files:**
- Modify: `lib/src/edit/mutation_ops.dart` (add import + class)
- Modify: `lib/src/edit/flac_metadata_editor.dart` (method + switch branch + imports)
- Test: `test/tier3_blocks_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `test/tier3_blocks_test.dart`:

```dart
  group('AppendRawBlock', () {
    test('append with afterIndex null inserts before trailing PADDING', () {
      final payload = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]);
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) =>
          e.appendRawBlock(FlacBlockType.application, payload));
      // Last block must still be PADDING (or the new block if no padding).
      expect(updated.blocks.last, isA<PaddingBlock>());
      final unknown = updated.blocks.whereType<UnknownBlock>().single;
      expect(unknown.rawTypeCode, FlacBlockType.application.code);
      expect(unknown.rawPayload, payload);
    });

    test('append with explicit afterIndex 0 inserts after STREAMINFO', () {
      final payload = Uint8List.fromList([1, 2, 3]);
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) => e.appendRawBlock(
            FlacBlockType.seekTable,
            payload,
            afterIndex: 0,
          ));
      expect(updated.blocks[1], isA<UnknownBlock>());
      expect((updated.blocks[1] as UnknownBlock).rawTypeCode,
          FlacBlockType.seekTable.code);
    });

    test('afterIndex beyond length appends at end', () {
      final payload = Uint8List.fromList([9]);
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) => e.appendRawBlock(
            FlacBlockType.application,
            payload,
            afterIndex: 99,
          ));
      expect(updated.blocks.last, isA<UnknownBlock>());
    });

    test('bytes round-trip through serialise + reparse', () {
      final payload = Uint8List.fromList([0x11, 0x22, 0x33, 0x44, 0x55]);
      final doc = FlacMetadataDocument.readFromBytes(_fixture());
      final updated = doc.edit((e) =>
          e.appendRawBlock(FlacBlockType.application, payload));
      final bytes = updated.toBytes();
      final reparsed = FlacParser.parseBytes(bytes);
      final app = reparsed.blocks.whereType<ApplicationBlock>().singleOrNull;
      // Application blocks have a minimum-valid parse path (4-byte app id +
      // data), so our 5-byte payload parses successfully.
      expect(app, isNotNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/tier3_blocks_test.dart -n AppendRawBlock`
Expected: FAIL — `appendRawBlock` not defined.

- [ ] **Step 3: Add mutation class**

Append to `lib/src/edit/mutation_ops.dart`:

```dart
/// Append a pre-serialised metadata block to the document.
///
/// The [payload] bytes are written verbatim with a block header carrying
/// [type]'s numeric code. The block is carried internally as an
/// [UnknownBlock] so no payload validation is performed; callers are
/// responsible for supplying well-formed bytes.
///
/// Position:
/// - [afterIndex] `null` — append at the tail, before any trailing
///   [PaddingBlock].
/// - [afterIndex] `0` — insert immediately after STREAMINFO.
/// - [afterIndex] `n > 0` — insert after the block currently at index `n`.
///   If `n >= blocks.length`, append at the tail.
final class AppendRawBlock extends MetadataMutation {
  /// Create a mutation that appends a raw block.
  const AppendRawBlock({
    required this.type,
    required this.payload,
    this.afterIndex,
  });

  /// The block type code that the serialiser should write.
  final FlacBlockType type;

  /// The pre-serialised block payload (excluding the 4-byte block header).
  final Uint8List payload;

  /// Where to insert the block. See class docs for semantics.
  final int? afterIndex;
}
```

Also add to the imports at the top of `mutation_ops.dart`:

```dart
import 'dart:typed_data';
import '../model/padding_block.dart';
```

(The `PaddingBlock` import is referenced only in docs, but `dart:typed_data` is needed for `Uint8List`.)

- [ ] **Step 4: Add editor method + branch**

In `lib/src/edit/flac_metadata_editor.dart`, add imports:

```dart
import 'dart:typed_data';
import '../model/unknown_block.dart';
```

Add the editor method before `applyMutation`:

```dart
  /// Append a pre-serialised block with the given [type] and [payload].
  ///
  /// Enqueues an [AppendRawBlock] mutation. See [AppendRawBlock] for
  /// positioning rules.
  void appendRawBlock(FlacBlockType type, Uint8List payload,
          {int? afterIndex}) =>
      _mutations.add(AppendRawBlock(
        type: type,
        payload: payload,
        afterIndex: afterIndex,
      ));
```

Add the switch branch:

```dart
      case AppendRawBlock m:
        final raw = UnknownBlock(
          rawTypeCode: m.type.code,
          rawPayload: Uint8List.fromList(m.payload),
        );
        if (m.afterIndex != null) {
          final idx = m.afterIndex!;
          if (idx >= blocks.length - 1) return [...blocks, raw];
          return [...blocks.sublist(0, idx + 1), raw, ...blocks.sublist(idx + 1)];
        }
        // afterIndex == null: insert before any trailing PaddingBlock.
        if (blocks.isNotEmpty && blocks.last is PaddingBlock) {
          return [
            ...blocks.sublist(0, blocks.length - 1),
            raw,
            blocks.last,
          ];
        }
        return [...blocks, raw];
```

- [ ] **Step 5: Run tests**

Run: `dart test test/tier3_blocks_test.dart -n AppendRawBlock`
Expected: PASS.

- [ ] **Step 6: Run full suite**

Run: `dart test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/src/edit/mutation_ops.dart lib/src/edit/flac_metadata_editor.dart test/tier3_blocks_test.dart
git commit -m "feat: add AppendRawBlock mutation (#15)"
```

---

### Task 6: Add shared block-selection helper

All three selection flags (and legacy flags in `bin/metaflac.dart`) need the same parsing logic. Extract it once.

**Files:**
- Create: `lib/src/cli/block_selection.dart`
- Test: `test/tier3_blocks_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `test/tier3_blocks_test.dart`:

```dart
import 'package:dart_metaflac/src/cli/block_selection.dart';
```

Add the import at the top of the file (below the `package:test/test.dart` import).

Then append the following tests:

```dart
  group('parseBlockTypes', () {
    test('parses comma-separated names case-insensitively', () {
      expect(
        parseBlockTypes('streaminfo,PICTURE,vorbis_comment'),
        {
          FlacBlockType.streamInfo,
          FlacBlockType.picture,
          FlacBlockType.vorbisComment,
        },
      );
    });

    test('rejects unknown names with an ArgumentError', () {
      expect(() => parseBlockTypes('BOGUS'), throwsArgumentError);
    });

    test('ignores surrounding whitespace', () {
      expect(
        parseBlockTypes(' PICTURE , PADDING '),
        {FlacBlockType.picture, FlacBlockType.padding},
      );
    });
  });

  group('parseBlockNumbers', () {
    test('parses comma-separated integers', () {
      expect(parseBlockNumbers('0,2,5'), {0, 2, 5});
    });

    test('rejects non-integer entries', () {
      expect(() => parseBlockNumbers('0,foo'), throwsArgumentError);
    });

    test('rejects negative values', () {
      expect(() => parseBlockNumbers('-1'), throwsArgumentError);
    });
  });
```

- [ ] **Step 2: Run tests to verify failure**

Run: `dart test test/tier3_blocks_test.dart -n parseBlock`
Expected: FAIL — `block_selection.dart` does not exist.

- [ ] **Step 3: Create the helper**

Create `lib/src/cli/block_selection.dart`:

```dart
import '../model/flac_block_type.dart';

/// Parses a comma-separated list of block type names (case-insensitive)
/// into a [Set] of [FlacBlockType].
///
/// Accepted names: `STREAMINFO`, `PADDING`, `APPLICATION`, `SEEKTABLE`,
/// `VORBIS_COMMENT`, `PICTURE`. Matches the names that upstream metaflac
/// uses on the command line.
///
/// Throws [ArgumentError] if [input] contains an unknown name. Empty
/// entries and surrounding whitespace are ignored.
Set<FlacBlockType> parseBlockTypes(String input) {
  final result = <FlacBlockType>{};
  for (final raw in input.split(',')) {
    final name = raw.trim().toUpperCase();
    if (name.isEmpty) continue;
    final type = _blockTypeFromName(name);
    if (type == null) {
      throw ArgumentError.value(
        raw,
        'block type',
        'Unknown block type. Valid: STREAMINFO, PADDING, APPLICATION, '
            'SEEKTABLE, VORBIS_COMMENT, PICTURE.',
      );
    }
    result.add(type);
  }
  return result;
}

/// Parses a comma-separated list of non-negative integers into a [Set].
///
/// Throws [ArgumentError] on non-integer or negative entries.
Set<int> parseBlockNumbers(String input) {
  final result = <int>{};
  for (final raw in input.split(',')) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    final n = int.tryParse(text);
    if (n == null) {
      throw ArgumentError.value(raw, 'block number', 'Not an integer.');
    }
    if (n < 0) {
      throw ArgumentError.value(raw, 'block number', 'Must be >= 0.');
    }
    result.add(n);
  }
  return result;
}

FlacBlockType? _blockTypeFromName(String name) {
  switch (name) {
    case 'STREAMINFO':
      return FlacBlockType.streamInfo;
    case 'PADDING':
      return FlacBlockType.padding;
    case 'APPLICATION':
      return FlacBlockType.application;
    case 'SEEKTABLE':
      return FlacBlockType.seekTable;
    case 'VORBIS_COMMENT':
      return FlacBlockType.vorbisComment;
    case 'PICTURE':
      return FlacBlockType.picture;
    default:
      return null;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/tier3_blocks_test.dart -n parseBlock`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/cli/block_selection.dart test/tier3_blocks_test.dart
git commit -m "feat: add block selection flag parsing helpers (#15)"
```

---

### Task 7: Add `blocks remove` and `blocks remove-all` subcommands

**Files:**
- Modify: `lib/src/cli/commands/blocks_command.dart`
- Modify: `test/cli_subcommands_test.dart`

- [ ] **Step 1: Write the failing tests**

Read the existing `test/cli_subcommands_test.dart` to understand the pattern, then append new test groups at the bottom of the file. The existing file uses a helper like `_runBlocks(args)` or similar — inspect it first, but the general pattern is:

```dart
  group('blocks remove', () {
    test('removes blocks by type', () async {
      final path = await _writeFixture(tempDir, 'remove.flac');
      final runner = MetaflacCommandRunner();
      final code = await runner.run(
          ['blocks', 'remove', '--block-type=PICTURE', path]);
      expect(code, 0);
      final reparsed = FlacMetadataDocument.readFromBytes(
          File(path).readAsBytesSync());
      expect(reparsed.pictures, isEmpty);
    });

    test('removes blocks by number', () async {
      final path = await _writeFixture(tempDir, 'remove-num.flac');
      final runner = MetaflacCommandRunner();
      final code = await runner.run(
          ['blocks', 'remove', '--block-number=2', path]);
      expect(code, 0);
    });

    test('fails without any selector flag', () async {
      final path = await _writeFixture(tempDir, 'no-sel.flac');
      final runner = MetaflacCommandRunner();
      expect(
        () async => await runner.run(['blocks', 'remove', path]),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects combining --block-type and --except-block-type', () async {
      final path = await _writeFixture(tempDir, 'conflict.flac');
      final runner = MetaflacCommandRunner();
      expect(
        () async => await runner.run([
          'blocks',
          'remove',
          '--block-type=PICTURE',
          '--except-block-type=PADDING',
          path,
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('--except-block-type keeps only listed types plus STREAMINFO', () async {
      final path = await _writeFixture(tempDir, 'except.flac');
      final runner = MetaflacCommandRunner();
      final code = await runner.run([
        'blocks',
        'remove',
        '--except-block-type=VORBIS_COMMENT',
        path,
      ]);
      expect(code, 0);
      final reparsed = FlacMetadataDocument.readFromBytes(
          File(path).readAsBytesSync());
      // Only STREAMINFO + VORBIS_COMMENT should remain.
      for (final b in reparsed.blocks) {
        expect(
          b.type == FlacBlockType.streamInfo ||
              b.type == FlacBlockType.vorbisComment,
          isTrue,
          reason: 'unexpected block: ${b.type}',
        );
      }
    });
  });

  group('blocks remove-all', () {
    test('leaves only STREAMINFO', () async {
      final path = await _writeFixture(tempDir, 'remove-all.flac');
      final runner = MetaflacCommandRunner();
      final code = await runner.run(['blocks', 'remove-all', path]);
      expect(code, 0);
      final reparsed = FlacMetadataDocument.readFromBytes(
          File(path).readAsBytesSync());
      expect(reparsed.blocks.length, 1);
      expect(reparsed.blocks.single, isA<StreamInfoBlock>());
    });
  });
```

If the test file doesn't already have a fixture helper `_writeFixture(tempDir, name)` and a shared `tempDir`, look at existing tests in `cli_subcommands_test.dart` and adapt. If needed, create a small helper at the top of the file that writes the `_fixture()` bytes from tier3_blocks_test (copy the function in, or export it from tier3_blocks_test — simplest is to duplicate).

- [ ] **Step 2: Run tests to verify failure**

Run: `dart test test/cli_subcommands_test.dart -n "blocks remove"`
Expected: FAIL — subcommand not registered.

- [ ] **Step 3: Implement `blocks remove` command**

In `lib/src/cli/commands/blocks_command.dart`, add to the imports (top of file):

```dart
import '../block_selection.dart';
```

Register the new subcommands in `BlocksCommand`:

```dart
class BlocksCommand extends Command<int> {
  BlocksCommand() {
    addSubcommand(BlocksListCommand());
    addSubcommand(BlocksRemoveCommand());
    addSubcommand(BlocksRemoveAllCommand());
  }
  // ...existing name/description unchanged
}
```

Add these classes at the end of the file:

```dart
/// Removes metadata blocks selected by type, except-type, or number.
class BlocksRemoveCommand extends BaseFlacCommand {
  BlocksRemoveCommand() {
    argParser
      ..addOption('block-type',
          help: 'Comma-separated block types to remove '
              '(STREAMINFO, PADDING, APPLICATION, SEEKTABLE, '
              'VORBIS_COMMENT, PICTURE)')
      ..addOption('except-block-type',
          help: 'Comma-separated block types to keep '
              '(others are removed)')
      ..addOption('block-number',
          help: 'Comma-separated 0-based block indices to remove')
      ..addFlag('dont-use-padding',
          help: 'Do not reuse padding; force full rewrite',
          negatable: false);
  }

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove metadata blocks by type or number';

  @override
  Future<int> run() async {
    final files = filePaths;
    final blockType = argResults!['block-type'] as String?;
    final exceptBlockType = argResults!['except-block-type'] as String?;
    final blockNumber = argResults!['block-number'] as String?;

    if (blockType != null && exceptBlockType != null) {
      throw UsageException(
        'Cannot combine --block-type and --except-block-type.',
        usage,
      );
    }
    if (blockType == null &&
        exceptBlockType == null &&
        blockNumber == null) {
      throw UsageException(
        'At least one of --block-type, --except-block-type, or '
        '--block-number is required.',
        usage,
      );
    }

    final dontUsePadding = argResults!['dont-use-padding'] as bool;

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(filePath, 'File not found: $filePath',
              'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        final mutations = <MetadataMutation>[];

        if (blockType != null) {
          final types = parseBlockTypes(blockType);
          mutations.add(RemoveBlocksByType(types));
        } else if (exceptBlockType != null) {
          final keep = parseBlockTypes(exceptBlockType);
          final bytes = file.readAsBytesSync();
          final doc = FlacParser.parseBytes(bytes);
          final toRemove = <FlacBlockType>{};
          for (final b in doc.blocks) {
            if (b.type == FlacBlockType.streamInfo) continue;
            if (!keep.contains(b.type)) toRemove.add(b.type);
          }
          mutations.add(RemoveBlocksByType(toRemove));
        }

        if (blockNumber != null) {
          mutations.add(RemoveBlocksByNumber(parseBlockNumbers(blockNumber)));
        }

        await FlacFileEditor.updateFile(
          filePath,
          mutations: mutations,
          options: FlacWriteOptions(
            preserveModTime: preserveModtime,
            explicitPaddingSize: dontUsePadding ? 0 : null,
          ),
        );

        if (useJson) {
          writeJson({
            'file': filePath,
            'success': true,
            'mutationsApplied': mutations.length,
          });
        } else {
          writeLine('Applied ${mutations.length} mutation(s) to $filePath');
        }
      } on ArgumentError catch (e) {
        throw UsageException(e.message.toString(), usage);
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}

/// Removes every metadata block except STREAMINFO.
class BlocksRemoveAllCommand extends BaseFlacCommand {
  BlocksRemoveAllCommand() {
    argParser.addFlag('dont-use-padding',
        help: 'Do not reuse padding; force full rewrite', negatable: false);
  }

  @override
  String get name => 'remove-all';

  @override
  String get description =>
      'Remove all metadata blocks except STREAMINFO';

  @override
  Future<int> run() async {
    final files = filePaths;
    final dontUsePadding = argResults!['dont-use-padding'] as bool;

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(filePath, 'File not found: $filePath',
              'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        await FlacFileEditor.updateFile(
          filePath,
          mutations: const [RemoveAllNonStreamInfo()],
          options: FlacWriteOptions(
            preserveModTime: preserveModtime,
            explicitPaddingSize: dontUsePadding ? 0 : null,
          ),
        );

        if (useJson) {
          writeJson({'file': filePath, 'success': true});
        } else {
          writeLine('Removed all non-STREAMINFO blocks from $filePath');
        }
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}
```

Also add the `FlacFileEditor` / `FlacWriteOptions` import at the top of `blocks_command.dart`:

```dart
import 'package:dart_metaflac/io.dart';
```

- [ ] **Step 4: Run tests**

Run: `dart test test/cli_subcommands_test.dart -n "blocks remove"`
Expected: PASS.

Also: `dart test test/cli_subcommands_test.dart -n "blocks remove-all"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/cli/commands/blocks_command.dart test/cli_subcommands_test.dart
git commit -m "feat: add 'blocks remove' and 'blocks remove-all' subcommands (#15)"
```

---

### Task 8: Add `blocks append` subcommand

**Files:**
- Modify: `lib/src/cli/commands/blocks_command.dart`
- Modify: `test/cli_subcommands_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/cli_subcommands_test.dart`:

```dart
  group('blocks append', () {
    test('appends a raw block from a file', () async {
      final flacPath = await _writeFixture(tempDir, 'append.flac');
      final blockPath = '${tempDir.path}/raw.bin';
      File(blockPath).writeAsBytesSync([0x41, 0x42, 0x43, 0x44, 0x00, 0x00]);

      final runner = MetaflacCommandRunner();
      final code = await runner.run([
        'blocks',
        'append',
        '--type=APPLICATION',
        '--from-file=$blockPath',
        flacPath,
      ]);
      expect(code, 0);

      final reparsed = FlacMetadataDocument.readFromBytes(
          File(flacPath).readAsBytesSync());
      // The block was of type APPLICATION with 4-byte id "ABCD".
      final app = reparsed.blocks.whereType<ApplicationBlock>().singleOrNull;
      expect(app, isNotNull);
    });

    test('requires --type and --from-file', () async {
      final flacPath = await _writeFixture(tempDir, 'append-missing.flac');
      final runner = MetaflacCommandRunner();
      expect(
        () async => await runner.run(['blocks', 'append', flacPath]),
        throwsA(isA<UsageException>()),
      );
    });
  });
```

- [ ] **Step 2: Run test to verify failure**

Run: `dart test test/cli_subcommands_test.dart -n "blocks append"`
Expected: FAIL.

- [ ] **Step 3: Implement `blocks append`**

In `lib/src/cli/commands/blocks_command.dart`, register it in `BlocksCommand`:

```dart
  BlocksCommand() {
    addSubcommand(BlocksListCommand());
    addSubcommand(BlocksRemoveCommand());
    addSubcommand(BlocksRemoveAllCommand());
    addSubcommand(BlocksAppendCommand());
  }
```

Add the class at the end of the file:

```dart
/// Appends a pre-serialised metadata block read from a binary file.
class BlocksAppendCommand extends BaseFlacCommand {
  BlocksAppendCommand() {
    argParser
      ..addOption('type',
          help: 'Block type name for the appended block '
              '(STREAMINFO, PADDING, APPLICATION, SEEKTABLE, '
              'VORBIS_COMMENT, PICTURE)')
      ..addOption('from-file',
          help: 'Path to the file containing the raw block payload')
      ..addOption('after',
          help: '0-based index after which to insert the block. '
              'Defaults to the end (before trailing PADDING).');
  }

  @override
  String get name => 'append';

  @override
  String get description =>
      'Append a pre-serialised metadata block from a file';

  @override
  Future<int> run() async {
    final files = filePaths;
    final typeStr = argResults!['type'] as String?;
    final fromFile = argResults!['from-file'] as String?;
    final afterStr = argResults!['after'] as String?;

    if (typeStr == null || fromFile == null) {
      throw UsageException(
        '--type and --from-file are required.',
        usage,
      );
    }

    final Set<FlacBlockType> types;
    try {
      types = parseBlockTypes(typeStr);
    } on ArgumentError catch (e) {
      throw UsageException(e.message.toString(), usage);
    }
    if (types.length != 1) {
      throw UsageException('--type must name exactly one block type.', usage);
    }
    final type = types.single;

    final int? afterIndex = afterStr == null ? null : int.tryParse(afterStr);
    if (afterStr != null && afterIndex == null) {
      throw UsageException('--after must be an integer.', usage);
    }

    final blockFile = File(fromFile);
    if (!blockFile.existsSync()) {
      writeError(fromFile, 'Block file not found: $fromFile',
          'FileSystemException');
      return 4;
    }
    final payload = blockFile.readAsBytesSync();

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(filePath, 'File not found: $filePath',
              'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        await FlacFileEditor.updateFile(
          filePath,
          mutations: [
            AppendRawBlock(
              type: type,
              payload: payload,
              afterIndex: afterIndex,
            ),
          ],
          options: FlacWriteOptions(preserveModTime: preserveModtime),
        );

        if (useJson) {
          writeJson({
            'file': filePath,
            'success': true,
            'appendedBytes': payload.length,
            'blockType': type.name,
          });
        } else {
          writeLine(
              'Appended ${payload.length} bytes of type ${type.name} to $filePath');
        }
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/cli_subcommands_test.dart -n "blocks append"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/cli/commands/blocks_command.dart test/cli_subcommands_test.dart
git commit -m "feat: add 'blocks append' subcommand (#15)"
```

---

### Task 9: Add selection filters to `blocks list`

**Files:**
- Modify: `lib/src/cli/commands/blocks_command.dart` (`BlocksListCommand`)
- Modify: `test/cli_subcommands_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/cli_subcommands_test.dart`:

```dart
  group('blocks list filters', () {
    test('--block-type=PICTURE shows only picture blocks', () async {
      final path = await _writeFixture(tempDir, 'list-filter.flac');
      final runner = MetaflacCommandRunner();
      final output = StringBuffer();
      // If your test harness uses a different capture mechanism, adapt here.
      final code = await IOOverrides.runZoned(
        () => runner.run(['blocks', 'list', '--block-type=PICTURE', path]),
        stdout: () => _MemStdout(output),
      );
      expect(code, 0);
      expect(output.toString(), contains('PICTURE'));
      expect(output.toString(), isNot(contains('STREAMINFO')));
    });

    test('--block-number preserves original indices', () async {
      final path = await _writeFixture(tempDir, 'list-num.flac');
      final runner = MetaflacCommandRunner();
      final output = StringBuffer();
      final code = await IOOverrides.runZoned(
        () => runner.run(['blocks', 'list', '--block-number=2', path]),
        stdout: () => _MemStdout(output),
      );
      expect(code, 0);
      expect(output.toString(), contains('BLOCK 2'));
      expect(output.toString(), isNot(contains('BLOCK 0')));
    });
  });
```

If the test file doesn't already have a `_MemStdout` helper or equivalent, use the existing mechanism in the file — check what existing list tests use for output capture. If none, inspect `test/cli_subcommands_test.dart` and follow its convention. If the file captures via `Process.run`, invoke the CLI as a subprocess instead.

**Note:** If the existing test file uses `Process.run(... 'bin/metaflac.dart' ...)` for output capture, use that pattern instead of `IOOverrides`. The point is: run `blocks list --block-type=PICTURE` and assert the captured stdout contains PICTURE but not STREAMINFO.

- [ ] **Step 2: Run tests to verify failure**

Run: `dart test test/cli_subcommands_test.dart -n "blocks list filters"`
Expected: FAIL — the flags don't exist on `BlocksListCommand`.

- [ ] **Step 3: Add the filter options to `BlocksListCommand`**

In `lib/src/cli/commands/blocks_command.dart`, modify `BlocksListCommand`:

```dart
class BlocksListCommand extends BaseFlacCommand {
  BlocksListCommand() {
    argParser
      ..addOption('block-type',
          help: 'Comma-separated block types to show')
      ..addOption('except-block-type',
          help: 'Comma-separated block types to hide')
      ..addOption('block-number',
          help: 'Comma-separated 0-based indices to show');
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all metadata blocks with types and sizes';

  @override
  Future<int> run() async {
    final files = filePaths;
    final blockType = argResults!['block-type'] as String?;
    final exceptBlockType = argResults!['except-block-type'] as String?;
    final blockNumber = argResults!['block-number'] as String?;

    if (blockType != null && exceptBlockType != null) {
      throw UsageException(
        'Cannot combine --block-type and --except-block-type.',
        usage,
      );
    }

    Set<FlacBlockType>? showTypes;
    Set<FlacBlockType>? hideTypes;
    Set<int>? showIndices;
    try {
      if (blockType != null) showTypes = parseBlockTypes(blockType);
      if (exceptBlockType != null) {
        hideTypes = parseBlockTypes(exceptBlockType);
      }
      if (blockNumber != null) {
        showIndices = parseBlockNumbers(blockNumber);
      }
    } on ArgumentError catch (e) {
      throw UsageException(e.message.toString(), usage);
    }

    var anyError = false;
    for (final filePath in files) {
      try {
        final file = File(filePath);
        if (!file.existsSync()) {
          writeError(filePath, 'File not found: $filePath',
              'FileSystemException');
          anyError = true;
          if (!continueOnError) return 4;
          continue;
        }

        final bytes = file.readAsBytesSync();
        final doc = FlacParser.parseBytes(bytes);
        final prefix = withFilename(files) ? '$filePath: ' : '';

        bool keep(int i, FlacMetadataBlock b) {
          if (showTypes != null && !showTypes!.contains(b.type)) return false;
          if (hideTypes != null && hideTypes!.contains(b.type)) return false;
          if (showIndices != null && !showIndices!.contains(i)) return false;
          return true;
        }

        if (useJson) {
          final blockList = <Map<String, Object?>>[];
          for (var i = 0; i < doc.blocks.length; i++) {
            final block = doc.blocks[i];
            if (!keep(i, block)) continue;
            blockList.add({
              'index': i,
              'type': block.type.name,
              'typeCode': block.type.code,
              'payloadSize': block.payloadLength,
            });
          }
          writeJson({'file': filePath, 'blocks': blockList});
        } else {
          for (var i = 0; i < doc.blocks.length; i++) {
            final block = doc.blocks[i];
            if (!keep(i, block)) continue;
            writeLine('${prefix}BLOCK $i: type=${block.type.name} '
                '(${block.type.code}), size=${block.payloadLength}');
          }
        }
      } on FlacMetadataException catch (e) {
        writeError(filePath, e.message, e.runtimeType.toString());
        anyError = true;
        if (!continueOnError) return exitCodeFor(e);
      } on FileSystemException catch (e) {
        writeError(filePath, e.message, 'FileSystemException');
        anyError = true;
        if (!continueOnError) return 4;
      }
    }
    return anyError ? 1 : 0;
  }
}
```

- [ ] **Step 4: Run tests**

Run: `dart test test/cli_subcommands_test.dart -n "blocks list"`
Expected: PASS (both old and new).

- [ ] **Step 5: Commit**

```bash
git add lib/src/cli/commands/blocks_command.dart test/cli_subcommands_test.dart
git commit -m "feat: add block-selection filters to 'blocks list' (#15)"
```

---

### Task 10: Add legacy flags in `bin/metaflac.dart`

Wire up `--remove`, `--remove-all`, `--append`, `--block-type`, `--except-block-type`, `--block-number` to the top-level parser, and make `--list` honour the filter flags.

**Files:**
- Modify: `bin/metaflac.dart`
- Modify: `test/metaflac_parity_test.dart`

- [ ] **Step 1: Write the failing tests**

Read `test/metaflac_parity_test.dart` to understand the invocation pattern (likely `Process.run('dart', ['run', 'bin/metaflac.dart', ...])` or similar). Then append:

```dart
  group('Tier 3 legacy flags', () {
    test('--remove --block-type=PICTURE strips pictures', () async {
      final path = await _writeLegacyFixture(tempDir, 'legacy-remove.flac');
      final result = await _runMetaflac(
          ['--remove', '--block-type=PICTURE', path]);
      expect(result.exitCode, 0);
      final doc = FlacMetadataDocument.readFromBytes(
          File(path).readAsBytesSync());
      expect(doc.pictures, isEmpty);
    });

    test('--remove-all leaves only STREAMINFO', () async {
      final path = await _writeLegacyFixture(tempDir, 'legacy-rall.flac');
      final result = await _runMetaflac(['--remove-all', path]);
      expect(result.exitCode, 0);
      final doc = FlacMetadataDocument.readFromBytes(
          File(path).readAsBytesSync());
      expect(doc.blocks.length, 1);
    });

    test('--append inserts a raw block', () async {
      final flacPath = await _writeLegacyFixture(tempDir, 'legacy-app.flac');
      final blockPath = '${tempDir.path}/raw.bin';
      File(blockPath).writeAsBytesSync([0x58, 0x59, 0x5A, 0x5B, 0x00]);
      final result = await _runMetaflac([
        '--append=$blockPath',
        '--block-type=APPLICATION',
        flacPath,
      ]);
      expect(result.exitCode, 0);
    });

    test('--list --block-type=PICTURE filters output', () async {
      final path = await _writeLegacyFixture(tempDir, 'legacy-list.flac');
      final result = await _runMetaflac(
          ['--list', '--block-type=PICTURE', path]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('PICTURE'));
      expect(result.stdout, isNot(contains('STREAMINFO')));
    });
  });
```

Use whatever `_runMetaflac` / `_writeLegacyFixture` helpers the file already defines; if the file uses a subprocess runner, match it.

- [ ] **Step 2: Run tests to verify failure**

Run: `dart test test/metaflac_parity_test.dart -n "Tier 3"`
Expected: FAIL — flags not recognised.

- [ ] **Step 3: Add flags to the top-level parser in `bin/metaflac.dart`**

Find the `final parser = ArgParser()` block (~line 31) and add after the existing options (before `// ── Global options ──`):

```dart
    // ── Tier 3: block management ───────────────────────────────────────
    ..addFlag('remove',
        help: 'Remove blocks matching --block-type/--except-block-type/'
            '--block-number',
        negatable: false)
    ..addFlag('remove-all',
        help: 'Remove all metadata blocks except STREAMINFO',
        negatable: false)
    ..addOption('append',
        help: 'Append a raw metadata block from FILE (use with --block-type)',
        valueHelp: 'FILE')
    ..addOption('block-type',
        help: 'Block types (comma-separated), e.g. PICTURE,PADDING')
    ..addOption('except-block-type',
        help: 'Block types to keep (comma-separated)')
    ..addOption('block-number',
        help: '0-based block indices (comma-separated)')
```

- [ ] **Step 4: Thread the legacy flags through `_processFile`**

In `bin/metaflac.dart`, add this import at the top:

```dart
import 'package:dart_metaflac/src/cli/block_selection.dart';
```

Inside `_processFile`, **before** `// ── Read operations ─────`, read the new options:

```dart
    final removeFlag = results['remove'] as bool;
    final removeAll = results['remove-all'] as bool;
    final appendPath = results['append'] as String?;
    final blockTypeOpt = results['block-type'] as String?;
    final exceptBlockTypeOpt = results['except-block-type'] as String?;
    final blockNumberOpt = results['block-number'] as String?;
```

Modify the `--list` path to honour filters. Replace the existing `if (results['list'] as bool)` block with:

```dart
    if (results['list'] as bool) {
      Set<FlacBlockType>? showTypes;
      Set<FlacBlockType>? hideTypes;
      Set<int>? showIndices;
      try {
        if (blockTypeOpt != null) showTypes = parseBlockTypes(blockTypeOpt);
        if (exceptBlockTypeOpt != null) {
          hideTypes = parseBlockTypes(exceptBlockTypeOpt);
        }
        if (blockNumberOpt != null) {
          showIndices = parseBlockNumbers(blockNumberOpt);
        }
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }

      final hasFilter =
          showTypes != null || hideTypes != null || showIndices != null;

      if (useJson) {
        final json = _metadataToJson(doc, filePath);
        _write(jsonEncode(json), quiet);
      } else if (hasFilter) {
        for (var i = 0; i < doc.blocks.length; i++) {
          final b = doc.blocks[i];
          if (showTypes != null && !showTypes.contains(b.type)) continue;
          if (hideTypes != null && hideTypes.contains(b.type)) continue;
          if (showIndices != null && !showIndices.contains(i)) continue;
          _write(
            '${prefix}BLOCK $i: type=${b.type.name} '
            '(${b.type.code}), size=${b.payloadLength}',
            quiet,
          );
        }
      } else {
        if (!quiet) _printMetadata(doc, prefix);
      }
      return _exitSuccess;
    }
```

Extend the `hasWriteOp` check to include the new flags:

```dart
    final hasWriteOp = removeTags.isNotEmpty ||
        removeFirstTag != null ||
        removeAllTags ||
        removeAllTagsExcept != null ||
        removeReplayGain ||
        setTags.isNotEmpty ||
        setTagFromFile.isNotEmpty ||
        importTagsFrom != null ||
        importPictureFrom != null ||
        removeFlag ||
        removeAll ||
        appendPath != null;
```

Add mutation building after the existing picture/tag logic, **before** the `if (dryRun)` block:

```dart
    if (removeAll) {
      mutations.add(const RemoveAllNonStreamInfo());
    } else if (removeFlag) {
      if (blockTypeOpt == null &&
          exceptBlockTypeOpt == null &&
          blockNumberOpt == null) {
        stderr.writeln(
            '--remove requires --block-type, --except-block-type, or --block-number');
        return _exitInvalidArgs;
      }
      if (blockTypeOpt != null && exceptBlockTypeOpt != null) {
        stderr.writeln(
            'Cannot combine --block-type and --except-block-type');
        return _exitInvalidArgs;
      }
      try {
        if (blockTypeOpt != null) {
          mutations.add(RemoveBlocksByType(parseBlockTypes(blockTypeOpt)));
        } else if (exceptBlockTypeOpt != null) {
          final keep = parseBlockTypes(exceptBlockTypeOpt);
          final toRemove = <FlacBlockType>{};
          for (final b in doc.blocks) {
            if (b.type == FlacBlockType.streamInfo) continue;
            if (!keep.contains(b.type)) toRemove.add(b.type);
          }
          mutations.add(RemoveBlocksByType(toRemove));
        }
        if (blockNumberOpt != null) {
          mutations.add(RemoveBlocksByNumber(parseBlockNumbers(blockNumberOpt)));
        }
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }
    }

    if (appendPath != null) {
      if (blockTypeOpt == null) {
        stderr.writeln('--append requires --block-type');
        return _exitInvalidArgs;
      }
      final Set<FlacBlockType> types;
      try {
        types = parseBlockTypes(blockTypeOpt);
      } on ArgumentError catch (e) {
        stderr.writeln('Error: ${e.message}');
        return _exitInvalidArgs;
      }
      if (types.length != 1) {
        stderr.writeln('--block-type must name exactly one type for --append');
        return _exitInvalidArgs;
      }
      final blockFile = File(appendPath);
      if (!blockFile.existsSync()) {
        _reportError(appendPath, 'Block file not found: $appendPath',
            'FileSystemException', useJson);
        return _exitIoError;
      }
      mutations.add(AppendRawBlock(
        type: types.single,
        payload: blockFile.readAsBytesSync(),
      ));
    }
```

- [ ] **Step 5: Run the legacy parity tests**

Run: `dart test test/metaflac_parity_test.dart -n "Tier 3"`
Expected: PASS.

Also: `dart test test/metaflac_parity_test.dart`
Expected: no regressions.

- [ ] **Step 6: Run the full test suite**

Run: `dart test`
Expected: everything passes.

- [ ] **Step 7: Commit**

```bash
git add bin/metaflac.dart test/metaflac_parity_test.dart
git commit -m "feat: add Tier 3 legacy flags --remove/--remove-all/--append (#15)"
```

---

### Task 11: Analyze + close the issue

- [ ] **Step 1: Run `dart analyze`**

Run: `dart analyze`
Expected: zero issues.

- [ ] **Step 2: Run the full suite once more**

Run: `dart test`
Expected: all tests pass.

- [ ] **Step 3: Final commit if analyze required any cleanups**

If analyze flagged anything that needed a fix, commit it with a cleanup message. Otherwise skip.

---

## Self-review notes

**Spec coverage:**
- `--remove` → Task 7 (subcommand) + Task 10 (legacy flag). ✓
- `--remove-all` → Task 7 + Task 10. ✓
- `--append` → Task 8 + Task 10. ✓
- `--block-number`, `--block-type`, `--except-block-type` as both list and remove selectors → Tasks 7 + 9 + 10. ✓
- `RemoveBlocksByType`, `RemoveBlocksByNumber`, `RemoveAllNonStreamInfo`, `AppendRawBlock` mutation types → Tasks 2–5. ✓
- CLI in `blocks_command.dart` → Tasks 7, 8, 9. ✓
- Legacy flag aliases in `bin/metaflac.dart` → Task 10. ✓
- Each new mutation has a test → Tasks 2–5. ✓
- `blocks remove --block-type=PICTURE` round-trip → Task 7. ✓
- `--remove-all` leaves only STREAMINFO → Task 7 + Task 10. ✓
- `--append` round-trip preserves raw bytes → Task 1 (serialiser fix) + Task 5. ✓

**Scope guard:** The UnknownBlock serialiser fix (Task 1) is prerequisite, not scope creep — `AppendRawBlock` is impossible without it.
