import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:path/path.dart' as p;

/// Decodes canvas image files (`note_images/{noteId}/{filename}`) into
/// `ui.Image` for painting, keyed by filename. Loads lazily and calls
/// [onLoaded] when a decode finishes so the canvas can repaint.
class CanvasImageCache {
  final String dirPath;
  final VoidCallback onLoaded;
  final Map<String, ui.Image> images = {};
  final Set<String> _loading = {};

  CanvasImageCache({required this.dirPath, required this.onLoaded});

  /// Returns the decoded image if ready, else triggers a load and returns null.
  ui.Image? get(String filename) {
    final cached = images[filename];
    if (cached != null) return cached;
    if (!_loading.contains(filename)) {
      _loading.add(filename);
      _load(filename);
    }
    return null;
  }

  Future<void> _load(String filename) async {
    try {
      final file = File(p.join(dirPath, filename));
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      images[filename] = frame.image;
    } catch (_) {
      // Missing/corrupt file — leave unloaded; painter draws a placeholder.
    }
    _loading.remove(filename);
    onLoaded();
  }

  void dispose() {
    for (final img in images.values) {
      img.dispose();
    }
    images.clear();
  }
}
