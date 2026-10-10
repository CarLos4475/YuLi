import '../../../domain/models/drawing_stroke_record.dart';
import '../../../domain/repositories/drawing_stroke_repository.dart';
import 'drawing_stroke_persistence.dart';
import 'note_cell_model.dart';
import 'tracked_list.dart';

class StrokeDeltaPersistence {
  final Map<TrackedEntry<DrawingStroke>, (int, DrawingStroke, int)> _saved = {};
  final Map<TrackedEntry<DrawingStroke>, (DrawingStroke?, int)> _retry = {};
  Future<void> _tail = Future.value();
  TrackedList<DrawingStroke>? _source;
  int? _blockId;

  TrackedList<DrawingStroke> _track(List<DrawingStroke> strokes) {
    if (strokes is TrackedList<DrawingStroke>) {
      if (_source != null && !identical(_source, strokes)) {
        throw StateError('A stroke journal belongs to one canvas');
      }
      return _source = strokes;
    }
    final source =
        _source ??= TrackedList<DrawingStroke>([], keyOf: (s) => s.dbId);
    source.replaceAll(strokes);
    return source;
  }

  void seed(List<DrawingStrokeRecord> rows, List<DrawingStroke> strokes) {
    final source = _track(strokes);
    _saved.clear();
    _retry.clear();
    for (var i = 0; i < rows.length; i++) {
      final entry = source.entryAt(i);
      _saved[entry] = (rows[i].id, entry.value, rows[i].position);
      if (rows[i].position == i) source.acknowledge(entry);
    }
  }

  Future<({int inserted, int updated, int deleted})> persist(
    DrawingStrokeRepository repository,
    int blockId,
    List<DrawingStroke> strokes, {
    void Function(int, DrawingStroke)? onAssignedId,
  }) {
    if (_blockId != null && _blockId != blockId) {
      throw StateError('A stroke journal belongs to one block');
    }
    _blockId = blockId;
    final changes = _track(strokes).takeChanges();
    final result = _tail.then(
      (_) => _persist(repository, blockId, changes, onAssignedId),
    );
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<({int inserted, int updated, int deleted})> _persist(
    DrawingStrokeRepository repository,
    int blockId,
    Map<TrackedEntry<DrawingStroke>, (DrawingStroke?, int)> changes,
    void Function(int, DrawingStroke)? onAssignedId,
  ) async {
    final pending = {..._retry, ...changes};
    if (pending.isEmpty) return (inserted: 0, updated: 0, deleted: 0);
    _retry
      ..clear()
      ..addAll(pending);
    final inserts = <DrawingStrokeWrite>[];
    final insertedEntries = <TrackedEntry<DrawingStroke>>[];
    final updates = <int, DrawingStrokeWrite>{};
    final positions = <int, int>{};
    final deletes = <int>[];
    for (final item in pending.entries) {
      final (stroke, position) = item.value;
      final saved = _saved[item.key];
      if (stroke == null) {
        if (saved != null) deletes.add(saved.$1);
      } else if (saved == null) {
        insertedEntries.add(item.key);
      } else {
        if (!identical(saved.$2, stroke)) {
          updates[saved.$1] = strokeWrite(position, stroke);
        }
        if (saved.$3 != position) positions[saved.$1] = position;
      }
    }
    insertedEntries.sort((a, b) => pending[a]!.$2.compareTo(pending[b]!.$2));
    inserts
      ..clear()
      ..addAll([
        for (final entry in insertedEntries)
          strokeWrite(pending[entry]!.$2, pending[entry]!.$1!),
      ]);
    final ids = await repository.applyBlockDelta(
      blockId,
      inserts: inserts,
      updates: updates,
      positions: positions,
      deletes: deletes,
    );
    final insertedIds = {
      for (var i = 0; i < ids.length; i++) insertedEntries[i]: ids[i],
    };
    for (final item in pending.entries) {
      final (stroke, position) = item.value;
      if (stroke == null) {
        _saved.remove(item.key);
        continue;
      }
      final id = insertedIds[item.key] ?? _saved[item.key]!.$1;
      stroke.dbId = id;
      item.key.value.dbId = id;
      _saved[item.key] = (id, stroke, position);
    }
    _retry.clear();
    for (final entry in insertedEntries) {
      if (entry.position >= 0) {
        onAssignedId?.call(entry.position, entry.value);
      }
    }
    return (
      inserted: inserts.length,
      updated: updates.length,
      deleted: deletes.length,
    );
  }
}
