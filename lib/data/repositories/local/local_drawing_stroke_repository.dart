import 'package:drift/drift.dart';

import '../../../domain/models/drawing_stroke_record.dart';
import '../../../domain/repositories/drawing_stroke_repository.dart';
import '../../local/database.dart';
import 'local_canvas_ocr_repository.dart';

class LocalDrawingStrokeRepository implements DrawingStrokeRepository {
  final AppDatabase _db;

  final void Function(Iterable<int>)? onChanged;

  LocalDrawingStrokeRepository(this._db, {this.onChanged});

  Future<T> _change<T>(Iterable<int> ids, Future<T> Function() write) async {
    final result = await _db.transaction(() async {
      final result = await write();
      await LocalCanvasOcrRepository.invalidate(_db, ids);
      return result;
    });
    try {
      onChanged?.call(ids);
    } catch (_) {
      // A derived-index observer must never turn a committed ink save into a retry.
    }
    return result;
  }

  Future<T> _changeStrokes<T>(List<int> ids, Future<T> Function() write) async {
    final blocks =
        await (_db.selectOnly(_db.drawingStrokes, distinct: true)
              ..addColumns([_db.drawingStrokes.blockId])
              ..where(_db.drawingStrokes.id.isIn(ids)))
            .get();
    return _change(
      blocks.map((r) => r.read(_db.drawingStrokes.blockId)!),
      write,
    );
  }

  @override
  Future<List<DrawingStrokeRecord>> getByBlock(int blockId) async {
    final rows = await _db.drawingStrokesDao.getByBlock(blockId);
    return _recordsFromRows(rows);
  }

  @override
  Future<List<DrawingStrokeRecord>> getByBlockBounds(
    int blockId,
    DrawingStrokeBounds bounds,
  ) async {
    final rows = await _db.drawingStrokesDao.getByBlockBounds(
      blockId,
      minX: bounds.minX,
      minY: bounds.minY,
      maxX: bounds.maxX,
      maxY: bounds.maxY,
    );
    return _recordsFromRows(rows);
  }

  @override
  Future<List<DrawingStrokeRecord>> getByBlockAfterPosition(
    int blockId, {
    required int afterPosition,
    required int limit,
  }) async {
    final rows = await _db.drawingStrokesDao.getByBlockAfterPosition(
      blockId,
      afterPosition: afterPosition,
      limit: limit,
    );
    return _recordsFromRows(rows);
  }

  @override
  Future<DrawingStrokeBounds?> getBoundsByBlock(int blockId) async {
    final bounds = await _db.drawingStrokesDao.getBoundsByBlock(blockId);
    if (bounds == null) return null;
    return DrawingStrokeBounds(
      minX: bounds.minX,
      minY: bounds.minY,
      maxX: bounds.maxX,
      maxY: bounds.maxY,
    );
  }

  @override
  Future<int?> getMaxPositionByBlock(int blockId) =>
      _db.drawingStrokesDao.getMaxPositionByBlock(blockId);

  @override
  Future<({int count, int points, int? maxPosition})> debugStatsByBlock(
    int blockId,
  ) => _db.drawingStrokesDao.debugStatsByBlock(blockId);

  List<DrawingStrokeRecord> _recordsFromRows(List<QueryRow> rows) {
    return [
      for (final r in rows)
        DrawingStrokeRecord(
          id: r.read<int>('id'),
          position: r.read<int>('position'),
          data: r.read<Uint8List>('data'),
        ),
    ];
  }

  @override
  Future<int> insert(int blockId, DrawingStrokeWrite stroke) => _change([
    blockId,
  ], () => _db.drawingStrokesDao.insertStroke(_toCompanion(blockId, stroke)));

  @override
  Future<List<int>> insertMany(
    int blockId,
    List<DrawingStrokeWrite> strokes,
  ) async {
    if (strokes.isEmpty) return const [];
    final now = DateTime.now();
    final rows = [
      for (final stroke in strokes) _toCompanion(blockId, stroke, now: now),
    ];
    final inserted = await _change([
      blockId,
    ], () => _db.drawingStrokesDao.insertStrokes(blockId, rows));
    return inserted.map((r) => r.id).toList();
  }

  @override
  Future<void> update(int strokeId, DrawingStrokeWrite stroke) =>
      _changeStrokes(
        [strokeId],
        () => _db.drawingStrokesDao.updateStroke(
          strokeId,
          _updateCompanion(stroke, DateTime.now()),
        ),
      );

  @override
  Future<void> updateMany(Map<int, DrawingStrokeWrite> strokesById) {
    if (strokesById.isEmpty) return Future.value();
    final now = DateTime.now();
    return _changeStrokes(
      strokesById.keys.toList(),
      () => _db.drawingStrokesDao.updateStrokes({
        for (final entry in strokesById.entries)
          entry.key: _updateCompanion(entry.value, now),
      }),
    );
  }

  @override
  Future<List<int>> replaceBlock(
    int blockId,
    List<DrawingStrokeWrite> strokes,
  ) async {
    await _change(
      [blockId],
      () => _db.drawingStrokesDao.replaceBlock(
        blockId,
        strokes.map((s) => _toCompanion(blockId, s)).toList(),
      ),
    );
    final rows = await _db.drawingStrokesDao.getByBlock(blockId);
    return rows.map((r) => r.read<int>('id')).toList();
  }

  @override
  Future<void> deleteByBlock(int blockId) =>
      _change([blockId], () => _db.drawingStrokesDao.deleteByBlock(blockId));

  @override
  Future<void> deleteByIds(List<int> ids) =>
      ids.isEmpty
          ? Future.value()
          : _changeStrokes(ids, () => _db.drawingStrokesDao.deleteByIds(ids));

  DrawingStrokesCompanion _updateCompanion(
    DrawingStrokeWrite stroke,
    DateTime updatedAt,
  ) => DrawingStrokesCompanion(
    data: Value(stroke.data),
    minX: Value(stroke.minX),
    minY: Value(stroke.minY),
    maxX: Value(stroke.maxX),
    maxY: Value(stroke.maxY),
    pointCount: Value(stroke.pointCount),
    updatedAt: Value(updatedAt),
  );

  DrawingStrokesCompanion _toCompanion(
    int blockId,
    DrawingStrokeWrite stroke, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return DrawingStrokesCompanion.insert(
      blockId: blockId,
      position: stroke.position,
      data: stroke.data,
      minX: stroke.minX,
      minY: stroke.minY,
      maxX: stroke.maxX,
      maxY: stroke.maxY,
      pointCount: stroke.pointCount,
      createdAt: Value(timestamp),
      updatedAt: Value(timestamp),
    );
  }
}
