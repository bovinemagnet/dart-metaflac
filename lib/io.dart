/// File-based IO adapters for `dart_metaflac`, built on `dart:io`.
///
/// This library is a separate public entry point from the pure-Dart core
/// in `package:dart_metaflac/dart_metaflac.dart`. Import it **in addition**
/// to the core library whenever you need to read or write FLAC metadata
/// to files on disc:
///
/// ```dart
/// import 'package:dart_metaflac/dart_metaflac.dart';  // core (no dart:io)
/// import 'package:dart_metaflac/io.dart';             // file APIs
///
/// Future<void> main() async {
///   final doc = await FlacFileEditor.readFile('song.flac');
///   await FlacFileEditor.updateFile(
///     'song.flac',
///     (editor) => editor.setTag('ARTIST', ['New Artist']),
///     options: const FlacWriteOptions(preserveModTime: true),
///   );
/// }
/// ```
///
/// Because this library depends on `dart:io`, it cannot be used on targets
/// where `dart:io` is unavailable (Flutter Web, WASM, browser). In those
/// environments, use the in-memory APIs from the core library
/// ([FlacMetadataDocument.readFromBytes], [FlacMetadataDocument.toBytes])
/// instead.
library dart_metaflac.io;

export 'src/io/atomic_writer.dart';
export 'src/io/flac_file_editor.dart';
export 'src/io/flac_write_options.dart';
export 'src/io/modtime.dart';
