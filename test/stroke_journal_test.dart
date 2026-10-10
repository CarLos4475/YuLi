import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/domain/models/drawing_stroke_record.dart';
import 'package:yuli/domain/repositories/drawing_stroke_repository.dart';
import 'package:yuli/presentation/screens/flight/drawing_stroke_persistence.dart';
import 'package:yuli/presentation/screens/flight/list_selection.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/stroke_delta_persistence.dart';
import 'package:yuli/presentation/screens/flight/tracked_list.dart';

import 'notebook_stroke_persistence_test.dart' show RecordingRepository, pen;

class CountingTrackedList extends TrackedList<DrawingStroke> {
  CountingTrackedList(super.values) : super(keyOf: (s) => s.dbId);
  int reads = 0;
  @override
  DrawingStroke operator [](int index) {
    reads++;
    return super[index];
  }
}

class Sink implements DrawingStrokeRepository {
  int calls = 0, writes = 0, positionWrites = 0, nextId = 0;
  @override
  Future<List<int>> applyBlockDelta(
    int blockId, {
    required List<DrawingStrokeWrite> inserts,
    required Map<int, DrawingStrokeWrite> updates,
    required Map<int, int> positions,
    required List<int> deletes,
  }) async {
    calls++;
    writes = inserts.length + updates.length + deletes.length;
    positionWrites = positions.length;
    return [for (final _ in inserts) ++nextId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FailOnceStroke extends DrawingStroke {
  FailOnceStroke() : super(colorValue: 0xff000000, strokeWidth: 3);
  bool failed = false;
  @override
  Uint8List toBytes() {
    if (!failed) {
      failed = true;
      throw StateError('Serialization failed');
    }
    return super.toBytes();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'serialization failure retains the journal for retry without new edits',
    () async {
      final journal = StrokeDeltaPersistence();
      final repo = Sink();
      final data = DrawingData(strokes: [FailOnceStroke(), pen(10)]);
      await expectLater(
        journal.persist(repo, 1, data.strokes),
        throwsStateError,
      );
      expect(repo.calls, 0);
      final result = await journal.persist(repo, 1, data.strokes);
      expect(result.inserted, 2);
      expect(data.strokes.map((s) => s.dbId), [1, 2]);
    },
  );

  test(
    'callback failure after commit never reinserts successful rows',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RecordingRepository(db);
      final journal = StrokeDeltaPersistence();
      final data = DrawingData(strokes: [pen(0), pen(10)]);
      await expectLater(
        journal.persist(
          repo,
          1,
          data.strokes,
          onAssignedId: (_, _) {
            throw StateError('Observer failed');
          },
        ),
        throwsStateError,
      );
      data.strokes[1] = data.strokes[1].clone()..points.translate(5, 0);
      await journal.persist(repo, 1, data.strokes);
      final rows = await repo.getByBlock(1);
      expect(rows.map((r) => strokeFromRecord(r).points.firstX), [0, 15]);
      expect(rows.map((r) => r.id), data.strokes.map((s) => s.dbId));
    },
  );

  test(
    'a journal rejects a different block before consuming its changes',
    () async {
      final repo = Sink();
      final journal = StrokeDeltaPersistence();
      final data = DrawingData(strokes: [pen(0)]);
      await journal.persist(repo, 1, data.strokes);
      data.strokes.add(pen(10));
      expect(() => journal.persist(repo, 2, data.strokes), throwsStateError);
      final result = await journal.persist(repo, 1, data.strokes);
      expect(result.inserted, 1);
      expect(data.strokes.map((s) => s.dbId), [1, 2]);
    },
  );
  test(
    '50000 strokes save reads no list entries after three replacements',
    () async {
      final list = CountingTrackedList([
        for (var i = 0; i < 50000; i++) pen(i.toDouble()),
      ]);
      final repository = Sink();
      final journal = StrokeDeltaPersistence();
      await journal.persist(repository, 1, list);
      for (final i in [0, 25000, 49999]) {
        list[i] = list[i].clone()..points.translate(4, 8);
      }
      list.reads = 0;
      await journal.persist(repository, 1, list);
      expect(list.reads, 0);
      expect(repository.writes, 3);
      expect(repository.positionWrites, 0);
      final calls = repository.calls;
      await journal.persist(repository, 1, list);
      expect(repository.calls, calls);
      expect(list.reads, 0);
    },
  );

  test(
    'edit then undo before save cancels geometry work and keeps IDs',
    () async {
      final data = DrawingData(strokes: [pen(0), pen(10)]);
      final repository = Sink();
      final journal = StrokeDeltaPersistence();
      await journal.persist(repository, 1, data.strokes);
      final old = data.strokes[0];
      data.strokes[0] = old.clone()..points.translate(90, 0);
      data.strokes[0] = old;
      await journal.persist(repository, 1, data.strokes);
      expect(repository.writes, 0);
      expect(data.strokes[0].dbId, 1);
      data.strokes.removeAt(0);
      data.strokes.insert(0, old);
      await journal.persist(repository, 1, data.strokes);
      expect(repository.writes, 0);
      expect(repository.positionWrites, 0);
    },
  );

  test('pending insert can be edited and deleted before IDs arrive', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo =
        RecordingRepository(db)
          ..gate = Completer<void>()
          ..entered = Completer<void>();
    final journal = StrokeDeltaPersistence();
    final data = DrawingData(strokes: [pen(0), pen(10)]);
    final first = journal.persist(repo, 1, data.strokes);
    await repo.entered!.future;
    data.strokes[1] = data.strokes[1].clone()..points.translate(50, 0);
    data.strokes.removeAt(0);
    final second = journal.persist(repo, 1, data.strokes);
    repo.gate!.complete();
    await Future.wait([first, second]);
    final rows = await repo.getByBlock(1);
    expect(rows, hasLength(1));
    expect(strokeFromRecord(rows.single).points.firstX, 60);
    expect(rows.single.id, data.strokes.single.dbId);
    expect(rows.single.position, 0);
  });

  test(
    'failed batch is retried with newer edits rather than stale geometry',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RecordingRepository(db);
      final journal = StrokeDeltaPersistence();
      final data = DrawingData(strokes: [pen(0), pen(10)]);
      await journal.persist(repo, 1, data.strokes);
      await db.customStatement(
        "CREATE TRIGGER reject_journal BEFORE INSERT ON drawing_strokes BEGIN SELECT RAISE(ABORT, 'retry'); END",
      );
      data.strokes[0] = data.strokes[0].clone()..points.translate(30, 0);
      data.strokes.add(pen(50));
      await expectLater(
        journal.persist(repo, 1, data.strokes),
        throwsA(anything),
      );
      data.strokes[0] = data.strokes[0].clone()..points.translate(70, 0);
      data.strokes.removeLast();
      await db.customStatement('DROP TRIGGER reject_journal');
      await journal.persist(repo, 1, data.strokes);
      final rows = await repo.getByBlock(1);
      expect(rows.map((r) => strokeFromRecord(r).points.firstX), [100, 10]);
      expect(rows.map((r) => r.id), data.strokes.map((s) => s.dbId));
    },
  );

  test(
    'random batched edits, reorder and restores match SQLite exactly',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = RecordingRepository(db);
      final journal = StrokeDeltaPersistence();
      final data = DrawingData(
        strokes: [for (var i = 0; i < 30; i++) pen(i.toDouble())],
      );
      final random = Random(20261008);
      final snapshots = <List<DrawingStroke>>[];
      for (var step = 0; step < 100; step++) {
        snapshots.add(List.of(data.strokes));
        switch (random.nextInt(5)) {
          case 0:
            data.strokes.insert(
              random.nextInt(data.strokes.length + 1),
              pen(1000 + step.toDouble()),
            );
          case 1:
            removeListSelection(data.strokes, [
              for (var i = 0; i < data.strokes.length; i++)
                if (random.nextInt(4) == 0) i,
            ]);
          case 2:
            if (data.strokes.isNotEmpty) {
              final i = random.nextInt(data.strokes.length);
              data.strokes[i] = data.strokes[i].clone()..points.translate(3, 4);
            }
          case 3:
            data.strokes = data.strokes.reversed.toList();
          case 4:
            data.strokes = snapshots[random.nextInt(snapshots.length)];
        }
        await journal.persist(repo, 1, data.strokes);
        final rows = await repo.getByBlock(1);
        expect(
          rows.map((r) => r.position),
          Iterable<int>.generate(data.strokes.length),
        );
        expect(
          rows.map((r) => strokeFromRecord(r).points.toNested()),
          data.strokes.map((s) => s.points.toNested()),
          reason: 'Step $step',
        );
        expect(rows.map((r) => r.id), data.strokes.map((s) => s.dbId));
      }
    },
  );
}
