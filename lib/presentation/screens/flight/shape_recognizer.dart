// Shape recognition for the whiteboard. Apple-Notes-style: when the user
// stops moving but keeps their stylus down, we run [detect] on the live
// stroke. If it matches a primitive (line / circle / ellipse / rectangle
// / triangle / arrow) we replace the freehand points with clean geometry.

import 'dart:math' as math;

import 'note_cell_model.dart';

class ShapeRecognizer {
  /// Detect a shape in `points`. Returns a clean stroke geometry or null if
  /// no high-confidence match. Output keeps caller's color/width.
  static List<List<double>>? detect(List<List<double>> points) {
    if (points.length < 12) return null;
    final bb = _bbox(points);
    final diag = math.sqrt(
        (bb.maxX - bb.minX) * (bb.maxX - bb.minX) +
            (bb.maxY - bb.minY) * (bb.maxY - bb.minY));
    if (diag < 30) return null;

    final closed = _isClosed(points, diag);

    if (!closed) {
      final lineFit = _tryLine(points, diag);
      if (lineFit != null) {
        final arrow = _tryArrow(points, lineFit, diag);
        if (arrow != null) return arrow;
        return lineFit;
      }
    }

    if (closed) {
      final poly = _tryPolygon(points, bb, diag);
      if (poly != null) return poly;

      final circle = _tryCircle(points, bb, diag);
      if (circle != null) return circle;
    }

    return null;
  }
}

// ─── Geometry helpers ─────────────────────────────────────────────────────

class _BBox {
  final double minX, minY, maxX, maxY;
  _BBox(this.minX, this.minY, this.maxX, this.maxY);
  double get width => maxX - minX;
  double get height => maxY - minY;
}

_BBox _bbox(List<List<double>> pts) {
  double minX = pts.first[0], maxX = pts.first[0];
  double minY = pts.first[1], maxY = pts.first[1];
  for (final p in pts) {
    if (p[0] < minX) minX = p[0];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] < minY) minY = p[1];
    if (p[1] > maxY) maxY = p[1];
  }
  return _BBox(minX, minY, maxX, maxY);
}

bool _isClosed(List<List<double>> pts, double diag) {
  final a = pts.first;
  final b = pts.last;
  final d = math.sqrt(
      (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));
  return d < diag * 0.20;
}

double _perpDist(List<double> p, List<double> a, List<double> b) {
  final dx = b[0] - a[0];
  final dy = b[1] - a[1];
  final mag = math.sqrt(dx * dx + dy * dy);
  if (mag < 1e-6) {
    return math.sqrt(
        (p[0] - a[0]) * (p[0] - a[0]) + (p[1] - a[1]) * (p[1] - a[1]));
  }
  final num = (dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]).abs();
  return num / mag;
}

List<List<double>> _douglasPeucker(List<List<double>> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  double dmax = 0;
  int idx = 0;
  for (int i = 1; i < pts.length - 1; i++) {
    final d = _perpDist(pts[i], pts.first, pts.last);
    if (d > dmax) {
      dmax = d;
      idx = i;
    }
  }
  if (dmax > eps) {
    final left = _douglasPeucker(pts.sublist(0, idx + 1), eps);
    final right = _douglasPeucker(pts.sublist(idx), eps);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [pts.first, pts.last];
}

// ─── Line detection ───────────────────────────────────────────────────────

List<List<double>>? _tryLine(List<List<double>> pts, double diag) {
  if (pts.length < 6) return null;
  final a = pts.first;
  final b = pts.last;
  double dmax = 0;
  for (final p in pts) {
    final d = _perpDist(p, a, b);
    if (d > dmax) dmax = d;
  }
  // Endpoints must be far apart enough.
  final len = math.sqrt(
      (b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]));
  if (len < diag * 0.6) return null;
  if (dmax > diag * 0.06) return null;
  return [
    [a[0], a[1]],
    [b[0], b[1]],
  ];
}

// ─── Arrow detection ──────────────────────────────────────────────────────
//
// Heuristic: a line+arrow stroke has a long mostly-straight segment then a
// sudden V-shaped kink at the end (the arrowhead). Detect by simplifying
// and checking for a corner near the tail with two short edges.

List<List<double>>? _tryArrow(
    List<List<double>> pts, List<List<double>> line, double diag) {
  if (pts.length < 16) return null;
  // Use simplified version of last 30% of points to find arrowhead.
  final tailStart = (pts.length * 0.7).floor();
  final tail = pts.sublist(tailStart);
  if (tail.length < 6) return null;
  final simp = _douglasPeucker(tail, diag * 0.04);
  if (simp.length < 3) return null;
  // Arrowhead detected if there's a sharp turn within the tail.
  final head = simp.last;
  final headLen = diag * 0.18;
  final dir = _norm(line[1][0] - line[0][0], line[1][1] - line[0][1]);
  // Two arrowhead edges at ±150° from line direction.
  final left = _rot(dir, math.pi * 5 / 6);
  final right = _rot(dir, -math.pi * 5 / 6);
  return [
    [line[0][0], line[0][1]],
    [head[0], head[1]],
    [head[0] + left[0] * headLen, head[1] + left[1] * headLen],
    [head[0], head[1]],
    [head[0] + right[0] * headLen, head[1] + right[1] * headLen],
  ];
}

List<double> _norm(double x, double y) {
  final m = math.sqrt(x * x + y * y);
  if (m < 1e-6) return [0, 0];
  return [x / m, y / m];
}

List<double> _rot(List<double> v, double a) {
  final c = math.cos(a);
  final s = math.sin(a);
  return [v[0] * c - v[1] * s, v[0] * s + v[1] * c];
}

// ─── Circle / ellipse detection ───────────────────────────────────────────

List<List<double>>? _tryCircle(
    List<List<double>> pts, _BBox bb, double diag) {
  final cx = (bb.minX + bb.maxX) / 2;
  final cy = (bb.minY + bb.maxY) / 2;
  // Mean radius + std dev relative to mean.
  double sumD = 0;
  for (final p in pts) {
    sumD += math.sqrt(
        (p[0] - cx) * (p[0] - cx) + (p[1] - cy) * (p[1] - cy));
  }
  final meanD = sumD / pts.length;
  if (meanD < 10) return null;
  double sumSq = 0;
  for (final p in pts) {
    final d = math.sqrt(
        (p[0] - cx) * (p[0] - cx) + (p[1] - cy) * (p[1] - cy));
    sumSq += (d - meanD) * (d - meanD);
  }
  final std = math.sqrt(sumSq / pts.length);
  final spread = std / meanD;

  final aspect = bb.width / (bb.height < 1e-6 ? 1 : bb.height);

  if (spread < 0.12 && aspect > 0.7 && aspect < 1.4) {
    // Circle.
    final rx = bb.width / 2;
    final ry = bb.height / 2;
    return _ellipsePoints(cx, cy, rx, ry, 48);
  }
  // Maybe ellipse: spread is large because radii differ. Re-evaluate via
  // bbox semi-axes — accept if the points lie close to that ellipse.
  if (aspect > 1.3 || aspect < 0.77) {
    final rx = bb.width / 2;
    final ry = bb.height / 2;
    if (rx < 8 || ry < 8) return null;
    double maxErr = 0;
    for (final p in pts) {
      final nx = (p[0] - cx) / rx;
      final ny = (p[1] - cy) / ry;
      final r = math.sqrt(nx * nx + ny * ny);
      final err = (r - 1).abs();
      if (err > maxErr) maxErr = err;
    }
    if (maxErr < 0.22) {
      return _ellipsePoints(cx, cy, rx, ry, 64);
    }
  }
  return null;
}

List<List<double>> _ellipsePoints(
    double cx, double cy, double rx, double ry, int segments) {
  final out = <List<double>>[];
  for (int i = 0; i <= segments; i++) {
    final t = (i / segments) * 2 * math.pi;
    out.add([cx + rx * math.cos(t), cy + ry * math.sin(t)]);
  }
  return out;
}

// ─── Polygon detection (rectangle / triangle) ─────────────────────────────

List<List<double>>? _tryPolygon(
    List<List<double>> pts, _BBox bb, double diag) {
  final loop = [...pts];
  if (loop.last != loop.first) {
    loop.add([loop.first[0], loop.first[1]]);
  }

  // Try multiple epsilon values — hand-drawn corners are imprecise.
  for (final epsFactor in [0.10, 0.08, 0.06]) {
    final simp = _douglasPeucker(loop, diag * epsFactor);
    if (simp.length < 4) continue;
    var verts = simp.sublist(0, simp.length - 1);

    // Merge vertices that are too close (imprecise corner = 2 points).
    verts = _mergeClose(verts, diag * 0.08);

    if (verts.length == 4) {
      if (_areAnglesNear(verts, math.pi / 2, math.pi / 6)) {
        return [
          [bb.minX, bb.minY],
          [bb.maxX, bb.minY],
          [bb.maxX, bb.maxY],
          [bb.minX, bb.maxY],
          [bb.minX, bb.minY],
        ];
      }
    }

    if (verts.length == 3) {
      return [
        [verts[0][0], verts[0][1]],
        [verts[1][0], verts[1][1]],
        [verts[2][0], verts[2][1]],
        [verts[0][0], verts[0][1]],
      ];
    }
  }

  // Fallback: if bbox aspect is rectangular-ish and points hug the bbox,
  // it's likely a rectangle even if DP couldn't simplify cleanly.
  final aspect = bb.width / (bb.height < 1e-6 ? 1 : bb.height);
  if (aspect > 0.4 && aspect < 2.5 && bb.width > 30 && bb.height > 30) {
    final maxDist = _maxDistToBbox(pts, bb);
    if (maxDist < diag * 0.15) {
      return [
        [bb.minX, bb.minY],
        [bb.maxX, bb.minY],
        [bb.maxX, bb.maxY],
        [bb.minX, bb.maxY],
        [bb.minX, bb.minY],
      ];
    }
  }

  return null;
}

List<List<double>> _mergeClose(List<List<double>> verts, double minDist) {
  if (verts.length <= 3) return verts;
  final out = <List<double>>[verts.first];
  for (int i = 1; i < verts.length; i++) {
    final prev = out.last;
    final dx = verts[i][0] - prev[0];
    final dy = verts[i][1] - prev[1];
    if (dx * dx + dy * dy < minDist * minDist) {
      out.last = [(prev[0] + verts[i][0]) / 2, (prev[1] + verts[i][1]) / 2];
    } else {
      out.add(verts[i]);
    }
  }
  return out;
}

double _maxDistToBbox(List<List<double>> pts, _BBox bb) {
  double maxD = 0;
  for (final p in pts) {
    final dx = [
      (p[0] - bb.minX).abs(),
      (p[0] - bb.maxX).abs(),
    ].reduce(math.min);
    final dy = [
      (p[1] - bb.minY).abs(),
      (p[1] - bb.maxY).abs(),
    ].reduce(math.min);
    final d = math.min(dx, dy);
    if (d > maxD) maxD = d;
  }
  return maxD;
}

bool _areAnglesNear(
    List<List<double>> verts, double target, double tolerance) {
  final n = verts.length;
  for (int i = 0; i < n; i++) {
    final prev = verts[(i - 1 + n) % n];
    final curr = verts[i];
    final next = verts[(i + 1) % n];
    final v1x = prev[0] - curr[0];
    final v1y = prev[1] - curr[1];
    final v2x = next[0] - curr[0];
    final v2y = next[1] - curr[1];
    final m1 = math.sqrt(v1x * v1x + v1y * v1y);
    final m2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (m1 < 1e-6 || m2 < 1e-6) return false;
    final cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
    final angle = math.acos(cos.clamp(-1.0, 1.0));
    if ((angle - target).abs() > tolerance) return false;
  }
  return true;
}

/// Convert clean point list to a DrawingStroke with given style.
DrawingStroke shapeToStroke(
    List<List<double>> points, int colorValue, double strokeW) {
  return DrawingStroke(
    colorValue: colorValue,
    strokeWidth: strokeW,
    points: points.map((p) => [p[0], p[1]]).toList(),
  );
}
