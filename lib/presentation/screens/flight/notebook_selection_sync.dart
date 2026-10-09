import 'note_cell_model.dart';
import 'notebook_stroke_selection.dart';

Set<int> syncNotebookSelectedObjects<T extends CanvasGeo>(
  List<T> world,
  Set<int> selected,
  List<List<T>> pages,
  double Function(int) pageOffset,
  int Function(double) targetPage,
  bool Function(int) isLoaded,
  T Function(T) clone,
  Set<int> touched,
) {
  final layout = NotebookStrokeLayout(pages.map((p) => p.length));
  final removals = <int, Set<int>>{};
  final appends = <int, List<T>>{};
  final placed = <(int, int)>[];
  for (final i in selected.toList()..sort()) {
    final source = layout.locate(i);
    if (source == null) continue;
    final value = world[i];
    var target = targetPage(value.y + value.h / 2);
    if (target < 0 || !isLoaded(target)) {
      target = source.$1;
    }
    final local = clone(value)..y -= pageOffset(target);
    touched.addAll([source.$1, target]);
    if (source.$1 == target) {
      pages[target][source.$2] = local;
      placed.add((target, source.$2));
    } else {
      (removals[source.$1] ??= {}).add(source.$2);
      (appends[target] ??= []).add(local);
    }
  }
  final sortedRemovals = {
    for (final entry in removals.entries)
      entry.key: entry.value.toList()..sort(),
  };
  final result = <(int, int)>[];
  for (final (page, index) in placed) {
    final removedBefore = countIndicesBefore(
      sortedRemovals[page] ?? const [],
      index,
    );
    result.add((page, index - removedBefore));
  }
  for (final entry in removals.entries) {
    var i = 0;
    pages[entry.key].removeWhere((_) => entry.value.contains(i++));
  }
  for (final entry in appends.entries) {
    final target = pages[entry.key];
    for (final value in entry.value) {
      result.add((entry.key, target.length));
      target.add(value);
    }
  }
  final next = NotebookStrokeLayout(pages.map((p) => p.length));
  return {for (final (page, local) in result) next.globalIndex(page, local)};
}
