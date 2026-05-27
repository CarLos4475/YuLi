import 'dart:ui';

import 'note_cell_model.dart';

void drawStroke(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;
  final paint = Paint()
    ..color = Color(stroke.colorValue)
    ..strokeWidth = stroke.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      Offset(stroke.points[0][0], stroke.points[0][1]),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path();
  path.moveTo(stroke.points[0][0], stroke.points[0][1]);
  for (int i = 1; i < stroke.points.length - 1; i++) {
    final x0 = stroke.points[i][0];
    final y0 = stroke.points[i][1];
    final x1 = stroke.points[i + 1][0];
    final y1 = stroke.points[i + 1][1];
    path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
  }
  final last = stroke.points.last;
  path.lineTo(last[0], last[1]);
  canvas.drawPath(path, paint);
}

List<List<double>> smoothPoints(List<List<double>> pts) {
  if (pts.length < 3) return pts;
  final out = <List<double>>[pts.first];
  for (int i = 1; i < pts.length - 1; i++) {
    out.add([
      (pts[i - 1][0] + pts[i][0] * 2 + pts[i + 1][0]) / 4,
      (pts[i - 1][1] + pts[i][1] * 2 + pts[i + 1][1]) / 4,
    ]);
  }
  out.add(pts.last);
  return out;
}
