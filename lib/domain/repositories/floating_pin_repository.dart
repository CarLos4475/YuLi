import '../models/floating_pin_record.dart';

abstract class FloatingPinRepository {
  /// Persisted pins of a note, in z-order (sort_order asc).
  Future<List<FloatingPinRecord>> forNote(int noteId);

  /// Inserts a new row; returns the assigned id. The passed [record].id is
  /// ignored (autoincrement).
  Future<int> insert(FloatingPinRecord record);

  Future<void> update(FloatingPinRecord record);

  Future<void> delete(int id);

  Future<void> deleteForCanvas(int noteId, int canvasBlockId);

  /// Persists the z-order: [idsInOrder] front-most last.
  Future<void> setOrder(List<int> idsInOrder);

  /// noteId → set of filenames its rows reference (for the storage GC). Notes
  /// with no rows are simply absent from the map.
  Future<Map<int, Set<String>>> referencedFilesByNote();
}
