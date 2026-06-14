import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart' show Offset, Rect, VoidCallback, Matrix4;
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

const double kLassoSnapStep = 25.0;

/// Gap (in screen px) between the selection box top and the rotation handle.
/// Divided by the view scale at use sites so it's constant on screen.
const double kLassoRotationGap = 28.0;

enum LassoPhase { idle, tracing, selected, moving, resizing, rotating }

class LassoDeleteResult {
  final List<(int, DrawingStroke)> removed;
  LassoDeleteResult(this.removed);
}

class LassoDuplicateResult {
  final int insertedCount;
  LassoDuplicateResult(this.insertedCount);
}

class LassoMoveResult {
  final Map<int, List<List<double>>> originalPoints;
  LassoMoveResult(this.originalPoints);
}

class LassoController {
  LassoPhase phase = LassoPhase.idle;

  ui.Image? liftedInk;
  Rect? liftedRect;

  void disposeLiftedInk() {
    liftedInk?.dispose();
    liftedInk = null;
    liftedRect = null;
  }

  /// Current view scale (1.0 when there's no zoom). Handle hit-areas are kept
  /// constant in *screen* pixels by dividing the base radius by this — so they
  /// don't balloon when the canvas is zoomed in.
  double hitScale = 1.0;

  List<Offset> lassoPath = [];
  Set<int> selectedIndices = {};
  Set<int> selectedImageIndices = {};
  Set<int> selectedBlockIndices = {};
  Set<int> selectedTextBlockIndices = {};
  Rect? boundingBox;

  Offset _dragStart = Offset.zero;
  Offset dragOffset = Offset.zero;
  Map<int, List<List<double>>>? _snapshotBeforeMove;
  Map<int, CanvasImage>? _imageSnapshot;
  Map<int, CanvasTaskBlock>? _blockSnapshot;

  Offset? resizePivot;
  double resizeScale = 1.0;
  double resizeScaleX = 1.0;
  double resizeScaleY = 1.0;
  bool _sideResize = false;
  int _sideAxis = 0; // 0=horizontal, 1=vertical
  Rect? _resizeOriginalBox;

  double rotationAngle = 0.0;
  Offset? _rotationCenter;

  List<DrawingStroke>? _clipboard;
  List<CanvasImage>? _imageClipboard;

  VoidCallback? onChanged;

  void _notify() => onChanged?.call();

  // ─── Tracing ───────────────────────────────────────────────────────────

  void startTracing(Offset worldPos) {
    phase = LassoPhase.tracing;
    lassoPath = [worldPos];
    selectedIndices = {};
    selectedImageIndices = {};
    selectedBlockIndices = {};
    selectedTextBlockIndices = {};
    boundingBox = null;
    dragOffset = Offset.zero;
    _notify();
  }

  void addTracePoint(Offset worldPos) {
    if (phase != LassoPhase.tracing) return;
    final last = lassoPath.last;
    if ((worldPos - last).distanceSquared < 9.0) return;
    lassoPath.add(worldPos);
    _notify();
  }

  void finishTracing(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    if (phase != LassoPhase.tracing) return;
    if (lassoPath.length < 3) {
      // Stylus tap fallback selects strokes only — image/block tap-select is a
      // finger-only gesture handled by the editor.
      if (lassoPath.isNotEmpty && !tapSelect(lassoPath.first, strokes)) {
        deselect();
      }
      return;
    }

    // Fast reject: a stroke can only be "inside" if its bounds overlap the
    // lasso polygon's bounds. The cheap rect test skips the per-point polygon
    // scan for the (vast) majority on a dense board — the O(n) "finish
    // selection" hitch. strokeBounds is Expando-cached so this is near-free.
    final lassoBounds = _polylineBounds(lassoPath);
    selectedIndices = {};
    for (int i = 0; i < strokes.length; i++) {
      if (!strokeBounds(strokes[i]).overlaps(lassoBounds)) continue;
      if (_isStrokeInside(strokes[i])) {
        selectedIndices.add(i);
      }
    }
    selectedImageIndices = {};
    for (int i = 0; i < images.length; i++) {
      if (_boxCenterInPolygon(images[i])) selectedImageIndices.add(i);
    }
    selectedBlockIndices = {};
    for (int i = 0; i < blocks.length; i++) {
      if (_boxCenterInPolygon(blocks[i])) selectedBlockIndices.add(i);
    }
    selectedTextBlockIndices = {};
    for (int i = 0; i < textBlocks.length; i++) {
      if (_boxCenterInPolygon(textBlocks[i])) selectedTextBlockIndices.add(i);
    }

    if (!hasSelection) {
      deselect();
      return;
    }

    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    lassoPath = [];
    phase = LassoPhase.selected;
    _notify();
  }

  // ─── Moving ────────────────────────────────────────────────────────────

  bool isTapInsideBoundingBox(Offset worldPos) {
    if (boundingBox == null) return false;
    return boundingBox!.inflate(6 / hitScale).contains(worldPos);
  }

  void startMove(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const []]) {
    if (phase != LassoPhase.selected) return;
    disposeLiftedInk();
    _dragStart = worldPos;
    dragOffset = Offset.zero;
    _snapshotStrokes(strokes);
    _snapshotImages(images);
    _snapshotBlocks(blocks);
    phase = LassoPhase.moving;
    _notify();
  }

  // Text blocks ride the same geometry path as task blocks (move/resize/rotate
  // mutate them in place); only mutations that change list length — selection,
  // bounding box, delete — thread the [textBlocks] list explicitly.

  void updateMove(Offset worldPos) {
    if (phase != LassoPhase.moving) return;
    dragOffset = worldPos - _dragStart;
    _notify();
  }

  LassoMoveResult finishMove(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      double snapStep = 0,
      List<CanvasTextBlock> textBlocks = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});

    // Snap the moved selection so its top-left lands on the grid.
    if (snapStep > 0 && boundingBox != null) {
      final tl = boundingBox!.topLeft;
      final nx = ((tl.dx + dragOffset.dx) / snapStep).round() * snapStep;
      final ny = ((tl.dy + dragOffset.dy) / snapStep).round() * snapStep;
      dragOffset = Offset(nx - tl.dx, ny - tl.dy);
    }

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          pts.setX(j, pts.x(j) + dragOffset.dx);
          pts.setY(j, pts.y(j) + dragOffset.dy);
        }
      }
    }
    _moveBoxes(images, selectedImageIndices, dragOffset);
    _moveBoxes(blocks, selectedBlockIndices, dragOffset);
    _moveBoxes(textBlocks, selectedTextBlockIndices, dragOffset);

    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    dragOffset = Offset.zero;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
    _blockSnapshot = null;
    disposeLiftedInk();
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  void _snapshotStrokes(List<DrawingStroke> strokes) {
    _snapshotBeforeMove = {};
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        _snapshotBeforeMove![i] = strokes[i].points.toNested();
      }
    }
  }

  void _snapshotImages(List<CanvasImage> images) {
    _imageSnapshot = {};
    for (final i in selectedImageIndices) {
      if (i < images.length) _imageSnapshot![i] = images[i].clone();
    }
  }

  void _snapshotBlocks(List<CanvasTaskBlock> blocks) {
    _blockSnapshot = {};
    for (final i in selectedBlockIndices) {
      if (i < blocks.length) _blockSnapshot![i] = blocks[i].clone();
    }
  }

  // ─── Shared box geometry (images + task blocks) ──────────────────────────

  void _moveBoxes(List<CanvasGeo> objs, Set<int> sel, Offset d) {
    for (final i in sel) {
      if (i < objs.length) {
        objs[i].x += d.dx;
        objs[i].y += d.dy;
      }
    }
  }

  void _scaleBoxes(
      List<CanvasGeo> objs, Set<int> sel, Offset pivot, double sx, double sy) {
    for (final i in sel) {
      if (i >= objs.length) continue;
      final o = objs[i];
      o.x = pivot.dx + (o.x - pivot.dx) * sx;
      o.y = pivot.dy + (o.y - pivot.dy) * sy;
      o.w *= sx;
      o.h *= sy;
    }
  }

  void _rotateBoxes(List<CanvasGeo> objs, Set<int> sel, Offset center,
      double cos, double sin, double angle) {
    for (final i in sel) {
      if (i >= objs.length) continue;
      final o = objs[i];
      final ocx = o.x + o.w / 2;
      final ocy = o.y + o.h / 2;
      final dx = ocx - center.dx;
      final dy = ocy - center.dy;
      final ncx = center.dx + dx * cos - dy * sin;
      final ncy = center.dy + dx * sin + dy * cos;
      o.x = ncx - o.w / 2;
      o.y = ncy - o.h / 2;
      o.rotation += angle;
    }
  }

  // ─── Resize (proportional from corners) ─────────────────────────────

  static const _handleHitScreenRadius = 18.0;

  /// Minimum world-space size for block-like selections (task + text). Both
  /// types reflow their content and auto-size height, so they can shrink very
  /// small — the user often zooms in to work, which makes a fixed min feel huge.
  static const _kMinBoxW = 40.0;
  static const _kMinBoxH = 24.0;

  double get _selMinW =>
      (selectedBlockIndices.isNotEmpty || selectedTextBlockIndices.isNotEmpty)
          ? _kMinBoxW : _kMinBoxW;
  double get _selMinH =>
      (selectedBlockIndices.isNotEmpty || selectedTextBlockIndices.isNotEmpty)
          ? _kMinBoxH : _kMinBoxH;

  /// Hit radius for the rotation handle (constant ~18px on screen).
  double get _handleHitRadius => _handleHitScreenRadius / hitScale;

  /// Hit radius for the edge (corner/side) handles. Capped to a fraction of the
  /// box so a small object (zoomed out) doesn't have its whole interior — the
  /// move zone — swallowed by overlapping handle hit areas.
  double get _edgeHandleHitRadius {
    final base = _handleHitScreenRadius / hitScale;
    final bb = boundingBox;
    if (bb == null) return base;
    final cap = bb.shortestSide * 0.3;
    return base < cap ? base : cap;
  }

  int? hitTestCornerHandle(Offset worldPos) {
    if (boundingBox == null) return null;
    final bb = boundingBox!;
    final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft];
    for (int i = 0; i < corners.length; i++) {
      if ((worldPos - corners[i]).distance < _edgeHandleHitRadius) return i;
    }
    return null;
  }

  void startResize(int cornerIndex, Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const []]) {
    if (phase != LassoPhase.selected || boundingBox == null) return;
    final bb = boundingBox!;
    final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft];
    resizePivot = corners[(cornerIndex + 2) % 4];
    _dragStart = worldPos;
    resizeScale = 1.0;
    _resizeOriginalBox = bb;
    _snapshotStrokes(strokes);
    _snapshotImages(images);
    _snapshotBlocks(blocks);
    phase = LassoPhase.resizing;
    _notify();
  }

  void updateResize(Offset worldPos) {
    if (phase != LassoPhase.resizing || resizePivot == null || _resizeOriginalBox == null) return;
    final pivotToDragStart = (_dragStart - resizePivot!).distance;
    if (pivotToDragStart < 1) return;
    final pivotToCurrent = (worldPos - resizePivot!).distance;
    var minScale = 0.1;
    if (selectedBlockIndices.isNotEmpty || selectedTextBlockIndices.isNotEmpty) {
      final minScaleW = _selMinW / _resizeOriginalBox!.width;
      final minScaleH = _selMinH / _resizeOriginalBox!.height;
      minScale = math.max(minScale, math.max(minScaleW, minScaleH));
    }
    resizeScale = (pivotToCurrent / pivotToDragStart).clamp(minScale, 5.0);
    _notify();
  }

  LassoMoveResult finishResize(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final s = resizeScale;

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final fountain = strokes[i].isFountainPen;
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          pts.setX(j, pivot.dx + (pts.x(j) - pivot.dx) * s);
          pts.setY(j, pivot.dy + (pts.y(j) - pivot.dy) * s);
          if (fountain && pts.comps >= 3) pts.setZ(j, pts.z(j) * s);
        }
      }
    }
    _scaleBoxes(images, selectedImageIndices, pivot, s, s);
    _scaleBoxes(blocks, selectedBlockIndices, pivot, s, s);
    _scaleBoxes(textBlocks, selectedTextBlockIndices, pivot, s, s);

    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    resizePivot = null;
    resizeScale = 1.0;
    _resizeOriginalBox = null;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
    _blockSnapshot = null;
    disposeLiftedInk();
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Side resize (free, one axis) ───────────────────────────────────

  /// True when the selection is purely blocks (text or task, no
  /// strokes/images). Both types auto-size their height to content, so
  /// vertical (top/bottom) side resize is disabled — only corners + horizontal.
  bool get blocksOnlySelection =>
      (selectedTextBlockIndices.isNotEmpty || selectedBlockIndices.isNotEmpty) &&
      selectedIndices.isEmpty &&
      selectedImageIndices.isEmpty;

  int? hitTestSideHandle(Offset worldPos) {
    if (boundingBox == null) return null;
    final bb = boundingBox!;
    final sides = [
      Offset(bb.center.dx, bb.top),
      Offset(bb.right, bb.center.dy),
      Offset(bb.center.dx, bb.bottom),
      Offset(bb.left, bb.center.dy),
    ];
    final blocksOnly = blocksOnlySelection;
    for (int i = 0; i < sides.length; i++) {
      // 0 = top, 2 = bottom: skip for block-only selections (height auto-sizes).
      if (blocksOnly && (i == 0 || i == 2)) continue;
      if ((worldPos - sides[i]).distance < _edgeHandleHitRadius) return i;
    }
    return null;
  }

  void startSideResize(int sideIndex, Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const []]) {
    if (phase != LassoPhase.selected || boundingBox == null) return;
    final bb = boundingBox!;
    final sides = [
      Offset(bb.center.dx, bb.top),
      Offset(bb.right, bb.center.dy),
      Offset(bb.center.dx, bb.bottom),
      Offset(bb.left, bb.center.dy),
    ];
    resizePivot = sides[(sideIndex + 2) % 4];
    _sideResize = true;
    _sideAxis = sideIndex % 2; // 0=top/bottom (scale Y), 1=left/right (scale X)
    _dragStart = worldPos;
    resizeScaleX = 1.0;
    resizeScaleY = 1.0;
    _resizeOriginalBox = bb;
    _snapshotStrokes(strokes);
    _snapshotImages(images);
    _snapshotBlocks(blocks);
    phase = LassoPhase.resizing;
    _notify();
  }

  void updateSideResize(Offset worldPos) {
    if (phase != LassoPhase.resizing || resizePivot == null || _resizeOriginalBox == null) return;
    if (_sideAxis == 1) {
      final startDist = (_dragStart.dx - resizePivot!.dx).abs();
      if (startDist < 1) return;
      final curDist = (worldPos.dx - resizePivot!.dx).abs();
      var minScale = 0.1;
      if (selectedBlockIndices.isNotEmpty || selectedTextBlockIndices.isNotEmpty) {
        minScale = math.max(minScale, _selMinW / _resizeOriginalBox!.width);
      }
      resizeScaleX = (curDist / startDist).clamp(minScale, 5.0);
      resizeScaleY = 1.0;
    } else {
      final startDist = (_dragStart.dy - resizePivot!.dy).abs();
      if (startDist < 1) return;
      final curDist = (worldPos.dy - resizePivot!.dy).abs();
      var minScale = 0.1;
      if (selectedBlockIndices.isNotEmpty || selectedTextBlockIndices.isNotEmpty) {
        minScale = math.max(minScale, _selMinH / _resizeOriginalBox!.height);
      }
      resizeScaleX = 1.0;
      resizeScaleY = (curDist / startDist).clamp(minScale, 5.0);
    }
    _notify();
  }

  LassoMoveResult finishSideResize(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final sx = resizeScaleX;
    final sy = resizeScaleY;

    final avg = (sx + sy) / 2;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final fountain = strokes[i].isFountainPen;
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          pts.setX(j, pivot.dx + (pts.x(j) - pivot.dx) * sx);
          pts.setY(j, pivot.dy + (pts.y(j) - pivot.dy) * sy);
          if (fountain && pts.comps >= 3) pts.setZ(j, pts.z(j) * avg);
        }
      }
    }
    _scaleBoxes(images, selectedImageIndices, pivot, sx, sy);
    _scaleBoxes(blocks, selectedBlockIndices, pivot, sx, sy);
    _scaleBoxes(textBlocks, selectedTextBlockIndices, pivot, sx, sy);

    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    _resetResizeState();
    _imageSnapshot = null;
    _blockSnapshot = null;
    disposeLiftedInk();
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Rotation ──────────────────────────────────────────────────────────

  Offset? get rotationHandlePos {
    if (boundingBox == null) return null;
    // Gap is constant on screen (÷ hitScale), so the handle stays clear of the
    // box when zoomed out instead of collapsing onto its top edge.
    return Offset(
        boundingBox!.center.dx, boundingBox!.top - kLassoRotationGap / hitScale);
  }

  bool hitTestRotationHandle(Offset worldPos) {
    final handle = rotationHandlePos;
    if (handle == null) return false;
    return (worldPos - handle).distance < _handleHitRadius;
  }

  void startRotation(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const []]) {
    if (phase != LassoPhase.selected || boundingBox == null) return;
    _rotationCenter = boundingBox!.center;
    _dragStart = worldPos;
    rotationAngle = 0.0;
    _snapshotStrokes(strokes);
    _snapshotImages(images);
    _snapshotBlocks(blocks);
    phase = LassoPhase.rotating;
    _notify();
  }

  void updateRotation(Offset worldPos) {
    if (phase != LassoPhase.rotating || _rotationCenter == null) return;
    final startAngle = math.atan2(
        _dragStart.dy - _rotationCenter!.dy, _dragStart.dx - _rotationCenter!.dx);
    final currentAngle = math.atan2(
        worldPos.dy - _rotationCenter!.dy, worldPos.dx - _rotationCenter!.dx);
    rotationAngle = currentAngle - startAngle;
    _notify();
  }

  LassoMoveResult finishRotation(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final center = _rotationCenter!;
    final cx = center.dx;
    final cy = center.dy;
    final cos = math.cos(rotationAngle);
    final sin = math.sin(rotationAngle);

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          final dx = pts.x(j) - cx;
          final dy = pts.y(j) - cy;
          pts.setX(j, cx + dx * cos - dy * sin);
          pts.setY(j, cy + dx * sin + dy * cos);
        }
      }
    }
    _rotateBoxes(images, selectedImageIndices, center, cos, sin, rotationAngle);
    _rotateBoxes(blocks, selectedBlockIndices, center, cos, sin, rotationAngle);
    _rotateBoxes(
        textBlocks, selectedTextBlockIndices, center, cos, sin, rotationAngle);

    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    rotationAngle = 0.0;
    _rotationCenter = null;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
    _blockSnapshot = null;
    disposeLiftedInk();
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Flip ──────────────────────────────────────────────────────────────

  void flipHorizontal(List<DrawingStroke> strokes) {
    if (boundingBox == null || selectedIndices.isEmpty) return;
    final cx = boundingBox!.center.dx;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          pts.setX(j, cx + (cx - pts.x(j)));
        }
      }
    }
    _notify();
  }

  void flipVertical(List<DrawingStroke> strokes) {
    if (boundingBox == null || selectedIndices.isEmpty) return;
    final cy = boundingBox!.center.dy;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final pts = strokes[i].points;
        for (int j = 0; j < pts.length; j++) {
          pts.setY(j, cy + (cy - pts.y(j)));
        }
      }
    }
    _notify();
  }

  // ─── Clipboard ─────────────────────────────────────────────────────────

  bool get hasClipboard =>
      (_clipboard != null && _clipboard!.isNotEmpty) ||
      (_imageClipboard != null && _imageClipboard!.isNotEmpty);

  void copySelected(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    _clipboard = _snapshotRelativeToCenter(strokes);
    _imageClipboard = _snapshotImagesRelativeToCenter(images);
    deselect();
  }

  void cutSelected(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const []]) {
    _clipboard = _snapshotRelativeToCenter(strokes);
    _imageClipboard = _snapshotImagesRelativeToCenter(images);
    // Task/text blocks are never cloned to the clipboard, so leave any selected
    // block in place instead of losing it.
    selectedBlockIndices = {};
    selectedTextBlockIndices = {};
    deleteSelected(strokes, images, blocks);
  }

  List<DrawingStroke> _snapshotRelativeToCenter(List<DrawingStroke> strokes) {
    final cx = boundingBox?.center.dx ?? 0;
    final cy = boundingBox?.center.dy ?? 0;
    final out = <DrawingStroke>[];
    for (final i in selectedIndices) {
      if (i >= strokes.length) continue;
      final s = strokes[i];
      out.add(DrawingStroke(
        colorValue: s.colorValue,
        strokeWidth: s.strokeWidth,
        isFountainPen: s.isFountainPen,
        filled: s.filled,
        isShape: s.isShape,
        isHighlighter: s.isHighlighter,
        points: s.points.mapXY((x, y) => Offset(x - cx, y - cy)),
      ));
    }
    return out;
  }

  List<CanvasImage> _snapshotImagesRelativeToCenter(
      List<CanvasImage> images) {
    final cx = boundingBox?.center.dx ?? 0;
    final cy = boundingBox?.center.dy ?? 0;
    final out = <CanvasImage>[];
    for (final i in selectedImageIndices) {
      if (i >= images.length) continue;
      out.add(images[i].clone()
        ..x -= cx
        ..y -= cy);
    }
    return out;
  }

  LassoDuplicateResult pasteAt(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [], double snapStep = 0]) {
    final clip = _clipboard ?? const [];
    final imgClip = _imageClipboard ?? const [];
    if (clip.isEmpty && imgClip.isEmpty) return LassoDuplicateResult(0);
    if (snapStep > 0) {
      worldPos = Offset(
        (worldPos.dx / snapStep).round() * snapStep,
        (worldPos.dy / snapStep).round() * snapStep,
      );
    }

    final startIdx = strokes.length;
    for (final s in clip) {
      strokes.add(DrawingStroke(
        colorValue: s.colorValue,
        strokeWidth: s.strokeWidth,
        isFountainPen: s.isFountainPen,
        filled: s.filled,
        isShape: s.isShape,
        isHighlighter: s.isHighlighter,
        points: s.points.mapXY(
          (x, y) => Offset(x + worldPos.dx, y + worldPos.dy),
        ),
      ));
    }
    final imgStart = images.length;
    for (final im in imgClip) {
      images.add(im.clone()
        ..x += worldPos.dx
        ..y += worldPos.dy);
    }

    selectedIndices =
        Set.from(List.generate(clip.length, (i) => startIdx + i));
    selectedImageIndices =
        Set.from(List.generate(imgClip.length, (i) => imgStart + i));
    selectedBlockIndices = {};
    boundingBox = _computeBoundingBox(strokes, images);
    phase = LassoPhase.selected;
    _notify();
    return LassoDuplicateResult(clip.length + imgClip.length);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  void _resetResizeState() {
    resizePivot = null;
    resizeScale = 1.0;
    resizeScaleX = 1.0;
    resizeScaleY = 1.0;
    _sideResize = false;
    _resizeOriginalBox = null;
    _snapshotBeforeMove = null;
  }

  bool get isSideResize => _sideResize;

  // ─── Change color / width ───────────────────────────────────────────

  void changeColor(List<DrawingStroke> strokes, int colorValue) {
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        strokes[i] = strokes[i].copyWith(colorValue: colorValue);
      }
    }
    _notify();
  }

  void changeWidth(List<DrawingStroke> strokes, double width) {
    for (final i in selectedIndices) {
      if (i >= strokes.length) continue;
      final s = strokes[i];
      if (s.isFountainPen) {
        // Fountain strokes carry per-point baked widths; rescale them so the
        // whole stroke thickens/thins proportionally instead of becoming a
        // flat pen line.
        final ratio = s.strokeWidth > 0 ? width / s.strokeWidth : 1.0;
        final pts = s.points.clone();
        if (pts.comps >= 3) {
          for (int j = 0; j < pts.length; j++) {
            pts.setZ(j, pts.z(j) * ratio);
          }
        }
        strokes[i] = DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: width,
          isFountainPen: true,
          points: pts,
        );
      } else {
        strokes[i] = s.copyWith(strokeWidth: width);
      }
    }
    _notify();
  }

  // ─── Delete ────────────────────────────────────────────────────────────

  LassoDeleteResult deleteSelected(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    final sorted = selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    final removed = <(int, DrawingStroke)>[];
    for (final i in sorted) {
      if (i < strokes.length) {
        removed.add((i, strokes.removeAt(i)));
      }
    }
    final sortedImgs = selectedImageIndices.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final i in sortedImgs) {
      if (i < images.length) images.removeAt(i);
    }
    final sortedBlocks = selectedBlockIndices.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final i in sortedBlocks) {
      if (i < blocks.length) blocks.removeAt(i);
    }
    final sortedText = selectedTextBlockIndices.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final i in sortedText) {
      if (i < textBlocks.length) textBlocks.removeAt(i);
    }
    deselect();
    return LassoDeleteResult(removed.reversed.toList());
  }

  // ─── Duplicate ─────────────────────────────────────────────────────────

  LassoDuplicateResult duplicateSelected(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    final copies = <DrawingStroke>[];
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final s = strokes[i];
        copies.add(DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          isFountainPen: s.isFountainPen,
          filled: s.filled,
          isShape: s.isShape,
          isHighlighter: s.isHighlighter,
          points: s.points.mapXY((x, y) => Offset(x + 15, y + 15)),
        ));
      }
    }
    final imgCopies = <CanvasImage>[];
    for (final i in selectedImageIndices) {
      if (i < images.length) {
        imgCopies.add(images[i].clone()
          ..x += 15
          ..y += 15);
      }
    }
    final startIdx = strokes.length;
    strokes.addAll(copies);
    final imgStart = images.length;
    images.addAll(imgCopies);

    selectedIndices = Set.from(
      List.generate(copies.length, (i) => startIdx + i),
    );
    selectedImageIndices = Set.from(
      List.generate(imgCopies.length, (i) => imgStart + i),
    );
    // Task/text blocks are not duplicated (shared task entities / would need a
    // new id); drop them from the post-duplicate selection.
    selectedBlockIndices = {};
    selectedTextBlockIndices = {};
    boundingBox = _computeBoundingBox(strokes, images);
    _notify();
    return LassoDuplicateResult(copies.length + imgCopies.length);
  }

  // ─── Select range (after duplicate) ────────────────────────────────────

  void selectRange(List<DrawingStroke> strokes, int from, int to) {
    selectedIndices = Set.from(List.generate(to - from, (i) => from + i));
    boundingBox = _computeBoundingBox(strokes);
    phase = LassoPhase.selected;
    _notify();
  }

  /// Programmatically select a single text block (by world-space index) and
  /// show the selection box — used right after inserting one from the AI chat
  /// so the user sees it's placed, selected and movable.
  void selectTextBlock(int index, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    selectedIndices = {};
    selectedImageIndices = {};
    selectedBlockIndices = {};
    selectedTextBlockIndices = {index};
    boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
    phase = LassoPhase.selected;
    _notify();
  }

  // ─── Tap to select single stroke ─────────────────────────────────────

  bool tapSelect(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    final hitRadius2 = (20.0 / hitScale) * (20.0 / hitScale);
    int? closestIdx;
    double closestDist = double.infinity;

    for (int i = 0; i < strokes.length; i++) {
      final pts = strokes[i].points;
      for (int j = 0; j < pts.length; j++) {
        final dx = pts.x(j) - worldPos.dx;
        final dy = pts.y(j) - worldPos.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 < hitRadius2 && d2 < closestDist) {
          closestDist = d2;
          closestIdx = i;
        }
      }
    }

    if (closestIdx != null) {
      selectedIndices = {closestIdx};
      selectedImageIndices = {};
      selectedBlockIndices = {};
      selectedTextBlockIndices = {};
      boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
      lassoPath = [];
      phase = LassoPhase.selected;
      _notify();
      return true;
    }

    // No stroke hit — try the widget overlays (text blocks then task blocks,
    // topmost first), then images.
    for (int i = textBlocks.length - 1; i >= 0; i--) {
      if (_boxRect(textBlocks[i]).contains(worldPos)) {
        selectedIndices = {};
        selectedImageIndices = {};
        selectedBlockIndices = {};
        selectedTextBlockIndices = {i};
        boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
        lassoPath = [];
        phase = LassoPhase.selected;
        _notify();
        return true;
      }
    }
    for (int i = blocks.length - 1; i >= 0; i--) {
      if (_boxRect(blocks[i]).contains(worldPos)) {
        selectedIndices = {};
        selectedImageIndices = {};
        selectedBlockIndices = {i};
        selectedTextBlockIndices = {};
        boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
        lassoPath = [];
        phase = LassoPhase.selected;
        _notify();
        return true;
      }
    }
    for (int i = images.length - 1; i >= 0; i--) {
      if (_boxRect(images[i]).contains(worldPos)) {
        selectedIndices = {};
        selectedImageIndices = {i};
        selectedBlockIndices = {};
        selectedTextBlockIndices = {};
        boundingBox = _computeBoundingBox(strokes, images, blocks, textBlocks);
        lassoPath = [];
        phase = LassoPhase.selected;
        _notify();
        return true;
      }
    }
    return false;
  }

  // ─── Deselect ──────────────────────────────────────────────────────────

  void deselect() {
    phase = LassoPhase.idle;
    lassoPath = [];
    selectedIndices = {};
    selectedImageIndices = {};
    selectedBlockIndices = {};
    selectedTextBlockIndices = {};
    boundingBox = null;
    dragOffset = Offset.zero;
    _resetResizeState();
    rotationAngle = 0.0;
    _rotationCenter = null;
    _imageSnapshot = null;
    _blockSnapshot = null;
    disposeLiftedInk();
    _notify();
  }

  bool get hasSelection =>
      selectedIndices.isNotEmpty ||
      selectedImageIndices.isNotEmpty ||
      selectedBlockIndices.isNotEmpty ||
      selectedTextBlockIndices.isNotEmpty;

  /// World-space transform of the in-progress gesture (move/resize/rotate),
  /// identity when idle. Lets widget overlays (task blocks) follow the gesture
  /// live instead of being hidden behind a painted ghost.
  Matrix4 liveGestureMatrix() {
    switch (phase) {
      case LassoPhase.moving:
        return Matrix4.translationValues(dragOffset.dx, dragOffset.dy, 0);
      case LassoPhase.resizing:
        final p = resizePivot;
        if (p == null) return Matrix4.identity();
        final sx = isSideResize ? resizeScaleX : resizeScale;
        final sy = isSideResize ? resizeScaleY : resizeScale;
        return Matrix4.translationValues(p.dx, p.dy, 0) *
            Matrix4.diagonal3Values(sx, sy, 1) *
            Matrix4.translationValues(-p.dx, -p.dy, 0);
      case LassoPhase.rotating:
        final c = boundingBox?.center;
        if (c == null) return Matrix4.identity();
        return Matrix4.translationValues(c.dx, c.dy, 0) *
            Matrix4.rotationZ(rotationAngle) *
            Matrix4.translationValues(-c.dx, -c.dy, 0);
      default:
        return Matrix4.identity();
    }
  }

  bool _boxCenterInPolygon(CanvasGeo o) =>
      _pointInPolygon(Offset(o.x + o.w / 2, o.y + o.h / 2), lassoPath);

  Rect _boxRect(CanvasGeo o) => Rect.fromLTWH(o.x, o.y, o.w, o.h);

  // ─── Geometry ──────────────────────────────────────────────────────────

  bool _isStrokeInside(DrawingStroke stroke) {
    if (stroke.points.isEmpty) return false;
    int inside = 0;
    final pts = stroke.points;
    for (int j = 0; j < pts.length; j++) {
      if (_pointInPolygon(pts.offset(j), lassoPath)) inside++;
    }
    return inside / pts.length >= 0.5;
  }

  static Rect _polylineBounds(List<Offset> pts) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static bool _pointInPolygon(Offset test, List<Offset> polygon) {
    final n = polygon.length;
    bool inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].dx, yi = polygon[i].dy;
      final xj = polygon[j].dx, yj = polygon[j].dy;
      if (((yi > test.dy) != (yj > test.dy)) &&
          (test.dx < (xj - xi) * (test.dy - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  Rect _computeBoundingBox(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final i in selectedIndices) {
      if (i >= strokes.length) continue;
      final box = strokeBounds(strokes[i]);
      if (box.left < minX) minX = box.left;
      if (box.right > maxX) maxX = box.right;
      if (box.top < minY) minY = box.top;
      if (box.bottom > maxY) maxY = box.bottom;
    }
    void includeBox(CanvasGeo o) {
      if (o.x < minX) minX = o.x;
      if (o.x + o.w > maxX) maxX = o.x + o.w;
      if (o.y < minY) minY = o.y;
      if (o.y + o.h > maxY) maxY = o.y + o.h;
    }

    for (final i in selectedImageIndices) {
      if (i < images.length) includeBox(images[i]);
    }
    for (final i in selectedBlockIndices) {
      if (i < blocks.length) includeBox(blocks[i]);
    }
    for (final i in selectedTextBlockIndices) {
      if (i < textBlocks.length) includeBox(textBlocks[i]);
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX - 8, minY - 8, maxX + 8, maxY + 8);
  }

  /// Recompute the bounding box from the current selection. Used by the editor
  /// when a selected task/text block's natural height changes after a width
  /// resize.
  void refreshBoundingBox(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [],
      List<CanvasTaskBlock> blocks = const [],
      List<CanvasTextBlock> textBlocks = const []]) {
    if (phase != LassoPhase.selected) return;
    final bb = _computeBoundingBox(strokes, images, blocks, textBlocks);
    if (bb == Rect.zero) {
      deselect();
      return;
    }
    boundingBox = bb;
    _notify();
  }
}
