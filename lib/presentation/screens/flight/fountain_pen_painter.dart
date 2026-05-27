import 'dart:ui';

import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';

/// Render a fountain-pen stroke onto [canvas].
///
/// Handles two point formats:
/// - **Baked** (completed stroke):  [x, y, width]
/// - **Raw** (in-progress stroke):  [x, y, pressure, timestamp]
void drawFountainPenStroke(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;

  final isRaw = stroke.points.first.length >= 4;

  List<Offset> centerline;
  List<double> widths;

  if (isRaw) {
    final rawPts =
        stroke.points.map((p) => Offset(p[0], p[1])).toList();
    final pressures =
        stroke.points.map((p) => p.length > 2 ? p[2] : 0.5).toList();
    final timestamps =
        stroke.points.map((p) => p.length > 3 ? p[3].toInt() : 0).toList();

    centerline =
        FountainPenEngine.chaikinSmooth(rawPts, iterations: 1);
    widths = FountainPenEngine.computeWidths(
      centerline,
      stroke.strokeWidth,
      pressures,
      timestamps,
    );
    FountainPenEngine.taperWidths(widths);
  } else {
    centerline =
        stroke.points.map((p) => Offset(p[0], p[1])).toList();
    widths = stroke.points
        .map((p) => p.length > 2 ? p[2] : stroke.strokeWidth)
        .toList();
  }

  if (centerline.length < 2) {
    if (centerline.length == 1) {
      final r = (widths.isNotEmpty ? widths[0] : stroke.strokeWidth) / 2;
      if (r > 0) {
        canvas.drawCircle(
          centerline[0],
          r,
          Paint()
            ..color = Color(stroke.colorValue)
            ..style = PaintingStyle.fill,
        );
      }
    }
    return;
  }

  final path = FountainPenEngine.tessellate(centerline, widths);
  canvas.drawPath(
    path,
    Paint()
      ..color = Color(stroke.colorValue)
      ..style = PaintingStyle.fill,
  );
}
