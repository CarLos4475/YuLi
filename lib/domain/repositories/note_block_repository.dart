import '../models/note_block.dart';

abstract class NoteBlockRepository {
  Stream<List<NoteBlock>> watchByNote(int noteId);
  Future<List<NoteBlock>> getByNote(int noteId);

  /// Insert a new block. If `afterPosition` is null, appends. Returns the
  /// stored block (with id assigned). Shifts subsequent blocks if needed.
  Future<NoteBlock> insertAtEnd(int noteId, NoteBlockType type,
      {Map<String, dynamic> payload = const {}});

  Future<NoteBlock> insertAfter(int noteId, int afterPosition,
      NoteBlockType type,
      {Map<String, dynamic> payload = const {}});

  /// REEMPLAZA el payload completo del bloque (no mergea). Cada caller debe
  /// pasar el payload ENTERO de su tipo de bloque — una llamada parcial borra
  /// las demás keys.
  Future<void> updatePayload(int blockId, Map<String, dynamic> payload);

  Future<void> delete(int blockId);

  Future<void> reorder(int noteId, List<int> orderedIds);
}
