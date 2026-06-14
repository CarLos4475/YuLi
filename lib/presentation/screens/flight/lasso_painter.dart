import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'canvas_image_cache.dart';
import 'drawing_engine.dart';
import 'note_cell_model.dart';
import 'lasso_controller.dart';

const _kDash = 8.0;
const _kGap = 5.0;
const _kDashTotal = _kDash + _kGap;

class LassoPainter extends CustomPainter {
  final LassoController ctrl;
  final double animValue;
  final List<DrawingStroke> strokes;
  final List<CanvasImage> images;
  final CanvasImageCache? imageCache;
  final Rect? visibleRect;

  /// When set, the selected strokes+images are "lifted": a pixel-exact,
  /// transparent texture (captured once) drawn at the live bounding box instead
  /// of redrawing the vector strokes/image ghosts. Lets a move slide the real
  /// pixels with no per-frame vector work and no re-raster on drop. Block
  /// overlays ride along as widgets (separate). Null on the notebook editor →
  /// falls back to vectors.
  final ui.Image? liftedInk;

  LassoPainter({
    required this.ctrl,
    required this.animValue,
    required this.strokes,
    this.images = const [],
    this.imageCache,
    this.visibleRect,
    this.liftedInk,
  });

  ui.Image? _img(CanvasImage im) => imageCache?.get(im.filename);

  @override
  void paint(Canvas canvas, Size size) {
    switch (ctrl.phase) {
      case LassoPhase.idle:
        return;
      case LassoPhase.tracing:
        _paintTracing(canvas);
      case LassoPhase.selected:
        _paintSelection(canvas, Offset.zero);
      case LassoPhase.moving:
        _paintSelection(canvas, ctrl.dragOffset);
      case LassoPhase.resizing:
        _paintResizing(canvas);
      case LassoPhase.rotating:
        _paintRotating(canvas);
    }
  }

  void _applyHighlighter(Paint paint, DrawingStroke stroke) {
    if (!stroke.isHighlighter) return;
    paint
      ..blendMode = BlendMode.multiply
      ..color = Color(stroke.colorValue).withValues(alpha: 0.5);
  }

  // ─── Tracing ───────────────────────────────────────────────────────────

  void _paintTracing(Canvas canvas) {
    final path = ctrl.lassoPath;
    if (path.length < 2) return;

    _drawDashedPolyline(canvas, path, const Color(0x99111111), 1.5);
    _drawDashedPolyline(
      canvas,
      [path.last, path.first],
      const Color(0x55111111),
      1.0,
    );
  }

  // ─── Selection ─────────────────────────────────────────────────────────

  void _paintSelection(Canvas canvas, Offset offset) {
    if (ctrl.phase == LassoPhase.moving && liftedInk != null) {
      final rect = ctrl.liftedRect ?? ctrl.boundingBox;
      if (rect != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          liftedInk!.width.toDouble(),
          liftedInk!.height.toDouble(),
        );
        final dst = rect.shift(offset);
        canvas.drawImageRect(
          liftedInk!,
          src,
          dst,
          Paint()..filterQuality = ui.FilterQuality.low,
        );
      }
      if (ctrl.boundingBox != null) {
        _drawBoundingBox(canvas, ctrl.boundingBox!.shift(offset));
      }
      return;
    }

    for (final i in ctrl.selectedImageIndices) {
      if (i >= images.length) continue;
      final im = images[i];
      if (ctrl.phase == LassoPhase.moving) {
        final ghost =
            im.clone()
              ..x += offset.dx
              ..y += offset.dy;
        drawCanvasImage(canvas, _img(im), ghost);
      }
      canvas.drawRect(
        Rect.fromLTWH(im.x + offset.dx, im.y + offset.dy, im.w, im.h),
        Paint()..color = const Color(0x332D4B8E),
      );
    }

    for (final i in ctrl.selectedIndices) {
      if (i >= strokes.length) continue;
      final s = strokes[i];
      _drawHighlight(canvas, s, offset);
    }

    if (ctrl.phase == LassoPhase.moving) {
      for (final i in ctrl.selectedIndices) {
        if (i >= strokes.length) continue;
        _drawStrokeWithOffset(canvas, strokes[i], offset);
      }
    }

    if (ctrl.boundingBox != null) {
      _drawBoundingBox(canvas, ctrl.boundingBox!.shift(offset));
    }
  }

  void _paintResizing(Canvas canvas) {
    final pivot = ctrl.resizePivot;
    if (pivot == null) return;
    final scX = ctrl.isSideResize ? ctrl.resizeScaleX : ctrl.resizeScale;
    final scY = ctrl.isSideResize ? ctrl.resizeScaleY : ctrl.resizeScale;

    // Lifted: stretch the captured texture into the scaled box (one blit) instead
    // of re-pathing every selected stroke per frame. Re-baked crisp on release.
    if (liftedInk != null && ctrl.liftedRect != null) {
      final lr = ctrl.liftedRect!;
      final src = Rect.fromLTWH(
        0,
        0,
        liftedInk!.width.toDouble(),
        liftedInk!.height.toDouble(),
      );
      final dst = Rect.fromPoints(
        Offset(
          pivot.dx + (lr.left - pivot.dx) * scX,
          pivot.dy + (lr.top - pivot.dy) * scY,
        ),
        Offset(
          pivot.dx + (lr.right - pivot.dx) * scX,
          pivot.dy + (lr.bottom - pivot.dy) * scY,
        ),
      );
      canvas.drawImageRect(
        liftedInk!,
        src,
        dst,
        Paint()..filterQuality = ui.FilterQuality.low,
      );
      if (ctrl.boundingBox != null) {
        final bb = ctrl.boundingBox!;
        _drawBoundingBox(
          canvas,
          Rect.fromPoints(
            Offset(
              pivot.dx + (bb.left - pivot.dx) * scX,
              pivot.dy + (bb.top - pivot.dy) * scY,
            ),
            Offset(
              pivot.dx + (bb.right - pivot.dx) * scX,
              pivot.dy + (bb.bottom - pivot.dy) * scY,
            ),
          ),
        );
      }
      return;
    }

    for (final i in ctrl.selectedImageIndices) {
      if (i >= images.length) continue;
      final im = images[i];
      final ghost =
          im.clone()
            ..x = pivot.dx + (im.x - pivot.dx) * scX
            ..y = pivot.dy + (im.y - pivot.dy) * scY
            ..w = im.w * scX
            ..h = im.h * scY;
      drawCanvasImage(canvas, _img(im), ghost);
      canvas.drawRect(
        Rect.fromLTWH(ghost.x, ghost.y, ghost.w, ghost.h),
        Paint()..color = const Color(0x332D4B8E),
      );
    }

    for (final i in ctrl.selectedIndices) {
      if (i >= strokes.length) continue;
      final stroke = strokes[i];
      _drawStrokeXY(canvas, stroke, pivot, scX, scY, highlight: true);
      _drawStrokeXY(canvas, stroke, pivot, scX, scY, highlight: false);
    }

    if (ctrl.boundingBox != null) {
      final bb = ctrl.boundingBox!;
      final scaledBox = Rect.fromPoints(
        Offset(
          pivot.dx + (bb.left - pivot.dx) * scX,
          pivot.dy + (bb.top - pivot.dy) * scY,
        ),
        Offset(
          pivot.dx + (bb.right - pivot.dx) * scX,
          pivot.dy + (bb.bottom - pivot.dy) * scY,
        ),
      );
      _drawBoundingBox(canvas, scaledBox);
    }
  }

  void _drawStrokeXY(
    Canvas canvas,
    DrawingStroke stroke,
    Offset pivot,
    double scX,
    double scY, {
    required bool highlight,
  }) {
    if (stroke.points.isEmpty) return;
    final avgScale = (scX + scY) / 2;
    final paint =
        Paint()
          ..color =
              highlight ? const Color(0x402D4B8E) : Color(stroke.colorValue)
          ..strokeWidth =
              highlight
                  ? (stroke.strokeWidth + 6) * avgScale
                  : stroke.strokeWidth * avgScale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
    if (!highlight) _applyHighlighter(paint, stroke);

    if (stroke.points.length == 1) {
      final pts = stroke.points;
      final px = pivot.dx + (pts.x(0) - pivot.dx) * scX;
      final py = pivot.dy + (pts.y(0) - pivot.dy) * scY;
      canvas.drawCircle(
        Offset(px, py),
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = _buildScaledPathXY(stroke, pivot, scX, scY);
    canvas.drawPath(path, paint);
  }

  Path _buildScaledPathXY(
    DrawingStroke stroke,
    Offset pivot,
    double scX,
    double scY,
  ) {
    final pts = stroke.points;
    double tx(double x) => pivot.dx + (x - pivot.dx) * scX;
    double ty(double y) => pivot.dy + (y - pivot.dy) * scY;

    final path = Path()..moveTo(tx(pts.x(0)), ty(pts.y(0)));
    if (stroke.isShape) {
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(tx(pts.x(i)), ty(pts.y(i)));
      }
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final x0 = tx(pts.x(i));
      final y0 = ty(pts.y(i));
      final x1 = tx(pts.x(i + 1));
      final y1 = ty(pts.y(i + 1));
      path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
    }
    path.lineTo(tx(pts.lastX), ty(pts.lastY));
    return path;
  }

  void _drawHighlight(Canvas canvas, DrawingStroke stroke, Offset offset) {
    if (stroke.points.isEmpty) return;
    final paint =
        Paint()
          ..color = const Color(0x402D4B8E)
          ..strokeWidth = stroke.strokeWidth + 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final pts = stroke.points;
      canvas.drawCircle(
        Offset(pts.x(0) + offset.dx, pts.y(0) + offset.dy),
        (stroke.strokeWidth + 6) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = _buildStrokePath(stroke, offset);
    canvas.drawPath(path, paint);
  }

  void _drawStrokeWithOffset(
    Canvas canvas,
    DrawingStroke stroke,
    Offset offset,
  ) {
    if (stroke.points.isEmpty) return;
    final paint =
        Paint()
          ..color = Color(stroke.colorValue)
          ..strokeWidth = stroke.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
    _applyHighlighter(paint, stroke);

    if (stroke.points.length == 1) {
      final pts = stroke.points;
      canvas.drawCircle(
        Offset(pts.x(0) + offset.dx, pts.y(0) + offset.dy),
        stroke.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = _buildStrokePath(stroke, offset);
    canvas.drawPath(path, paint);
  }

  Path _buildStrokePath(DrawingStroke stroke, Offset offset) {
    final pts = stroke.points;
    final path = Path()..moveTo(pts.x(0) + offset.dx, pts.y(0) + offset.dy);
    if (stroke.isShape) {
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts.x(i) + offset.dx, pts.y(i) + offset.dy);
      }
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final x0 = pts.x(i) + offset.dx;
      final y0 = pts.y(i) + offset.dy;
      final x1 = pts.x(i + 1) + offset.dx;
      final y1 = pts.y(i + 1) + offset.dy;
      path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
    }
    path.lineTo(pts.lastX + offset.dx, pts.lastY + offset.dy);
    return path;
  }

  // ─── Bounding box ──────────────────────────────────────────────────────

  void _paintRotating(Canvas canvas) {
    final center = ctrl.boundingBox?.center;
    if (center == null) return;
    final angle = ctrl.rotationAngle;
    final cos = math.cos(angle);
    final sin = math.sin(angle);

    // Lifted: rotate the captured texture about the box center (one blit) instead
    // of re-pathing every selected stroke per frame. Re-baked crisp on release.
    if (liftedInk != null && ctrl.liftedRect != null) {
      final lr = ctrl.liftedRect!;
      final src = Rect.fromLTWH(
        0,
        0,
        liftedInk!.width.toDouble(),
        liftedInk!.height.toDouble(),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawImageRect(
        liftedInk!,
        src,
        lr,
        Paint()..filterQuality = ui.FilterQuality.low,
      );
      canvas.restore();
      if (ctrl.boundingBox != null) {
        final bb = ctrl.boundingBox!;
        final corners =
            [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft]
                .map((c) => _rotatePoint(c, center, cos, sin))
                .toList();
        _drawDashedPolyline(
          canvas,
          corners,
          const Color(0x802D4B8E),
          1.5 / (ctrl.hitScale <= 0 ? 1.0 : ctrl.hitScale),
          close: true,
        );
      }
      return;
    }

    for (final i in ctrl.selectedImageIndices) {
      if (i >= images.length) continue;
      final im = images[i];
      final icx = im.x + im.w / 2;
      final icy = im.y + im.h / 2;
      final r = _rotatePoint(Offset(icx, icy), center, cos, sin);
      final ghost =
          im.clone()
            ..x = r.dx - im.w / 2
            ..y = r.dy - im.h / 2
            ..rotation = im.rotation + angle;
      drawCanvasImage(canvas, _img(im), ghost);
    }

    for (final i in ctrl.selectedIndices) {
      if (i >= strokes.length) continue;
      _drawStrokeRotated(canvas, strokes[i], center, cos, sin, highlight: true);
      _drawStrokeRotated(
        canvas,
        strokes[i],
        center,
        cos,
        sin,
        highlight: false,
      );
    }

    if (ctrl.boundingBox != null) {
      final bb = ctrl.boundingBox!;
      final corners =
          [
            bb.topLeft,
            bb.topRight,
            bb.bottomRight,
            bb.bottomLeft,
          ].map((c) => _rotatePoint(c, center, cos, sin)).toList();
      _drawDashedPolyline(
        canvas,
        corners,
        const Color(0x802D4B8E),
        1.5 / (ctrl.hitScale <= 0 ? 1.0 : ctrl.hitScale),
        close: true,
      );
    }
  }

  void _drawStrokeRotated(
    Canvas canvas,
    DrawingStroke stroke,
    Offset center,
    double cos,
    double sin, {
    required bool highlight,
  }) {
    if (stroke.points.isEmpty) return;
    final paint =
        Paint()
          ..color =
              highlight ? const Color(0x402D4B8E) : Color(stroke.colorValue)
          ..strokeWidth =
              highlight ? stroke.strokeWidth + 6 : stroke.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
    if (!highlight) _applyHighlighter(paint, stroke);

    if (stroke.points.length == 1) {
      final r = _rotatePoint(stroke.points.offset(0), center, cos, sin);
      canvas.drawCircle(
        r,
        paint.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = _buildRotatedPath(stroke, center, cos, sin);
    canvas.drawPath(path, paint);
  }

  Path _buildRotatedPath(
    DrawingStroke stroke,
    Offset center,
    double cos,
    double sin,
  ) {
    final pts = stroke.points;
    Offset r(int i) => _rotatePoint(pts.offset(i), center, cos, sin);
    final first = r(0);
    final path = Path()..moveTo(first.dx, first.dy);
    if (stroke.isShape) {
      for (int i = 1; i < pts.length; i++) {
        final p = r(i);
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final p0 = r(i);
      final p1 = r(i + 1);
      path.quadraticBezierTo(
        p0.dx,
        p0.dy,
        (p0.dx + p1.dx) / 2,
        (p0.dy + p1.dy) / 2,
      );
    }
    final last = r(pts.length - 1);
    path.lineTo(last.dx, last.dy);
    return path;
  }

  static Offset _rotatePoint(Offset p, Offset center, double cos, double sin) {
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    return Offset(
      center.dx + dx * cos - dy * sin,
      center.dy + dx * sin + dy * cos,
    );
  }

  void _drawBoundingBox(Canvas canvas, Rect box) {
    // Everything below is drawn at a constant SIZE ON SCREEN (÷ scale) so the
    // box, handles and rotation knob stay visible and aimable when zoomed out.
    final s = ctrl.hitScale <= 0 ? 1.0 : ctrl.hitScale;
    _drawDashedPolyline(
      canvas,
      [
        Offset(box.left, box.top),
        Offset(box.right, box.top),
        Offset(box.right, box.bottom),
        Offset(box.left, box.bottom),
      ],
      const Color(0x802D4B8E),
      1.5 / s,
      close: true,
    );

    final handlePaint =
        Paint()
          ..color = const Color(0xFF2D4B8E)
          ..style = PaintingStyle.fill;
    final hs = 7.0 / s;
    for (final corner in [
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: hs, height: hs),
        handlePaint,
      );
    }
    final ss = 6.0 / s;
    // Text-only selections can't resize vertically → omit the top/bottom side
    // handles (matches hitTestSideHandle).
    final sideHandles =
        ctrl.blocksOnlySelection
            ? [
              Offset(box.right, box.center.dy),
              Offset(box.left, box.center.dy),
            ]
            : [
              Offset(box.center.dx, box.top),
              Offset(box.right, box.center.dy),
              Offset(box.center.dx, box.bottom),
              Offset(box.left, box.center.dy),
            ];
    for (final side in sideHandles) {
      canvas.drawRect(
        Rect.fromCenter(center: side, width: ss, height: ss),
        handlePaint,
      );
    }
    final rotHandle = Offset(box.center.dx, box.top - kLassoRotationGap / s);
    canvas.drawLine(
      Offset(box.center.dx, box.top),
      rotHandle,
      Paint()
        ..color = const Color(0x802D4B8E)
        ..strokeWidth = 1 / s,
    );
    canvas.drawCircle(rotHandle, 6 / s, handlePaint);
  }

  // ─── Dashed path utility ───────────────────────────────────────────────

  void _drawDashedPolyline(
    Canvas canvas,
    List<Offset> points,
    Color color,
    double width, {
    bool close = false,
  }) {
    if (points.length < 2) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

    final phaseOffset = animValue * _kDashTotal;
    var dashStart = -phaseOffset;
    var segmentStart = 0.0;
    final count = close ? points.length : points.length - 1;

    for (int i = 0; i < count; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final delta = b - a;
      final length = delta.distance;
      if (length <= 0) continue;
      final segmentEnd = segmentStart + length;
      while (dashStart + _kDash <= segmentStart) {
        dashStart += _kDashTotal;
      }
      var currentDash = dashStart;
      while (currentDash < segmentEnd) {
        final start = currentDash.clamp(segmentStart, segmentEnd);
        final end = (currentDash + _kDash).clamp(segmentStart, segmentEnd);
        if (end > start) {
          final localStart = (start - segmentStart) / length;
          final localEnd = (end - segmentStart) / length;
          canvas.drawLine(
            Offset.lerp(a, b, localStart)!,
            Offset.lerp(a, b, localEnd)!,
            paint,
          );
        }
        currentDash += _kDashTotal;
      }
      dashStart = currentDash - _kDashTotal;
      segmentStart = segmentEnd;
    }
  }

  @override
  bool shouldRepaint(LassoPainter old) => true;
}
