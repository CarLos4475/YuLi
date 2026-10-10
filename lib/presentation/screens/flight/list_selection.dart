List<(int, T)> removeListSelection<T>(List<T> values, Iterable<int> indices) {
  final selected = indices.where((i) => i >= 0 && i < values.length).toSet();
  if (selected.isEmpty) return [];
  final sorted = selected.toList()..sort();
  final removed = [for (final i in sorted) (i, values[i])];
  if (sorted.first == values.length - sorted.length) {
    values.removeRange(sorted.first, values.length);
  } else {
    var index = 0;
    values.removeWhere((_) => selected.contains(index++));
  }
  return removed;
}
