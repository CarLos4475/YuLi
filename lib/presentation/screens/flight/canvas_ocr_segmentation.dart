import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:crypto/crypto.dart';

import '../../../domain/models/canvas_ocr.dart';
import '../../../domain/models/drawing_stroke_record.dart';
import 'drawing_stroke_persistence.dart';

class CanvasInkGroup {
  final String hash;
  final Rect bounds;
  final List<List<Offset>> strokes;
  const CanvasInkGroup(this.hash, this.bounds, this.strokes);
}

List<CanvasInkGroup> segmentCanvasInk(List<DrawingStrokeRecord> records) {
  final groups = <_InkLine>[];
  for (final record in records) {
    final stroke = strokeFromRecord(record);
    if (stroke.isShape || stroke.isHighlighter || stroke.points.isEmpty) {
      continue;
    }
    final points = <Offset>[];
    final step = math.max(1, (stroke.points.length / 256).ceil());
    for (var i = 0; i < stroke.points.length; i += step) {
      final point = stroke.points.offset(i);
      if (!point.dx.isFinite || !point.dy.isFinite) continue;
      points.add(point);
    }
    final last = stroke.points.offset(stroke.points.length - 1);
    if (last.dx.isFinite &&
        last.dy.isFinite &&
        (points.isEmpty || points.last != last)) {
      points.add(last);
    }
    if (points.isEmpty) continue;
    if (points.length == 1) points.add(points.first);
    var bounds = Rect.fromPoints(points.first, points.first);
    for (final p in points.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
    }
    _InkLine? match;
    var nearest = double.infinity;
    for (final group in groups) {
      if (group.strokes.length >= 64) continue;
      final height = math.max(
        12.0,
        math.max(group.bounds.height, bounds.height),
      );
      final dy = (bounds.center.dy - group.bounds.center.dy).abs();
      final gap = math.max(
        bounds.left - group.bounds.right,
        group.bounds.left - bounds.right,
      );
      if (dy <= height * .55 && gap < height * 3 && dy < nearest) {
        nearest = dy;
        match = group;
      }
    }
    if (match == null) {
      match = _InkLine(bounds);
      groups.add(match);
    }
    match.bounds = match.bounds.expandToInclude(bounds);
    match.strokes.add(points);
    match.identities.add('${record.id}:${sha256.convert(record.data)}');
  }
  groups.sort((a, b) {
    final y = a.bounds.top.compareTo(b.bounds.top);
    return y == 0 ? a.bounds.left.compareTo(b.bounds.left) : y;
  });
  return groups
      .map(
        (g) => CanvasInkGroup(
          sha256
              .convert(utf8.encode('es:v1:${g.identities.join('|')}'))
              .toString(),
          g.bounds,
          g.strokes
              .map((s) => s.map((p) => p - g.bounds.topLeft).toList())
              .toList(),
        ),
      )
      .toList();
}

class _InkLine {
  Rect bounds;
  final strokes = <List<Offset>>[];
  final identities = <String>[];
  _InkLine(this.bounds);
}

List<CanvasOcrWord> alignCanvasWords(CanvasInkGroup group, String text) {
  final tokens = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9]+').allMatches(text).toList();
  if (tokens.isEmpty || tokens.length > 64 || text.contains('\n')) return [];
  final boxes = <Rect>[];
  for (final stroke in group.strokes) {
    if (stroke.isEmpty) continue;
    var box = Rect.fromPoints(stroke.first, stroke.first);
    for (final p in stroke.skip(1)) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    boxes.add(box);
  }
  boxes.sort((a, b) => a.left.compareTo(b.left));
  final clusters = <Rect>[];
  final gap = math.max(4.0, group.bounds.height * .35);
  for (final box in boxes) {
    if (clusters.isEmpty || box.left - clusters.last.right > gap) {
      clusters.add(box);
    } else {
      clusters[clusters.length - 1] = clusters.last.expandToInclude(box);
    }
  }
  // Never infer word widths from character counts: require actual ink gaps.
  if (clusters.length != tokens.length ||
      clusters.any((b) => b.isEmpty || b.height < group.bounds.height * .25)) {
    return [];
  }
  return [
    for (var i = 0; i < tokens.length; i++)
      CanvasOcrWord(
        tokens[i].start,
        tokens[i].end,
        clusters[i].shift(group.bounds.topLeft),
      ),
  ];
}
