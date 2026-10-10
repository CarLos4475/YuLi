import 'dart:ui';

import 'note_cell_model.dart';
import 'stroke_tiles.dart';
import 'tracked_list.dart';

class TrackedStrokeIndex {
  TrackedStrokeIndex(this.strokes) {
    _tiles.rebuild(strokes);
    for (var i = 0; i < strokes.length; i++) {
      final entry = strokes.entryAt(i);
      _indexed[entry] = entry.value;
    }
    strokes.addMutationObserver(_changed);
  }

  final TrackedList<DrawingStroke> strokes;
  final StrokeTileIndex _tiles = StrokeTileIndex();
  final Map<TrackedEntry<DrawingStroke>, DrawingStroke> _indexed = {};
  final Set<TrackedEntry<DrawingStroke>> _pending = {};

  void _changed(TrackedEntry<DrawingStroke> entry) {
    if (entry.position < 0 || !identical(_indexed[entry], entry.value)) {
      _pending.add(entry);
    }
  }

  // Clone assignment can precede point edits; index the final geometry at query time.
  void _sync() {
    if (_pending.isEmpty) return;
    final removed = <DrawingStroke>[];
    final added = <DrawingStroke>[];
    for (final entry in _pending) {
      final old = _indexed[entry];
      final current = entry.position < 0 ? null : entry.value;
      if (identical(old, current)) continue;
      if (old != null) removed.add(old);
      if (current == null) {
        _indexed.remove(entry);
      } else {
        _indexed[entry] = current;
        added.add(current);
      }
    }
    _tiles.removeStrokes(removed);
    _tiles.appendAll(added);
    _pending.clear();
  }

  List<int> indicesInRect(Rect bounds) {
    _sync();
    return [
      for (final stroke in _tiles.strokesInRect(bounds))
        if (strokes.positionOf(stroke) case final position?) position,
    ]..sort();
  }

  void dispose() {
    strokes.removeMutationObserver(_changed);
    _pending.clear();
    _indexed.clear();
    _tiles.dispose();
  }
}
