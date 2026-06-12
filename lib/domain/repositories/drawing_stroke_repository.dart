import '../models/drawing_stroke_record.dart';

abstract class DrawingStrokeRepository {
  Future<List<DrawingStrokeRecord>> getByBlock(int blockId);
  Future<List<DrawingStrokeRecord>> getByBlockBounds(
    int blockId,
    DrawingStrokeBounds bounds,
  );
  Future<List<DrawingStrokeRecord>> getByBlockAfterPosition(
    int blockId, {
    required int afterPosition,
    required int limit,
  });
  Future<DrawingStrokeBounds?> getBoundsByBlock(int blockId);
  Future<int> insert(int blockId, DrawingStrokeWrite stroke);

  /// In-place update of one stroke row (geometry edit; row keeps its id).
  Future<void> update(int strokeId, DrawingStrokeWrite stroke);

  /// In-place update of many stroke rows in one DB batch.
  Future<void> updateMany(Map<int, DrawingStrokeWrite> strokesById);

  Future<List<int>> replaceBlock(int blockId, List<DrawingStrokeWrite> strokes);
  Future<void> deleteByBlock(int blockId);

  /// Delete a specific set of stroke rows by id.
  Future<void> deleteByIds(List<int> ids);
}
