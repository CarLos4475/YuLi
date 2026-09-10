import 'dart:ui';

import '../../../domain/models/canvas_ocr.dart';

class CanvasOcrMatch {
  final int blockId;
  final Rect bounds;
  final String identity;
  const CanvasOcrMatch(this.blockId, this.bounds, this.identity);
}

List<CanvasOcrMatch> searchCanvasOcrIsolate(
  (List<CanvasOcrPage>, String) input,
) => findCanvasOcrMatches(input.$1, input.$2);

List<CanvasOcrMatch> findCanvasOcrMatches(
  List<CanvasOcrPage> pages,
  String query,
) {
  final q = normalizeCanvasSearch(query.trim());
  if (q.isEmpty || q.length > 256) return [];
  final matches = <CanvasOcrMatch>[];
  for (final page in pages) {
    if (!page.isCurrent) continue;
    for (final s in page.segments) {
      final text = normalizeCanvasSearch(s.effectiveText);
      var from = 0;
      while (from < text.length) {
        final index = text.indexOf(q, from);
        if (index < 0) break;
        matches.add(
          CanvasOcrMatch(
            page.blockId,
            s.boundsForRange(index, index + q.length) ?? s.bounds,
            '${page.blockId}:${s.hash}:$index',
          ),
        );
        if (matches.length >= 1000) return matches;
        from = index + q.length;
      }
    }
  }
  return matches;
}
