import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/canvas_selection_history.dart';
import 'package:yuli/presentation/screens/flight/lasso_controller.dart';
import 'package:yuli/presentation/screens/flight/list_selection.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/notebook_structural_edit.dart';

import 'canvas_selection_history_test.dart' show CountingList, pen;

class BatchOnlyList<T> extends CountingList<T> {
  BatchOnlyList(super.values);
  @override
  T removeAt(int index) => throw StateError('Repeated removeAt is forbidden');
}

void main() {
  test('large selection deletes in one compaction with ordered results', () {
    final list = BatchOnlyList(List.generate(50000, (i) => i));
    final selected = {for (var i = 0; i < 50000; i += 2) i};
    final removed = removeListSelection(list, selected);
    expect(removed.length, 25000);
    expect(list.reads, lessThanOrEqualTo(75000));
    expect(list.writes, lessThanOrEqualTo(25000));
    expect(removed.map((v) => v.$1), selected);
    expect(list, [for (var i = 1; i < 50000; i += 2) i]);
  });

  test('controller delete handles all four collections by batch', () {
    final strokes = BatchOnlyList([pen(0), pen(50), pen(100)]);
    final images = BatchOnlyList([
      CanvasImage(filename: 'a', x: 0, y: 0, w: 10, h: 10),
    ]);
    final tasks = BatchOnlyList([CanvasTaskBlock(x: 0, y: 0, w: 100, h: 60)]);
    final texts = BatchOnlyList([CanvasTextBlock(x: 0, y: 0, w: 100, h: 60)]);
    final ctrl =
        LassoController()
          ..selectedIndices = {2, 0}
          ..selectedImageIndices = {0}
          ..selectedBlockIndices = {0}
          ..selectedTextBlockIndices = {0};
    final removed = ctrl.deleteSelected(strokes, images, tasks, texts);
    expect(removed.removed.map((v) => v.$1), [0, 2]);
    expect(strokes.single.points.firstX, 50);
    expect(images, isEmpty);
    expect(tasks, isEmpty);
    expect(texts, isEmpty);
  });

  test(
    'mixed page deletion history retains unselected objects and original positions',
    () {
      final untouched = CanvasImage(
        filename: 'outside-page',
        x: 0,
        y: 1900,
        w: 10,
        h: 10,
      );
      final pages = [
        DrawingData(strokes: [pen(0), pen(50), pen(100)], images: [untouched]),
        DrawingData(
          strokes: [pen(150)],
          textBlocks: [CanvasTextBlock(x: 10, y: 20, w: 100, h: 60)],
        ),
      ];
      final before = {
        0: CanvasSelectionSnapshot.capture(pages[0], strokes: {0, 2}),
        1: CanvasSelectionSnapshot.capture(pages[1], strokes: {0}, texts: {0}),
      };
      final edit = NotebookStructuralEdit(
        pages,
        (p) => p * 1000,
        (y) => y ~/ 1000,
      );
      edit.delete(before);
      expect(edit.touched, {0, 1});
      expect(pages[0].strokes.single.points.firstX, 50);
      expect(pages[1].strokes, isEmpty);
      expect(pages[1].textBlocks, isEmpty);
      expect(identical(pages[0].images.single, untouched), isTrue);
      final history = [
        for (var p = 0; p < pages.length; p++)
          CanvasSelectionChange(
            before[p]!,
            CanvasSelectionSnapshot.capture(pages[p]),
          ),
      ];
      for (var i = 0; i < 3; i++) {
        for (var p = 0; p < pages.length; p++) {
          history[p].apply(pages[p], undo: true);
        }
        expect(pages[0].strokes.map((s) => s.points.firstX), [0, 50, 100]);
        expect(pages[1].strokes.single.points.firstX, 150);
        expect(pages[1].textBlocks, hasLength(1));
        for (var p = 0; p < pages.length; p++) {
          history[p].apply(pages[p], undo: false);
        }
        expect(pages[0].strokes.single.points.firstX, 50);
        expect(pages[1].strokes, isEmpty);
      }
    },
  );

  test('cut keeps linked tasks through delete, undo, redo and paste', () {
    final task = CanvasTaskBlock(x: 0, y: 0, w: 100, h: 60);
    final page = DrawingData(strokes: [pen(0)], taskBlocks: [task]);
    final before = CanvasSelectionSnapshot.capture(page, strokes: {0});
    final compact = DrawingData(
      strokes: [page.strokes.single],
      taskBlocks: [task.clone()],
    );
    final ctrl =
        LassoController()
          ..selectedIndices = {0}
          ..selectedBlockIndices = {0};
    ctrl.cutSelected(
      compact.strokes,
      compact.images,
      compact.taskBlocks,
      compact.textBlocks,
    );
    expect(compact.taskBlocks, hasLength(1));
    final edit = NotebookStructuralEdit([page], (_) => 0, (_) => 0);
    edit.delete({0: before});
    final history = CanvasSelectionChange(
      before,
      CanvasSelectionSnapshot.capture(page),
    );
    expect(page.strokes, isEmpty);
    expect(identical(page.taskBlocks.single, task), isTrue);
    history.apply(page, undo: true);
    expect(page.strokes, hasLength(1));
    history.apply(page, undo: false);
    expect(identical(page.taskBlocks.single, task), isTrue);
    final pasted = DrawingData();
    ctrl.pasteAt(
      Offset.zero,
      pasted.strokes,
      pasted.images,
      0,
      pasted.textBlocks,
    );
    edit.append(pasted);
    expect(page.strokes, hasLength(1));
    expect(identical(page.taskBlocks.single, task), isTrue);
  });

  test(
    'append routes only new ink and objects and selects their final indices',
    () {
      final existing = pen(300)..dbId = 40;
      final pages = [
        DrawingData(strokes: [existing]),
        DrawingData(strokes: [pen(400)]),
      ];
      final before = [
        for (final page in pages) CanvasSelectionSnapshot.capture(page),
      ];
      final world = DrawingData(
        strokes: [pen(10), pen(20)..points.translate(0, 1200)],
        images: [CanvasImage(filename: 'image', x: 1, y: 1300, w: 10, h: 10)],
        textBlocks: [CanvasTextBlock(x: 5, y: 200, w: 100, h: 60)],
      );
      final edit = NotebookStructuralEdit(
        pages,
        (p) => p * 1000,
        (y) => y ~/ 1000,
      );
      edit.append(world);
      expect(edit.strokes, {1, 3});
      expect(edit.images, {0});
      expect(edit.texts, {0});
      expect(pages[1].strokes.last.points.y(0), 200);
      expect(pages[1].images.single.y, 300);
      expect(identical(pages[0].strokes.first, existing), isTrue);
      expect(pages[0].strokes.first.dbId, 40);
      expect(pages[0].strokes.last.dbId, isNull);
      final history = [
        CanvasSelectionChange(
          before[0],
          CanvasSelectionSnapshot.capture(pages[0], strokes: {1}, texts: {0}),
        ),
        CanvasSelectionChange(
          before[1],
          CanvasSelectionSnapshot.capture(pages[1], strokes: {1}, images: {0}),
        ),
      ];
      for (var p = 0; p < pages.length; p++) {
        history[p].apply(pages[p], undo: true);
      }
      expect(pages[0].strokes.length, 1);
      expect(pages[1].images, isEmpty);
      for (var p = 0; p < pages.length; p++) {
        history[p].apply(pages[p], undo: false);
      }
      expect(pages[1].images.single.y, 300);
    },
  );

  test('paste into an unloaded page makes no partial changes', () {
    final page = DrawingData(strokes: [pen(0)]);
    final edit = NotebookStructuralEdit(
      [page, null],
      (p) => p * 1000,
      (y) => y ~/ 1000,
    );
    final world = DrawingData(
      strokes: [pen(10), pen(20)..points.translate(0, 1200)],
    );
    expect(() => edit.append(world), throwsA(isA<NotebookPageNotLoaded>()));
    expect(page.strokes, hasLength(1));
    expect(edit.touched, isEmpty);
  });
}
