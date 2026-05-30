import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, VoidCallback;
import 'note_cell_model.dart';

const double kLassoSnapStep = 25.0;

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

  /// Current view scale (1.0 when there's no zoom). Handle hit-areas are kept
  /// constant in *screen* pixels by dividing the base radius by this — so they
  /// don't balloon when the canvas is zoomed in.
  double hitScale = 1.0;

  List<Offset> lassoPath = [];
  Set<int> selectedIndices = {};
  Set<int> selectedImageIndices = {};
  Rect? boundingBox;

  Offset _dragStart = Offset.zero;
  Offset dragOffset = Offset.zero;
  Map<int, List<List<double>>>? _snapshotBeforeMove;
  Map<int, CanvasImage>? _imageSnapshot;

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
      [List<CanvasImage> images = const []]) {
    if (phase != LassoPhase.tracing) return;
    if (lassoPath.length < 3) {
      // Stylus tap fallback selects strokes only — image tap-select is a
      // finger-only gesture handled by the editor.
      if (lassoPath.isNotEmpty && !tapSelect(lassoPath.first, strokes)) {
        deselect();
      }
      return;
    }

    selectedIndices = {};
    for (int i = 0; i < strokes.length; i++) {
      if (_isStrokeInside(strokes[i])) {
        selectedIndices.add(i);
      }
    }
    selectedImageIndices = {};
    for (int i = 0; i < images.length; i++) {
      if (_imageCenterInPolygon(images[i])) selectedImageIndices.add(i);
    }

    if (!hasSelection) {
      deselect();
      return;
    }

    boundingBox = _computeBoundingBox(strokes, images);
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
      [List<CanvasImage> images = const []]) {
    if (phase != LassoPhase.selected) return;
    _dragStart = worldPos;
    dragOffset = Offset.zero;
    _snapshotBeforeMove = {};
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        _snapshotBeforeMove![i] =
            strokes[i].points.map((p) => List<double>.from(p)).toList();
      }
    }
    _snapshotImages(images);
    phase = LassoPhase.moving;
    _notify();
  }

  void updateMove(Offset worldPos) {
    if (phase != LassoPhase.moving) return;
    dragOffset = worldPos - _dragStart;
    _notify();
  }

  LassoMoveResult finishMove(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const [], double snapStep = 0]) {
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
        for (final p in strokes[i].points) {
          p[0] += dragOffset.dx;
          p[1] += dragOffset.dy;
        }
      }
    }
    for (final i in selectedImageIndices) {
      if (i < images.length) {
        images[i].x += dragOffset.dx;
        images[i].y += dragOffset.dy;
      }
    }

    boundingBox = _computeBoundingBox(strokes, images);
    dragOffset = Offset.zero;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  void _snapshotImages(List<CanvasImage> images) {
    _imageSnapshot = {};
    for (final i in selectedImageIndices) {
      if (i < images.length) _imageSnapshot![i] = images[i].clone();
    }
  }

  // ─── Resize (proportional from corners) ─────────────────────────────

  static const _handleHitScreenRadius = 18.0;
  double get _handleHitRadius => _handleHitScreenRadius / hitScale;

  int? hitTestCornerHandle(Offset worldPos) {
    if (boundingBox == null) return null;
    final bb = boundingBox!;
    final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft];
    for (int i = 0; i < corners.length; i++) {
      if ((worldPos - corners[i]).distance < _handleHitRadius) return i;
    }
    return null;
  }

  void startResize(int cornerIndex, Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    if (phase != LassoPhase.selected || boundingBox == null) return;
    final bb = boundingBox!;
    final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft];
    resizePivot = corners[(cornerIndex + 2) % 4];
    _dragStart = worldPos;
    resizeScale = 1.0;
    _resizeOriginalBox = bb;
    _snapshotBeforeMove = {};
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        _snapshotBeforeMove![i] =
            strokes[i].points.map((p) => List<double>.from(p)).toList();
      }
    }
    _snapshotImages(images);
    phase = LassoPhase.resizing;
    _notify();
  }

  void updateResize(Offset worldPos) {
    if (phase != LassoPhase.resizing || resizePivot == null || _resizeOriginalBox == null) return;
    final pivotToDragStart = (_dragStart - resizePivot!).distance;
    if (pivotToDragStart < 1) return;
    final pivotToCurrent = (worldPos - resizePivot!).distance;
    resizeScale = (pivotToCurrent / pivotToDragStart).clamp(0.1, 5.0);
    _notify();
  }

  LassoMoveResult finishResize(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final s = resizeScale;

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final fountain = strokes[i].isFountainPen;
        for (final p in strokes[i].points) {
          p[0] = pivot.dx + (p[0] - pivot.dx) * s;
          p[1] = pivot.dy + (p[1] - pivot.dy) * s;
          if (fountain && p.length >= 3) p[2] *= s;
        }
      }
    }
    for (final i in selectedImageIndices) {
      if (i < images.length) {
        final im = images[i];
        im.x = pivot.dx + (im.x - pivot.dx) * s;
        im.y = pivot.dy + (im.y - pivot.dy) * s;
        im.w *= s;
        im.h *= s;
      }
    }

    boundingBox = _computeBoundingBox(strokes, images);
    resizePivot = null;
    resizeScale = 1.0;
    _resizeOriginalBox = null;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Side resize (free, one axis) ───────────────────────────────────

  int? hitTestSideHandle(Offset worldPos) {
    if (boundingBox == null) return null;
    final bb = boundingBox!;
    final sides = [
      Offset(bb.center.dx, bb.top),
      Offset(bb.right, bb.center.dy),
      Offset(bb.center.dx, bb.bottom),
      Offset(bb.left, bb.center.dy),
    ];
    for (int i = 0; i < sides.length; i++) {
      if ((worldPos - sides[i]).distance < _handleHitRadius) return i;
    }
    return null;
  }

  void startSideResize(int sideIndex, Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
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
    _snapshotBeforeMove = {};
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        _snapshotBeforeMove![i] =
            strokes[i].points.map((p) => List<double>.from(p)).toList();
      }
    }
    _snapshotImages(images);
    phase = LassoPhase.resizing;
    _notify();
  }

  void updateSideResize(Offset worldPos) {
    if (phase != LassoPhase.resizing || resizePivot == null) return;
    if (_sideAxis == 1) {
      final startDist = (_dragStart.dx - resizePivot!.dx).abs();
      if (startDist < 1) return;
      final curDist = (worldPos.dx - resizePivot!.dx).abs();
      resizeScaleX = (curDist / startDist).clamp(0.1, 5.0);
      resizeScaleY = 1.0;
    } else {
      final startDist = (_dragStart.dy - resizePivot!.dy).abs();
      if (startDist < 1) return;
      final curDist = (worldPos.dy - resizePivot!.dy).abs();
      resizeScaleX = 1.0;
      resizeScaleY = (curDist / startDist).clamp(0.1, 5.0);
    }
    _notify();
  }

  LassoMoveResult finishSideResize(List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final sx = resizeScaleX;
    final sy = resizeScaleY;

    final avg = (sx + sy) / 2;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final fountain = strokes[i].isFountainPen;
        for (final p in strokes[i].points) {
          p[0] = pivot.dx + (p[0] - pivot.dx) * sx;
          p[1] = pivot.dy + (p[1] - pivot.dy) * sy;
          if (fountain && p.length >= 3) p[2] *= avg;
        }
      }
    }
    for (final i in selectedImageIndices) {
      if (i < images.length) {
        final im = images[i];
        im.x = pivot.dx + (im.x - pivot.dx) * sx;
        im.y = pivot.dy + (im.y - pivot.dy) * sy;
        im.w *= sx;
        im.h *= sy;
      }
    }

    boundingBox = _computeBoundingBox(strokes, images);
    _resetResizeState();
    _imageSnapshot = null;
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Rotation ──────────────────────────────────────────────────────────

  Offset? get rotationHandlePos {
    if (boundingBox == null) return null;
    return Offset(boundingBox!.center.dx, boundingBox!.top - 14);
  }

  bool hitTestRotationHandle(Offset worldPos) {
    final handle = rotationHandlePos;
    if (handle == null) return false;
    return (worldPos - handle).distance < _handleHitRadius;
  }

  void startRotation(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    if (phase != LassoPhase.selected || boundingBox == null) return;
    _rotationCenter = boundingBox!.center;
    _dragStart = worldPos;
    rotationAngle = 0.0;
    _snapshotBeforeMove = {};
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        _snapshotBeforeMove![i] =
            strokes[i].points.map((p) => List<double>.from(p)).toList();
      }
    }
    _snapshotImages(images);
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
      [List<CanvasImage> images = const []]) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final cx = _rotationCenter!.dx;
    final cy = _rotationCenter!.dy;
    final cos = math.cos(rotationAngle);
    final sin = math.sin(rotationAngle);

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        for (final p in strokes[i].points) {
          final dx = p[0] - cx;
          final dy = p[1] - cy;
          p[0] = cx + dx * cos - dy * sin;
          p[1] = cy + dx * sin + dy * cos;
        }
      }
    }
    for (final i in selectedImageIndices) {
      if (i < images.length) {
        final im = images[i];
        final icx = im.x + im.w / 2;
        final icy = im.y + im.h / 2;
        final dx = icx - cx;
        final dy = icy - cy;
        final ncx = cx + dx * cos - dy * sin;
        final ncy = cy + dx * sin + dy * cos;
        im.x = ncx - im.w / 2;
        im.y = ncy - im.h / 2;
        im.rotation += rotationAngle;
      }
    }

    boundingBox = _computeBoundingBox(strokes, images);
    rotationAngle = 0.0;
    _rotationCenter = null;
    _snapshotBeforeMove = null;
    _imageSnapshot = null;
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
        for (final p in strokes[i].points) {
          p[0] = cx + (cx - p[0]);
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
        for (final p in strokes[i].points) {
          p[1] = cy + (cy - p[1]);
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
      [List<CanvasImage> images = const []]) {
    _clipboard = _snapshotRelativeToCenter(strokes);
    _imageClipboard = _snapshotImagesRelativeToCenter(images);
    deleteSelected(strokes, images);
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
        points: s.points.map((p) {
          final q = List<double>.from(p);
          q[0] -= cx;
          q[1] -= cy;
          return q;
        }).toList(),
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
        points: s.points.map((p) {
          final q = List<double>.from(p);
          q[0] += worldPos.dx;
          q[1] += worldPos.dy;
          return q;
        }).toList(),
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
        final pts = s.points.map((p) {
          final q = List<double>.from(p);
          if (q.length >= 3) q[2] = p[2] * ratio;
          return q;
        }).toList();
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
      [List<CanvasImage> images = const []]) {
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
          points: s.points.map((p) {
            final q = List<double>.from(p);
            q[0] += 15;
            q[1] += 15;
            return q;
          }).toList(),
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

  // ─── Tap to select single stroke ─────────────────────────────────────

  bool tapSelect(Offset worldPos, List<DrawingStroke> strokes,
      [List<CanvasImage> images = const []]) {
    final hitRadius2 = (20.0 / hitScale) * (20.0 / hitScale);
    int? closestIdx;
    double closestDist = double.infinity;

    for (int i = 0; i < strokes.length; i++) {
      for (final p in strokes[i].points) {
        final dx = p[0] - worldPos.dx;
        final dy = p[1] - worldPos.dy;
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
      boundingBox = _computeBoundingBox(strokes, images);
      lassoPath = [];
      phase = LassoPhase.selected;
      _notify();
      return true;
    }

    // No stroke hit — try images (topmost first, since they're drawn behind).
    for (int i = images.length - 1; i >= 0; i--) {
      if (_imageRect(images[i]).contains(worldPos)) {
        selectedIndices = {};
        selectedImageIndices = {i};
        boundingBox = _computeBoundingBox(strokes, images);
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
    boundingBox = null;
    dragOffset = Offset.zero;
    _resetResizeState();
    rotationAngle = 0.0;
    _rotationCenter = null;
    _imageSnapshot = null;
    _notify();
  }

  bool get hasSelection =>
      selectedIndices.isNotEmpty || selectedImageIndices.isNotEmpty;

  bool _imageCenterInPolygon(CanvasImage im) =>
      _pointInPolygon(Offset(im.x + im.w / 2, im.y + im.h / 2), lassoPath);

  Rect _imageRect(CanvasImage im) => Rect.fromLTWH(im.x, im.y, im.w, im.h);

  // ─── Geometry ──────────────────────────────────────────────────────────

  bool _isStrokeInside(DrawingStroke stroke) {
    if (stroke.points.isEmpty) return false;
    int inside = 0;
    for (final p in stroke.points) {
      if (_pointInPolygon(Offset(p[0], p[1]), lassoPath)) inside++;
    }
    return inside / stroke.points.length >= 0.5;
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
      [List<CanvasImage> images = const []]) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final i in selectedIndices) {
      if (i >= strokes.length) continue;
      for (final p in strokes[i].points) {
        if (p[0] < minX) minX = p[0];
        if (p[0] > maxX) maxX = p[0];
        if (p[1] < minY) minY = p[1];
        if (p[1] > maxY) maxY = p[1];
      }
    }
    for (final i in selectedImageIndices) {
      if (i >= images.length) continue;
      final im = images[i];
      if (im.x < minX) minX = im.x;
      if (im.x + im.w > maxX) maxX = im.x + im.w;
      if (im.y < minY) minY = im.y;
      if (im.y + im.h > maxY) maxY = im.y + im.h;
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX - 8, minY - 8, maxX + 8, maxY + 8);
  }
}
