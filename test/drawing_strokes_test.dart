import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_drawing_stroke_repository.dart';
import 'package:yuli/data/repositories/local/local_note_block_repository.dart';
import 'package:yuli/domain/models/drawing_stroke_record.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/presentation/screens/flight/drawing_stroke_persistence.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalNoteBlockRepository blockRepo;
  late LocalDrawingStrokeRepository strokeRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    blockRepo = LocalNoteBlockRepository(db);
    strokeRepo = LocalDrawingStrokeRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> makeDrawingBlock() async {
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'f', color: '#FFFFFF'));
    final noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(folderId: folderId));
    final block = await blockRepo.insertAtEnd(
      noteId,
      NoteBlockType.drawing,
      payload: {'h': 4000, 's': [], 'whiteboard': true},
    );
    return block.id;
  }

  DrawingStroke pen(double x, double y) => DrawingStroke(
    colorValue: 0xFF000000,
    strokeWidth: 3,
    points: [
      [x, y],
      [x + 10, y + 10],
    ],
  );

  test('insert + getByBlock round-trips strokes with dbId', () async {
    final blockId = await makeDrawingBlock();
    final a = pen(0, 0);
    final b = pen(50, 50);
    a.dbId = await strokeRepo.insert(blockId, strokeWrite(0, a));
    b.dbId = await strokeRepo.insert(blockId, strokeWrite(1, b));

    final rows = await strokeRepo.getByBlock(blockId);
    expect(rows.length, 2);
    final restored = rows.map(strokeFromRecord).toList();
    expect(restored[0].dbId, a.dbId);
    expect(restored[0].points.first, [0.0, 0.0]);
    expect(restored[1].points.first, [50.0, 50.0]);
  });

  test('insertMany round-trips strokes in position order', () async {
    final blockId = await makeDrawingBlock();
    final strokes = [pen(0, 0), pen(50, 50), pen(100, 100)];
    final ids = await strokeRepo.insertMany(blockId, [
      for (final (i, stroke) in strokes.indexed) strokeWrite(i, stroke),
    ]);
    for (final (i, id) in ids.indexed) {
      strokes[i].dbId = id;
    }

    final rows = await strokeRepo.getByBlock(blockId);
    expect(rows.map((r) => r.id).toList(), ids);
    expect(rows.map((r) => r.position).toList(), [0, 1, 2]);
    expect(rows.map(strokeFromRecord).map((s) => s.dbId).toList(), ids);
  });

  test('getByBlock returns rows ordered by position', () async {
    final blockId = await makeDrawingBlock();
    // Insert out of order: position 5 then 2.
    await strokeRepo.insert(blockId, strokeWrite(5, pen(0, 0)));
    await strokeRepo.insert(blockId, strokeWrite(2, pen(99, 99)));
    final rows = await strokeRepo.getByBlock(blockId);
    expect(rows.map((r) => r.position).toList(), [2, 5]);
  });

  test('update mutates the stored payload in place, keeps id', () async {
    final blockId = await makeDrawingBlock();
    final s = pen(0, 0);
    s.dbId = await strokeRepo.insert(blockId, strokeWrite(0, s));
    // Move it.
    final moved = DrawingStroke(
      colorValue: s.colorValue,
      strokeWidth: s.strokeWidth,
      points: [
        [100, 100],
        [110, 110],
      ],
    )..dbId = s.dbId;
    await strokeRepo.update(s.dbId!, strokeWrite(0, moved));

    final rows = await strokeRepo.getByBlock(blockId);
    expect(rows.length, 1);
    expect(rows.first.id, s.dbId);
    expect(strokeFromRecord(rows.first).points.first, [100.0, 100.0]);
  });

  test('updateMany mutates several stored strokes in one batch', () async {
    final blockId = await makeDrawingBlock();
    final a = pen(0, 0);
    final b = pen(10, 10);
    final c = pen(20, 20);
    a.dbId = await strokeRepo.insert(blockId, strokeWrite(0, a));
    b.dbId = await strokeRepo.insert(blockId, strokeWrite(1, b));
    c.dbId = await strokeRepo.insert(blockId, strokeWrite(2, c));

    final movedA = pen(100, 100)..dbId = a.dbId;
    final movedC = pen(300, 300)..dbId = c.dbId;
    await strokeRepo.updateMany({
      a.dbId!: strokeWrite(0, movedA),
      c.dbId!: strokeWrite(2, movedC),
    });

    final restored =
        (await strokeRepo.getByBlock(blockId)).map(strokeFromRecord).toList();
    expect(restored.map((s) => s.dbId).toList(), [a.dbId, b.dbId, c.dbId]);
    expect(restored[0].points.first, [100.0, 100.0]);
    expect(restored[1].points.first, [10.0, 10.0]);
    expect(restored[2].points.first, [300.0, 300.0]);
  });

  test('deleteByIds removes only the named rows', () async {
    final blockId = await makeDrawingBlock();
    final a = pen(0, 0)
      ..dbId = await strokeRepo.insert(blockId, strokeWrite(0, pen(0, 0)));
    final b = pen(1, 1)
      ..dbId = await strokeRepo.insert(blockId, strokeWrite(1, pen(1, 1)));
    final c = pen(2, 2)
      ..dbId = await strokeRepo.insert(blockId, strokeWrite(2, pen(2, 2)));

    await strokeRepo.deleteByIds([a.dbId!, c.dbId!]);
    final rows = await strokeRepo.getByBlock(blockId);
    expect(rows.map((r) => r.id).toList(), [b.dbId]);
  });

  test(
    'getByBlockBounds returns strokes intersecting the query rect',
    () async {
      final blockId = await makeDrawingBlock();
      await strokeRepo.insert(blockId, strokeWrite(0, pen(0, 0)));
      await strokeRepo.insert(blockId, strokeWrite(1, pen(100, 100)));
      await strokeRepo.insert(blockId, strokeWrite(2, pen(300, 300)));

      final bounds = await strokeRepo.getBoundsByBlock(blockId);
      expect(bounds, isNotNull);
      expect(bounds!.minX, -3.5);
      expect(bounds.minY, -3.5);
      expect(bounds.maxX, 313.5);
      expect(bounds.maxY, 313.5);

      final rows = await strokeRepo.getByBlockBounds(
        blockId,
        const DrawingStrokeBounds(minX: 90, minY: 90, maxX: 120, maxY: 120),
      );
      expect(rows.map((r) => r.position).toList(), [1]);
    },
  );

  test('getByBlockAfterPosition pages rows by position', () async {
    final blockId = await makeDrawingBlock();
    await strokeRepo.insert(blockId, strokeWrite(0, pen(0, 0)));
    await strokeRepo.insert(blockId, strokeWrite(1, pen(10, 10)));
    await strokeRepo.insert(blockId, strokeWrite(2, pen(20, 20)));
    await strokeRepo.insert(blockId, strokeWrite(3, pen(30, 30)));

    final rows = await strokeRepo.getByBlockAfterPosition(
      blockId,
      afterPosition: 1,
      limit: 2,
    );
    expect(rows.map((r) => r.position).toList(), [2, 3]);
  });

  test('getMaxPositionByBlock returns highest stored position', () async {
    final blockId = await makeDrawingBlock();
    expect(await strokeRepo.getMaxPositionByBlock(blockId), isNull);

    await strokeRepo.insert(blockId, strokeWrite(7, pen(0, 0)));
    await strokeRepo.insert(blockId, strokeWrite(3, pen(10, 10)));
    await strokeRepo.insert(blockId, strokeWrite(11, pen(20, 20)));

    expect(await strokeRepo.getMaxPositionByBlock(blockId), 11);
  });

  test(
    'round-trips every real stroke kind (fountain/shape/highlighter)',
    () async {
      final blockId = await makeDrawingBlock();
      final fountain = DrawingStroke(
        colorValue: 0xFF112233,
        strokeWidth: 4,
        isFountainPen: true,
        points: [
          [0, 0, 2.0],
          [5, 5, 3.5],
          [10, 2, 1.0],
        ],
      );
      final shape = DrawingStroke(
        colorValue: 0xFF445566,
        strokeWidth: 2,
        isShape: true,
        filled: true,
        points: [
          [0, 0],
          [20, 0],
          [20, 20],
          [0, 20],
        ],
      );
      final hl = DrawingStroke(
        colorValue: 0x55FFFF00,
        strokeWidth: 18,
        isHighlighter: true,
        points: [
          [0, 0],
          [30, 0],
        ],
      );
      for (final (i, s) in [fountain, shape, hl].indexed) {
        s.dbId = await strokeRepo.insert(blockId, strokeWrite(i, s));
      }
      final restored =
          (await strokeRepo.getByBlock(blockId)).map(strokeFromRecord).toList();
      expect(restored.length, 3);
      expect(restored[0].isFountainPen, true);
      expect(restored[0].points[1], [5.0, 5.0, 3.5]);
      expect(restored[1].isShape, true);
      expect(restored[1].filled, true);
      expect(restored[2].isHighlighter, true);
    },
  );

  test('reload via getByNote + getByBlock recovers a saved board', () async {
    // Simulate the editor: create block, persist strokes + payload, then reopen.
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'f', color: '#FFFFFF'));
    final noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(folderId: folderId));
    final block = await blockRepo.insertAtEnd(
      noteId,
      NoteBlockType.drawing,
      payload: {'h': 4000, 's': [], 'whiteboard': true},
    );
    final s = pen(7, 7);
    s.dbId = await strokeRepo.insert(block.id, strokeWrite(0, s));
    await blockRepo.updatePayload(block.id, {
      'h': 4000,
      's': const [],
      'bg': 'grid',
      'whiteboard': true,
    });

    // Reopen path.
    final blocks = await blockRepo.getByNote(noteId);
    final reopened = blocks.whereType<DrawingBlock>().first;
    final rows = await strokeRepo.getByBlock(reopened.id);
    expect(rows.length, 1, reason: 'strokes must survive reopen');
    expect(
      reopened.background,
      'grid',
      reason: 'bg config must survive reopen',
    );
  });
}
