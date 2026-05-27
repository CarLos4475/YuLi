import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, VoidCallback;
import 'note_cell_model.dart';

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

  List<Offset> lassoPath = [];
  Set<int> selectedIndices = {};
  Rect? boundingBox;

  Offset _dragStart = Offset.zero;
  Offset dragOffset = Offset.zero;
  Map<int, List<List<double>>>? _snapshotBeforeMove;

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

  void finishTracing(List<DrawingStroke> strokes) {
    if (phase != LassoPhase.tracing) return;
    if (lassoPath.length < 3) {
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

    if (selectedIndices.isEmpty) {
      deselect();
      return;
    }

    boundingBox = _computeBoundingBox(strokes);
    lassoPath = [];
    phase = LassoPhase.selected;
    _notify();
  }

  // ─── Moving ────────────────────────────────────────────────────────────

  bool isTapInsideBoundingBox(Offset worldPos) {
    if (boundingBox == null) return false;
    return boundingBox!.inflate(12).contains(worldPos);
  }

  void startMove(Offset worldPos, List<DrawingStroke> strokes) {
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
    phase = LassoPhase.moving;
    _notify();
  }

  void updateMove(Offset worldPos) {
    if (phase != LassoPhase.moving) return;
    dragOffset = worldPos - _dragStart;
    _notify();
  }

  LassoMoveResult finishMove(List<DrawingStroke> strokes) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        for (final p in strokes[i].points) {
          p[0] += dragOffset.dx;
          p[1] += dragOffset.dy;
        }
      }
    }

    boundingBox = _computeBoundingBox(strokes);
    dragOffset = Offset.zero;
    _snapshotBeforeMove = null;
    phase = LassoPhase.selected;
    _notify();
    return result;
  }

  // ─── Resize (proportional from corners) ─────────────────────────────

  static const _handleHitRadius = 24.0;

  int? hitTestCornerHandle(Offset worldPos) {
    if (boundingBox == null) return null;
    final bb = boundingBox!;
    final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft];
    for (int i = 0; i < corners.length; i++) {
      if ((worldPos - corners[i]).distance < _handleHitRadius) return i;
    }
    return null;
  }

  void startResize(int cornerIndex, Offset worldPos, List<DrawingStroke> strokes) {
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

  LassoMoveResult finishResize(List<DrawingStroke> strokes) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final s = resizeScale;

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        for (final p in strokes[i].points) {
          p[0] = pivot.dx + (p[0] - pivot.dx) * s;
          p[1] = pivot.dy + (p[1] - pivot.dy) * s;
        }
      }
    }

    boundingBox = _computeBoundingBox(strokes);
    resizePivot = null;
    resizeScale = 1.0;
    _resizeOriginalBox = null;
    _snapshotBeforeMove = null;
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

  void startSideResize(int sideIndex, Offset worldPos, List<DrawingStroke> strokes) {
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

  LassoMoveResult finishSideResize(List<DrawingStroke> strokes) {
    final result = LassoMoveResult(_snapshotBeforeMove ?? {});
    final pivot = resizePivot!;
    final sx = resizeScaleX;
    final sy = resizeScaleY;

    for (final i in selectedIndices) {
      if (i < strokes.length) {
        for (final p in strokes[i].points) {
          p[0] = pivot.dx + (p[0] - pivot.dx) * sx;
          p[1] = pivot.dy + (p[1] - pivot.dy) * sy;
        }
      }
    }

    boundingBox = _computeBoundingBox(strokes);
    _resetResizeState();
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

  void startRotation(Offset worldPos, List<DrawingStroke> strokes) {
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

  LassoMoveResult finishRotation(List<DrawingStroke> strokes) {
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

    boundingBox = _computeBoundingBox(strokes);
    rotationAngle = 0.0;
    _rotationCenter = null;
    _snapshotBeforeMove = null;
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

  bool get hasClipboard => _clipboard != null && _clipboard!.isNotEmpty;

  void copySelected(List<DrawingStroke> strokes) {
    _clipboard = [];
    final cx = boundingBox?.center.dx ?? 0;
    final cy = boundingBox?.center.dy ?? 0;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final s = strokes[i];
        _clipboard!.add(DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points.map((p) => [p[0] - cx, p[1] - cy]).toList(),
        ));
      }
    }
    deselect();
  }

  void cutSelected(List<DrawingStroke> strokes) {
    _clipboard = [];
    final cx = boundingBox?.center.dx ?? 0;
    final cy = boundingBox?.center.dy ?? 0;
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final s = strokes[i];
        _clipboard!.add(DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points.map((p) => [p[0] - cx, p[1] - cy]).toList(),
        ));
      }
    }
    deleteSelected(strokes);
  }

  LassoDuplicateResult pasteAt(Offset worldPos, List<DrawingStroke> strokes) {
    if (_clipboard == null || _clipboard!.isEmpty) {
      return LassoDuplicateResult(0);
    }
    final startIdx = strokes.length;
    for (final s in _clipboard!) {
      strokes.add(DrawingStroke(
        colorValue: s.colorValue,
        strokeWidth: s.strokeWidth,
        points: s.points.map((p) => [p[0] + worldPos.dx, p[1] + worldPos.dy]).toList(),
      ));
    }
    selectedIndices = Set.from(
      List.generate(_clipboard!.length, (i) => startIdx + i),
    );
    boundingBox = _computeBoundingBox(strokes);
    phase = LassoPhase.selected;
    _notify();
    return LassoDuplicateResult(_clipboard!.length);
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
        final s = strokes[i];
        strokes[i] = DrawingStroke(
          colorValue: colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points,
        );
      }
    }
    _notify();
  }

  void changeWidth(List<DrawingStroke> strokes, double width) {
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final s = strokes[i];
        strokes[i] = DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: width,
          points: s.points,
        );
      }
    }
    _notify();
  }

  // ─── Delete ────────────────────────────────────────────────────────────

  LassoDeleteResult deleteSelected(List<DrawingStroke> strokes) {
    final sorted = selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    final removed = <(int, DrawingStroke)>[];
    for (final i in sorted) {
      if (i < strokes.length) {
        removed.add((i, strokes.removeAt(i)));
      }
    }
    deselect();
    return LassoDeleteResult(removed.reversed.toList());
  }

  // ─── Duplicate ─────────────────────────────────────────────────────────

  LassoDuplicateResult duplicateSelected(List<DrawingStroke> strokes) {
    final copies = <DrawingStroke>[];
    for (final i in selectedIndices) {
      if (i < strokes.length) {
        final s = strokes[i];
        copies.add(DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points.map((p) => [p[0] + 15, p[1] + 15]).toList(),
        ));
      }
    }
    final startIdx = strokes.length;
    strokes.addAll(copies);

    selectedIndices = Set.from(
      List.generate(copies.length, (i) => startIdx + i),
    );
    boundingBox = _computeBoundingBox(strokes);
    _notify();
    return LassoDuplicateResult(copies.length);
  }

  // ─── Select range (after duplicate) ────────────────────────────────────

  void selectRange(List<DrawingStroke> strokes, int from, int to) {
    selectedIndices = Set.from(List.generate(to - from, (i) => from + i));
    boundingBox = _computeBoundingBox(strokes);
    phase = LassoPhase.selected;
    _notify();
  }

  // ─── Tap to select single stroke ─────────────────────────────────────

  bool tapSelect(Offset worldPos, List<DrawingStroke> strokes) {
    const hitRadius2 = 20.0 * 20.0;
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
      boundingBox = _computeBoundingBox(strokes);
      lassoPath = [];
      phase = LassoPhase.selected;
      _notify();
      return true;
    }
    return false;
  }

  // ─── Deselect ──────────────────────────────────────────────────────────

  void deselect() {
    phase = LassoPhase.idle;
    lassoPath = [];
    selectedIndices = {};
    boundingBox = null;
    dragOffset = Offset.zero;
    _resetResizeState();
    rotationAngle = 0.0;
    _rotationCenter = null;
    _notify();
  }

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

  Rect _computeBoundingBox(List<DrawingStroke> strokes) {
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
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX - 8, minY - 8, maxX + 8, maxY + 8);
  }
}
