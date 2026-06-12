class DrawingStrokeRecord {
  final int id;
  final int position;
  final Map<String, dynamic> payload;

  const DrawingStrokeRecord({
    required this.id,
    required this.position,
    required this.payload,
  });
}

class DrawingStrokeWrite {
  final int position;
  final Map<String, dynamic> payload;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final int pointCount;

  const DrawingStrokeWrite({
    required this.position,
    required this.payload,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.pointCount,
  });
}
