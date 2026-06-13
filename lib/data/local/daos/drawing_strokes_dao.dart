import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/drawing_strokes_table.dart';

part 'drawing_strokes_dao.g.dart';

@DriftAccessor(tables: [DrawingStrokes])
class DrawingStrokesDao extends DatabaseAccessor<AppDatabase>
    with _$DrawingStrokesDaoMixin {
  DrawingStrokesDao(super.db);

  // Read paths select ONLY id/position/data (what the load actually uses), not
  // the full row. Skipping min/max/pointCount and especially the two DateTime
  // columns (created_at/updated_at — each parsed into a DateTime per row) is a
  // big slice of the open-time cost on dense notes (e.g. ~569k rows × 2 parses).
  Future<List<QueryRow>> getByBlock(int blockId) => customSelect(
    'SELECT id, position, data FROM drawing_strokes '
    'WHERE block_id = ? ORDER BY position ASC',
    variables: [Variable.withInt(blockId)],
    readsFrom: {drawingStrokes},
  ).get();

  Future<List<QueryRow>> getByBlockBounds(
    int blockId, {
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
  }) => customSelect(
    'SELECT id, position, data FROM drawing_strokes '
    'WHERE block_id = ? AND max_x >= ? AND min_x <= ? '
    'AND max_y >= ? AND min_y <= ? ORDER BY position ASC',
    variables: [
      Variable.withInt(blockId),
      Variable.withReal(minX),
      Variable.withReal(maxX),
      Variable.withReal(minY),
      Variable.withReal(maxY),
    ],
    readsFrom: {drawingStrokes},
  ).get();

  Future<List<QueryRow>> getByBlockAfterPosition(
    int blockId, {
    required int afterPosition,
    required int limit,
  }) => customSelect(
    'SELECT id, position, data FROM drawing_strokes '
    'WHERE block_id = ? AND position > ? ORDER BY position ASC LIMIT ?',
    variables: [
      Variable.withInt(blockId),
      Variable.withInt(afterPosition),
      Variable.withInt(limit),
    ],
    readsFrom: {drawingStrokes},
  ).get();

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

  Future<({int count, int points, int? maxPosition})> debugStatsByBlock(
    int blockId,
  ) async {
    final row =
        await customSelect(
          '''
          SELECT
            COUNT(*) AS row_count,
            COALESCE(SUM(point_count), 0) AS point_count,
            MAX(position) AS max_position
          FROM drawing_strokes
          WHERE block_id = ?
          ''',
          variables: [Variable.withInt(blockId)],
          readsFrom: {drawingStrokes},
        ).getSingle();
    return (
      count: row.read<int>('row_count'),
      points: row.read<int>('point_count'),
      maxPosition: row.readNullable<int>('max_position'),
    );
  }

  Future<int> insertStroke(DrawingStrokesCompanion row) =>
      into(drawingStrokes).insert(row);

  Future<List<DrawingStrokeRow>> insertStrokes(
    int blockId,
    List<DrawingStrokesCompanion> rows,
  ) async {
    if (rows.isEmpty) return const [];
    return transaction(() async {
      final maxRow =
          await customSelect(
            '''
            SELECT MAX(id) AS max_id
            FROM drawing_strokes
            WHERE block_id = ?
            ''',
            variables: [Variable.withInt(blockId)],
            readsFrom: {drawingStrokes},
          ).getSingle();
      final previousMaxId = maxRow.readNullable<int>('max_id') ?? 0;
      await batch((b) => b.insertAll(drawingStrokes, rows));
      return (select(drawingStrokes)
            ..where(
              (s) =>
                  s.blockId.equals(blockId) &
                  s.id.isBiggerThanValue(previousMaxId),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.position)]))
          .get();
    });
  }

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
