import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:uuid/uuid.dart';

enum CellType { markdown, drawing }

class NoteCell {
  final String id;
  final CellType type;
  String content;
  DrawingData? drawingData;

  NoteCell({
    String? id,
    required this.type,
    this.content = '',
    this.drawingData,
  }) : id = id ?? const Uuid().v4();
}

class DrawingData {
  double height;
  List<DrawingStroke> strokes;

  DrawingData({
    this.height = 300,
    List<DrawingStroke>? strokes,
  }) : strokes = strokes ?? [];

  Map<String, dynamic> toJson() => {
        'h': height,
        's': strokes.map((s) => s.toJson()).toList(),
      };

  factory DrawingData.fromJson(Map<String, dynamic> json) => DrawingData(
        height: (json['h'] as num?)?.toDouble() ?? 300,
        strokes: (json['s'] as List?)
                ?.map(
                    (s) => DrawingStroke.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class DrawingStroke {
  final int colorValue;
  final double strokeWidth;
  final List<List<double>> points;

  DrawingStroke({
    required this.colorValue,
    required this.strokeWidth,
    List<List<double>>? points,
  }) : points = points ?? [];

  Map<String, dynamic> toJson() => {
        'c': colorValue,
        'w': strokeWidth,
        'p': points,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
        colorValue: json['c'] as int,
        strokeWidth: (json['w'] as num).toDouble(),
        points: (json['p'] as List)
            .map((p) =>
                (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
      );
}

// ─── Scribble detection ──────────────────────────────────────────────────────

bool isScribble(List<List<double>> points) {
  if (points.length < 15) return false;

  int crossings = 0;
  final len = points.length;
  for (int i = 0; i < len - 3 && crossings < 5; i++) {
    for (int j = i + 2; j < len - 1; j++) {
      if (_segmentsIntersect(
        points[i][0], points[i][1], points[i + 1][0], points[i + 1][1],
        points[j][0], points[j][1], points[j + 1][0], points[j + 1][1],
      )) {
        crossings++;
        if (crossings >= 5) return true;
      }
    }
  }
  return false;
}

bool _segmentsIntersect(
  double ax, double ay, double bx, double by,
  double cx, double cy, double dx, double dy,
) {
  double cross(double ux, double uy, double vx, double vy) => ux * vy - uy * vx;
  final d1 = cross(dx - cx, dy - cy, ax - cx, ay - cy);
  final d2 = cross(dx - cx, dy - cy, bx - cx, by - cy);
  final d3 = cross(bx - ax, by - ay, cx - ax, cy - ay);
  final d4 = cross(bx - ax, by - ay, dx - ax, dy - ay);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

Rect scribbleBounds(List<List<double>> points) {
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (final p in points) {
    if (p[0] < minX) minX = p[0];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] < minY) minY = p[1];
    if (p[1] > maxY) maxY = p[1];
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

// ─── Serialization ───────────────────────────────────────────────────────────

final _cellRe = RegExp(r'<!-- CELL (\w+) (\S+)(?: (.*))? -->');

List<NoteCell> parseCells(String raw) {
  if (!raw.contains('<!-- CELL ')) {
    return [NoteCell(type: CellType.markdown, content: raw)];
  }

  final cells = <NoteCell>[];
  final matches = _cellRe.allMatches(raw).toList();

  for (int i = 0; i < matches.length; i++) {
    final m = matches[i];
    final typeName = m.group(1)!;
    final id = m.group(2)!;
    final extra = m.group(3);

    if (typeName == 'markdown') {
      final start = m.end;
      final end =
          i + 1 < matches.length ? matches[i + 1].start : raw.length;
      var content = raw.substring(start, end);
      if (content.startsWith('\n')) content = content.substring(1);
      while (content.endsWith('\n')) {
        content = content.substring(0, content.length - 1);
      }
      cells.add(NoteCell(id: id, type: CellType.markdown, content: content));
    } else if (typeName == 'drawing') {
      DrawingData data;
      if (extra != null && extra.isNotEmpty) {
        try {
          data = DrawingData.fromJson(
              jsonDecode(extra) as Map<String, dynamic>);
        } catch (_) {
          data = DrawingData();
        }
      } else {
        data = DrawingData();
      }
      cells.add(
          NoteCell(id: id, type: CellType.drawing, drawingData: data));
    }
  }

  return cells.isEmpty
      ? [NoteCell(type: CellType.markdown, content: raw)]
      : cells;
}

String cleanCellContent(String raw) {
  var cleaned = raw;
  cleaned = cleaned.replaceAll(RegExp(r'<!-- CELL \w+ \S+.*?-->'), '');
  cleaned = cleaned.replaceAll(RegExp(r':::\s*(left|center|right)\s*\n?'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^:::\s*$', multiLine: true), '');
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return cleaned.trim();
}

String serializeCells(List<NoteCell> cells) {
  if (cells.length == 1 && cells[0].type == CellType.markdown) {
    return cells[0].content;
  }

  final buf = StringBuffer();
  for (final cell in cells) {
    switch (cell.type) {
      case CellType.markdown:
        buf.writeln('<!-- CELL markdown ${cell.id} -->');
        buf.writeln(cell.content);
      case CellType.drawing:
        final data = cell.drawingData;
        if (data != null) {
          for (final stroke in data.strokes) {
            stroke.points.removeWhere(
                (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
          }
          data.strokes.removeWhere((s) => s.points.isEmpty);
        }
        try {
          final json = jsonEncode(data?.toJson() ?? {});
          buf.writeln('<!-- CELL drawing ${cell.id} $json -->');
        } catch (_) {
          buf.writeln('<!-- CELL drawing ${cell.id} {} -->');
        }
    }
  }
  return buf.toString();
}
