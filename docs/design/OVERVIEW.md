# Product Requirements Document (PRD): `dart-metaflac`

**Document Version:** 1.0
**Product Name:** `dart-metaflac`
**Target Platforms:** Dart CLI (Windows, macOS, Linux), Flutter (iOS, Android, Web, Desktop)

---

## 1. Executive Summary

`dart-metaflac` is a pure Dart library and command-line interface (CLI) tool designed to read, write, and manipulate FLAC metadata (specifically Vorbis comments and Picture blocks). It serves a dual purpose: achieving functional parity with the reference C-based `metaflac` utility, while exposing a clean, agnostic API that can be embedded natively within any Dart or Flutter project without relying on Foreign Function Interfaces (FFI) or external system dependencies.

## 2. Goals and Objectives

* **100% Pure Dart:** Implement the FLAC metadata specification entirely in Dart to ensure maximum cross-platform compatibility, including Web.
* **CLI Parity:** Replicate the command-line arguments and behavior of the standard `metaflac` tool for users who want a standalone, drop-in replacement.
* **Developer-Friendly API:** Expose a modular, stream-friendly library architecture that allows Flutter and Dart developers to easily manipulate audio metadata in their applications.
* **Safe File Manipulation:** Implement robust parsing and rewriting logic, particularly concerning METADATA_BLOCK padding, to ensure audio streams are never corrupted during tag updates.

---

## 3. Architecture & System Design

To satisfy the requirement of being both a standalone CLI and an embeddable library, the project will be strictly separated into two layers:

### 3.1. The Core Library (`lib/`)
* **I/O Agnostic:** The core parsing and serializing logic will rely on Dart's `Stream`, `Sink`, and `Uint8List` abstractions rather than `dart:io`. This ensures the library can be used in Flutter Web or memory-buffered applications.
* **Immutability & Safety:** Metadata blocks will be represented as immutable Dart data classes. Updates will return new instances, which are then serialized back to the target destination.
* **Components:**
    * `FlacParser`: Reads the `fLaC` marker and iterates through `METADATA_BLOCK_HEADER`s.
    * `VorbisCommentProcessor`: Decodes/Encodes vendor strings and key-value user comments.
    * `PictureBlockProcessor`: Handles the extraction and embedding of album art.

### 3.2. The CLI Frontend (`bin/`)
* **Platform Specific:** Uses `dart:io` to read files, manage temporary writing, and handle standard input/output.
* **ArgParser:** Translates standard `metaflac` POSIX-style arguments into core library API calls.

---

## 4. Functional Requirements

### 4.1. Core Library Requirements (API)

| Feature ID | Feature | Description |
| :--- | :--- | :--- |
| **LIB-01** | Parse FLAC Headers | Traverse a FLAC file/stream and map all metadata blocks (STREAMINFO, PADDING, APPLICATION, SEEKTABLE, VORBIS_COMMENT, CUESHEET, PICTURE). |
| **LIB-02** | Read Vorbis Comments | Extract the vendor string and all tag/value pairs as a Dart `Map<String, List<String>>` (handling multiple values per key). |
| **LIB-03** | Write Vorbis Comments | Serialize a modified map of tags back into a valid VORBIS_COMMENT block. |
| **LIB-04** | Extract Pictures | Read `METADATA_BLOCK_PICTURE`, extracting MIME type, description, dimensions, and raw image bytes. |
| **LIB-05** | Embed Pictures | Construct a valid `METADATA_BLOCK_PICTURE` from raw bytes and user-provided specifications. |
| **LIB-06** | Padding Management | Automatically utilize existing `PADDING` blocks to expand/shrink tags in-place without rewriting the entire audio stream, when possible. |
| **LIB-07** | Safe File Rewrite | Safely stream the audio data to a new file/buffer if the new metadata exceeds available padding. |

### 4.2. CLI Tool Requirements (Parity)

The CLI tool must support the following standard `metaflac` operations:

* **General Options:**
    * `--preserve-modtime`: Preserve the original file's modification time.
    * `--with-filename`: Force printing the filename with output.
    * `--no-utf8-convert`: Do not convert tags from UTF-8 to local charset.
* **Information/Read Operations:**
    * `--show-md5`: Show the MD5 signature from the STREAMINFO block.
    * `--list`: Dump all metadata blocks in human-readable format.
    * `--export-tags-to=FILE`: Export Vorbis comments to a file (or stdout).
    * `--export-picture-to=FILE`: Extract album art.
* **Manipulation/Write Operations:**
    * `--remove-tag=NAME`: Remove all tags whose name matches `NAME`.
    * `--remove-all-tags`: Remove all Vorbis comments.
    * `--set-tag=FIELD`: Add a tag (e.g., `--set-tag="ARTIST=The Beatles"`).
    * `--import-tags-from=FILE`: Import tags from a file.
    * `--import-picture-from=FILENAME`: Import a picture and attach it.

---

## 5. Non-Functional Requirements

* **Performance:** The library must be capable of updating tags in a 50MB FLAC file in under 100ms (assuming adequate padding exists), by avoiding the buffering of the entire file into memory.
* **Memory Efficiency:** Audio frame data should be streamed, never loaded entirely into RAM.
* **Error Handling:** The library must throw specific, typed exceptions (e.g., `FlacCorruptHeaderException`, `FlacInsufficientPaddingException`) rather than generic errors.
* **Test Coverage:** Minimum 85% unit test coverage, including tests for corrupted files, edge-case padding, and large embedded pictures.

---

## 6. Proposed API Integration (Example)

To ensure developer adoption, the library syntax should be idiomatic and declarative.

```dart
import 'package:dart_metaflac/dart_metaflac.dart';
import 'dart:io';

Future<void> main() async {
  final file = File('song.flac');
  
  // 1. Initialize the editor
  final editor = FlacEditor(file.openRead());
  
  // 2. Read existing metadata
  final metadata = await editor.readMetadata();
  final tags = metadata.vorbisComments;
  print('Current Artist: ${tags['ARTIST']?.first}');
  
  // 3. Update tags
  tags['ARTIST'] = ['New Artist Name'];
  tags['ALBUM'] = ['Awesome Album'];
  
  // 4. Save changes safely
  final newStream = await editor.updateMetadata(
    vorbisComments: tags,
    // The library handles padding logic internally
  );
  
  // Write to destination
  final outFile = File('song_updated.flac');
  await newStream.pipe(outFile.openWrite());
}
```

---

## 7. Delivery Milestones

* **Phase 1: Foundation & Reading**
    * Implement FLAC stream parsing.
    * Extract STREAMINFO, VORBIS_COMMENT, and PICTURE blocks.
    * Implement `metaflac --list` parity.
* **Phase 2: Writing & Padding Logic**
    * Implement metadata serialization.
    * Develop the padding calculation engine (in-place updates vs. full file rewrites).
    * Test file integrity post-rewrite.
* **Phase 3: CLI Completion**
    * Implement `args` parsing for all targeted `metaflac` commands.
    * Handle cross-platform CLI output formatting.
* **Phase 4: Documentation & Release**
    * Publish `README.md`, standard API documentation (DartDoc).
    * Provide example Flutter project utilizing the library.
    * Publish to `pub.dev`.
