import 'dart:typed_data';

class DrawingStrokeRecord {
  final int id;
  final int position;
  final Uint8List data;

  const DrawingStrokeRecord({
    required this.id,
    required this.position,
    required this.data,
  });
}

class DrawingStrokeBounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const DrawingStrokeBounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });
}

class DrawingStrokeWrite {
  final int position;
  final Uint8List data;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final int pointCount;

  const DrawingStrokeWrite({
    required this.position,
    required this.data,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.pointCount,
  });
}
