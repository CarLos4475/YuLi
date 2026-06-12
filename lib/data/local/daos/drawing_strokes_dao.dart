import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/drawing_strokes_table.dart';

part 'drawing_strokes_dao.g.dart';

@DriftAccessor(tables: [DrawingStrokes])
class DrawingStrokesDao extends DatabaseAccessor<AppDatabase>
    with _$DrawingStrokesDaoMixin {
  DrawingStrokesDao(super.db);

  Future<List<DrawingStrokeRow>> getByBlock(int blockId) =>
      (select(drawingStrokes)
            ..where((s) => s.blockId.equals(blockId))
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .get();

  Future<int> insertStroke(DrawingStrokesCompanion row) =>
      into(drawingStrokes).insert(row);

  /// Update a single stroke row by its id (in-place geometry edit: payload +
  /// bounds change, the row keeps its id and position).
  Future<void> updateStroke(int id, DrawingStrokesCompanion row) =>
      (update(drawingStrokes)..where((s) => s.id.equals(id))).write(row);

  Future<void> updateStrokes(Map<int, DrawingStrokesCompanion> rowsById) async {
    if (rowsById.isEmpty) return;
    await transaction(() async {
      await batch((b) {
        for (final entry in rowsById.entries) {
          b.update(
            drawingStrokes,
            entry.value,
            where: (s) => s.id.equals(entry.key),
          );
        }
      });
    });
  }

  Future<void> deleteByBlock(int blockId) =>
      (delete(drawingStrokes)..where((s) => s.blockId.equals(blockId))).go();

  /// Delete a specific set of stroke rows by id (lasso/eraser delete).
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(drawingStrokes)..where((s) => s.id.isIn(ids))).go();
  }

  Future<void> replaceBlock(
    int blockId,
    List<DrawingStrokesCompanion> rows,
  ) async {
    await transaction(() async {
      await deleteByBlock(blockId);
      if (rows.isEmpty) return;
      await batch((b) => b.insertAll(drawingStrokes, rows));
    });
  }
}
