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

  Future<List<DrawingStrokeRow>> getByBlockBounds(
    int blockId, {
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
  }) =>
      (select(drawingStrokes)
            ..where(
              (s) =>
                  s.blockId.equals(blockId) &
                  s.maxX.isBiggerOrEqualValue(minX) &
                  s.minX.isSmallerOrEqualValue(maxX) &
                  s.maxY.isBiggerOrEqualValue(minY) &
                  s.minY.isSmallerOrEqualValue(maxY),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .get();

  Future<List<DrawingStrokeRow>> getByBlockAfterPosition(
    int blockId, {
    required int afterPosition,
    required int limit,
  }) =>
      (select(drawingStrokes)
            ..where(
              (s) =>
                  s.blockId.equals(blockId) &
                  s.position.isBiggerThanValue(afterPosition),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.position)])
            ..limit(limit))
          .get();

  Future<({double minX, double minY, double maxX, double maxY})?>
  getBoundsByBlock(int blockId) async {
    final row =
        await customSelect(
          '''
          SELECT
            MIN(min_x) AS min_x,
            MIN(min_y) AS min_y,
            MAX(max_x) AS max_x,
            MAX(max_y) AS max_y
          FROM drawing_strokes
          WHERE block_id = ?
          ''',
          variables: [Variable.withInt(blockId)],
          readsFrom: {drawingStrokes},
        ).getSingle();
    final minX = row.readNullable<double>('min_x');
    final minY = row.readNullable<double>('min_y');
    final maxX = row.readNullable<double>('max_x');
    final maxY = row.readNullable<double>('max_y');
    if (minX == null || minY == null || maxX == null || maxY == null) {
      return null;
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  Future<int?> getMaxPositionByBlock(int blockId) async {
    final row =
        await customSelect(
          '''
          SELECT MAX(position) AS max_position
          FROM drawing_strokes
          WHERE block_id = ?
          ''',
          variables: [Variable.withInt(blockId)],
          readsFrom: {drawingStrokes},
        ).getSingle();
    return row.readNullable<int>('max_position');
  }

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
