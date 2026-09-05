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
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
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
  final path = Path()..moveTo(pts.x(0), pts.y(0));
  for (int i = 1; i < pts.length; i++) {
    path.lineTo(pts.x(i), pts.y(i));
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..color = Color(stroke.colorValue).withValues(alpha: 0.22)
      ..style = PaintingStyle.fill,
  );
}

/// Level-of-detail for a given canvas zoom. At low zoom a stroke is only a few
/// screen pixels, so its grain texture / fountain-width / extra points are
/// sub-pixel — drawing them in full is pure raster cost (the heat on dense,
/// zoomed-out boards). LOD 0 = full fidelity; 1/2 = decimated flat polyline.
/// Zoom at/above which strokes render at full fidelity (LOD 0). Below it the
/// vector tiles decimate (flat polyline, no fountain width, plain highlighter) —
/// so this is also the zoom below which the crisp LOD-0 overview raster is
/// preferred over the tiles (see _overviewActive in both editors).
const double kLodFullDetailScale = 0.6;

int lodForScale(double scale) {
  if (scale >= kLodFullDetailScale) return 0;
  if (scale >= 0.32) return 1;
  return 2;
}

int _decimationStep(int lod) => lod <= 1 ? 3 : 6;

/// Cheap fallback render used at LOD ≥ 1: a flat anti-aliased polyline through
/// every Nth point, no grain / no blend / no per-segment width. Visually
/// indistinguishable when the stroke is a few px tall, far cheaper to rasterize.
class _SimpPathEntry {
  final int step, pointCount;
  final double firstX, firstY, lastX, lastY;
  final Path path;
  const _SimpPathEntry(
    this.step,
    this.pointCount,
    this.firstX,
    this.firstY,
    this.lastX,
    this.lastY,
    this.path,
  );
  bool matches(DrawingStroke s, int step) {
    final p = s.points;
    return this.step == step &&
        pointCount == p.length &&
        firstX == p.firstX &&
        firstY == p.firstY &&
        lastX == p.lastX &&
        lastY == p.lastY;
  }
}

// Decimated path cached per stroke (one LOD at a time — a stroke is only drawn
// at the current zoom). Without this, crossing an LOD threshold rebuilt every
// visible stroke's polyline on the UI thread → a 100ms+ build spike on zoom.
final _simpPathCache = Expando<_SimpPathEntry>();

Path _buildSimplifiedPath(DrawingStroke stroke, int step) {
  final pts = stroke.points;
  final path = Path()..moveTo(pts.x(0), pts.y(0));
  for (int i = step; i < pts.length; i += step) {
    path.lineTo(pts.x(i), pts.y(i));
  }
  path.lineTo(pts.lastX, pts.lastY); // always close on the true endpoint
  return path;
}

Path _cachedSimplifiedPath(DrawingStroke stroke, int step) {
  final cached = _simpPathCache[stroke];
  if (cached != null && cached.matches(stroke, step)) return cached.path;
  final pts = stroke.points;
  final path = _buildSimplifiedPath(stroke, step);
  _simpPathCache[stroke] = _SimpPathEntry(
    step,
    pts.length,
    pts.firstX,
    pts.firstY,
    pts.lastX,
    pts.lastY,
    path,
  );
  return path;
}

void _drawStrokeSimplified(
  Canvas canvas,
  DrawingStroke stroke,
  int step, {
  bool cache = true,
}) {
  final pts = stroke.points;
  final paint =
      Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
  if (stroke.isHighlighter) {
    // Match the LOD-0 highlighter (drawStroke): multiply + 0.5. Without this the
    // marker visibly jumps to a stronger plain-srcOver tint the moment the view
    // decimates (zoom < kLodFullDetailScale) — the "highlighter gets darker on
    // pan/lasso" glitch.
    paint
      ..blendMode = BlendMode.multiply
      ..color = Color(stroke.colorValue).withValues(alpha: 0.5);
  }
  if (pts.length == 1) {
    canvas.drawCircle(
      Offset(pts.x(0), pts.y(0)),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  canvas.drawPath(
    cache
        ? _cachedSimplifiedPath(stroke, step)
        : _buildSimplifiedPath(stroke, step),
    paint,
  );
}

void drawStroke(
  Canvas canvas,
  DrawingStroke stroke, {
  double viewScale = 1.0,
  int lod = 0,
  // When false, paths are built transiently (not stored in the per-stroke
  // Expando cache). Used by one-shot full-board renders (the overview bake of a
  // very dense board) so they don't permanently retain a Path per stroke —
  // caching all of, say, 1.1M strokes' paths is what OOMs the open.
  bool cache = true,
  bool preserveAppearance = false,
}) {
  if (stroke.points.isEmpty) return;
  if (lod > 0 && !preserveAppearance) {
    _drawStrokeSimplified(canvas, stroke, _decimationStep(lod), cache: cache);
    return;
  }
  if (stroke.isFountainPen) {
    drawFountainPenStroke(canvas, stroke, viewScale: viewScale, cache: cache);
    return;
  }
  if (stroke.isPencil) {
    drawPencilStroke(canvas, stroke, cache: cache);
    return;
  }
  fillStrokeShape(canvas, stroke);
  final paint =
      Paint()
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
      Offset(stroke.points.x(0), stroke.points.y(0)),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  canvas.drawPath(
    cache
        ? cachedStrokePath(stroke, () => buildStrokePath(stroke))
        : buildStrokePath(stroke),
    paint,
  );
}

/// Prediction strength: how many averaged input-segments past the last point to
/// extrapolate the live ink. Masks input-to-display latency so the ink tracks
/// the pen tip (kills the "ink lags behind, then jumps forward on lift" feel).
/// Higher = stickier to the pen but more overshoot on sharp direction changes.
const double _kPredict = 2.5;

/// Draw the IN-PROGRESS stroke with a short predicted tip extrapolated from the
/// recent velocity, so the live ink keeps up with the pen. The committed stroke
/// (drawn via [drawStroke]) never includes the prediction → saved geometry stays
/// faithful, and the prediction self-cancels when the pen slows (velocity → 0).
void drawActiveStroke(
  Canvas canvas,
  DrawingStroke stroke, {
  double viewScale = 1.0,
}) {
  if (stroke.isShape) {
    drawStroke(canvas, stroke, viewScale: viewScale);
    return;
  }
  final tip = predictedTipPoint(stroke.points);
  if (tip == null) {
    drawStroke(canvas, stroke, viewScale: viewScale);
    return;
  }
  final extended = stroke.points.clone()..addLikeLast(tip.dx, tip.dy);
  drawStroke(
    canvas,
    DrawingStroke(
      colorValue: stroke.colorValue,
      strokeWidth: stroke.strokeWidth,
      isFountainPen: stroke.isFountainPen,
      isHighlighter: stroke.isHighlighter,
      isPencil: stroke.isPencil,
      isShape: stroke.isShape,
      filled: stroke.filled,
      points: extended,
    ),
    viewScale: viewScale,
  );
}

/// The extrapolated tip the live preview leads with (from the averaged recent
/// velocity). Also appended to a stroke on lift so the committed geometry ends
/// where the preview ended — no backward retraction. Returns null if there
/// aren't enough points or the pen isn't moving.
Offset? predictedTipPoint(StrokePoints pts) {
  final n = pts.length;
  if (n < 2) return null;
  final m = (n - 1) < 3 ? (n - 1) : 3;
  double vx = 0, vy = 0;
  for (int i = n - m; i < n; i++) {
    vx += pts.x(i) - pts.x(i - 1);
    vy += pts.y(i) - pts.y(i - 1);
  }
  vx /= m;
  vy /= m;
  return Offset(pts.lastX + vx * _kPredict, pts.lastY + vy * _kPredict);
}

/// Build the pencil's filled outline from its raw `[x, y, pressure]` points.
/// Downsamples first (slow strokes pack points densely, which destabilizes the
/// edge normals and reads as noise — same fix the fountain pen uses), derives a
/// per-point width from stylus pressure, smooths + tapers it, then tessellates
/// with clean edges (the grain fill supplies the texture, not edge wobble).
Path buildPencilPath(DrawingStroke stroke) {
  final raw = stroke.points;
  final pts = raw.toOffsets();
  final pressures = [
    for (int i = 0; i < raw.length; i++) raw.comps > 2 ? raw.z(i) : 0.5,
  ];
  final ts = List<int>.filled(raw.length, 0);
  final (dsPts, dsPre, _) = FountainPenEngine.downsample(
    pts,
    pressures,
    ts,
    minDist: 2.0,
  );
  final basePts = FountainPenEngine.smoothPolyline(dsPts, passes: 1);

  final base = stroke.strokeWidth;
  // Centered so medium pressure ≈ the selected base width (faithful), with a
  // modest ±30% pressure range.
  final rawWidths = [
    for (final p in dsPre) base * (0.7 + 0.6 * (p * p * (3 - 2 * p))),
  ];
  final widths = FountainPenEngine.smoothWidths(rawWidths, windowSize: 3);
  FountainPenEngine.taperWidths(widths, taperLength: 3);

  final centerline = FountainPenEngine.catmullRom(basePts, subdiv: 3);
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
    (coarse + 1) * (coarse + 1),
    (_) => rng.nextDouble(),
  );
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
      img,
      TileMode.repeated,
      TileMode.repeated,
      _identity4x4,
    );
  });
  return null;
}

/// Render a pencil stroke: the pressure-tapered strip, filled with the grain
/// texture tinted to the stroke color. Overall opacity follows the mean stylus
/// pressure, so a light hand leaves a lighter mark.
void drawPencilStroke(
  Canvas canvas,
  DrawingStroke stroke, {
  bool cache = true,
}) {
  final base = Color(stroke.colorValue);
  final pts = stroke.points;
  if (pts.length < 2) {
    canvas.drawCircle(
      Offset(pts.x(0), pts.y(0)),
      stroke.strokeWidth / 2,
      Paint()
        ..color = base.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill,
    );
    return;
  }

  double sum = 0;
  for (int i = 0; i < pts.length; i++) {
    sum += pts.comps > 2 ? pts.z(i) : 0.5;
  }
  final meanP = sum / pts.length;
  final alpha = (0.5 + 0.42 * meanP).clamp(0.45, 0.92);

  final path =
      cache
          ? cachedStrokePath(stroke, () => buildPencilPath(stroke))
          : buildPencilPath(stroke);
  final paint =
      Paint()
        ..color = base.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
  final grain = _pencilGrainShader();
  if (grain != null) {
    paint
      ..shader = grain
      ..colorFilter = ColorFilter.mode(
        base.withValues(alpha: alpha),
        BlendMode.srcIn,
      );
  }
  canvas.drawPath(path, paint);
}

/// Build the outline path for a non-fountain stroke. Recognized shapes
/// ([DrawingStroke.isShape]) use crisp straight segments; freehand strokes use
/// quadratic midpoint smoothing.
Path buildStrokePath(DrawingStroke stroke) {
  final pts = stroke.points;
  final path = Path()..moveTo(pts.x(0), pts.y(0));
  if (stroke.isShape) {
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts.x(i), pts.y(i));
    }
    return path;
  }
  for (int i = 1; i < pts.length - 1; i++) {
    final x0 = pts.x(i);
    final y0 = pts.y(i);
    final x1 = pts.x(i + 1);
    final y1 = pts.y(i + 1);
    path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
  }
  path.lineTo(pts.lastX, pts.lastY);
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
