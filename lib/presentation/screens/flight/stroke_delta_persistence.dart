import '../../../domain/models/drawing_stroke_record.dart';
import '../../../domain/repositories/drawing_stroke_repository.dart';
import 'drawing_stroke_persistence.dart';
import 'note_cell_model.dart';

class StrokeDeltaPersistence {
  final Map<int, (DrawingStroke, int)> _saved = {};
  Future<void> _tail = Future.value();

  void seed(List<DrawingStrokeRecord> rows, List<DrawingStroke> strokes) {
    _saved.clear();
    for (var i = 0; i < rows.length; i++) {
      _saved[rows[i].id] = (strokes[i], rows[i].position);
    }
  }

  Future<({int inserted, int updated, int deleted})> persist(
    DrawingStrokeRepository repository,
    int blockId,
    List<DrawingStroke> strokes,
  ) {
    final snapshot = List<DrawingStroke>.of(strokes);
    final result = _tail.then((_) => _persist(repository, blockId, snapshot));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  // Committed strokes use copy-on-write. Keep row IDs separate from the objects:
  // history can resurrect an object with a new ID while a save is awaiting.
  Future<({int inserted, int updated, int deleted})> _persist(
    DrawingStrokeRepository repository,
    int blockId,
    List<DrawingStroke> strokes,
  ) async {
    final inserts = <DrawingStrokeWrite>[];
    final insertedIndices = <int>[];
    final updates = <int, DrawingStrokeWrite>{};
    final positions = <int, int>{};
    final retained = <int>{};
    final next = <int, (DrawingStroke, int)>{};
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final id = stroke.dbId;
      final saved = _saved[id];
      if (id == null || saved == null || !retained.add(id)) {
        inserts.add(strokeWrite(i, stroke));
        insertedIndices.add(i);
        continue;
      }
      if (!identical(saved.$1, stroke)) updates[id] = strokeWrite(i, stroke);
      if (saved.$2 != i) positions[id] = i;
      next[id] = (stroke, i);
    }
    final deletes = _saved.keys.where((id) => !retained.contains(id)).toList();
    final ids = await repository.applyBlockDelta(
      blockId,
      inserts: inserts,
      updates: updates,
      positions: positions,
      deletes: deletes,
    );
    for (var i = 0; i < ids.length; i++) {
      final position = insertedIndices[i];
      final stroke = strokes[position];
      stroke.dbId = ids[i];
      next[ids[i]] = (stroke, position);
    }
    _saved
      ..clear()
      ..addAll(next);
    return (
      inserted: inserts.length,
      updated: updates.length,
      deleted: deletes.length,
    );
  }
}
