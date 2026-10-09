import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_drawing_stroke_repository.dart';
import 'package:yuli/domain/models/drawing_stroke_record.dart';
import 'package:yuli/presentation/screens/flight/drawing_stroke_persistence.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_delta_persistence.dart';

class RecordingRepository extends LocalDrawingStrokeRepository {
  RecordingRepository(super.db);
  int writes = 0;
  int orderWrites = 0;
  Completer<void>? gate;
  Completer<void>? entered;

  @override
  Future<List<int>> applyBlockDelta(
    int blockId, {
    required List<DrawingStrokeWrite> inserts,
    required Map<int, DrawingStrokeWrite> updates,
    required Map<int, int> positions,
    required List<int> deletes,
  }) async {
    writes = inserts.length + updates.length + deletes.length;
    orderWrites = positions.length;
    if (entered != null && !entered!.isCompleted) entered!.complete();
    if (gate != null) await gate!.future;
    return super.applyBlockDelta(
      blockId,
      inserts: inserts,
      updates: updates,
      positions: positions,
      deletes: deletes,
    );
  }

  @override
  Future<List<int>> replaceBlock(
    int blockId,
    List<DrawingStrokeWrite> strokes,
  ) => throw StateError('Notebook must not replace the whole page');
}

DrawingStroke pen(double x) => DrawingStroke(
  colorValue: 0xff000000,
  strokeWidth: 3,
  points: StrokePoints.fromNested([
    [x, 0],
    [x + 10, 10],
  ]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RecordingRepository repository;
  late StrokeDeltaPersistence persistence;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RecordingRepository(db);
    persistence = StrokeDeltaPersistence();
  });
  tearDown(() => db.close());

  Future<List<DrawingStroke>> load(int block) async =>
      (await repository.getByBlock(block)).map(strokeFromRecord).toList();

  test(
    'move, undo and redo update only one row and keep IDs and order',
    () async {
      final original = [for (var i = 0; i < 1000; i++) pen(i.toDouble())];
      await persistence.persist(repository, 1, original);
      final ids = original.map((s) => s.dbId).toList();
      final moved = List<DrawingStroke>.of(original);
      moved[500] = original[500].clone()..points.translate(100, 20);
      for (final state in [moved, original, moved]) {
        final result = await persistence.persist(repository, 1, state);
        expect(result, (inserted: 0, updated: 1, deleted: 0));
        expect(repository.writes, 1);
        expect(repository.orderWrites, 0);
        final restored = await load(1);
        expect(restored.map((s) => s.dbId), ids);
        expect(restored[500].points.toNested(), state[500].points.toNested());
      }
    },
  );

  test(
    'delete and resurrect a middle stroke preserves compositing order',
    () async {
      final original = [pen(0), pen(10), pen(20)];
      await persistence.persist(repository, 1, original);
      final survivorIds = [original.first.dbId, original.last.dbId];
      for (var attempt = 0; attempt < 3; attempt++) {
        await persistence.persist(repository, 1, [
          original.first,
          original.last,
        ]);
        expect((await load(1)).map((s) => s.dbId), survivorIds);
        await persistence.persist(repository, 1, original);
        expect((await load(1)).map((s) => s.points.firstX), [0, 10, 20]);
        expect((await load(1)).map((s) => s.dbId), original.map((s) => s.dbId));
      }
    },
  );

  test(
    'cross-page move and undo remain isolated in either save order',
    () async {
      for (final destinationFirst in [true, false]) {
        final sourceId = destinationFirst ? 1 : 3;
        final targetId = sourceId + 1;
        final sourceState = StrokeDeltaPersistence();
        final targetState = StrokeDeltaPersistence();
        final original = [pen(0), pen(10), pen(20)];
        final target = [pen(90)];
        await sourceState.persist(repository, sourceId, original);
        await targetState.persist(repository, targetId, target);
        final moved = original[1].clone()..points.translate(0, 1200);
        final sourceAfter = [original.first, original.last];
        final targetAfter = [...target, moved];
        Future<void> save(List<DrawingStroke> a, List<DrawingStroke> b) async {
          if (destinationFirst) {
            await targetState.persist(repository, targetId, b);
            await sourceState.persist(repository, sourceId, a);
          } else {
            await sourceState.persist(repository, sourceId, a);
            await targetState.persist(repository, targetId, b);
          }
        }

        await save(sourceAfter, targetAfter);
        expect((await load(sourceId)).map((s) => s.points.firstX), [0, 20]);
        expect((await load(targetId)).map((s) => s.points.firstX), [90, 10]);
        await save(original, target);
        expect((await load(sourceId)).map((s) => s.points.firstX), [0, 10, 20]);
        expect((await load(targetId)).map((s) => s.points.firstX), [90]);
        await save(sourceAfter, targetAfter);
        expect((await load(sourceId)).map((s) => s.points.firstX), [0, 20]);
        expect((await load(targetId)).map((s) => s.points.firstX), [90, 10]);
      }
    },
  );

  test(
    'failed transaction rolls back deletes, geometry and order; retry is exact',
    () async {
      final before = [pen(0), pen(10), pen(20)];
      await persistence.persist(repository, 1, before);
      final ids = before.map((s) => s.dbId).toList();
      final after = [before[2].clone()..points.translate(40, 0), pen(99)];
      await db.customStatement('''CREATE TRIGGER reject_test_insert
      BEFORE INSERT ON drawing_strokes BEGIN
        SELECT RAISE(ABORT, 'Test transaction failure');
      END''');
      await expectLater(
        persistence.persist(repository, 1, after),
        throwsA(anything),
      );
      expect(after[1].dbId, isNull);
      expect((await load(1)).map((s) => s.dbId), ids);
      expect((await load(1)).map((s) => s.points.firstX), [0, 10, 20]);
      await db.customStatement('DROP TRIGGER reject_test_insert');
      await persistence.persist(repository, 1, after);
      expect((await load(1)).map((s) => s.points.firstX), [60, 99]);
      expect((await load(1)).first.dbId, ids[2]);
      expect(await persistence.persist(repository, 1, after), (
        inserted: 0,
        updated: 0,
        deleted: 0,
      ));
    },
  );

  test(
    'edits and undo while a save awaits are persisted on the next flush',
    () async {
      final original = [pen(0), pen(10)];
      await persistence.persist(repository, 1, original);
      final added = pen(20);
      final intermediate = [
        original.first,
        original.last.clone()..points.translate(30, 0),
        added,
      ];
      repository.gate = Completer<void>();
      repository.entered = Completer<void>();
      final saving = persistence.persist(repository, 1, intermediate);
      await repository.entered!.future;
      final next = [
        original.first,
        original.last,
        added.clone()..points.translate(50, 0),
      ];
      repository.gate!.complete();
      await saving;
      repository.gate = null;
      await persistence.persist(repository, 1, next);
      expect((await load(1)).map((s) => s.points.firstX), [0, 10, 70]);
      expect(await persistence.persist(repository, 1, next), (
        inserted: 0,
        updated: 0,
        deleted: 0,
      ));
    },
  );

  test('load, edit and clear use the persisted baseline', () async {
    await repository.insertMany(1, [
      strokeWrite(4, pen(0)),
      strokeWrite(8, pen(10)),
    ]);
    final rows = await repository.getByBlock(1);
    final strokes = rows.map(strokeFromRecord).toList();
    persistence.seed(rows, strokes);
    await persistence.persist(repository, 1, strokes);
    expect(repository.writes, 0);
    expect((await repository.getByBlock(1)).map((s) => s.position), [0, 1]);
    await persistence.persist(repository, 1, []);
    expect(await load(1), isEmpty);
    await persistence.persist(repository, 1, strokes);
    expect((await load(1)).map((s) => s.points.firstX), [0, 10]);
  });

  test(
    'overlapping saves are serialized and capture list membership',
    () async {
      final first = [pen(0), pen(10)];
      repository.gate = Completer<void>();
      repository.entered = Completer<void>();
      final saving = persistence.persist(repository, 1, first);
      await repository.entered!.future;
      final second = [first.last];
      final queued = persistence.persist(repository, 1, second);
      second.clear();
      repository.gate!.complete();
      await Future.wait([saving, queued]);
      expect((await load(1)).map((s) => s.points.firstX), [10]);
      expect((await load(1)).single.dbId, first.last.dbId);
    },
  );

  test(
    'block delta cannot modify or delete rows owned by another page',
    () async {
      final foreign = await repository.insert(2, strokeWrite(0, pen(10)));
      await repository.applyBlockDelta(
        1,
        inserts: [],
        updates: {foreign: strokeWrite(0, pen(90))},
        positions: {foreign: 15},
        deletes: [foreign],
      );
      final row = (await repository.getByBlock(2)).single;
      expect(row.position, 0);
      expect(strokeFromRecord(row).points.firstX, 10);
    },
  );
}
