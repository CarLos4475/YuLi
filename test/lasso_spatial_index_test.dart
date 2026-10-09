import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/lasso_controller.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/notebook_stroke_selection.dart';
import 'package:yuli/presentation/screens/flight/stroke_tiles.dart';

DrawingStroke pen(double x, double y, {double dx = 40, double width = 3}) =>
    DrawingStroke(
      colorValue: 0xff000000,
      strokeWidth: width,
      points: StrokePoints.fromNested([
        [x, y],
        [x + dx, y + 10],
      ]),
    );

class CountingStrokes extends ListBase<DrawingStroke> {
  CountingStrokes(this.strokes);
  final List<DrawingStroke> strokes;
  int reads = 0;
  @override
  int get length => strokes.length;
  @override
  set length(int value) => strokes.length = value;
  @override
  DrawingStroke operator [](int index) {
    reads++;
    return strokes[index];
  }

  @override
  void operator []=(int index, DrawingStroke value) => strokes[index] = value;
}

void trace(
  LassoController controller,
  List<Offset> path,
  List<DrawingStroke> strokes,
) {
  controller.startTracing(path.first);
  for (final point in path.skip(1)) {
    controller.addTracePoint(point);
  }
  controller.finishTracing(strokes);
}

void main() {
  test(
    'indexed taps and polygons match exhaustive selection at every zoom',
    () {
      final random = Random(402);
      final strokes = [
        pen(-512, -512),
        pen(512, 512),
        pen(512, 512),
        pen(-900, 50, dx: 1900),
        pen(500, 490, width: 80),
        for (var i = 0; i < 250; i++)
          pen(
            random.nextDouble() * 4000 - 1000,
            random.nextDouble() * 4000 - 1000,
            dx: random.nextDouble() * 600,
            width: random.nextDouble() * 80,
          ),
      ];
      final index = StrokeTileIndex(preserveOrder: true)..rebuild(strokes);
      addTearDown(index.dispose);
      final indexed =
          LassoController()
            ..strokeCandidates =
                (bounds) => index.strokeIndicesInRect(bounds, strokes);
      final exhaustive = LassoController();
      for (final scale in [0.1, 0.5, 1.0, 4.0]) {
        indexed.hitScale = exhaustive.hitScale = scale;
        for (final point in [
          const Offset(512, 512),
          const Offset(-512, -512),
          Offset.zero,
          for (var i = 0; i < 80; i++)
            Offset(
              random.nextDouble() * 4000 - 1000,
              random.nextDouble() * 4000 - 1000,
            ),
        ]) {
          indexed.deselect();
          exhaustive.deselect();
          expect(
            indexed.tapSelect(point, strokes),
            exhaustive.tapSelect(point, strokes),
          );
          expect(indexed.selectedIndices, exhaustive.selectedIndices);
          final path = [
            point,
            point + const Offset(170, 0),
            point + const Offset(80, 90),
            point + const Offset(0, 180),
          ];
          trace(indexed, path, strokes);
          trace(exhaustive, path, strokes);
          expect(
            indexed.selectedIndices.toList(),
            exhaustive.selectedIndices.toList(),
          );
          expect(indexed.boundingBox, exhaustive.boundingBox);
        }
      }
    },
  );

  test('positions survive replacement, split, delete, undo and append', () {
    final a = pen(100, 100), b = pen(520, 100), c = pen(1200, 100);
    var strokes = [a, b, c];
    final index = StrokeTileIndex(preserveOrder: true)..rebuild(strokes);
    addTearDown(index.dispose);
    final moved = b.clone()..points.translate(1100, 0);
    index.inheritOrder(b, moved);
    strokes[1] = moved;
    index.removeStrokes([b]);
    index.appendAll([moved]);
    expect(
      index.strokeIndicesInRect(
        const Rect.fromLTWH(1500, 0, 300, 200),
        strokes,
      ),
      [1],
    );
    expect(
      index.strokeIndicesInRect(const Rect.fromLTWH(500, 0, 150, 200), strokes),
      isEmpty,
    );
    final pieces = [pen(100, 100, dx: 5), pen(125, 100, dx: 5)];
    for (final piece in pieces) {
      index.inheritOrder(a, piece);
    }
    strokes = [...pieces, moved, c];
    index.removeStrokes([a]);
    index.appendAll(pieces);
    index.syncListPositions(strokes);
    strokes.removeAt(2);
    index.removeStrokes([moved]);
    index.syncListPositions(strokes);
    expect(
      index.strokeIndicesInRect(
        const Rect.fromLTWH(-10, -10, 3000, 300),
        strokes,
      ),
      [0, 1, 2],
    );
    strokes = [a, b, c];
    index.rebuild(strokes);
    final added = pen(-520, 0);
    strokes.add(added);
    index.append(added);
    expect(
      index.strokeIndicesInRect(
        const Rect.fromLTWH(-600, -50, 200, 100),
        strokes,
      ),
      [3],
    );
    index.clear();
    strokes = [pen(0, 0)];
    index.append(strokes.single);
    expect(
      index.strokeIndicesInRect(
        const Rect.fromLTWH(-10, -10, 100, 100),
        strokes,
      ),
      [0],
    );
  });

  test('small selection visits only candidates in a 50000 stroke board', () {
    final strokes = CountingStrokes([
      pen(10, 10),
      for (var i = 1; i < 50000; i++)
        pen(10000 + (i % 100) * 20, (i ~/ 100) * 20),
    ]);
    final index = StrokeTileIndex(preserveOrder: true)..rebuild(strokes);
    addTearDown(index.dispose);
    final controller =
        LassoController()
          ..strokeCandidates =
              (bounds) => index.strokeIndicesInRect(bounds, strokes);
    strokes.reads = 0;
    expect(controller.tapSelect(const Offset(10, 10), strokes), isTrue);
    expect(strokes.reads, lessThan(10));
    strokes.reads = 0;
    trace(controller, [
      Offset.zero,
      const Offset(100, 0),
      const Offset(100, 100),
      const Offset(0, 100),
    ], strokes);
    expect(controller.selectedIndices, {0});
    expect(strokes.reads, lessThan(10));
  });

  test(
    'regional invalidation and defensive rebuild restore list positions',
    () {
      final a = pen(0, 0), b = pen(600, 0), c = pen(1200, 0);
      final index = StrokeTileIndex(preserveOrder: true)..rebuild([a, b, c]);
      addTearDown(index.dispose);
      final strokes = [a, c];
      index.invalidateRegion(const Rect.fromLTWH(500, -20, 200, 100), strokes);
      expect(
        index.strokeIndicesInRect(
          const Rect.fromLTWH(1100, -20, 200, 100),
          strokes,
        ),
        [1],
      );
      final reordered = [c, a];
      expect(
        index.strokeIndicesInRect(
          const Rect.fromLTWH(1100, -20, 200, 100),
          reordered,
        ),
        [0],
      );
    },
  );

  test(
    'cross-page selection remaps directly after source removal and destination append',
    () {
      final a = pen(0, 0), b = pen(100, 0), c = pen(200, 0);
      final source = [a, b], destination = [c];
      final indices = [
        StrokeTileIndex()..rebuild(source),
        StrokeTileIndex()..rebuild(destination),
      ];
      addTearDown(() {
        for (final index in indices) {
          index.dispose();
        }
      });
      final moved = a.clone()..points.translate(500, 0);
      source.removeAt(0);
      destination.add(moved);
      indices[0].removeStrokes([a]);
      indices[1].append(moved);
      indices[0].syncListPositions(source);
      indices[1].syncListPositions(destination);
      final layout = NotebookStrokeLayout([source.length, destination.length]);
      final local = indices[1].listPosition(moved)!;
      expect(local, 1);
      expect(layout.globalIndex(1, local), 2);
      expect(NotebookStrokeView([source, destination])[2], same(moved));
      final replacement = moved.clone()..points.translate(20, 0);
      indices[1].inheritOrder(moved, replacement);
      destination[local] = replacement;
      indices[1].removeStrokes([moved]);
      indices[1].append(replacement);
      expect(indices[1].listPosition(replacement), local);
    },
  );

  test('page layout handles empty pages and remaps cross-page moves', () {
    final a = pen(10, 10), b = pen(20, 20), c = pen(30, 30);
    final pages = <List<DrawingStroke>>[
      [],
      [a, b],
      [],
      [c],
      [],
    ];
    var view = NotebookStrokeView(pages);
    expect(view.toList(), [a, b, c]);
    expect(view.layout.locate(0), (1, 0));
    expect(view.layout.locate(2), (3, 0));
    expect(view.layout.locate(3), isNull);
    pages[1].removeAt(0);
    pages[3].add(a);
    view = NotebookStrokeView(pages);
    expect(view.toList(), [b, c, a]);
    expect(view.layout.globalIndex(3, 1), 2);
    expect(view.layout.locate(2), (3, 1));
  });

  test(
    'eraser defers position repair until selection without rebuilding tiles',
    () {
      final strokes = CountingStrokes([
        for (var i = 0; i < 1000; i++) pen(i * 100.0, 0),
      ]);
      final index = StrokeTileIndex()..rebuild(strokes);
      addTearDown(index.dispose);
      final removed = strokes.strokes.removeAt(0);
      index.removeStrokes([removed]);
      index.invalidateListPositions();
      final added = pen(-100, 0);
      strokes.strokes.add(added);
      index.append(added);
      final revision = index.revision;
      expect(
        index.strokeIndicesInRect(
          const Rect.fromLTWH(-110, -10, 60, 40),
          strokes,
        ),
        [999],
      );
      expect(index.revision, revision);
      strokes.reads = 0;
      expect(
        index.strokeIndicesInRect(
          const Rect.fromLTWH(90, -10, 60, 40),
          strokes,
        ),
        [0],
      );
      expect(strokes.reads, lessThan(5));
    },
  );

  test('notebook query includes ink protruding across a page boundary', () {
    const stride = 1200.0;
    final local = [
      [pen(10, 1210)],
      <DrawingStroke>[],
      [pen(10, 10)],
    ];
    final indices = [
      for (final page in local) StrokeTileIndex()..rebuild(page),
    ];
    addTearDown(() {
      for (final index in indices) {
        index.dispose();
      }
    });
    final world = NotebookStrokeView([
      for (var i = 0; i < local.length; i++)
        [
          for (final stroke in local[i])
            stroke.clone()..points.translate(0, i * stride),
        ],
    ]);
    final controller =
        LassoController()
          ..strokeCandidates = (bounds) sync* {
            for (var page = 0; page < local.length; page++) {
              for (final i in indices[page].strokeIndicesInRect(
                bounds.shift(Offset(0, -page * stride)),
                local[page],
              )) {
                yield world.layout.globalIndex(page, i);
              }
            }
          };
    expect(controller.tapSelect(const Offset(10, 1210), world), isTrue);
    expect(controller.selectedIndices, {0});
    expect(controller.tapSelect(const Offset(10, 2410), world), isTrue);
    expect(controller.selectedIndices, {1});
  });
}
