import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/drawing_stroke_record.dart';
import '../../../domain/repositories/drawing_stroke_repository.dart';
import '../../local/database.dart';

class LocalDrawingStrokeRepository implements DrawingStrokeRepository {
  final AppDatabase _db;

  LocalDrawingStrokeRepository(this._db);

  @override
  Future<List<DrawingStrokeRecord>> getByBlock(int blockId) async {
    final rows = await _db.drawingStrokesDao.getByBlock(blockId);
    final records = <DrawingStrokeRecord>[];
    for (final r in rows) {
      try {
        final payload = jsonDecode(r.payload);
        if (payload is Map<String, dynamic>) {
          records.add(
            DrawingStrokeRecord(
              id: r.id,
              position: r.position,
              payload: payload,
            ),
          );
        }
      } catch (_) {}
    }
    return records;
  }

  @override
  Future<int> insert(int blockId, DrawingStrokeWrite stroke) =>
      _db.drawingStrokesDao.insertStroke(_toCompanion(blockId, stroke));

  @override
  Future<void> update(int strokeId, DrawingStrokeWrite stroke) => _db
      .drawingStrokesDao
      .updateStroke(strokeId, _updateCompanion(stroke, DateTime.now()));

  @override
  Future<void> updateMany(Map<int, DrawingStrokeWrite> strokesById) {
    if (strokesById.isEmpty) return Future.value();
    final now = DateTime.now();
    return _db.drawingStrokesDao.updateStrokes({
      for (final entry in strokesById.entries)
        entry.key: _updateCompanion(entry.value, now),
    });
  }

  @override
  Future<List<int>> replaceBlock(
    int blockId,
    List<DrawingStrokeWrite> strokes,
  ) async {
    await _db.drawingStrokesDao.replaceBlock(
      blockId,
      strokes.map((s) => _toCompanion(blockId, s)).toList(),
    );
    final rows = await _db.drawingStrokesDao.getByBlock(blockId);
    return rows.map((r) => r.id).toList();
  }

  @override
  Future<void> deleteByBlock(int blockId) =>
      _db.drawingStrokesDao.deleteByBlock(blockId);

  @override
  Future<void> deleteByIds(List<int> ids) =>
      _db.drawingStrokesDao.deleteByIds(ids);

  DrawingStrokesCompanion _updateCompanion(
    DrawingStrokeWrite stroke,
    DateTime updatedAt,
  ) => DrawingStrokesCompanion(
    payload: Value(jsonEncode(stroke.payload)),
    minX: Value(stroke.minX),
    minY: Value(stroke.minY),
    maxX: Value(stroke.maxX),
    maxY: Value(stroke.maxY),
    pointCount: Value(stroke.pointCount),
    updatedAt: Value(updatedAt),
  );

  DrawingStrokesCompanion _toCompanion(int blockId, DrawingStrokeWrite stroke) {
    final now = DateTime.now();
    return DrawingStrokesCompanion.insert(
      blockId: blockId,
      position: stroke.position,
      payload: jsonEncode(stroke.payload),
      minX: stroke.minX,
      minY: stroke.minY,
      maxX: stroke.maxX,
      maxY: stroke.maxY,
      pointCount: stroke.pointCount,
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }
}
