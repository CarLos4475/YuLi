import 'canvas_selection_history.dart';
import 'list_selection.dart';
import 'note_cell_model.dart';
import 'notebook_stroke_selection.dart';

class NotebookPageNotLoaded implements Exception {
  const NotebookPageNotLoaded();
}

class NotebookStructuralEdit {
  NotebookStructuralEdit(this.pages, this.pageOffset, this.targetPage);
  final List<DrawingData?> pages;
  final double Function(int) pageOffset;
  final int Function(double) targetPage;
  final Set<int> touched = {};
  final Map<int, List<DrawingStroke>> removed = {};
  final Map<int, List<DrawingStroke>> added = {};
  Set<int> strokes = {}, images = {}, tasks = {}, texts = {};

  void delete(Map<int, CanvasSelectionSnapshot> selection) {
    for (final item in selection.entries) {
      final data = pages[item.key];
      final before = item.value;
      if (data == null || before.isEmpty) continue;
      touched.add(item.key);
      removed[item.key] =
          removeListSelection(
            data.strokes,
            before.strokes.values.keys,
          ).map((v) => v.$2).toList();
      removeListSelection(data.images, before.images.values.keys);
      removeListSelection(data.taskBlocks, before.tasks.values.keys);
      removeListSelection(data.textBlocks, before.texts.values.keys);
    }
  }

  void append(DrawingData world) {
    int destination(double y) {
      final page = targetPage(y);
      if (page < 0 || page >= pages.length || pages[page] == null) {
        throw const NotebookPageNotLoaded();
      }
      return page;
    }

    double centerY(DrawingStroke stroke) {
      var sum = 0.0;
      for (var i = 0; i < stroke.points.length; i++) {
        sum += stroke.points.y(i);
      }
      return stroke.points.isEmpty ? 0 : sum / stroke.points.length;
    }

    final strokePages = [
      for (final stroke in world.strokes) destination(centerY(stroke)),
    ];
    final imagePages = [
      for (final v in world.images) destination(v.y + v.h / 2),
    ];
    final taskPages = [
      for (final v in world.taskBlocks) destination(v.y + v.h / 2),
    ];
    final textPages = [
      for (final v in world.textBlocks) destination(v.y + v.h / 2),
    ];
    final placed = <(int, int)>[];
    for (var i = 0; i < world.strokes.length; i++) {
      final page = strokePages[i];
      final local = world.strokes[i].clone()..dbId = null;
      local.points.translate(0, -pageOffset(page));
      placed.add((page, pages[page]!.strokes.length));
      pages[page]!.strokes.add(local);
      (added[page] ??= []).add(local);
      touched.add(page);
    }
    final layout = NotebookStrokeLayout(
      pages.map((p) => p?.strokes.length ?? 0),
    );
    strokes = {for (final (p, i) in placed) layout.globalIndex(p, i)};
    Set<int> appendObjects<T extends CanvasGeo>(
      List<T> values,
      List<int> destinations,
      List<T> Function(DrawingData) list,
      T Function(T) clone,
    ) {
      final placed = <(int, int)>[];
      for (var i = 0; i < values.length; i++) {
        final page = destinations[i];
        final target = list(pages[page]!);
        placed.add((page, target.length));
        target.add(clone(values[i])..y -= pageOffset(page));
        touched.add(page);
      }
      final layout = NotebookStrokeLayout(
        pages.map((p) => p == null ? 0 : list(p).length),
      );
      return {for (final (p, i) in placed) layout.globalIndex(p, i)};
    }

    images = appendObjects(
      world.images,
      imagePages,
      (d) => d.images,
      (v) => v.clone(),
    );
    tasks = appendObjects(
      world.taskBlocks,
      taskPages,
      (d) => d.taskBlocks,
      (v) => v.clone(),
    );
    texts = appendObjects(
      world.textBlocks,
      textPages,
      (d) => d.textBlocks,
      (v) => v.clone(),
    );
  }
}
