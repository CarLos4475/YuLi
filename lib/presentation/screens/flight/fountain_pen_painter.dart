import 'dart:ui';

import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

/// Render a fountain-pen stroke onto [canvas].
///
/// Handles two point formats:
/// - **Baked** (completed stroke):  [x, y, width]
/// - **Raw** (in-progress stroke):  [x, y, pressure, timestamp]
void drawFountainPenStroke(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;

  final isRaw = stroke.points.first.length >= 4;

  if (isRaw) {
    _drawRawFountainPreview(canvas, stroke);
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
    return FountainPenEngine.tessellate(centerline, widths);
  });
  canvas.drawPath(
    path,
    Paint()
      ..color = Color(stroke.colorValue)
      ..style = PaintingStyle.fill,
  );
}

void _drawRawFountainPreview(Canvas canvas, DrawingStroke stroke) {
  final points = stroke.points;
  final color = Color(stroke.colorValue);
  if (points.length == 1) {
    final pressure = points.first.length > 2 ? points.first[2] : 0.5;
    final r = stroke.strokeWidth * pressureWidthFactor(pressure) / 2;
    canvas.drawCircle(
      Offset(points.first[0], points.first[1]),
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    return;
  }

  final paint =
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  for (int i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final start = Offset(a[0], a[1]);
    final end = Offset(b[0], b[1]);
    final delta = end - start;
    final dist = delta.distance;
    if (dist <= 0) continue;
    final pa = a.length > 2 ? a[2] : 0.5;
    final pb = b.length > 2 ? b[2] : 0.5;
    final pressure = (pa + pb) * 0.5;
    final directionFactor = 1.0 + (delta.dy / dist) * 0.35;
    final pressureFactor = pressureWidthFactor(pressure);
    final taper =
        i < 4
            ? i / 4
            : points.length - i < 4
            ? (points.length - i).clamp(1, 4) / 4
            : 1.0;
    paint.strokeWidth =
        (stroke.strokeWidth * directionFactor * pressureFactor).clamp(
          0.5,
          stroke.strokeWidth * 2.0,
        ) *
        taper;
    if (paint.strokeWidth > 0) canvas.drawLine(start, end, paint);
  }
}
