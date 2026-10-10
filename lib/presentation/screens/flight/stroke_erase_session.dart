import 'canvas_selection_history.dart';
import 'list_selection.dart';
import 'note_cell_model.dart';
import 'tracked_list.dart';

class StrokeEraseSession {
  StrokeEraseSession(this.strokes);

  final TrackedList<DrawingStroke> strokes;
  final Map<TrackedEntry<DrawingStroke>, DrawingStroke> _erased = {};

  Set<int> get indices => {
    for (final item in _erased.entries)
      if (item.key.position >= 0 && identical(item.key.value, item.value))
        item.key.position,
  };

  bool collect(Iterable<int> candidates, bool Function(DrawingStroke) hit) {
    var changed = false;
    for (final i in candidates) {
      final entry = strokes.entryAt(i);
      if (identical(_erased[entry], entry.value) || !hit(entry.value)) continue;
      _erased[entry] = entry.value;
      changed = true;
    }
    return changed;
  }

  SelectionChange<DrawingStroke>? commit() {
    final selected = indices;
    _erased.clear();
    if (selected.isEmpty) return null;
    final before = IndexedSelection.capture(strokes, selected, (s) => s);
    removeListSelection(strokes, selected);
    return SelectionChange(before, IndexedSelection(strokes.length, {}));
  }
}
