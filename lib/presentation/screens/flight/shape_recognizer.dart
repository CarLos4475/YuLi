// Shape recognition for the whiteboard / notebook. Apple-Notes-style: when the
// user stops moving but keeps their stylus down, we run [detect] on the live
// stroke. If it matches a primitive (line / arrow / circle / ellipse /
// rectangle / triangle) we replace the freehand points with clean geometry and
// then let the ongoing drag resize/redirect it until the pen lifts.

import 'dart:math' as math;

enum ShapeKind { line, arrow, circle, ellipse, rectangle, triangle, star, pentagram }

class RecognizedShape {
  final ShapeKind kind;
  final List<List<double>> points;
  const RecognizedShape(this.kind, this.points);

  /// Open shapes (line/arrow) are adjusted by moving their end point;
  /// closed shapes are scaled around their centre.
  bool get isOpen => kind == ShapeKind.line || kind == ShapeKind.arrow;
}

class ShapeRecognizer {
  /// Detect a shape in [points]. Returns the recognized geometry + kind, or
  /// null if no confident match. Output keeps the caller's color/width.
  static RecognizedShape? detect(List<List<double>> points) {
    if (points.length < 12) return null;
    final bb = _bbox(points);
    final diag = math.sqrt(bb.width * bb.width + bb.height * bb.height);
    if (diag < 22) return null;

    final closed = _isClosed(points, diag);
    final resampled = _resample(points, 64);

    // Straight line / arrow take priority for clearly-open strokes.
    final line = _tryLine(points, diag);
    if (line != null && !closed) {
      if (_hasArrowhead(points, line, diag)) {
        return RecognizedShape(
            ShapeKind.arrow, buildArrowShape(line[0][0], line[0][1], line[1][0], line[1][1]));
      }
      return RecognizedShape(ShapeKind.line, [
        [line[0][0], line[0][1]],
        [line[1][0], line[1][1]],
      ]);
    }

    // Five-pointed stars — tried before polygons (a star's 5 tips would
    // otherwise confuse the corner counter). Discriminates a clean outline
    // from a crossing-line pentagram by the drawn path's self-intersections.
    final star = _tryStar(resampled);
    if (star != null) return star;

    // Closed shapes — tried even if not perfectly closed, since people rarely
    // close a circle/rectangle exactly.
    final poly = _tryPolygon(resampled, bb, diag);
    if (poly != null) return poly;

    final circle = _tryCircle(resampled, bb);
    if (circle != null) return circle;

    // Closed-ish but actually a line (thin loop) — accept the line.
    if (line != null) {
      return RecognizedShape(ShapeKind.line, [
        [line[0][0], line[0][1]],
        [line[1][0], line[1][1]],
      ]);
    }
    return null;
  }
}

// ─── Live-adjust builders (shared with the editors) ────────────────────────

List<List<double>> buildLineShape(double ax, double ay, double bx, double by) =>
    [
      [ax, ay],
      [bx, by],
    ];

/// Axis-aligned rectangle centred at [cx],[cy] with footprint [w]x[h].
/// Closed polyline (last point repeats the first).
List<List<double>> buildRectShape(double cx, double cy, double w, double h) {
  final hw = w / 2, hh = h / 2;
  return [
    [cx - hw, cy - hh],
    [cx + hw, cy - hh],
    [cx + hw, cy + hh],
    [cx - hw, cy + hh],
    [cx - hw, cy - hh],
  ];
}

/// Ellipse centred at [cx],[cy] with radii [w]/2 x [h]/2 (a circle when equal).
List<List<double>> buildEllipseShape(double cx, double cy, double w, double h) =>
    _ellipsePoints(cx, cy, w / 2, h / 2, 64);

/// Upright isosceles triangle centred at [cx],[cy] with footprint [w]x[h].
List<List<double>> buildTriangleShape(double cx, double cy, double w, double h) {
  final hw = w / 2, hh = h / 2;
  return [
    [cx, cy - hh],
    [cx + hw, cy + hh],
    [cx - hw, cy + hh],
    [cx, cy - hh],
  ];
}

/// Clean geometry for a shape inserted at [cx],[cy] with footprint [w]x[h].
/// Used by the editors' "insert shape" tool (no recognition involved).
List<List<double>> buildShape(
    ShapeKind kind, double cx, double cy, double w, double h) {
  switch (kind) {
    case ShapeKind.rectangle:
      return buildRectShape(cx, cy, w, h);
    case ShapeKind.circle:
    case ShapeKind.ellipse:
      return buildEllipseShape(cx, cy, w, h);
    case ShapeKind.triangle:
      return buildTriangleShape(cx, cy, w, h);
    case ShapeKind.line:
      return buildLineShape(cx - w / 2, cy, cx + w / 2, cy);
    case ShapeKind.arrow:
      return buildArrowShape(cx - w / 2, cy, cx + w / 2, cy);
    case ShapeKind.star:
      return buildStarShape(cx, cy, w, h);
    case ShapeKind.pentagram:
      return buildPentagramShape(cx, cy, w, h);
  }
}

/// Five-pointed star outline (10 vertices, tip/valley alternating, closed).
List<List<double>> buildStarShape(double cx, double cy, double w, double h) =>
    _starPoints(cx, cy, math.min(w, h) / 2, -math.pi / 2, pentagram: false);

/// Five-line pentagram — the {5/2} star polygon: tips joined skipping one, the
/// edges crossing in the centre. Closed path but never filled (hollow centre).
List<List<double>> buildPentagramShape(double cx, double cy, double w, double h) =>
    _starPoints(cx, cy, math.min(w, h) / 2, -math.pi / 2, pentagram: true);

/// Geometry shared by the menu builders and the snap recognizer. [tipAngle] is
/// the angle of the first outer point; the rest follow every 72°.
List<List<double>> _starPoints(double cx, double cy, double R, double tipAngle,
    {required bool pentagram}) {
  const step = 2 * math.pi / 5;
  if (pentagram) {
    final tips = <List<double>>[];
    for (int k = 0; k < 5; k++) {
      final a = tipAngle + k * step;
      tips.add([cx + R * math.cos(a), cy + R * math.sin(a)]);
    }
    const order = [0, 2, 4, 1, 3];
    final out = [
      for (final i in order) [tips[i][0], tips[i][1]]
    ];
    out.add([out.first[0], out.first[1]]);
    return out;
  }
  final r = R * 0.382; // classic inner/outer ratio of a regular 5-point star
  final out = <List<double>>[];
  for (int k = 0; k < 5; k++) {
    final ao = tipAngle + k * step;
    out.add([cx + R * math.cos(ao), cy + R * math.sin(ao)]);
    final ai = ao + step / 2;
    out.add([cx + r * math.cos(ai), cy + r * math.sin(ai)]);
  }
  out.add([out.first[0], out.first[1]]);
  return out;
}

/// Closed shapes can carry a translucent fill; open shapes (line/arrow) and the
/// hollow-centred pentagram can't.
bool shapeKindIsClosed(ShapeKind kind) =>
    kind == ShapeKind.rectangle ||
    kind == ShapeKind.triangle ||
    kind == ShapeKind.circle ||
    kind == ShapeKind.ellipse ||
    kind == ShapeKind.star;

List<List<double>> buildArrowShape(
    double ax, double ay, double bx, double by) {
  final dir = _norm(bx - ax, by - ay);
  final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
  final headLen = (len * 0.22).clamp(8.0, 44.0);
  final left = _rot(dir, math.pi * 5 / 6);
  final right = _rot(dir, -math.pi * 5 / 6);
  return [
    [ax, ay],
    [bx, by],
    [bx + left[0] * headLen, by + left[1] * headLen],
    [bx, by],
    [bx + right[0] * headLen, by + right[1] * headLen],
  ];
}

/// Centroid of a closed shape's vertices. Ignores the duplicated closing
/// vertex so the scale centre isn't biased toward the start point.
List<double> shapeCentroid(List<List<double>> pts) {
  var n = pts.length;
  if (n > 1 &&
      pts.first[0] == pts.last[0] &&
      pts.first[1] == pts.last[1]) {
    n--;
  }
  double sx = 0, sy = 0;
  for (int i = 0; i < n; i++) {
    sx += pts[i][0];
    sy += pts[i][1];
  }
  return [sx / n, sy / n];
}

/// Scale [pts] around [cx],[cy] by factor [k].
List<List<double>> scaleShape(
        List<List<double>> pts, double cx, double cy, double k) =>
    pts
        .map((p) => [cx + (p[0] - cx) * k, cy + (p[1] - cy) * k])
        .toList();

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

double _dist(List<double> a, List<double> b) =>
    math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));

bool _isClosed(List<List<double>> pts, double diag) {
  final d = _dist(pts.first, pts.last);
  return d < diag * 0.22;
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

/// Uniform arc-length resampling to [n] points. Removes the speed-bias that
/// destabilizes corner/curvature analysis.
List<List<double>> _resample(List<List<double>> pts, int n) {
  if (pts.length < 2) return pts;
  double total = 0;
  for (int i = 1; i < pts.length; i++) {
    total += _dist(pts[i - 1], pts[i]);
  }
  if (total < 1e-6) return [pts.first, pts.last];
  final interval = total / (n - 1);
  final out = <List<double>>[
    [pts.first[0], pts.first[1]]
  ];
  double accum = 0;
  var prev = pts.first;
  int i = 1;
  while (i < pts.length) {
    final curr = pts[i];
    final d = _dist(prev, curr);
    if (d > 0 && accum + d >= interval) {
      final t = (interval - accum) / d;
      final np = [prev[0] + t * (curr[0] - prev[0]), prev[1] + t * (curr[1] - prev[1])];
      out.add(np);
      prev = np;
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
  final len = _dist(a, b);
  if (len < diag * 0.6) return null;
  if (dmax > diag * 0.08) return null;
  return [
    [a[0], a[1]],
    [b[0], b[1]],
  ];
}

// ─── Arrow detection ──────────────────────────────────────────────────────
//
// A line+arrow stroke ends in a V-shaped barb: drawn continuously, the tail
// contains at least one sharp (>~115°) reversal. A plain line has none.

bool _hasArrowhead(
    List<List<double>> pts, List<List<double>> line, double diag) {
  if (pts.length < 16) return false;
  final tailStart = (pts.length * 0.65).floor();
  final tail = pts.sublist(tailStart);
  if (tail.length < 4) return false;
  final simp = _douglasPeucker(tail, diag * 0.05);
  if (simp.length < 3) return false;
  int sharp = 0;
  for (int i = 1; i < simp.length - 1; i++) {
    final ax = simp[i][0] - simp[i - 1][0];
    final ay = simp[i][1] - simp[i - 1][1];
    final bx = simp[i + 1][0] - simp[i][0];
    final by = simp[i + 1][1] - simp[i][1];
    final ma = math.sqrt(ax * ax + ay * ay);
    final mb = math.sqrt(bx * bx + by * by);
    if (ma < 1e-3 || mb < 1e-3) continue;
    final cos = (ax * bx + ay * by) / (ma * mb);
    final turn = math.acos(cos.clamp(-1.0, 1.0));
    if (turn > 2.0) sharp++; // > ~115°
  }
  return sharp >= 1;
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

RecognizedShape? _tryCircle(List<List<double>> pts, _BBox bb) {
  final c = shapeCentroid(pts);
  final cx = c[0], cy = c[1];
  double sumD = 0;
  for (final p in pts) {
    sumD += _dist(p, [cx, cy]);
  }
  final meanD = sumD / pts.length;
  if (meanD < 10) return null;
  double sumSq = 0;
  for (final p in pts) {
    final d = _dist(p, [cx, cy]);
    sumSq += (d - meanD) * (d - meanD);
  }
  final spread = math.sqrt(sumSq / pts.length) / meanD;
  final aspect = bb.width / (bb.height < 1e-6 ? 1 : bb.height);

  if (spread < 0.18 && aspect > 0.75 && aspect < 1.34) {
    return RecognizedShape(
        ShapeKind.circle, _ellipsePoints(cx, cy, meanD, meanD, 48));
  }

  // Ellipse: radii differ. Validate points lie near the bbox ellipse.
  final ecx = (bb.minX + bb.maxX) / 2;
  final ecy = (bb.minY + bb.maxY) / 2;
  final rx = bb.width / 2;
  final ry = bb.height / 2;
  if (rx < 8 || ry < 8) return null;
  double maxErr = 0;
  for (final p in pts) {
    final nx = (p[0] - ecx) / rx;
    final ny = (p[1] - ecy) / ry;
    final r = math.sqrt(nx * nx + ny * ny);
    final err = (r - 1).abs();
    if (err > maxErr) maxErr = err;
  }
  if (maxErr < 0.25) {
    return RecognizedShape(
        ShapeKind.ellipse, _ellipsePoints(ecx, ecy, rx, ry, 64));
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

class _Corner {
  final List<double> p;
  final double turn;
  _Corner(this.p, this.turn);
}

/// Find dominant corners on a (near-)closed resampled contour via local
/// turning-angle maxima with non-maximum suppression.
List<_Corner> _dominantCorners(List<List<double>> pts) {
  final n = pts.length;
  if (n < 8) return [];
  final k = math.max(2, n ~/ 12);
  final turns = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final a = pts[(i - k + n) % n];
    final c = pts[(i + k) % n];
    final v1x = pts[i][0] - a[0], v1y = pts[i][1] - a[1];
    final v2x = c[0] - pts[i][0], v2y = c[1] - pts[i][1];
    final m1 = math.sqrt(v1x * v1x + v1y * v1y);
    final m2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (m1 < 1e-6 || m2 < 1e-6) continue;
    final cos = (v1x * v2x + v1y * v2y) / (m1 * m2);
    turns[i] = math.acos(cos.clamp(-1.0, 1.0)); // turning angle (0=straight)
  }
  const thresh = 0.7; // ~40°
  final corners = <_Corner>[];
  for (int i = 0; i < n; i++) {
    if (turns[i] < thresh) continue;
    bool isMax = true;
    for (int j = -k; j <= k; j++) {
      final m = (i + j + n) % n;
      if (turns[m] > turns[i]) {
        isMax = false;
        break;
      }
    }
    if (isMax) corners.add(_Corner([pts[i][0], pts[i][1]], turns[i]));
  }
  return corners;
}

List<List<double>> _bboxRect(_BBox bb) => [
      [bb.minX, bb.minY],
      [bb.maxX, bb.minY],
      [bb.maxX, bb.maxY],
      [bb.minX, bb.maxY],
      [bb.minX, bb.minY],
    ];

/// Fraction of points lying within [tol] of any bbox side. ~1.0 for an
/// axis-aligned rectangle, low for triangles (diagonal edges) and circles
/// (arcs bow inward away from the corners).
double _hugFraction(List<List<double>> pts, _BBox bb, double tol) {
  int near = 0;
  for (final p in pts) {
    final dEdge = math.min(
      math.min((p[0] - bb.minX).abs(), (p[0] - bb.maxX).abs()),
      math.min((p[1] - bb.minY).abs(), (p[1] - bb.maxY).abs()),
    );
    if (dEdge < tol) near++;
  }
  return near / pts.length;
}

/// True when all four bbox sides carry a meaningful share of points. A
/// rectangle covers every side; a triangle leaves one side touched only by a
/// single vertex.
bool _allSidesCovered(List<List<double>> pts, _BBox bb, double tol) {
  int top = 0, bottom = 0, left = 0, right = 0;
  for (final p in pts) {
    if ((p[1] - bb.minY).abs() < tol) top++;
    if ((p[1] - bb.maxY).abs() < tol) bottom++;
    if ((p[0] - bb.minX).abs() < tol) left++;
    if ((p[0] - bb.maxX).abs() < tol) right++;
  }
  final minCov = pts.length * 0.05;
  return top > minCov && bottom > minCov && left > minCov && right > minCov;
}

RecognizedShape? _tryPolygon(List<List<double>> pts, _BBox bb, double diag) {
  // Axis-aligned rectangle: the contour hugs its bounding box AND every side
  // is covered. Robust to corner-count quirks (e.g. wide/short rectangles
  // whose short sides have too few samples to yield 4 corners) while rejecting
  // triangles (one side touched only by a vertex) and circles (arcs bow in).
  if (bb.width > 20 && bb.height > 20) {
    final tol = diag * 0.05;
    if (_hugFraction(pts, bb, tol) > 0.80 &&
        _allSidesCovered(pts, bb, tol)) {
      return RecognizedShape(ShapeKind.rectangle, _bboxRect(bb));
    }
  }

  var corners = _dominantCorners(pts);
  // A spurious extra corner at the start/end seam → drop the weakest.
  if (corners.length == 5) {
    double minTurn = double.infinity;
    int minIdx = 0;
    for (int i = 0; i < corners.length; i++) {
      if (corners[i].turn < minTurn) {
        minTurn = corners[i].turn;
        minIdx = i;
      }
    }
    corners.removeAt(minIdx);
  }
  if (corners.length < 3 || corners.length > 4) return null;

  final verts = corners.map((c) => c.p).toList();

  // 4 corners with right-ish angles — rectangle (axis-aligned bbox if upright,
  // otherwise keep the detected quad to support rotated rectangles).
  if (verts.length == 4 && _areAnglesNear(verts, math.pi / 2, math.pi / 5)) {
    if (_isAxisAligned(verts)) {
      return RecognizedShape(ShapeKind.rectangle, _bboxRect(bb));
    }
    return RecognizedShape(ShapeKind.rectangle, [
      ...verts.map((v) => [v[0], v[1]]),
      [verts[0][0], verts[0][1]],
    ]);
  }

  if (verts.length == 3) {
    return RecognizedShape(ShapeKind.triangle, [
      [verts[0][0], verts[0][1]],
      [verts[1][0], verts[1][1]],
      [verts[2][0], verts[2][1]],
      [verts[0][0], verts[0][1]],
    ]);
  }
  return null;
}

bool _isAxisAligned(List<List<double>> verts) {
  final n = verts.length;
  for (int i = 0; i < n; i++) {
    final a = verts[i];
    final b = verts[(i + 1) % n];
    final dx = (b[0] - a[0]).abs();
    final dy = (b[1] - a[1]).abs();
    // Each edge should be mostly horizontal or mostly vertical.
    final minor = math.min(dx, dy);
    final major = math.max(dx, dy);
    if (major < 1e-6) continue;
    if (minor / major > 0.25) return false;
  }
  return true;
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

// ─── Star / pentagram detection ───────────────────────────────────────────
//
// Both shapes share one silhouette: 5 radial tips with deep valleys (~0.38 of
// the tip radius) between them — so the angular radius profile alone can't tell
// them apart. The discriminator is the DRAWN path: an outline never crosses
// itself, a one-stroke pentagram crosses ~5 times.

RecognizedShape? _tryStar(List<List<double>> pts) {
  final c = shapeCentroid(pts);
  final cx = c[0], cy = c[1];

  // Silhouette radius per angular bin (the farthest point seen at each angle),
  // remembering which actual point produced it so we can reuse the user's real
  // tips later instead of synthesizing perfect ones.
  const bins = 60;
  final rad = List<double>.filled(bins, 0);
  final radPt = List<List<double>?>.filled(bins, null);
  for (final p in pts) {
    final d = _dist(p, [cx, cy]);
    final a = math.atan2(p[1] - cy, p[0] - cx); // -pi..pi
    final b = (((a + math.pi) / (2 * math.pi)) * bins).floor() % bins;
    if (d > rad[b]) {
      rad[b] = d;
      radPt[b] = p;
    }
  }
  // Fill gaps from the nearest populated bin so peak counting stays stable.
  for (int i = 0; i < bins; i++) {
    if (rad[i] > 0) continue;
    for (int o = 1; o < bins; o++) {
      final l = rad[(i - o + bins) % bins];
      final r = rad[(i + o) % bins];
      if (l > 0 || r > 0) {
        rad[i] = math.max(l, r);
        break;
      }
    }
  }

  double maxR = 0, minR = double.infinity;
  for (final v in rad) {
    if (v > maxR) maxR = v;
    if (v < minR) minR = v;
  }
  if (maxR < 9) return null;
  if (minR / maxR > 0.6) return null; // not spiky enough (circle / pentagon)

  // Find prominent tips: circular local maxima above a mid threshold, merged
  // within a window so a flat top isn't double-counted.
  final thresh = minR + 0.45 * (maxR - minR);
  const k = 3;
  final used = List<bool>.filled(bins, false);
  final peakBins = <int>[];
  for (int i = 0; i < bins; i++) {
    if (used[i] || rad[i] < thresh) continue;
    bool isMax = true;
    for (int j = -k; j <= k; j++) {
      if (j == 0) continue;
      if (rad[(i + j + bins) % bins] > rad[i]) {
        isMax = false;
        break;
      }
    }
    if (!isMax) continue;
    peakBins.add(i);
    for (int j = -k; j <= k; j++) {
      used[(i + j + bins) % bins] = true;
    }
  }
  if (peakBins.length != 5) return null;

  final pentagram = _countSelfIntersections(pts) >= 3;

  if (pentagram) {
    // Keep the user's asymmetry: join their actual tips with straight lines in
    // the {5/2} skip-one order. We straighten the edges but don't regularize
    // the star into a perfect symmetric one.
    final tips = <List<double>>[];
    for (final b in peakBins) {
      List<double>? pt;
      double best = -1;
      for (int j = -k; j <= k; j++) {
        final bb = (b + j + bins) % bins;
        if (radPt[bb] != null && rad[bb] > best) {
          best = rad[bb];
          pt = radPt[bb];
        }
      }
      if (pt != null) tips.add([pt[0], pt[1]]);
    }
    if (tips.length == 5) {
      tips.sort((p, q) => math
          .atan2(p[1] - cy, p[0] - cx)
          .compareTo(math.atan2(q[1] - cy, q[0] - cx)));
      const order = [0, 2, 4, 1, 3];
      final out = [
        for (final i in order) [tips[i][0], tips[i][1]]
      ];
      out.add([out.first[0], out.first[1]]);
      return RecognizedShape(ShapeKind.pentagram, out);
    }
  }

  // Clean outline star → tidy regular geometry (this is the "limpia" variant).
  double tipAngle = 0, far = -1;
  for (final p in pts) {
    final d = _dist(p, [cx, cy]);
    if (d > far) {
      far = d;
      tipAngle = math.atan2(p[1] - cy, p[0] - cx);
    }
  }
  return RecognizedShape(
    ShapeKind.star,
    _starPoints(cx, cy, maxR, tipAngle, pentagram: false),
  );
}

/// Number of times the (closed) polyline [pts] crosses itself, ignoring
/// adjacent segments and the closing seam.
int _countSelfIntersections(List<List<double>> pts) {
  final n = pts.length;
  if (n < 6) return 0;
  int count = 0;
  for (int i = 0; i < n - 1; i++) {
    for (int j = i + 2; j < n - 1; j++) {
      if (i == 0 && j == n - 2) continue; // first & last share the seam vertex
      if (_segmentsCross(pts[i], pts[i + 1], pts[j], pts[j + 1])) count++;
    }
  }
  return count;
}

/// Proper (interior) crossing of segments a-b and c-d. Collinear / endpoint
/// touches don't count.
bool _segmentsCross(
    List<double> a, List<double> b, List<double> c, List<double> d) {
  double cross(List<double> o, List<double> p, List<double> q) =>
      (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0]);
  final d1 = cross(c, d, a);
  final d2 = cross(c, d, b);
  final d3 = cross(a, b, c);
  final d4 = cross(a, b, d);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}
