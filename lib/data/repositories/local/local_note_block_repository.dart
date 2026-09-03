import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/note_block.dart';
import '../../../domain/repositories/note_block_repository.dart';
import '../../local/database.dart';

class LocalNoteBlockRepository implements NoteBlockRepository {
  final AppDatabase _db;

  LocalNoteBlockRepository(this._db);

  @override
  Stream<List<NoteBlock>> watchByNote(int noteId) => _db.noteBlocksDao
      .watchByNote(noteId)
      .map((rows) => rows.map(_rowToBlock).toList());

  @override
  Future<List<NoteBlock>> getByNote(int noteId) async {
    final rows = await _db.noteBlocksDao.getByNote(noteId);
    return rows.map(_rowToBlock).toList();
  }

  @override
  Future<List<NoteBlock>> getByNoteIds(List<int> noteIds) async {
    final rows = await _db.noteBlocksDao.getByNoteIds(noteIds);
    return rows.map(_rowToBlock).toList();
  }

  @override
  Future<NoteBlock> insertAtEnd(
    int noteId,
    NoteBlockType type, {
    Map<String, dynamic> payload = const {},
  }) async {
    final maxPos = await _db.noteBlocksDao.getMaxPosition(noteId);
    final row = await _db.noteBlocksDao.insertBlock(
      NoteBlocksCompanion.insert(
        noteId: noteId,
        position: maxPos + 1,
        type: type.toDbString(),
        payload: Value(jsonEncode(payload)),
      ),
    );
    return _rowToBlock(row);
  }

  @override
  Future<NoteBlock> insertAfter(
    int noteId,
    int afterPosition,
    NoteBlockType type, {
    Map<String, dynamic> payload = const {},
  }) async {
    // Shift all blocks with position > afterPosition by +1.
    await _db.customUpdate(
      "UPDATE note_blocks SET position = position + 1 "
      "WHERE note_id = ? AND position > ?",
      variables: [Variable.withInt(noteId), Variable.withInt(afterPosition)],
      updates: {_db.noteBlocks},
      updateKind: UpdateKind.update,
    );
    final row = await _db.noteBlocksDao.insertBlock(
      NoteBlocksCompanion.insert(
        noteId: noteId,
        position: afterPosition + 1,
        type: type.toDbString(),
        payload: Value(jsonEncode(payload)),
      ),
    );
    return _rowToBlock(row);
  }

  @override
  Future<void> updatePayload(int blockId, Map<String, dynamic> payload) =>
      _db.noteBlocksDao.updateBlock(
        NoteBlocksCompanion(
          id: Value(blockId),
          payload: Value(jsonEncode(payload)),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> delete(int blockId) async {
    await _db.drawingStrokesDao.deleteByBlock(blockId);
    await _db.noteBlocksDao.deleteBlock(blockId);
  }

  @override
  Future<void> reorder(int noteId, List<int> orderedIds) =>
      _db.noteBlocksDao.reorder(noteId, orderedIds);

  NoteBlock _rowToBlock(NoteBlockRow row) => NoteBlock.fromPayload(
    id: row.id,
    noteId: row.noteId,
    position: row.position,
    type: NoteBlockType.fromString(row.type),
    payload: row.payload,
  );
}
