import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'fountain_pen_engine.dart';
import 'fountain_pen_painter.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

final Paint _imagePaint = Paint()..filterQuality = FilterQuality.medium;

/// Draw a canvas image (behind strokes) honoring its position/size/rotation.
/// While the bitmap is still decoding, [image] is null and a light placeholder
/// box is drawn instead.
void drawCanvasImage(Canvas canvas, Image? image, CanvasImage ci) {
  final rect = Rect.fromLTWH(ci.x, ci.y, ci.w, ci.h);
  canvas.save();
  if (ci.rotation != 0) {
    final c = rect.center;
    canvas
      ..translate(c.dx, c.dy)
      ..rotate(ci.rotation)
      ..translate(-c.dx, -c.dy);
  }
  if (image != null) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, rect, _imagePaint);
  } else {
    canvas.drawRect(rect, Paint()..color = const Color(0x14000000));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
  canvas.restore();
}

/// Translucent fill for recognized closed shapes (GoodNotes-style). Builds a
/// straight-edge polygon from the stroke points and fills it with the stroke
/// color at low opacity. No-op for open / fountain / tiny strokes.
void fillStrokeShape(Canvas canvas, DrawingStroke stroke) {
  if (!stroke.filled || stroke.isFountainPen || stroke.points.length < 3) {
    return;
  }
  final pts = stroke.points;
  final path = Path()..moveTo(pts[0][0], pts[0][1]);
  for (int i = 1; i < pts.length; i++) {
    path.lineTo(pts[i][0], pts[i][1]);
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..color = Color(stroke.colorValue).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill,
  );
}

void drawStroke(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;
  if (stroke.isFountainPen) {
    drawFountainPenStroke(canvas, stroke);
    return;
  }
  if (stroke.isPencil) {
    drawPencilStroke(canvas, stroke);
    return;
  }
  fillStrokeShape(canvas, stroke);
  final paint = Paint()
    ..color = Color(stroke.colorValue)
    ..strokeWidth = stroke.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (stroke.isHighlighter) {
    // Multiply blend keeps the ink underneath dark/legible while tinting the
    // paper — reads like a real marker without reordering render passes.
    paint
      ..blendMode = BlendMode.multiply
      ..color = Color(stroke.colorValue).withValues(alpha: 0.5);
  }
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      Offset(stroke.points[0][0], stroke.points[0][1]),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  canvas.drawPath(cachedStrokePath(stroke, () => buildStrokePath(stroke)), paint);
}

/// Flat-width centerline strip with tapered tips (touch-down / lift-off),
/// reusing the fountain-pen tessellator. Gives a plain pen a livelier feel
/// without per-point pressure/velocity width.
Path buildTaperedPenPath(DrawingStroke stroke) {
  final pts = stroke.points.map((p) => Offset(p[0], p[1])).toList();
  final centerline = FountainPenEngine.chaikinSmooth(pts, iterations: 1);
  final widths = List<double>.filled(centerline.length, stroke.strokeWidth);
  FountainPenEngine.taperWidths(widths, taperLength: 5);
  return FountainPenEngine.tessellate(centerline, widths);
}

ImageShader? _pencilGrain;
bool _pencilGrainLoading = false;

/// Lazily builds a small tiling graphite-grain texture ONCE and exposes it as a
/// repeating [ImageShader]. Returns null until the async decode finishes (the
/// first pencil stroke renders as a plain translucent strip, then grain kicks
/// in). Deliberately a GPU-sampled raster — one [drawPath] per stroke inside the
/// already-cached layers, never a per-frame redraw — so it cannot reproduce the
/// old full-screen noise-Picture stall.
ImageShader? _pencilGrainShader() {
  if (_pencilGrain != null) return _pencilGrain;
  if (_pencilGrainLoading) return null;
  _pencilGrainLoading = true;
  const n = 96;
  final px = Uint8List(n * n * 4);
  final rng = math.Random(7);
  for (int i = 0; i < n * n; i++) {
    final a = (110 + rng.nextDouble() * 145).toInt();
    px[i * 4] = 255;
    px[i * 4 + 1] = 255;
    px[i * 4 + 2] = 255;
    px[i * 4 + 3] = a;
  }
  decodeImageFromPixels(px, n, n, PixelFormat.rgba8888, (img) {
    _pencilGrain = ImageShader(
      img,
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList(<double>[
        1, 0, 0, 0, //
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]),
    );
  });
  return null;
}

/// Render a pencil stroke: the tapered flat-width strip, filled with the grain
/// texture tinted to the stroke color at reduced opacity (graphite feel).
void drawPencilStroke(Canvas canvas, DrawingStroke stroke) {
  final base = Color(stroke.colorValue);
  if (stroke.points.length < 2) {
    canvas.drawCircle(
      Offset(stroke.points[0][0], stroke.points[0][1]),
      stroke.strokeWidth / 2,
      Paint()
        ..color = base.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill,
    );
    return;
  }
  final path = cachedStrokePath(stroke, () => buildTaperedPenPath(stroke));
  final paint = Paint()
    ..color = base.withValues(alpha: 0.82)
    ..style = PaintingStyle.fill;
  final grain = _pencilGrainShader();
  if (grain != null) {
    paint
      ..shader = grain
      ..colorFilter =
          ColorFilter.mode(base.withValues(alpha: 0.82), BlendMode.srcIn);
  }
  canvas.drawPath(path, paint);
}

/// Build the outline path for a non-fountain stroke. Recognized shapes
/// ([DrawingStroke.isShape]) use crisp straight segments; freehand strokes use
/// quadratic midpoint smoothing.
Path buildStrokePath(DrawingStroke stroke) {
  final pts = stroke.points;
  final path = Path()..moveTo(pts[0][0], pts[0][1]);
  if (stroke.isShape) {
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i][0], pts[i][1]);
    }
    return path;
  }
  for (int i = 1; i < pts.length - 1; i++) {
    final x0 = pts[i][0];
    final y0 = pts[i][1];
    final x1 = pts[i + 1][0];
    final y1 = pts[i + 1][1];
    path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
  }
  path.lineTo(pts.last[0], pts.last[1]);
  return path;
}

List<List<double>> smoothPoints(List<List<double>> pts) {
  if (pts.length < 3) return pts;
  final out = <List<double>>[pts.first];
  for (int i = 1; i < pts.length - 1; i++) {
    out.add([
      (pts[i - 1][0] + pts[i][0] * 2 + pts[i + 1][0]) / 4,
      (pts[i - 1][1] + pts[i][1] * 2 + pts[i + 1][1]) / 4,
    ]);
  }
  out.add(pts.last);
  return out;
}
