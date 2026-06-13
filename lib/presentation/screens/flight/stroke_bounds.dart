import 'package:flutter/material.dart';

import 'note_cell_model.dart';

class StrokeBoundsCacheEntry {
  final int pointCount;
  final double firstX;
  final double firstY;
  final double lastX;
  final double lastY;
  final double strokeWidth;
  final Rect bounds;

  const StrokeBoundsCacheEntry({
    required this.pointCount,
    required this.firstX,
    required this.firstY,
    required this.lastX,
    required this.lastY,
    required this.strokeWidth,
    required this.bounds,
  });

  bool matches(DrawingStroke stroke) {
    final p = stroke.points;
    if (p.isEmpty) return pointCount == 0;
    return pointCount == p.length &&
        firstX == p.firstX &&
        firstY == p.firstY &&
        lastX == p.lastX &&
        lastY == p.lastY &&
        strokeWidth == stroke.strokeWidth;
  }
}

final _strokeBoundsCache = Expando<StrokeBoundsCacheEntry>();

Rect strokeBounds(DrawingStroke stroke) {
  final cached = _strokeBoundsCache[stroke];
  if (cached != null && cached.matches(stroke)) return cached.bounds;
  final points = stroke.points;
  if (points.isEmpty) return Rect.zero;
  var left = points.firstX;
  var top = points.firstY;
  var right = left;
  var bottom = top;
  for (int i = 1; i < points.length; i++) {
    final x = points.x(i);
    final y = points.y(i);
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  final pad = stroke.strokeWidth * 0.5 + 2;
  final bounds = Rect.fromLTRB(
    left - pad,
    top - pad,
    right + pad,
    bottom + pad,
  );
  _strokeBoundsCache[stroke] = StrokeBoundsCacheEntry(
    pointCount: points.length,
    firstX: points.firstX,
    firstY: points.firstY,
    lastX: points.lastX,
    lastY: points.lastY,
    strokeWidth: stroke.strokeWidth,
    bounds: bounds,
  );
  return bounds;
}

bool strokeOverlapsRect(DrawingStroke stroke, Rect rect) =>
    strokeBounds(stroke).overlaps(rect);

class _StrokePathCacheEntry {
  final int pointCount;
  final double firstX;
  final double firstY;
  final double lastX;
  final double lastY;
  final double strokeWidth;
  final Path path;

  const _StrokePathCacheEntry({
    required this.pointCount,
    required this.firstX,
    required this.firstY,
    required this.lastX,
    required this.lastY,
    required this.strokeWidth,
    required this.path,
  });

  bool matches(DrawingStroke stroke) {
    final p = stroke.points;
    if (p.isEmpty) return pointCount == 0;
    return pointCount == p.length &&
        firstX == p.firstX &&
        firstY == p.firstY &&
        lastX == p.lastX &&
        lastY == p.lastY &&
        strokeWidth == stroke.strokeWidth;
  }
}

final _strokePathCache = Expando<_StrokePathCacheEntry>();

/// Per-stroke geometry cache. Baked strokes are immutable, so the rendered
/// [Path] can be reused across repaints (pan/zoom). The signature (point count
/// + endpoints + width) catches the in-place mutations that lasso commits make
/// (move/rotate/resize/flip all move the endpoints) and the growing active
/// stroke (point count changes each tick). Mirrors [strokeBounds].
Path cachedStrokePath(DrawingStroke stroke, Path Function() build) {
  final cached = _strokePathCache[stroke];
  if (cached != null && cached.matches(stroke)) return cached.path;
  final path = build();
  final points = stroke.points;
  if (points.isNotEmpty) {
    _strokePathCache[stroke] = _StrokePathCacheEntry(
      pointCount: points.length,
      firstX: points.firstX,
      firstY: points.firstY,
      lastX: points.lastX,
      lastY: points.lastY,
      strokeWidth: stroke.strokeWidth,
      path: path,
    );
  }
  return path;
}
