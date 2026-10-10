import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/canvas_selection_history.dart';
import 'package:yuli/presentation/screens/flight/lasso_controller.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/notebook_selection_sync.dart';
import 'package:yuli/presentation/screens/flight/notebook_stroke_selection.dart';
import 'package:yuli/presentation/screens/flight/stroke_tiles.dart';

DrawingStroke pen(double x) => DrawingStroke(
  colorValue: 0xff000000,
  strokeWidth: 3,
  points: StrokePoints.fromNested([
    [x, 0],
    [x + 30, 40],
  ]),
);

class CountingList<T> extends ListBase<T> {
  CountingList(this.values);
  final List<T> values;
  int reads = 0;
  int writes = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  void add(T value) => values.add(value);
  @override
  T operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, T value) {
    writes++;
    values[index] = value;
  }
}

void main() {
  test('capture and transform undo touch only selection in 50000 strokes', () {
    final list = CountingList([for (var i = 0; i < 50000; i++) pen(i * 10)]);
    final selection = {10, 25000, 49999};
    final before = IndexedSelection.capture(list, selection, (s) => s);
    expect(list.reads, 3);
    for (final i in selection) {
      list[i] = list[i].clone()..points.translate(50, 60);
    }
    final after = IndexedSelection.capture(list, selection, (s) => s);
    final change = SelectionChange(before, after);
    list.reads = list.writes = 0;
    for (var i = 0; i < 5; i++) {
      change.apply(list, undo: true, copy: (s) => s);
      change.apply(list, undo: false, copy: (s) => s);
    }
    expect(list.reads, 0);
    expect(list.writes, 30);
    expect(before.values[10]!.points.firstX, 100);
    expect(list[10].points.firstX, 150);
  });

  test('random replacements, deletions and insertions restore exact order', () {
    final random = Random(9021);
    var next = 1000;
    for (var run = 0; run < 500; run++) {
      final original = List.generate(random.nextInt(100), (i) => i);
      final removed = {
        for (var i = 0; i < original.length; i++)
          if (random.nextBool()) i: original[i],
      };
      final desired = [
        for (var i = 0; i < original.length; i++)
          if (!removed.containsKey(i)) original[i],
      ];
      for (var i = random.nextInt(20); i > 0; i--) {
        desired.insert(random.nextInt(desired.length + 1), next++);
      }
      final inserted = {
        for (var i = 0; i < desired.length; i++)
          if (desired[i] >= 1000) i: desired[i],
      };
      final change = SelectionChange(
        IndexedSelection(original.length, removed),
        IndexedSelection(desired.length, inserted),
      );
      final target = List.of(original);
      for (var i = 0; i < 3; i++) {
        change.apply(target, undo: false, copy: (v) => v);
        expect(target, desired);
        change.apply(target, undo: true, copy: (v) => v);
        expect(target, original);
      }
    }
  });

  test('tail add history avoids traversing earlier strokes', () {
    final list = CountingList(List.generate(50000, (i) => i));
    final change = SelectionChange(
      IndexedSelection<int>(50000, {}),
      IndexedSelection(50001, {50000: 50000}),
    );
    change.apply(list, undo: false, copy: (v) => v);
    expect(list.reads, 0);
    change.apply(list, undo: true, copy: (v) => v);
    expect(list.reads, 0);
    expect(list.length, 50000);
  });

  test(
    'mixed selection duplicate and delete history preserves untouched objects',
    () {
      final untouched = pen(0);
      final image = CanvasImage(filename: 'a.png', x: 5, y: 5, w: 40, h: 40);
      final data = DrawingData(strokes: [untouched, pen(80)], images: [image]);
      final ctrl =
          LassoController()
            ..selectedIndices = {1}
            ..selectedImageIndices = {0};
      ctrl.refreshBoundingBox(data.strokes, data.images);
      final before = CanvasSelectionSnapshot.capture(
        data,
        strokes: {1},
        images: {0},
      );
      ctrl.duplicateSelected(data.strokes, data.images);
      final after = before.captureAfter(
        data,
        strokes: ctrl.selectedIndices,
        images: ctrl.selectedImageIndices,
        tasks: {},
        texts: {},
      );
      final duplicate = CanvasSelectionChange(before, after);
      duplicate.apply(data, undo: true);
      expect(data.strokes.length, 2);
      expect(data.images.length, 1);
      expect(identical(data.strokes.first, untouched), isTrue);
      duplicate.apply(data, undo: false);
      expect(data.strokes.length, 3);
      expect(data.images.length, 2);
      final deleteBefore = CanvasSelectionSnapshot.capture(
        data,
        strokes: {2},
        images: {1},
      );
      ctrl.selectedIndices = {2};
      ctrl.selectedImageIndices = {1};
      ctrl.deleteSelected(data.strokes, data.images);
      final deleted = CanvasSelectionChange(
        deleteBefore,
        deleteBefore.captureAfter(
          data,
          strokes: {},
          images: {},
          tasks: {},
          texts: {},
        ),
      );
      deleted.apply(data, undo: true);
      data.images.last.x = 999;
      deleted.apply(data, undo: false);
      deleted.apply(data, undo: true);
      expect(data.images.last.x, isNot(999));
    },
  );

  test(
    'sparse page view clones only queried values and leaves sources intact',
    () {
      final source = [for (var i = 0; i < 50000; i++) pen(i.toDouble())];
      var copies = 0;
      final view = NotebookSelectionView([<DrawingStroke>[], source], (
        page,
        s,
      ) {
        copies++;
        return s.clone()..points.translate(0, page * 1000);
      });
      final ctrl =
          LassoController()
            ..selectedIndices = {10, 49999}
            ..phase = LassoPhase.selected;
      ctrl.refreshBoundingBox(view);
      ctrl.startMove(Offset.zero, view);
      ctrl.updateMove(const Offset(30, 40));
      ctrl.finishMove(view);
      expect(copies, 2);
      expect(source[10].points.firstX, 10);
      expect(view[10].points.firstX, 40);
      expect(view[10].points.y(0), 1040);
    },
  );

  test(
    'cross page object edits preserve unselected ownership and remap selection',
    () {
      CanvasImage box(String id, double y) =>
          CanvasImage(filename: id, x: 0, y: y, w: 20, h: 20);
      final protruding = box('unselected', 1300);
      final pages = [
        [box('A', 20), protruding, box('B', 40)],
        [box('C', 50)],
        <CanvasImage>[],
      ];
      final before = [for (final page in pages) List.of(page)];
      final view = NotebookSelectionView(
        pages,
        (p, v) => v.clone()..y += p * 1000,
      );
      view[0].y = 1400;
      view[2].y = 60;
      view[3].y = 200;
      final touched = <int>{};
      final selection = syncNotebookSelectedObjects(
        view,
        {0, 2, 3},
        pages,
        (p) => p * 1000,
        (y) => y ~/ 1000,
        (p) => p < 3,
        (v) => v.clone(),
        touched,
      );
      expect(pages.map((p) => p.map((v) => v.filename).toList()).toList(), [
        ['unselected', 'B', 'C'],
        ['A'],
        [],
      ]);
      expect(identical(pages[0][0], protruding), isTrue);
      expect(selection, {1, 2, 3});
      expect(touched, {0, 1});
      final first = SelectionChange(
        IndexedSelection.capture(before[0], [0, 2], (v) => v.clone()),
        IndexedSelection.capture(pages[0], [1, 2], (v) => v.clone()),
      );
      final second = SelectionChange(
        IndexedSelection.capture(before[1], [0], (v) => v.clone()),
        IndexedSelection.capture(pages[1], [0], (v) => v.clone()),
      );
      for (var i = 0; i < 3; i++) {
        first.apply(pages[0], undo: true, copy: (v) => v.clone());
        second.apply(pages[1], undo: true, copy: (v) => v.clone());
        expect(pages[0].map((v) => v.filename), ['A', 'unselected', 'B']);
        expect(pages[1].single.filename, 'C');
        first.apply(pages[0], undo: false, copy: (v) => v.clone());
        second.apply(pages[1], undo: false, copy: (v) => v.clone());
      }
    },
  );

  test(
    'selection undo keeps spatial identity and stacking at tile boundaries',
    () {
      final data = DrawingData(strokes: [pen(512), pen(512), pen(-512)]);
      final tiles = StrokeTileIndex(preserveOrder: true)..rebuild(data.strokes);
      addTearDown(tiles.dispose);
      final before = CanvasSelectionSnapshot.capture(data, strokes: {1});
      final old = data.strokes[1];
      data.strokes[1] = old.clone()..points.translate(1024, 1024);
      tiles.inheritOrder(old, data.strokes[1]);
      tiles.removeStrokes([old]);
      tiles.append(data.strokes[1]);
      final after = CanvasSelectionSnapshot.capture(data, strokes: {1});
      final delta = CanvasSelectionChange(before, after);
      for (final undo in [true, false, true, false]) {
        final previous = data.strokes[1];
        delta.apply(data, undo: undo);
        tiles.inheritOrder(previous, data.strokes[1]);
        tiles.removeStrokes([previous]);
        tiles.append(data.strokes[1]);
        expect(
          tiles.strokeIndicesInRect(
            const Rect.fromLTWH(510, -2, 40, 45),
            data.strokes,
          ),
          undo ? [0, 1] : [0],
        );
        expect(tiles.listPosition(data.strokes[1]), 1);
      }
    },
  );
}
