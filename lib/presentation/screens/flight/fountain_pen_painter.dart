import 'dart:ui';

import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

/// Render a fountain-pen stroke onto [canvas].
///
/// Handles two point formats:
/// - **Baked** (completed stroke):  [x, y, width]
/// - **Raw** (in-progress stroke):  [x, y, pressure, timestamp]
void drawFountainPenStroke(Canvas canvas, DrawingStroke stroke,
    {double viewScale = 1.0}) {
  if (stroke.points.isEmpty) return;

  final isRaw = stroke.points.first.length >= 4;

  // In-progress stroke: render with the SAME geometry the finished stroke will
  // have, so there's no jump/shrink when the pen lifts.
  if (isRaw) {
    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      final pressure = p.length > 2 ? p[2] : 0.5;
      final r = stroke.strokeWidth * pressureWidthFactor(pressure) / 2;
      if (r > 0) {
        canvas.drawCircle(
          Offset(p[0], p[1]),
          r,
          Paint()
            ..color = Color(stroke.colorValue)
            ..style = PaintingStyle.fill,
        );
      }
      return;
    }
    final path = cachedStrokePath(
      stroke,
      () => FountainPenEngine.rawFountainPath(
          stroke.points, stroke.strokeWidth,
          viewScale: viewScale),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(stroke.colorValue)
        ..style = PaintingStyle.fill,
    );
    return;
  }

  final pts = stroke.points;
  if (pts.length < 2) {
    final first = pts.first;
    final r = (first.length > 2 ? first[2] : stroke.strokeWidth) / 2;
    if (r > 0) {
      canvas.drawCircle(
        Offset(first[0], first[1]),
        r,
        Paint()
          ..color = Color(stroke.colorValue)
          ..style = PaintingStyle.fill,
      );
    }
    return;
  }

  // Centerline/widths are only needed on a cache miss → build them lazily so
  // repaints (pan/zoom) of an unchanged baked stroke skip the allocations.
  final path = cachedStrokePath(stroke, () {
    final centerline = pts.map((p) => Offset(p[0], p[1])).toList();
    final widths =
        pts.map((p) => p.length > 2 ? p[2] : stroke.strokeWidth).toList();
    return FountainPenEngine.tessellate(centerline, widths,
        tangentWindow: 3, noiseAmp: 0);
  });
  canvas.drawPath(
    path,
    Paint()
      ..color = Color(stroke.colorValue)
      ..style = PaintingStyle.fill,
  );
}

