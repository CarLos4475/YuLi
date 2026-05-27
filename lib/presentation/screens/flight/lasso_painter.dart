import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'note_cell_model.dart';
import 'lasso_controller.dart';

const _kDash = 8.0;
const _kGap = 5.0;
const _kDashTotal = _kDash + _kGap;

class LassoPainter extends CustomPainter {
  final LassoController ctrl;
  final double animValue;
  final List<DrawingStroke> strokes;
  final Rect? visibleRect;

  LassoPainter({
    required this.ctrl,
    required this.animValue,
    required this.strokes,
    this.visibleRect,
  });

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

  // ─── Tracing ───────────────────────────────────────────────────────────

  void _paintTracing(Canvas canvas) {
    final path = ctrl.lassoPath;
    if (path.length < 2) return;

    final tracePath = Path()..moveTo(path.first.dx, path.first.dy);
    for (int i = 1; i < path.length; i++) {
      tracePath.lineTo(path[i].dx, path[i].dy);
    }
    _drawDashedPath(canvas, tracePath, const Color(0x99111111), 1.5);

    final closePath = Path()
      ..moveTo(path.last.dx, path.last.dy)
      ..lineTo(path.first.dx, path.first.dy);
    _drawDashedPath(canvas, closePath, const Color(0x55111111), 1.0);
  }

  // ─── Selection ─────────────────────────────────────────────────────────

  void _paintSelection(Canvas canvas, Offset offset) {
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

    for (final i in ctrl.selectedIndices) {
      if (i >= strokes.length) continue;
      final stroke = strokes[i];
      _drawStrokeXY(canvas, stroke, pivot, scX, scY, highlight: true);
      _drawStrokeXY(canvas, stroke, pivot, scX, scY, highlight: false);
    }

    if (ctrl.boundingBox != null) {
      final bb = ctrl.boundingBox!;
      final scaledBox = Rect.fromPoints(
        Offset(pivot.dx + (bb.left - pivot.dx) * scX, pivot.dy + (bb.top - pivot.dy) * scY),
        Offset(pivot.dx + (bb.right - pivot.dx) * scX, pivot.dy + (bb.bottom - pivot.dy) * scY),
      );
      _drawBoundingBox(canvas, scaledBox);
    }
  }

  void _drawStrokeXY(Canvas canvas, DrawingStroke stroke, Offset pivot,
      double scX, double scY, {required bool highlight}) {
    if (stroke.points.isEmpty) return;
    final avgScale = (scX + scY) / 2;
    final paint = Paint()
      ..color = highlight ? const Color(0x402D4B8E) : Color(stroke.colorValue)
      ..strokeWidth = highlight
          ? (stroke.strokeWidth + 6) * avgScale
          : stroke.strokeWidth * avgScale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final p = stroke.points[0];
      final px = pivot.dx + (p[0] - pivot.dx) * scX;
      final py = pivot.dy + (p[1] - pivot.dy) * scY;
      canvas.drawCircle(Offset(px, py), paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill);
      return;
    }

    final path = _buildScaledPathXY(stroke, pivot, scX, scY);
    canvas.drawPath(path, paint);
  }

  Path _buildScaledPathXY(DrawingStroke stroke, Offset pivot, double scX, double scY) {
    final pts = stroke.points;
    double tx(double x) => pivot.dx + (x - pivot.dx) * scX;
    double ty(double y) => pivot.dy + (y - pivot.dy) * scY;

    final path = Path()..moveTo(tx(pts[0][0]), ty(pts[0][1]));
    for (int i = 1; i < pts.length - 1; i++) {
      final x0 = tx(pts[i][0]);
      final y0 = ty(pts[i][1]);
      final x1 = tx(pts[i + 1][0]);
      final y1 = ty(pts[i + 1][1]);
      path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
    }
    final last = pts.last;
    path.lineTo(tx(last[0]), ty(last[1]));
    return path;
  }

  void _drawHighlight(Canvas canvas, DrawingStroke stroke, Offset offset) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0x402D4B8E)
      ..strokeWidth = stroke.strokeWidth + 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final p = stroke.points[0];
      canvas.drawCircle(
        Offset(p[0] + offset.dx, p[1] + offset.dy),
        (stroke.strokeWidth + 6) / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = _buildStrokePath(stroke, offset);
    canvas.drawPath(path, paint);
  }

  void _drawStrokeWithOffset(Canvas canvas, DrawingStroke stroke, Offset offset) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = Color(stroke.colorValue)
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final p = stroke.points[0];
      canvas.drawCircle(
        Offset(p[0] + offset.dx, p[1] + offset.dy),
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
    final path = Path()
      ..moveTo(pts[0][0] + offset.dx, pts[0][1] + offset.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final x0 = pts[i][0] + offset.dx;
      final y0 = pts[i][1] + offset.dy;
      final x1 = pts[i + 1][0] + offset.dx;
      final y1 = pts[i + 1][1] + offset.dy;
      path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
    }
    final last = pts.last;
    path.lineTo(last[0] + offset.dx, last[1] + offset.dy);
    return path;
  }

  // ─── Bounding box ──────────────────────────────────────────────────────

  void _paintRotating(Canvas canvas) {
    final center = ctrl.boundingBox?.center;
    if (center == null) return;
    final angle = ctrl.rotationAngle;
    final cos = math.cos(angle);
    final sin = math.sin(angle);

    for (final i in ctrl.selectedIndices) {
      if (i >= strokes.length) continue;
      _drawStrokeRotated(canvas, strokes[i], center, cos, sin, highlight: true);
      _drawStrokeRotated(canvas, strokes[i], center, cos, sin, highlight: false);
    }

    if (ctrl.boundingBox != null) {
      final bb = ctrl.boundingBox!;
      final corners = [bb.topLeft, bb.topRight, bb.bottomRight, bb.bottomLeft]
          .map((c) => _rotatePoint(c, center, cos, sin))
          .toList();
      final path = Path()
        ..moveTo(corners[0].dx, corners[0].dy)
        ..lineTo(corners[1].dx, corners[1].dy)
        ..lineTo(corners[2].dx, corners[2].dy)
        ..lineTo(corners[3].dx, corners[3].dy)
        ..close();
      _drawDashedPath(canvas, path, const Color(0x802D4B8E), 1.5);
    }
  }

  void _drawStrokeRotated(Canvas canvas, DrawingStroke stroke, Offset center,
      double cos, double sin, {required bool highlight}) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = highlight
          ? const Color(0x402D4B8E)
          : Color(stroke.colorValue)
      ..strokeWidth = highlight ? stroke.strokeWidth + 6 : stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      final p = stroke.points[0];
      final r = _rotatePoint(Offset(p[0], p[1]), center, cos, sin);
      canvas.drawCircle(r, paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill);
      return;
    }

    final path = _buildRotatedPath(stroke, center, cos, sin);
    canvas.drawPath(path, paint);
  }

  Path _buildRotatedPath(DrawingStroke stroke, Offset center, double cos, double sin) {
    final pts = stroke.points;
    Offset r(int i) => _rotatePoint(Offset(pts[i][0], pts[i][1]), center, cos, sin);
    final first = r(0);
    final path = Path()..moveTo(first.dx, first.dy);
    for (int i = 1; i < pts.length - 1; i++) {
      final p0 = r(i);
      final p1 = r(i + 1);
      path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    final last = r(pts.length - 1);
    path.lineTo(last.dx, last.dy);
    return path;
  }

  static Offset _rotatePoint(Offset p, Offset center, double cos, double sin) {
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    return Offset(center.dx + dx * cos - dy * sin, center.dy + dx * sin + dy * cos);
  }

  void _drawBoundingBox(Canvas canvas, Rect box) {
    final path = Path()
      ..moveTo(box.left, box.top)
      ..lineTo(box.right, box.top)
      ..lineTo(box.right, box.bottom)
      ..lineTo(box.left, box.bottom)
      ..close();
    _drawDashedPath(canvas, path, const Color(0x802D4B8E), 1.5);

    final handlePaint = Paint()
      ..color = const Color(0xFF2D4B8E)
      ..style = PaintingStyle.fill;
    const hs = 6.0;
    for (final corner in [
      box.topLeft, box.topRight, box.bottomLeft, box.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: hs, height: hs),
        handlePaint,
      );
    }
    final sidePaint = Paint()
      ..color = const Color(0xFF2D4B8E)
      ..style = PaintingStyle.fill;
    const ss = 5.0;
    for (final side in [
      Offset(box.center.dx, box.top),
      Offset(box.right, box.center.dy),
      Offset(box.center.dx, box.bottom),
      Offset(box.left, box.center.dy),
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: side, width: ss, height: ss),
        sidePaint,
      );
    }
    final rotHandle = Offset(box.center.dx, box.top - 14);
    canvas.drawLine(
      Offset(box.center.dx, box.top),
      rotHandle,
      Paint()..color = const Color(0x802D4B8E)..strokeWidth = 1,
    );
    canvas.drawCircle(rotHandle, 5, handlePaint);
  }

  // ─── Dashed path utility ───────────────────────────────────────────────

  void _drawDashedPath(Canvas canvas, Path source, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final metrics = source.computeMetrics();
    final phaseOffset = animValue * _kDashTotal;

    for (final metric in metrics) {
      double dist = -phaseOffset;
      while (dist < metric.length) {
        final start = dist.clamp(0.0, metric.length);
        final end = (dist + _kDash).clamp(0.0, metric.length);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), paint);
        }
        dist += _kDashTotal;
      }
    }
  }

  @override
  bool shouldRepaint(LassoPainter old) => true;
}
