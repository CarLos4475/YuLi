import 'package:flutter/material.dart';

import 'drawing_engine.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

/// Spatial index of strokes bucketed into fixed world-space tiles, plus a
/// per-tile version counter. It does NOT cache pixels — it feeds one
/// [RepaintBoundary]+[CustomPaint] per tile, so Flutter's compositor caches each
/// tile's RASTER. That is the whole point: when a stroke is committed/edited,
/// only the affected tiles bump their version → only those tiles re-rasterize;
/// every other visible tile reuses its cached layer. Repaint cost becomes
/// O(strokes in the touched tile) instead of O(all visible strokes), which is
/// what makes writing/lasso stay smooth on dense boards.
///
/// It's a [ChangeNotifier] so the stroke layer rebuilds (re-emitting tile
/// widgets with fresh versions) whenever the ink changes, without a full-tree
/// setState.
/// World-space side of a stroke tile, in logical pixels.
const double kStrokeTileSize = 512;

class StrokeTileIndex extends ChangeNotifier {
  StrokeTileIndex({this.tileSize = kStrokeTileSize});

  final double tileSize;

  final Map<(int, int), List<DrawingStroke>> _tiles = {};
  final Map<(int, int), int> _versions = {};

  /// Monotonic counter bumped on every mutation — lets a non-tiled fallback
  /// painter (zoomed out) detect ink changes via its [paintVersion].
  int revision = 0;

  // ─── Mutations (kept in lock-step with the editor's stroke list) ──────────

  /// Replace the whole index from [strokes]. Used on load / undo-restore /
  /// clear — anything that swaps the stroke list wholesale.
  void rebuild(List<DrawingStroke> strokes) {
    final touched = <(int, int)>{..._tiles.keys};
    _tiles.clear();
    for (final s in strokes) {
      _index(s, touched);
    }
    _bump(touched);
    notifyListeners();
  }

  /// Add one freshly committed stroke to its tiles. O(tiles it spans).
  void append(DrawingStroke stroke) {
    final touched = <(int, int)>{};
    _index(stroke, touched);
    _bump(touched);
    notifyListeners();
  }

  /// Rebuild only the tiles overlapping [region] from [all] (the current stroke
  /// list). Used after a geometry edit whose extent is known (move/resize/
  /// rotate/erase/delete). Tiles outside [region] keep their strokes + raster.
  void invalidateRegion(Rect region, List<DrawingStroke> all) {
    final grid = _gridAlign(region);
    final keys = _keysIn(grid).toSet();
    if (keys.isEmpty) return;
    for (final k in keys) {
      _tiles[k] = <DrawingStroke>[];
    }
    // Exact pixel bounds of the cleared tiles. Do NOT use `grid` for the skip
    // test below: when an edge lands exactly on a tile boundary, _keysIn yields
    // one extra tile past grid's right/bottom. That tile gets cleared, but a
    // stroke living only inside it fails `b.overlaps(grid)` and is never
    // re-added → it vanishes (the "invisible chunks" on erase/lasso/undo).
    var minL = double.infinity, minT = double.infinity;
    var maxR = double.negativeInfinity, maxB = double.negativeInfinity;
    for (final k in keys) {
      final l = k.$1 * tileSize, t = k.$2 * tileSize;
      if (l < minL) minL = l;
      if (t < minT) minT = t;
      if (l + tileSize > maxR) maxR = l + tileSize;
      if (t + tileSize > maxB) maxB = t + tileSize;
    }
    final cleared = Rect.fromLTRB(minL, minT, maxR, maxB);
    for (final s in all) {
      final b = strokeBounds(s);
      if (!b.overlaps(cleared)) continue;
      for (final k in _keysIn(b)) {
        if (keys.contains(k)) (_tiles[k] ??= <DrawingStroke>[]).add(s);
      }
    }
    // Drop now-empty tiles so the builder doesn't emit blank widgets.
    for (final k in keys) {
      if (_tiles[k]!.isEmpty) _tiles.remove(k);
    }
    _bump(keys);
    notifyListeners();
  }

  void clear() {
    final touched = <(int, int)>{..._tiles.keys};
    _tiles.clear();
    _bump(touched);
    notifyListeners();
  }

  // ─── Reads (used by the tile-widget builder) ──────────────────────────────

  bool get isEmpty => _tiles.isEmpty;

  int get debugTileCount => _tiles.length;

  int get debugEntryCount =>
      _tiles.values.fold(0, (total, strokes) => total + strokes.length);

  List<DrawingStroke>? strokesAt((int, int) key) => _tiles[key];

  int versionAt((int, int) key) => _versions[key] ?? 0;

  /// Non-empty tile keys overlapping [rect].
  Iterable<(int, int)> tilesInRect(Rect rect) sync* {
    for (final k in _keysIn(rect)) {
      final list = _tiles[k];
      if (list != null && list.isNotEmpty) yield k;
    }
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  void _index(DrawingStroke s, Set<(int, int)> touched) {
    final b = strokeBounds(s);
    for (final k in _keysIn(b)) {
      (_tiles[k] ??= <DrawingStroke>[]).add(s);
      touched.add(k);
    }
  }

  void _bump(Iterable<(int, int)> keys) {
    revision++;
    for (final k in keys) {
      _versions[k] = (_versions[k] ?? 0) + 1;
    }
  }

  Rect _gridAlign(Rect r) => Rect.fromLTRB(
    (r.left / tileSize).floor() * tileSize,
    (r.top / tileSize).floor() * tileSize,
    ((r.right / tileSize).floor() + 1) * tileSize,
    ((r.bottom / tileSize).floor() + 1) * tileSize,
  );

  Iterable<(int, int)> _keysIn(Rect rect) sync* {
    final startX = (rect.left / tileSize).floor();
    final endX = (rect.right / tileSize).floor();
    final startY = (rect.top / tileSize).floor();
    final endY = (rect.bottom / tileSize).floor();
    for (int ty = startY; ty <= endY; ty++) {
      for (int tx = startX; tx <= endX; tx++) {
        yield (tx, ty);
      }
    }
  }
}

/// Paints the strokes of ONE tile, clipped to the tile, in its own
/// [RepaintBoundary] (added by [strokeTileWidgets]) so Flutter caches its raster.
class StrokeTilePainter extends CustomPainter {
  StrokeTilePainter({
    required this.strokes,
    required this.tileOrigin,
    required this.version,
    this.hidden,
    this.clipBounds,
    this.lod = 0,
  });

  final List<DrawingStroke> strokes;
  final Offset tileOrigin;
  final int version;

  /// Level-of-detail for the current zoom (0 = full). At higher LOD strokes are
  /// drawn as cheap decimated polylines so zoomed-out tiles rasterize fast.
  final int lod;

  /// Strokes to skip (identity set) — the lasso selection during a live
  /// move/resize/rotate, drawn by the overlay instead. Null when nothing hidden.
  final Set<DrawingStroke>? hidden;

  /// Extra clip in the tile's drawing space (same coords as the strokes). The
  /// notebook passes each page's rect so ink near an edge can't bleed into the
  /// lateral margin or the inter-page gap. Null on the whiteboard (tile clip only).
  final Rect? clipBounds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-tileOrigin.dx, -tileOrigin.dy);
    canvas.clipRect(
      Rect.fromLTWH(tileOrigin.dx, tileOrigin.dy, size.width, size.height),
    );
    if (clipBounds != null) canvas.clipRect(clipBounds!);
    final h = hidden;
    for (final s in strokes) {
      if (h != null && h.contains(s)) continue;
      drawStroke(canvas, s, lod: lod);
    }
  }

  @override
  bool shouldRepaint(StrokeTilePainter old) =>
      old.version != version ||
      old.lod != lod ||
      !identical(old.strokes, strokes) ||
      !identical(old.hidden, hidden) ||
      old.clipBounds != clipBounds;
}

/// Build one positioned [RepaintBoundary] tile widget per non-empty tile
/// overlapping [localRect]. Tiles are positioned in the canvas Stack at
/// [worldOffset] + tile origin, so a notebook page can offset its page-local
/// tiles into world space. [hiddenStrokes], when non-null (a live lasso
/// gesture), is passed only to the tiles that actually contain a hidden stroke,
/// so unaffected tiles never re-rasterize on grab/release.
List<Widget> strokeTileWidgets({
  required StrokeTileIndex index,
  required Rect localRect,
  Offset worldOffset = Offset.zero,
  Set<DrawingStroke>? hiddenStrokes,
  Object keyPrefix = 0,
  Rect? clipBounds,
  int lod = 0,
}) {
  final out = <Widget>[];
  final size = index.tileSize;
  for (final key in index.tilesInRect(localRect)) {
    final strokes = index.strokesAt(key)!;
    final tileOrigin = Offset(key.$1 * size, key.$2 * size);
    Set<DrawingStroke>? hidden;
    if (hiddenStrokes != null) {
      for (final s in strokes) {
        if (hiddenStrokes.contains(s)) {
          hidden = hiddenStrokes;
          break;
        }
      }
    }
    out.add(
      Positioned(
        key: ValueKey('$keyPrefix:${key.$1}:${key.$2}'),
        left: worldOffset.dx + tileOrigin.dx,
        top: worldOffset.dy + tileOrigin.dy,
        width: size,
        height: size,
        child: RepaintBoundary(
          child: CustomPaint(
            isComplex: true,
            willChange: false,
            painter: StrokeTilePainter(
              strokes: strokes,
              tileOrigin: tileOrigin,
              version: index.versionAt(key),
              hidden: hidden,
              clipBounds: clipBounds,
              lod: lod,
            ),
            size: Size(size, size),
          ),
        ),
      ),
    );
  }
  return out;
}
