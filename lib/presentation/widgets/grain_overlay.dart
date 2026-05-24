import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Applies a subtle grain texture over any surface.
/// Uses a deterministic noise pattern pre-recorded in a ui.Picture.
/// Opacity: 8-12%, more visible in dark mode (intentional).
class GrainOverlay extends StatelessWidget {
  final Widget child;
  final double opacity;

  const GrainOverlay({
    super.key,
    required this.child,
    this.opacity = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class _GrainPainter extends CustomPainter {
  final double opacity;
  static const int _seed = 42;
  static const int _cols = 200;
  static const int _rows = 400;

  static final Map<double, ui.Picture> _pictureCache = {};

  _GrainPainter({required this.opacity}) {
    if (!_pictureCache.containsKey(opacity)) {
      _pictureCache[opacity] = _createNoisePicture(opacity);
    }
  }

  static ui.Picture _createNoisePicture(double opacity) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _cols.toDouble(), _rows.toDouble()));
    final rng = math.Random(_seed);
    final paint = Paint();
    const density = 0.15;

    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        if (rng.nextDouble() > density) continue;
        final brightness = rng.nextDouble();
        paint.color = Color.fromRGBO(
          (brightness * 255).round(),
          (brightness * 255).round(),
          (brightness * 255).round(),
          opacity,
        );
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0),
          paint,
        );
      }
    }
    return recorder.endRecording();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final picture = _pictureCache[opacity];
    if (picture == null) return;

    canvas.save();
    canvas.scale(size.width / _cols, size.height / _rows);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.opacity != opacity;
}
