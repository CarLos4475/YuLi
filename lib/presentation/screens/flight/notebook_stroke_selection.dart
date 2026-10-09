import 'dart:collection';

import 'note_cell_model.dart';

class NotebookStrokeLayout {
  NotebookStrokeLayout(Iterable<int> counts) {
    for (final count in counts) {
      _starts.add(_starts.last + count);
    }
  }

  final List<int> _starts = [0];
  int get length => _starts.last;
  int globalIndex(int page, int local) => _starts[page] + local;

  (int, int)? locate(int index) {
    if (index < 0 || index >= length) return null;
    var low = 0;
    var high = _starts.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (_starts[mid] <= index) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low, index - _starts[low]);
  }
}

class NotebookStrokeView extends ListBase<DrawingStroke> {
  NotebookStrokeView(this.pages)
    : layout = NotebookStrokeLayout(pages.map((page) => page.length));

  final List<List<DrawingStroke>> pages;
  final NotebookStrokeLayout layout;

  @override
  int get length => layout.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only stroke view');

  @override
  DrawingStroke operator [](int index) {
    final location = layout.locate(index);
    if (location == null) throw RangeError.index(index, this);
    return pages[location.$1][location.$2];
  }

  @override
  void operator []=(int index, DrawingStroke value) =>
      throw UnsupportedError('Read-only stroke view');
}

class NotebookSelectionView<T> extends ListBase<T> {
  NotebookSelectionView(this.pages, this.toWorld)
    : layout = NotebookStrokeLayout(pages.map((page) => page.length));

  final List<List<T>> pages;
  final T Function(int page, T value) toWorld;
  final NotebookStrokeLayout layout;
  final Map<int, T> _values = {};

  @override
  int get length => layout.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Fixed length selection view');

  @override
  T operator [](int index) => _values.putIfAbsent(index, () {
    final location = layout.locate(index);
    if (location == null) throw RangeError.index(index, this);
    return toWorld(location.$1, pages[location.$1][location.$2]);
  });

  @override
  void operator []=(int index, T value) {
    RangeError.checkValidIndex(index, this);
    _values[index] = value;
  }
}

int countIndicesBefore(List<int> sorted, int index) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (sorted[mid] < index) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
