import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'package:uuid/uuid.dart';

import '../../../domain/models/page_background.dart';

enum CellType { markdown, drawing }

enum DrawTool { pen, fountainPen, highlighter, eraser, lasso }

/// stroke = erase the whole stroke on touch (object eraser, default).
/// partial = erase only the touched portion, splitting the stroke.
enum EraserMode { stroke, partial }

class NoteCell {
  final String id;
  final CellType type;
  String content;
  DrawingData? drawingData;

  NoteCell({
    String? id,
    required this.type,
    this.content = '',
    this.drawingData,
  }) : id = id ?? const Uuid().v4();
}

class DrawingData {
  double height;
  List<DrawingStroke> strokes;
  List<CanvasImage> images;
  PageBackground background;

  /// Paper color (ARGB). null → editor's default paper color.
  int? bgColorValue;

  DrawingData({
    this.height = 300,
    List<DrawingStroke>? strokes,
    List<CanvasImage>? images,
    this.background = PageBackground.blank,
    this.bgColorValue,
  })  : strokes = strokes ?? [],
        images = images ?? [];

  Map<String, dynamic> toJson() => {
        'h': height,
        's': strokes.map((s) => s.toJson()).toList(),
        if (images.isNotEmpty) 'i': images.map((im) => im.toJson()).toList(),
        'bg': background.toDbString(),
        if (bgColorValue != null) 'bgc': bgColorValue,
      };

  factory DrawingData.fromJson(Map<String, dynamic> json) => DrawingData(
        height: (json['h'] as num?)?.toDouble() ?? 300,
        strokes: (json['s'] as List?)
                ?.map(
                    (s) => DrawingStroke.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        images: (json['i'] as List?)
                ?.map((im) => CanvasImage.fromJson(im as Map<String, dynamic>))
                .toList() ??
            [],
        background: PageBackground.fromString((json['bg'] as String?) ?? ''),
        bgColorValue: (json['bgc'] as num?)?.toInt(),
      );
}

/// An image placed on the drawing canvas. Stored by [filename] only — the
/// absolute path is rebuilt from the note id at load time, so it survives app
/// reinstalls / sandbox path changes. Geometry is an explicit transform.
class CanvasImage {
  final String filename;
  double x;
  double y;
  double w;
  double h;
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

class DrawingStroke {
  final int colorValue;
  final double strokeWidth;
  final List<List<double>> points;
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

  DrawingStroke({
    required this.colorValue,
    required this.strokeWidth,
    List<List<double>>? points,
    this.isFountainPen = false,
    this.filled = false,
    this.isShape = false,
    this.isHighlighter = false,
  }) : points = points ?? [];

  /// Deep copy. Preserves flags and every point component (fountain-pen points
  /// carry a 3rd baked-width value).
  DrawingStroke clone() => DrawingStroke(
        colorValue: colorValue,
        strokeWidth: strokeWidth,
        isFountainPen: isFountainPen,
        filled: filled,
        isShape: isShape,
        isHighlighter: isHighlighter,
        points: points.map((p) => List<double>.from(p)).toList(),
      );

  DrawingStroke copyWith({
    int? colorValue,
    double? strokeWidth,
    List<List<double>>? points,
  }) =>
      DrawingStroke(
        colorValue: colorValue ?? this.colorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        isFountainPen: isFountainPen,
        filled: filled,
        isShape: isShape,
        isHighlighter: isHighlighter,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'c': colorValue,
        'w': strokeWidth,
        'p': points,
        if (isFountainPen) 'f': 1,
        if (filled) 'fl': 1,
        if (isShape) 'sh': 1,
        if (isHighlighter) 'hl': 1,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
        colorValue: json['c'] as int,
        strokeWidth: (json['w'] as num).toDouble(),
        points: (json['p'] as List)
            .map((p) =>
                (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
        isFountainPen: (json['f'] as int?) == 1,
        filled: (json['fl'] as int?) == 1,
        isShape: (json['sh'] as int?) == 1,
        isHighlighter: (json['hl'] as int?) == 1,
      );
}

// ─── Scribble detection ──────────────────────────────────────────────────────

/// Arc-length resample to [n] evenly-spaced points. Preserves the path shape
/// while normalising point density so that angular-variance and
/// crossing-density analysis see the same "resolution" regardless of how
/// many raw pointer events were delivered.
List<List<double>> _resampleTo(List<List<double>> pts, int n) {
  if (pts.length < 3 || pts.length <= n) return pts;
  double total = 0;
  for (int i = 1; i < pts.length; i++) {
    final dx = pts[i][0] - pts[i - 1][0];
    final dy = pts[i][1] - pts[i - 1][1];
    total += math.sqrt(dx * dx + dy * dy);
  }
  if (total < 1e-6) return pts;
  final interval = total / (n - 1);
  final out = <List<double>>[
    [pts.first[0], pts.first[1]]
  ];
  double accum = 0;
  var prev = pts.first;
  int i = 1;
  while (i < pts.length && out.length < n) {
    final curr = pts[i];
    final dx = curr[0] - prev[0];
    final dy = curr[1] - prev[1];
    final d = math.sqrt(dx * dx + dy * dy);
    if (d > 0 && accum + d >= interval) {
      final t = (interval - accum) / d;
      out.add([
        prev[0] + t * (curr[0] - prev[0]),
        prev[1] + t * (curr[1] - prev[1]),
      ]);
      prev = out.last;
      accum = 0;
    } else {
      accum += d;
      prev = curr;
      i++;
    }
  }
  while (out.length < n) {
    out.add([pts.last[0], pts.last[1]]);
  }
  return out;
}

bool isScribble(List<List<double>> points) {
  if (points.length < 15) return false;

  final bounds = scribbleBounds(points);
  if (bounds.width > 120 || bounds.height > 120) return false;

  // Path length (original points — resampling wouldn't change it).
  double pathLength = 0;
  for (int i = 1; i < points.length; i++) {
    final dx = points[i][0] - points[i - 1][0];
    final dy = points[i][1] - points[i - 1][1];
    pathLength += math.sqrt(dx * dx + dy * dy);
  }
  if (pathLength < 20) return false;

  // Normalise point density so angular variance / crossing density work
  // reliably regardless of how many raw pointer events Flutter delivers.
  // Without this, a scribble drawn when the app is "warm" (high event rate)
  // has consecutive segments so close they appear nearly collinear → angVar ≈ 0.
  const anN = 40;
  final analysisPts =
      points.length > anN ? _resampleTo(points, anN) : points;

  // (B) Angular variance: average |sin(angle)| between consecutive segments.
  // Scribbles zigzag sharply; cursive flows smoothly even through loops.
  double totalAngle = 0;
  int angleSegments = 0;
  for (int i = 1; i < analysisPts.length - 1; i++) {
    final ax = analysisPts[i][0] - analysisPts[i - 1][0];
    final ay = analysisPts[i][1] - analysisPts[i - 1][1];
    final bx = analysisPts[i + 1][0] - analysisPts[i][0];
    final by = analysisPts[i + 1][1] - analysisPts[i][1];
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
        analysisPts[i][0], analysisPts[i][1],
        analysisPts[i + 1][0], analysisPts[i + 1][1],
        analysisPts[j][0], analysisPts[j][1],
        analysisPts[j + 1][0], analysisPts[j + 1][1],
      )) {
        crossings++;
      }
    }
  }

  final crossingDensity = crossings / pathLength;

  return crossings >= 4 && crossingDensity > 0.04 && angularVariance > 0.25;
}

bool _segmentsIntersect(
  double ax, double ay, double bx, double by,
  double cx, double cy, double dx, double dy,
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
    double px, double py, double ax, double ay, double bx, double by) {
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
    DrawingStroke s, Offset pos, double radius) {
  final pts = s.points;
  final r2 = radius * radius;
  if (pts.isEmpty) return const [];
  if (pts.length == 1) {
    final dx = pts[0][0] - pos.dx;
    final dy = pts[0][1] - pos.dy;
    return dx * dx + dy * dy < r2 ? const [] : [s];
  }
  final runs = <List<List<double>>>[];
  var cur = <List<double>>[];
  var anyErased = false;
  for (final p in pts) {
    final dx = p[0] - pos.dx;
    final dy = p[1] - pos.dy;
    if (dx * dx + dy * dy < r2) {
      anyErased = true;
      if (cur.length >= 2) runs.add(cur);
      cur = [];
    } else {
      cur.add(List<double>.from(p));
    }
  }
  if (cur.length >= 2) runs.add(cur);
  if (!anyErased) return [s];
  return runs
      .map((pl) => DrawingStroke(
            colorValue: s.colorValue,
            strokeWidth: s.strokeWidth,
            isFountainPen: s.isFountainPen,
            isHighlighter: s.isHighlighter,
            points: pl,
          ))
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
    final dx = pts[0][0] - pos.dx;
    final dy = pts[0][1] - pos.dy;
    return dx * dx + dy * dy < r2;
  }
  for (int i = 0; i < pts.length - 1; i++) {
    if (_distToSegment2(pos.dx, pos.dy, pts[i][0], pts[i][1], pts[i + 1][0],
            pts[i + 1][1]) <
        r2) {
      return true;
    }
  }
  return false;
}

Rect scribbleBounds(List<List<double>> points) {
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (final p in points) {
    if (p[0] < minX) minX = p[0];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] < minY) minY = p[1];
    if (p[1] > maxY) maxY = p[1];
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

// ─── Serialization ───────────────────────────────────────────────────────────

final _cellRe = RegExp(r'<!-- CELL (\w+) (\S+)(?: (.*))? -->');

List<NoteCell> parseCells(String raw) {
  if (!raw.contains('<!-- CELL ')) {
    return [NoteCell(type: CellType.markdown, content: raw)];
  }

  final cells = <NoteCell>[];
  final matches = _cellRe.allMatches(raw).toList();

  for (int i = 0; i < matches.length; i++) {
    final m = matches[i];
    final typeName = m.group(1)!;
    final id = m.group(2)!;
    final extra = m.group(3);

    if (typeName == 'markdown') {
      final start = m.end;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : raw.length;
      var content = raw.substring(start, end);
      if (content.startsWith('\n')) content = content.substring(1);
      while (content.endsWith('\n')) {
        content = content.substring(0, content.length - 1);
      }
      cells.add(NoteCell(id: id, type: CellType.markdown, content: content));
    } else if (typeName == 'drawing') {
      DrawingData data;
      if (extra != null && extra.isNotEmpty) {
        try {
          data = DrawingData.fromJson(
              jsonDecode(extra) as Map<String, dynamic>);
        } catch (_) {
          data = DrawingData();
        }
      } else {
        data = DrawingData();
      }
      cells.add(
          NoteCell(id: id, type: CellType.drawing, drawingData: data));
    }
  }

  return cells.isEmpty
      ? [NoteCell(type: CellType.markdown, content: raw)]
      : cells;
}

String cleanCellContent(String raw) {
  var cleaned = raw;
  cleaned = cleaned.replaceAll(RegExp(r'<!-- CELL \w+ \S+.*?-->'), '');
  cleaned = cleaned.replaceAll(RegExp(r':::\s*(left|center|right)\s*\n?'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^:::\s*$', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return cleaned.trim();
}

String serializeCells(List<NoteCell> cells) {
  if (cells.length == 1 && cells[0].type == CellType.markdown) {
    return cells[0].content;
  }

  final buf = StringBuffer();
  for (final cell in cells) {
    switch (cell.type) {
      case CellType.markdown:
        buf.writeln('<!-- CELL markdown ${cell.id} -->');
        buf.writeln(cell.content);
      case CellType.drawing:
        final data = cell.drawingData;
        if (data != null) {
          for (final stroke in data.strokes) {
            stroke.points.removeWhere(
                (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
          }
          data.strokes.removeWhere((s) => s.points.isEmpty);
        }
        try {
          final json = jsonEncode(data?.toJson() ?? {});
          buf.writeln('<!-- CELL drawing ${cell.id} $json -->');
        } catch (_) {
          buf.writeln('<!-- CELL drawing ${cell.id} {} -->');
        }
    }
  }
  return buf.toString();
}
