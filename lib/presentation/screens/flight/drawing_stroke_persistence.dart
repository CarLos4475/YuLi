import '../../../domain/models/drawing_stroke_record.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

DrawingStroke strokeFromRecord(DrawingStrokeRecord record) {
  final stroke = DrawingStroke.fromJson(record.payload);
  stroke.dbId = record.id;
  return stroke;
}

DrawingStrokeWrite strokeWrite(int position, DrawingStroke stroke) {
  final b = strokeBounds(stroke);
  return DrawingStrokeWrite(
    position: position,
    payload: stroke.toJson()..remove('dbid'),
    minX: b.left,
    minY: b.top,
    maxX: b.right,
    maxY: b.bottom,
    pointCount: stroke.points.length,
  );
}
