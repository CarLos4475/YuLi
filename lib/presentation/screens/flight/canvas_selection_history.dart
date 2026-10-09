import 'note_cell_model.dart';

class IndexedSelection<T> {
  IndexedSelection(this.length, this.values);

  factory IndexedSelection.capture(
    List<T> source,
    Iterable<int> indices,
    T Function(T) copy,
  ) => IndexedSelection(source.length, {
    for (final i in indices)
      if (i >= 0 && i < source.length) i: copy(source[i]),
  });

  final int length;
  final Map<int, T> values;
}

class SelectionChange<T> {
  SelectionChange(this.before, this.after);

  final IndexedSelection<T> before;
  final IndexedSelection<T> after;

  bool get structural =>
      before.length != after.length ||
      before.values.length != after.values.length ||
      !before.values.keys.every(after.values.containsKey);

  void apply(
    List<T> target, {
    required bool undo,
    required T Function(T) copy,
  }) {
    final from = undo ? after : before;
    final to = undo ? before : after;
    if (target.length != from.length) {
      throw StateError('Selection history does not match the canvas');
    }
    if (!structural) {
      for (final entry in to.values.entries) {
        target[entry.key] = copy(entry.value);
      }
      return;
    }
    final commonLength = from.length < to.length ? from.length : to.length;
    if (from.values.length == from.length - commonLength &&
        to.values.length == to.length - commonLength &&
        from.values.keys.every((i) => i >= commonLength) &&
        to.values.keys.every((i) => i >= commonLength)) {
      if (target.length > commonLength) {
        target.removeRange(commonLength, target.length);
      }
      for (var i = commonLength; i < to.length; i++) {
        target.add(copy(to.values[i] as T));
      }
      return;
    }
    // Structural edits compact once, avoiding one array shift per selected item.
    final result = <T>[];
    var sourceIndex = 0;
    for (var i = 0; i < to.length; i++) {
      if (to.values.containsKey(i)) {
        result.add(copy(to.values[i] as T));
      } else {
        while (from.values.containsKey(sourceIndex)) {
          sourceIndex++;
        }
        result.add(target[sourceIndex++]);
      }
    }
    target
      ..clear()
      ..addAll(result);
  }
}

class CanvasSelectionSnapshot {
  CanvasSelectionSnapshot(this.strokes, this.images, this.tasks, this.texts);

  factory CanvasSelectionSnapshot.capture(
    DrawingData data, {
    Iterable<int> strokes = const [],
    Iterable<int> images = const [],
    Iterable<int> tasks = const [],
    Iterable<int> texts = const [],
  }) => CanvasSelectionSnapshot(
    IndexedSelection.capture(data.strokes, strokes, (s) => s),
    IndexedSelection.capture(data.images, images, (s) => s.clone()),
    IndexedSelection.capture(data.taskBlocks, tasks, (s) => s.clone()),
    IndexedSelection.capture(data.textBlocks, texts, (s) => s.clone()),
  );

  final IndexedSelection<DrawingStroke> strokes;
  final IndexedSelection<CanvasImage> images;
  final IndexedSelection<CanvasTaskBlock> tasks;
  final IndexedSelection<CanvasTextBlock> texts;

  bool get isEmpty =>
      strokes.values.isEmpty &&
      images.values.isEmpty &&
      tasks.values.isEmpty &&
      texts.values.isEmpty;

  CanvasSelectionSnapshot captureAfter(
    DrawingData data, {
    required Iterable<int> strokes,
    required Iterable<int> images,
    required Iterable<int> tasks,
    required Iterable<int> texts,
  }) {
    Iterable<int> retained<T>(
      IndexedSelection<T> old,
      List<T> list,
      Iterable<int> selected,
    ) => {if (list.length >= old.length) ...old.values.keys, ...selected};
    return CanvasSelectionSnapshot.capture(
      data,
      strokes: retained(this.strokes, data.strokes, strokes),
      images: retained(this.images, data.images, images),
      tasks: retained(this.tasks, data.taskBlocks, tasks),
      texts: retained(this.texts, data.textBlocks, texts),
    );
  }
}

class CanvasSelectionChange {
  CanvasSelectionChange(
    CanvasSelectionSnapshot before,
    CanvasSelectionSnapshot after,
  ) : strokes = SelectionChange(before.strokes, after.strokes),
      images = SelectionChange(before.images, after.images),
      tasks = SelectionChange(before.tasks, after.tasks),
      texts = SelectionChange(before.texts, after.texts);

  final SelectionChange<DrawingStroke> strokes;
  final SelectionChange<CanvasImage> images;
  final SelectionChange<CanvasTaskBlock> tasks;
  final SelectionChange<CanvasTextBlock> texts;

  void apply(DrawingData data, {required bool undo}) {
    strokes.apply(data.strokes, undo: undo, copy: (s) => s);
    images.apply(data.images, undo: undo, copy: (s) => s.clone());
    tasks.apply(data.taskBlocks, undo: undo, copy: (s) => s.clone());
    texts.apply(data.textBlocks, undo: undo, copy: (s) => s.clone());
  }
}
