import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/domain/models/drawing_stroke_record.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/domain/repositories/drawing_stroke_repository.dart';
import 'package:yuli/domain/repositories/note_block_repository.dart';
import 'package:yuli/domain/services/pending_saves.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/drawing_cell.dart';
import 'package:yuli/presentation/screens/flight/drawing_stroke_persistence.dart';
import 'package:yuli/presentation/screens/flight/note_block_widgets.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';

DrawingStroke pen(double x) => DrawingStroke(
  colorValue: 0xff000000,
  strokeWidth: 3,
  points: StrokePoints.fromNested([
    [x, 100],
    [x + 100, 150],
    [x + 200, 200],
  ]),
);

class StrokeRepository implements DrawingStrokeRepository {
  final rows = <int, List<DrawingStrokeRecord>>{};
  final writes = <(int, int)>[];
  Completer<void>? gate;
  int nextId = 10000;
  @override
  Future<List<DrawingStrokeRecord>> getByBlock(int blockId) async =>
      rows[blockId] ?? [];
  @override
  Future<List<int>> applyBlockDelta(
    int blockId, {
    required List<DrawingStrokeWrite> inserts,
    required Map<int, DrawingStrokeWrite> updates,
    required Map<int, int> positions,
    required List<int> deletes,
  }) async {
    writes.add((blockId, inserts.length + updates.length + deletes.length));
    if (gate != null) await gate!.future;
    final current = rows[blockId] ?? [];
    final result = <DrawingStrokeRecord>[
      for (final row in current)
        if (!deletes.contains(row.id))
          DrawingStrokeRecord(
            id: row.id,
            position: positions[row.id] ?? row.position,
            data: updates[row.id]?.data ?? row.data,
          ),
    ];
    final ids = <int>[];
    for (final write in inserts) {
      final id = nextId++;
      ids.add(id);
      result.add(
        DrawingStrokeRecord(id: id, position: write.position, data: write.data),
      );
    }
    rows[blockId] = result..sort((a, b) => a.position.compareTo(b.position));
    return ids;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BlockRepository implements NoteBlockRepository {
  final payloads = <(int, Map<String, dynamic>)>[];
  @override
  Future<void> updatePayload(int id, Map<String, dynamic> payload) async {
    payloads.add((id, payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cell lasso move undo redo uses copy on write', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    // The test font Ahem is wider than the platform monospace toolbar font.
    tester.platformDispatcher.textScaleFactorTestValue = 0.75;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original = pen(100);
    final untouched = pen(650);
    final data = DrawingData(height: 400, strokes: [original, untouched]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingCell(
            data: data,
            onChanged: (_) {},
            onDelete: () {},
            onDrawStart: () {},
            onDrawEnd: () {},
            onScrollLockChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(YuLiIcons.chevronDown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAZO'));
    await tester.pump();
    final canvas = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_StrokePainter',
    );
    final center = tester.getTopLeft(canvas) + const Offset(200, 150);
    final select = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await select.up();
    await tester.pump();
    final drag = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await drag.moveBy(const Offset(50, 20));
    await drag.up();
    await tester.pump();
    expect(original.points.firstX, 100);
    expect(data.strokes.first.points.firstX, 150);
    expect(identical(data.strokes[1], untouched), isTrue);
    await tester.tap(find.byIcon(YuLiIcons.undo));
    await tester.pump();
    expect(data.strokes.first.points.firstX, 100);
    await tester.tap(find.byIcon(YuLiIcons.redo));
    await tester.pump();
    expect(data.strokes.first.points.firstX, 150);
    expect(identical(data.strokes[1], untouched), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'embedded saves retain metadata and original block across pending edits',
    (tester) async {
      final strokes = StrokeRepository();
      final blocks = BlockRepository();
      strokes.rows[1] = [
        for (var i = 0; i < 1000; i++)
          DrawingStrokeRecord(
            id: i + 1,
            position: i,
            data: strokeWrite(i, pen(i.toDouble())).data,
          ),
      ];
      final now = DateTime(2026);
      var block = const DrawingBlock(
        id: 1,
        noteId: 1,
        position: 0,
        height: 300,
        strokesJson: '[]',
        background: 'grid',
        bgColor: 0xffeeeeee,
        starred: true,
        name: 'Dibujo',
        imagesJson: '[{"f":"image.png","x":1,"y":2,"w":30,"h":40}]',
      );
      late StateSetter rebuild;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            drawingStrokeRepositoryProvider.overrideWithValue(strokes),
            noteBlockRepositoryProvider.overrideWithValue(blocks),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return BlockRouter(
                    block: block,
                    note: Note(
                      id: 1,
                      folderId: 1,
                      rawMarkdown: '',
                      sizeBytes: 0,
                      createdAt: now,
                      updatedAt: now,
                    ),
                    folder: Folder(
                      id: 1,
                      name: 'Prueba',
                      color: Colors.blue,
                      createdAt: now,
                    ),
                    index: 0,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cell = tester.widget<DrawingCell>(find.byType(DrawingCell));
      expect(cell.data.strokes.length, 1000);
      final original = cell.data.strokes[500];
      final unchanged = cell.data.strokes[501];
      strokes.gate = Completer<void>();
      cell.data.strokes[500] = original.clone()..points.translate(30, 40);
      cell.onChanged(cell.data);
      await tester.pump();
      cell.data.strokes[500] = original;
      cell.onChanged(cell.data);
      rebuild(
        () =>
            block = const DrawingBlock(
              id: 2,
              noteId: 1,
              position: 0,
              height: 300,
              strokesJson: '[]',
            ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DrawingCell>(find.byType(DrawingCell)).data.strokes,
        isEmpty,
      );
      strokes.gate!.complete();
      await tester.pumpAndSettle();
      await PendingSaves.flush();
      expect(strokes.writes, [(1, 1), (1, 1)]);
      expect(strokes.rows[1]!.length, 1000);
      expect(strokeFromRecord(strokes.rows[1]![500]).points.firstX, 500);
      expect(unchanged.dbId, 502);
      expect(blocks.payloads.map((v) => v.$1), [1, 1]);
      for (final (_, payload) in blocks.payloads) {
        expect(payload['starred'], true);
        expect(payload['name'], 'Dibujo');
        expect(payload['bg'], 'grid');
        expect(payload['bgc'], 0xffeeeeee);
        expect(payload['i'], hasLength(1));
        expect(payload['s'], isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
