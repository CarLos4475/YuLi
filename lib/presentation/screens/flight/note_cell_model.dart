import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;
import 'package:uuid/uuid.dart';

import '../../../domain/models/page_background.dart';
import 'stroke_points.dart';

export 'stroke_points.dart';

enum DrawTool {
  pen,
  pencil,
  fountainPen,
  highlighter,
  eraser,
  lasso,
  text,
  task,
}

/// stroke = erase the whole stroke on touch (object eraser, default).
/// partial = erase only the touched portion, splitting the stroke.
enum EraserMode { stroke, partial }

class DrawingData {
  double height;
  List<DrawingStroke> strokes;
  List<CanvasImage> images;
  List<CanvasTaskBlock> taskBlocks;
  List<CanvasTextBlock> textBlocks;
  PageBackground background;

  /// Paper color (ARGB). null → editor's default paper color.
  int? bgColorValue;

  DrawingData({
    this.height = 300,
    List<DrawingStroke>? strokes,
    List<CanvasImage>? images,
    List<CanvasTaskBlock>? taskBlocks,
    List<CanvasTextBlock>? textBlocks,
    this.background = PageBackground.blank,
    this.bgColorValue,
  }) : strokes = strokes ?? [],
       images = images ?? [],
       taskBlocks = taskBlocks ?? [],
       textBlocks = textBlocks ?? [];

  Map<String, dynamic> toJson() => {
    'h': height,
    's': strokes.map((s) => s.toJson()).toList(),
    if (images.isNotEmpty) 'i': images.map((im) => im.toJson()).toList(),
    if (taskBlocks.isNotEmpty) 't': taskBlocks.map((b) => b.toJson()).toList(),
    if (textBlocks.isNotEmpty) 'tx': textBlocks.map((b) => b.toJson()).toList(),
    'bg': background.toDbString(),
    if (bgColorValue != null) 'bgc': bgColorValue,
  };

  factory DrawingData.fromJson(Map<String, dynamic> json) => DrawingData(
    height: (json['h'] as num?)?.toDouble() ?? 300,
    strokes:
        (json['s'] as List?)
            ?.map((s) => DrawingStroke.fromJson(s as Map<String, dynamic>))
            .toList() ??
        [],
    images:
        (json['i'] as List?)
            ?.map((im) => CanvasImage.fromJson(im as Map<String, dynamic>))
            .toList() ??
        [],
    taskBlocks:
        (json['t'] as List?)
            ?.map((b) => CanvasTaskBlock.fromJson(b as Map<String, dynamic>))
            .toList() ??
        [],
    textBlocks:
        (json['tx'] as List?)
            ?.map((b) => CanvasTextBlock.fromJson(b as Map<String, dynamic>))
            .toList() ??
        [],
    background: PageBackground.fromString((json['bg'] as String?) ?? ''),
    bgColorValue: (json['bgc'] as num?)?.toInt(),
  );
}

/// Shared mutable geometry for canvas objects driven by the lasso (images and
/// task blocks alike): an axis-aligned box plus a rotation about its center.
/// Lets the [LassoController] move/resize/rotate any box without caring whether
/// it's a bitmap or an interactive widget.
abstract class CanvasGeo {
  double get x;
  set x(double v);
  double get y;
  set y(double v);
  double get w;
  set w(double v);
  double get h;
  set h(double v);
  double get rotation;
  set rotation(double v);
}

/// An image placed on the drawing canvas. Stored by [filename] only — the
/// absolute path is rebuilt from the note id at load time, so it survives app
/// reinstalls / sandbox path changes. Geometry is an explicit transform.
class CanvasImage implements CanvasGeo {
  final String filename;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  double rotation;

  CanvasImage({
    required this.filename,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
  });

  CanvasImage clone() => CanvasImage(
    filename: filename,
    x: x,
    y: y,
    w: w,
    h: h,
    rotation: rotation,
  );

  Map<String, dynamic> toJson() => {
    'f': filename,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    if (rotation != 0) 'r': rotation,
  };

  factory CanvasImage.fromJson(Map<String, dynamic> json) => CanvasImage(
    filename: json['f'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
    rotation: (json['r'] as num?)?.toDouble() ?? 0,
  );
}

/// An interactive task block placed on the drawing canvas. Geometry mirrors
/// [CanvasImage] (so the lasso treats both identically); [taskIds] reference
/// real Task entities linked to the host note (FIGHT/LAB live globally). The
/// block content is rendered as a widget overlay, never painted to the canvas.
class CanvasTaskBlock implements CanvasGeo {
  /// Stable id for overlay widget keys (survives reorders of the list).
  final String id;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  double rotation;
  List<int> taskIds;

  /// Uniform visual scale applied on top of the content layout. The card is
  /// laid out at width `w / scale` (text reflow) and then scaled by [scale], so
  /// corner-resize (which multiplies [scale]) grows the whole block including
  /// its text, while side-resize (which only changes [w]) reflows the text at
  /// the same font size.
  double scale;

  CanvasTaskBlock({
    String? id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.scale = 1.0,
    List<int>? taskIds,
  }) : id = id ?? const Uuid().v4(),
       taskIds = taskIds ?? [];

  CanvasTaskBlock clone() => CanvasTaskBlock(
    id: id,
    x: x,
    y: y,
    w: w,
    h: h,
    rotation: rotation,
    scale: scale,
    taskIds: List<int>.from(taskIds),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    if (rotation != 0) 'r': rotation,
    if (scale != 1.0) 'sc': scale,
    'ids': taskIds,
  };

  factory CanvasTaskBlock.fromJson(Map<String, dynamic> json) =>
      CanvasTaskBlock(
        id: json['id'] as String?,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        rotation: (json['r'] as num?)?.toDouble() ?? 0,
        scale: (json['sc'] as num?)?.toDouble() ?? 1.0,
        taskIds:
            ((json['ids'] as List?) ?? const [])
                .map((e) => (e as num).toInt())
                .toList(),
      );
}

/// An interactive markdown text block placed on the drawing canvas. Geometry
/// mirrors [CanvasTaskBlock] (same lasso treatment, same uniform-scale resize
/// model) but it holds raw [markdown] rendered with the note editor's markdown
/// engine — so a chat message "sent to canvas" looks identical to a note cell.
class CanvasTextBlock implements CanvasGeo {
  /// Stable id for overlay widget keys (survives reorders of the list).
  final String id;
  @override
  double x;
  @override
  double y;
  @override
  double w;
  @override
  double h;
  @override
  double rotation;

  /// Markdown source rendered by the shared note markdown engine.
  String markdown;

  /// Uniform visual scale applied on top of the content layout. The content is
  /// laid out at width `w / scale` (text reflow) and then scaled by [scale], so
  /// corner/vertical resize (which multiplies [scale]) grows the whole block
  /// including its text, while horizontal resize (which only changes [w])
  /// reflows the text at the same font size.
  double scale;

  /// When true the block was created from the AI chat as a fixed square; its
  /// height never auto-adjusts and overflow is scrollable instead of clipped.
  bool isSquare;

  CanvasTextBlock({
    String? id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.scale = 1.0,
    this.markdown = '',
    this.isSquare = false,
  }) : id = id ?? const Uuid().v4();

  CanvasTextBlock clone() => CanvasTextBlock(
    id: id,
    x: x,
    y: y,
    w: w,
    h: h,
    rotation: rotation,
    scale: scale,
    markdown: markdown,
    isSquare: isSquare,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    if (rotation != 0) 'r': rotation,
    if (scale != 1.0) 'sc': scale,
    if (isSquare) 'sq': true,
    'md': markdown,
  };

  factory CanvasTextBlock.fromJson(Map<String, dynamic> json) =>
      CanvasTextBlock(
        id: json['id'] as String?,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        rotation: (json['r'] as num?)?.toDouble() ?? 0,
        scale: (json['sc'] as num?)?.toDouble() ?? 1.0,
        markdown: (json['md'] as String?) ?? '',
        isSquare: json['sq'] as bool? ?? false,
      );
}

class DrawingStroke {
  int? dbId;
  final int colorValue;
  final double strokeWidth;
  final StrokePoints points;
  final bool isFountainPen;

  /// Closed snapped shape rendered with a translucent fill of [colorValue]
  /// (GoodNotes-style). Only set on recognized closed shapes.
  final bool filled;

  /// Recognized shape (line/arrow/circle/rect/triangle): rendered as a crisp
  /// straight-edge polyline instead of the freehand quadratic smoothing.
  final bool isShape;

  /// Highlighter stroke: wide + translucent, drawn with a multiply blend so the
  /// ink underneath stays readable.
  final bool isHighlighter;

  /// Pencil stroke: flat-width tapered strip filled with a grain texture +
  /// translucency for a graphite feel.
  final bool isPencil;

  DrawingStroke({
    this.dbId,
    required this.colorValue,
    required this.strokeWidth,
    StrokePoints? points,
    this.isFountainPen = false,
    this.filled = false,
    this.isShape = false,
    this.isHighlighter = false,
    this.isPencil = false,
  }) : points = points ?? StrokePoints();

  /// Deep copy. Preserves flags and every point component (fountain-pen points
  /// carry a 3rd baked-width value).
  DrawingStroke clone() => DrawingStroke(
    dbId: dbId,
    colorValue: colorValue,
    strokeWidth: strokeWidth,
    isFountainPen: isFountainPen,
    filled: filled,
    isShape: isShape,
    isHighlighter: isHighlighter,
    isPencil: isPencil,
    points: points.clone(),
  );

  DrawingStroke copyWith({
    int? colorValue,
    double? strokeWidth,
    StrokePoints? points,
  }) => DrawingStroke(
    dbId: dbId,
    colorValue: colorValue ?? this.colorValue,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isFountainPen: isFountainPen,
    filled: filled,
    isShape: isShape,
    isHighlighter: isHighlighter,
    isPencil: isPencil,
    points: points ?? this.points,
  );

  Map<String, dynamic> toJson() => {
    if (dbId != null) 'dbid': dbId,
    'c': colorValue,
    'w': strokeWidth,
    'p': points.toNested(),
    if (isFountainPen) 'f': 1,
    if (filled) 'fl': 1,
    if (isShape) 'sh': 1,
    if (isHighlighter) 'hl': 1,
    if (isPencil) 'pc': 1,
  };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
    dbId: (json['dbid'] as num?)?.toInt(),
    colorValue: json['c'] as int,
    strokeWidth: (json['w'] as num).toDouble(),
    points: StrokePoints.fromNested(
      (json['p'] as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
    ),
    isFountainPen: (json['f'] as int?) == 1,
    filled: (json['fl'] as int?) == 1,
    isShape: (json['sh'] as int?) == 1,
    isHighlighter: (json['hl'] as int?) == 1,
    isPencil: (json['pc'] as int?) == 1,
  );

  static const int _binFountainPen = 1;
  static const int _binFilled = 2;
  static const int _binShape = 4;
  static const int _binHighlighter = 8;
  static const int _binPencil = 16;

  /// Compact binary encoding of a single stroke (see [DrawingStroke.fromBytes]).
  /// Stored as a BLOB per row — ~2-3x smaller than the JSON payload and far
  /// cheaper to decode (no string tokenising / number-from-text parsing, the
  /// real bottleneck when opening dense notes). [dbId] is NOT encoded — it's the
  /// row id, owned by the persistence layer. Little-endian, host-portable.
  Uint8List toBytes() {
    final comps = points.comps;
    final n = points.length;
    final bd = ByteData(16 + n * comps * 4);
    bd.setUint8(0, 1); // format version
    var flags = 0;
    if (isFountainPen) flags |= _binFountainPen;
    if (filled) flags |= _binFilled;
    if (isShape) flags |= _binShape;
    if (isHighlighter) flags |= _binHighlighter;
    if (isPencil) flags |= _binPencil;
    bd.setUint8(1, flags);
    bd.setUint8(2, comps);
    bd.setUint8(3, 0); // reserved
    bd.setUint32(4, colorValue, Endian.little);
    bd.setFloat32(8, strokeWidth, Endian.little);
    bd.setUint32(12, n, Endian.little);
    // Bulk-copy the contiguous float region (host LE == our format on all
    // targets). The 16-byte header keeps the points 4-byte aligned.
    if (n > 0) {
      Float32List.view(bd.buffer, 16, n * comps).setAll(0, points.packed());
    }
    return bd.buffer.asUint8List();
  }

  /// Decode a stroke BLOB. The points are a contiguous little-endian float32
  /// region after the 16-byte header → a single bulk copy into a [Float32List],
  /// not ~N sub-list allocations. This is the open-time / RAM win the whole
  /// [StrokePoints] refactor exists for.
  factory DrawingStroke.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final flags = bd.getUint8(1);
    final comps = bd.getUint8(2);
    final color = bd.getUint32(4, Endian.little);
    final width = bd.getFloat32(8, Endian.little);
    final n = bd.getUint32(12, Endian.little);
    final data = Float32List(n * comps);
    final byteOff = bytes.offsetInBytes + 16;
    if (byteOff % 4 == 0) {
      data.setAll(0, Float32List.view(bytes.buffer, byteOff, n * comps));
    } else {
      for (var i = 0; i < n * comps; i++) {
        data[i] = bd.getFloat32(16 + i * 4, Endian.little);
      }
    }
    return DrawingStroke(
      colorValue: color,
      strokeWidth: width,
      points: StrokePoints.fromFloat32(data, comps),
      isFountainPen: flags & _binFountainPen != 0,
      filled: flags & _binFilled != 0,
      isShape: flags & _binShape != 0,
      isHighlighter: flags & _binHighlighter != 0,
      isPencil: flags & _binPencil != 0,
    );
  }
}

// ─── Scribble detection ──────────────────────────────────────────────────────

/// Arc-length resample to [n] evenly-spaced points. Preserves the path shape
/// while normalising point density so that angular-variance and
/// crossing-density analysis see the same "resolution" regardless of how
/// many raw pointer events were delivered.
StrokePoints _resampleTo(StrokePoints pts, int n) {
  if (pts.length < 3 || pts.length <= n) return pts;
  double total = 0;
  for (int i = 1; i < pts.length; i++) {
    final dx = pts.x(i) - pts.x(i - 1);
    final dy = pts.y(i) - pts.y(i - 1);
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total < 1e-6) return pts;
  final interval = total / (n - 1);
  final out = StrokePoints(comps: 2)..add(pts.x(0), pts.y(0));
  double accum = 0;
  double prevX = pts.x(0), prevY = pts.y(0);
  int i = 1;
  while (i < pts.length && out.length < n) {
    final cx = pts.x(i);
    final cy = pts.y(i);
    final dx = cx - prevX;
    final dy = cy - prevY;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > 0 && accum + d >= interval) {
      final t = (interval - accum) / d;
      final nx = prevX + t * (cx - prevX);
      final ny = prevY + t * (cy - prevY);
      out.add(nx, ny);
      prevX = nx;
      prevY = ny;
      accum = 0;
    } else {
      accum += d;
      prevX = cx;
      prevY = cy;
      i++;
    }
  }
  while (out.length < n) {
    out.add(pts.lastX, pts.lastY);
  }
  return out;
}

/// Detects the "scribble to erase" gesture. Points are in WORLD/canvas
/// coordinates, but the gesture is perceptual — what the user drew on screen.
/// [viewScale] (canvas zoom) converts the absolute size thresholds and the
/// crossing density to screen pixels, so the same hand motion reads identically
/// whether the canvas is zoomed in or out. Without it, zooming in shrinks a
/// stroke's world footprint, letting normal small cursive slip past the size
/// gate while inflating the crossing density — and legitimate handwriting gets
/// erased. Defaults to 1.0 for callers drawing in unscaled coordinates.
bool isScribble(StrokePoints points, {double viewScale = 1.0}) {
  if (points.length < 15) return false;

  final scale = viewScale.isFinite && viewScale > 0 ? viewScale : 1.0;

  // Bounds in screen pixels: how big the scribble actually looked.
  final bounds = scribbleBounds(points);
  if (bounds.width * scale > 120 || bounds.height * scale > 120) return false;

  // Path length in screen pixels (original points — resampling wouldn't change
  // it).
  double pathLength = 0;
  for (int i = 1; i < points.length; i++) {
    final dx = points.x(i) - points.x(i - 1);
    final dy = points.y(i) - points.y(i - 1);
    pathLength += math.sqrt(dx * dx + dy * dy);
  }
  pathLength *= scale;
  if (pathLength < 20) return false;

  // Normalise point density so angular variance / crossing density work
  // reliably regardless of how many raw pointer events Flutter delivers.
  // Without this, a scribble drawn when the app is "warm" (high event rate)
  // has consecutive segments so close they appear nearly collinear → angVar ≈ 0.
  const anN = 40;
  final analysisPts = points.length > anN ? _resampleTo(points, anN) : points;

  // (B) Angular variance: average |sin(angle)| between consecutive segments.
  // Scribbles zigzag sharply; cursive flows smoothly even through loops.
  double totalAngle = 0;
  int angleSegments = 0;
  for (int i = 1; i < analysisPts.length - 1; i++) {
    final ax = analysisPts.x(i) - analysisPts.x(i - 1);
    final ay = analysisPts.y(i) - analysisPts.y(i - 1);
    final bx = analysisPts.x(i + 1) - analysisPts.x(i);
    final by = analysisPts.y(i + 1) - analysisPts.y(i);
    final magSqA = ax * ax + ay * ay;
    final magSqB = bx * bx + by * by;
    if (magSqA < 1 || magSqB < 1) continue;
    totalAngle += (ax * by - ay * bx).abs() / math.sqrt(magSqA * magSqB);
    angleSegments++;
  }
  if (angleSegments == 0) return false;
  final angularVariance = totalAngle / angleSegments;

  // (D) Crossing density: self-intersections per pixel of path.
  int crossings = 0;
  final len = analysisPts.length;
  for (int i = 0; i < len - 3 && crossings < 50; i++) {
    for (int j = i + 2; j < len - 1; j++) {
      if (_segmentsIntersect(
        analysisPts.x(i),
        analysisPts.y(i),
        analysisPts.x(i + 1),
        analysisPts.y(i + 1),
        analysisPts.x(j),
        analysisPts.y(j),
        analysisPts.x(j + 1),
        analysisPts.y(j + 1),
      )) {
        crossings++;
      }
    }
  }

  final crossingDensity = crossings / pathLength;

  return crossings >= 4 && crossingDensity > 0.04 && angularVariance > 0.25;
}

bool _segmentsIntersect(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
  double dx,
  double dy,
) {
  double cross(double ux, double uy, double vx, double vy) => ux * vy - uy * vx;
  final d1 = cross(dx - cx, dy - cy, ax - cx, ay - cy);
  final d2 = cross(dx - cx, dy - cy, bx - cx, by - cy);
  final d3 = cross(bx - ax, by - ay, cx - ax, cy - ay);
  final d4 = cross(bx - ax, by - ay, dx - ax, dy - ay);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

// ─── Eraser hit test ─────────────────────────────────────────────────────────

double _distToSegment2(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-9) {
    final ex = px - ax;
    final ey = py - ay;
    return ex * ex + ey * ey;
  }
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx;
  final cy = ay + t * dy;
  final ex = px - cx;
  final ey = py - cy;
  return ex * ex + ey * ey;
}

/// Partial erase: remove points within [radius] of [pos], returning the
/// surviving pieces (0, 1, or more). Returns the original `[s]` unchanged when
/// nothing was erased. Pieces keep color/width/fountain/highlighter; the
/// shape/fill flags are dropped (a clean shape being cut becomes plain ink).
List<DrawingStroke> splitStrokeByEraser(
  DrawingStroke s,
  Offset pos,
  double radius,
) {
  final pts = s.points;
  final comps = pts.comps;
  final r = radius + s.strokeWidth / 2;
  final r2 = r * r;
  if (pts.isEmpty) return const [];
  if (pts.length == 1) {
    final dx = pts.x(0) - pos.dx;
    final dy = pts.y(0) - pos.dy;
    return dx * dx + dy * dy < r2 ? const [] : [s];
  }
  // Subdivide segments that the eraser crosses so sparse strokes
  // (shape-snap rectangles / triangles with only 4-5 vertices) and
  // wide strokes (highlighter) are cut correctly at the hit point. The
  // interpolated cut point carries every component (preserving fountain/pencil
  // width) so the stroke stays uniform-stride. Cold path (eraser) → the small
  // nested temp buffer here is fine.
  final sub = <List<double>>[];
  for (int i = 0; i < pts.length; i++) {
    sub.add([for (int c = 0; c < comps; c++) pts.comp(i, c)]);
    if (i < pts.length - 1) {
      final ax = pts.x(i);
      final ay = pts.y(i);
      final bx = pts.x(i + 1);
      final by = pts.y(i + 1);
      final d2 = _distToSegment2(pos.dx, pos.dy, ax, ay, bx, by);
      if (d2 < r2) {
        final dxSeg = bx - ax;
        final dySeg = by - ay;
        final len2 = dxSeg * dxSeg + dySeg * dySeg;
        if (len2 >= 1e-9) {
          var t = ((pos.dx - ax) * dxSeg + (pos.dy - ay) * dySeg) / len2;
          t = t.clamp(0.0, 1.0);
          sub.add([
            for (int c = 0; c < comps; c++)
              pts.comp(i, c) + t * (pts.comp(i + 1, c) - pts.comp(i, c)),
          ]);
        }
      }
    }
  }
  final runs = <List<List<double>>>[];
  var cur = <List<double>>[];
  var anyErased = false;
  for (final p in sub) {
    final dx = p[0] - pos.dx;
    final dy = p[1] - pos.dy;
    if (dx * dx + dy * dy < r2) {
      anyErased = true;
      if (cur.length >= 2) runs.add(cur);
      cur = [];
    } else {
      cur.add(p);
    }
  }
  if (cur.length >= 2) runs.add(cur);
  if (!anyErased) return [s];
  return runs
      .map(
        (pl) => DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          isFountainPen: s.isFountainPen,
          isHighlighter: s.isHighlighter,
          isPencil: s.isPencil,
          points: StrokePoints.fromNested(pl),
        ),
      )
      .toList();
}

/// True when the eraser tip at [pos] (with world-space [radius]) touches the
/// stroke. Tests distance to each segment plus the stroke's own half-width, so
/// only what the tip actually overlaps is erased.
bool strokeHitByEraser(DrawingStroke s, Offset pos, double radius) {
  final pts = s.points;
  if (pts.isEmpty) return false;
  final r = radius + s.strokeWidth / 2;
  final r2 = r * r;
  if (pts.length == 1) {
    final dx = pts.x(0) - pos.dx;
    final dy = pts.y(0) - pos.dy;
    return dx * dx + dy * dy < r2;
  }
  for (int i = 0; i < pts.length - 1; i++) {
    if (_distToSegment2(
          pos.dx,
          pos.dy,
          pts.x(i),
          pts.y(i),
          pts.x(i + 1),
          pts.y(i + 1),
        ) <
        r2) {
      return true;
    }
  }
  return false;
}

Rect scribbleBounds(StrokePoints points) {
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (int i = 0; i < points.length; i++) {
    final x = points.x(i);
    final y = points.y(i);
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

// ─── Serialization ───────────────────────────────────────────────────────────

/// Strips legacy `<!-- CELL -->` markers + division markers from a note's
/// rawMarkdown for snippet/preview rendering (e.g. Lab card source preview).
String cleanCellContent(String raw) {
  var cleaned = raw;
  cleaned = cleaned.replaceAll(RegExp(r'<!-- CELL \w+ \S+.*?-->'), '');
  cleaned = cleaned.replaceAll(RegExp(r':::\s*(left|center|right)\s*\n?'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^:::\s*$', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return cleaned.trim();
}
