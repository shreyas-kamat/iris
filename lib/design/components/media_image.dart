/// A generated image stored on the Hermes host and referenced by MEDIA:path.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

typedef MediaImageLoader = Future<Uint8List?> Function(String path);

class MediaImage extends StatefulWidget {
  const MediaImage({required this.path, required this.load, super.key});

  final String path;
  final MediaImageLoader load;

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  late Future<Uint8List?> _image = widget.load(widget.path);

  @override
  void didUpdateWidget(MediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _image = widget.load(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _image,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes != null && bytes.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return TextButton.icon(
        onPressed: () => setState(() => _image = widget.load(widget.path)),
        icon: const Icon(Icons.broken_image_outlined),
        label: const Text('Couldn\'t load image · Retry'),
      );
    },
  );
}
