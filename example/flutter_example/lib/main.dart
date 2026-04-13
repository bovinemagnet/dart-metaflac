/// Minimal Flutter example for `dart_metaflac`.
///
/// Loads a FLAC file from the app's asset bundle, reads its Vorbis
/// comment tags, and displays them in a simple list view. Works on all
/// Flutter targets — mobile, desktop, and web — because it uses only the
/// pure-Dart core library (no `dart:io`).
///
/// If you want to *write* metadata back to a file on a non-web target,
/// add `import 'package:dart_metaflac/io.dart';` and use
/// [FlacFileEditor.updateFile]. Do not add that import on Flutter Web —
/// it pulls in `dart:io`, which is unavailable in the browser.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dart_metaflac/dart_metaflac.dart';

void main() {
  runApp(const DartMetaflacExampleApp());
}

class DartMetaflacExampleApp extends StatelessWidget {
  const DartMetaflacExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dart_metaflac example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const FlacTagViewer(assetPath: 'assets/sample.flac'),
    );
  }
}

class FlacTagViewer extends StatefulWidget {
  const FlacTagViewer({super.key, required this.assetPath});

  final String assetPath;

  @override
  State<FlacTagViewer> createState() => _FlacTagViewerState();
}

class _FlacTagViewerState extends State<FlacTagViewer> {
  late Future<List<MapEntry<String, String>>> _tagsFuture;

  @override
  void initState() {
    super.initState();
    _tagsFuture = _loadTags();
  }

  Future<List<MapEntry<String, String>>> _loadTags() async {
    // Load the FLAC bytes from the asset bundle. On web this resolves
    // to a network fetch; on mobile/desktop it reads from the app
    // package. Either way, dart_metaflac only ever sees a Uint8List.
    final data = await rootBundle.load(widget.assetPath);
    final bytes = data.buffer.asUint8List();

    final doc = FlacMetadataDocument.readFromBytes(bytes);
    final vc = doc.vorbisComment;
    if (vc == null) return const [];

    return [
      for (final entry in vc.comments.entries) MapEntry(entry.key, entry.value),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FLAC tags')),
      body: FutureBuilder<List<MapEntry<String, String>>>(
        future: _tagsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final tags = snapshot.data ?? const [];
          if (tags.isEmpty) {
            return const Center(child: Text('No Vorbis comments found.'));
          }
          return ListView.separated(
            itemCount: tags.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final tag = tags[i];
              return ListTile(
                title: Text(tag.key),
                subtitle: Text(tag.value),
              );
            },
          );
        },
      ),
    );
  }
}
