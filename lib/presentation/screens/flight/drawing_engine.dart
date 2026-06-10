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

/// Build the pencil's filled outline from its raw `[x, y, pressure]` points.
/// Downsamples first (slow strokes pack points densely, which destabilizes the
/// edge normals and reads as noise — same fix the fountain pen uses), derives a
/// per-point width from stylus pressure, smooths + tapers it, then tessellates
/// with clean edges (the grain fill supplies the texture, not edge wobble).
Path buildPencilPath(DrawingStroke stroke) {
  final raw = stroke.points;
  final pts = raw.map((p) => Offset(p[0], p[1])).toList();
  final pressures = raw.map((p) => p.length > 2 ? p[2] : 0.5).toList();
  final ts = List<int>.filled(raw.length, 0);
  final (dsPts, dsPre, _) =
      FountainPenEngine.downsample(pts, pressures, ts, minDist: 2.0);

  final base = stroke.strokeWidth;
  // Centered so medium pressure ≈ the selected base width (faithful), with a
  // modest ±30% pressure range.
  final rawWidths = [
    for (final p in dsPre) base * (0.7 + 0.6 * (p * p * (3 - 2 * p))),
  ];
  final widths = FountainPenEngine.smoothWidths(rawWidths, windowSize: 3);
  FountainPenEngine.taperWidths(widths, taperLength: 4);

  final centerline = FountainPenEngine.catmullRom(dsPts, subdiv: 4);
  final w = FountainPenEngine.interpolateWidths(widths, centerline.length);
  return FountainPenEngine.tessellate(centerline, w, noiseAmp: 0.0);
}

ImageShader? _pencilGrain;
bool _pencilGrainLoading = false;

final Float64List _identity4x4 = Float64List.fromList(<double>[
  1, 0, 0, 0, //
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
]);

/// Lazily builds a tiling graphite-grain texture ONCE and exposes it as a
/// repeating [ImageShader]. Returns null until the async decode finishes (the
/// first pencil stroke renders plain, then grain kicks in). The texture is
/// value-noise (soft paper-tooth clumps modulated by a fine speckle) rather than
/// per-pixel white noise, so it reads like graphite on paper instead of TV
/// static. Deliberately a GPU-sampled raster — one [drawPath] per stroke inside
/// the already-cached layers, never a per-frame redraw — so it cannot reproduce
/// the old full-screen noise-Picture stall.
ImageShader? _pencilGrainShader() {
  if (_pencilGrain != null) return _pencilGrain;
  if (_pencilGrainLoading) return null;
  _pencilGrainLoading = true;

  const n = 128;
  const coarse = 24; // soft-clump cells across the tile
  final rng = math.Random(7);
  final grid = List<double>.generate(
      (coarse + 1) * (coarse + 1), (_) => rng.nextDouble());
  double soft(double gx, double gy) {
    final x0 = gx.floor();
    final y0 = gy.floor();
    final fx = gx - x0;
    final fy = gy - y0;
    double g(int x, int y) =>
        grid[(y % (coarse + 1)) * (coarse + 1) + (x % (coarse + 1))];
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final top = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx;
    final bot = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx;
    return top + (bot - top) * sy;
  }

  final px = Uint8List(n * n * 4);
  for (int y = 0; y < n; y++) {
    for (int x = 0; x < n; x++) {
      final clump = soft(x / n * coarse, y / n * coarse);
      final speck = rng.nextDouble();
      var v = 0.55 * clump + 0.45 * speck;
      v = 0.4 + 0.6 * v; // lift so the lead stays mostly present
      final i = (y * n + x) * 4;
      px[i] = 255;
      px[i + 1] = 255;
      px[i + 2] = 255;
      px[i + 3] = (v.clamp(0.0, 1.0) * 255).toInt();
    }
  }
  decodeImageFromPixels(px, n, n, PixelFormat.rgba8888, (img) {
    _pencilGrain = ImageShader(
        img, TileMode.repeated, TileMode.repeated, _identity4x4);
  });
  return null;
}

/// Render a pencil stroke: the pressure-tapered strip, filled with the grain
/// texture tinted to the stroke color. Overall opacity follows the mean stylus
/// pressure, so a light hand leaves a lighter mark.
void drawPencilStroke(Canvas canvas, DrawingStroke stroke) {
  final base = Color(stroke.colorValue);
  final pts = stroke.points;
  if (pts.length < 2) {
    canvas.drawCircle(
      Offset(pts[0][0], pts[0][1]),
      stroke.strokeWidth / 2,
      Paint()
        ..color = base.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill,
    );
    return;
  }

  double sum = 0;
  for (final p in pts) {
    sum += p.length > 2 ? p[2] : 0.5;
  }
  final meanP = sum / pts.length;
  final alpha = (0.5 + 0.42 * meanP).clamp(0.45, 0.92);

  final path = cachedStrokePath(stroke, () => buildPencilPath(stroke));
  final paint = Paint()
    ..color = base.withValues(alpha: alpha)
    ..style = PaintingStyle.fill;
  final grain = _pencilGrainShader();
  if (grain != null) {
    paint
      ..shader = grain
      ..colorFilter =
          ColorFilter.mode(base.withValues(alpha: alpha), BlendMode.srcIn);
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
