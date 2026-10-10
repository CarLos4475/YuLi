import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_bounds.dart';
import 'package:yuli/presentation/screens/flight/stroke_erase_session.dart';
import 'package:yuli/presentation/screens/flight/tracked_stroke_index.dart';
import 'package:yuli/presentation/screens/flight/notebook_stroke_selection.dart';

import 'lasso_spatial_index_test.dart' show pen, CountingStrokes;
import 'stroke_journal_test.dart' show CountingTrackedList;

void main() {
  test(
    'queries and sparse edits among 50000 strokes never rescan the list',
    () {
      final strokes = CountingTrackedList([
        for (var i = 0; i < 50000; i++) pen(i * 600.0, 0),
      ]);
      final index = TrackedStrokeIndex(strokes);
      addTearDown(index.dispose);
      strokes[20] = strokes[20].clone()..points.translate(0, 900);
      strokes.takeChanges();
      strokes.reads = 0;
      expect(index.indicesInRect(const Rect.fromLTWH(12000, 890, 100, 100)), [
        20,
      ]);
      expect(
        index.indicesInRect(const Rect.fromLTWH(12000, -10, 100, 100)),
        isEmpty,
      );
      expect(strokes.reads, 0);
      strokes.removeAt(0);
      strokes.reads = 0;
      expect(index.indicesInRect(const Rect.fromLTWH(12000, 890, 100, 100)), [
        19,
      ]);
      expect(strokes.reads, 0);
    },
  );

  test(
    'index matches exhaustive bounds through replacement, undo and hydration',
    () {
      final random = Random(34);
      final strokes = CountingTrackedList([
        pen(-512, -512, dx: 2048, width: 80),
        pen(512, 512),
        for (var i = 0; i < 100; i++)
          pen(random.nextDouble() * 3000, random.nextDouble() * 3000),
      ]);
      final index = TrackedStrokeIndex(strokes);
      addTearDown(index.dispose);
      void compare() {
        for (var i = 0; i < 20; i++) {
          final rect = Rect.fromLTWH(
            random.nextDouble() * 3500 - 500,
            random.nextDouble() * 3500 - 500,
            600,
            600,
          );
          expect(index.indicesInRect(rect), [
            for (var j = 0; j < strokes.length; j++)
              if (strokeBounds(strokes[j]).overlaps(rect)) j,
          ]);
        }
      }

      for (var step = 0; step < 40; step++) {
        final before = strokes.toList();
        final i = random.nextInt(strokes.length);
        strokes[i] = strokes[i].clone();
        strokes[i].points.translate(800, -600);
        compare();
        final erase = StrokeEraseSession(strokes);
        erase.collect([i], (_) => true);
        final change = erase.commit()!;
        compare();
        change.apply(strokes, undo: true, copy: (s) => s);
        compare();
        change.apply(strokes, undo: false, copy: (s) => s);
        compare();
        strokes.replaceAll(before.reversed);
        compare();
        strokes.add(pen(4000, 4000));
      }
      strokes.replaceAll([pen(8000, 8000)]);
      expect(index.indicesInRect(const Rect.fromLTWH(7900, 7900, 300, 300)), [
        0,
      ]);
      expect(
        index.indicesInRect(const Rect.fromLTWH(-600, -600, 5000, 5000)),
        isEmpty,
      );
    },
  );

  test('eraser checks only candidates and stores only removed entries', () {
    final strokes = CountingTrackedList([
      for (var i = 0; i < 5000; i++) pen(i * 600.0, 0),
    ]);
    final index = TrackedStrokeIndex(strokes);
    addTearDown(index.dispose);
    final session = StrokeEraseSession(strokes);
    var checked = 0;
    final expected = <int>{};
    for (final i in [2, 4999, 200, 2]) {
      final point = Offset(i * 600.0, 0);
      session.collect(
        index.indicesInRect(Rect.fromCircle(center: point, radius: 7)),
        (s) {
          checked++;
          return strokeHitByEraser(s, point, 7);
        },
      );
      expected.add(i);
    }
    expect(checked, 3);
    expect(strokes, hasLength(5000));
    expect(session.indices, expected);
    final change = session.commit()!;
    expect(change.before.values.keys.toSet(), expected);
    expect(change.after.values, isEmpty);
    expect(strokes, hasLength(4997));
    change.apply(strokes, undo: true, copy: (s) => s);
    expect(strokes, hasLength(5000));
    expect(index.indicesInRect(const Rect.fromLTWH(1190, -10, 100, 100)), [2]);
    change.apply(strokes, undo: false, copy: (s) => s);
    expect(
      index.indicesInRect(const Rect.fromLTWH(1190, -10, 100, 100)),
      isEmpty,
    );
    expect(session.commit(), isNull);
  });

  test(
    'eraser preview follows identities when external edits shift the list',
    () {
      final data = DrawingData(strokes: [pen(0, 0), pen(100, 0), pen(200, 0)]);
      final session = StrokeEraseSession(data.strokes);
      session.collect([1, 2], (_) => true);
      data.strokes.removeAt(0);
      data.strokes[1] = data.strokes[1].clone()..points.translate(100, 0);
      expect(session.indices, {0});
      final change = session.commit()!;
      expect(data.strokes.single.points.firstX, 300);
      change.apply(data.strokes, undo: true, copy: (s) => s);
      expect(data.strokes.map((s) => s.points.firstX), [100, 300]);
    },
  );

  test(
    'spatial eraser agrees with exhaustive hits at tile edges and thick segments',
    () {
      final random = Random(513);
      final data = DrawingData(
        strokes: [
          pen(-512, 512, dx: 2200, width: 80),
          pen(512, -512, dx: 0, width: 60),
          for (var i = 0; i < 200; i++)
            pen(
              random.nextDouble() * 3000 - 1000,
              random.nextDouble() * 3000 - 1000,
              dx: random.nextDouble() * 700,
              width: random.nextDouble() * 100,
            ),
        ],
      );
      final index = TrackedStrokeIndex(data.strokes);
      addTearDown(index.dispose);
      for (final point in [
        const Offset(0, 540),
        const Offset(512, -535),
        for (var i = 0; i < 100; i++)
          Offset(
            random.nextDouble() * 3000 - 1000,
            random.nextDouble() * 3000 - 1000,
          ),
      ]) {
        final session = StrokeEraseSession(data.strokes);
        session.collect(
          index.indicesInRect(Rect.fromCircle(center: point, radius: 7)),
          (s) => strokeHitByEraser(s, point, 7),
        );
        expect(session.indices, {
          for (var i = 0; i < data.strokes.length; i++)
            if (strokeHitByEraser(data.strokes[i], point, 7)) i,
        });
      }
    },
  );

  test(
    'writing detection and OCR access only selected entries across pages',
    () {
      final first = CountingStrokes([
        for (var i = 0; i < 10000; i++) pen(i.toDouble(), 0),
      ]);
      final second = CountingStrokes([
        DrawingStroke(
          colorValue: 0xff000000,
          strokeWidth: 3,
          points: pen(0, 0).points,
          isShape: true,
        ),
        DrawingStroke(
          colorValue: 0xff000000,
          strokeWidth: 3,
          points: pen(0, 0).points,
          isHighlighter: true,
        ),
        pen(40, 50),
      ]);
      final pages = [first, <DrawingStroke>[], second];
      final local = NotebookStrokeView(pages);
      expect(selectionHasWriting(local, [10000, 10001]), isFalse);
      expect(selectionHasWriting(local, [10002]), isTrue);
      expect(first.reads, 0);
      expect(second.reads, 3);
      var conversions = 0;
      final world = NotebookSelectionView(pages, (page, stroke) {
        conversions++;
        return stroke.clone()..points.translate(0, page * 1000.0);
      });
      final selected = [-1, 9999, 10000, 10001, 10002, 20000];
      final text = selectedWritingPoints(world, selected);
      expect(text, hasLength(2));
      expect(text.last.first, const Offset(40, 2050));
      expect(
        selectedWritingPoints(world, selected, includeShapes: true),
        hasLength(3),
      );
      expect(conversions, 4);
      expect(first.reads, 1);
      expect(second.reads, 6);
      expect(second.strokes.last.points.firstY, 50);
    },
  );
}
