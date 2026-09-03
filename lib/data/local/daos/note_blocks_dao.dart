import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/note_blocks_table.dart';

part 'note_blocks_dao.g.dart';

@DriftAccessor(tables: [NoteBlocks])
class NoteBlocksDao extends DatabaseAccessor<AppDatabase>
    with _$NoteBlocksDaoMixin {
  NoteBlocksDao(super.db);

  Stream<List<NoteBlockRow>> watchByNote(int noteId) =>
      (select(noteBlocks)
            ..where((b) => b.noteId.equals(noteId))
            ..orderBy([(b) => OrderingTerm.asc(b.position)]))
          .watch();

  Future<List<NoteBlockRow>> getByNote(int noteId) =>
      (select(noteBlocks)
            ..where((b) => b.noteId.equals(noteId))
            ..orderBy([(b) => OrderingTerm.asc(b.position)]))
          .get();

  Future<List<NoteBlockRow>> getByNoteIds(List<int> noteIds) {
    if (noteIds.isEmpty) return Future.value(const []);
    return (select(noteBlocks)
          ..where((b) => b.noteId.isIn(noteIds))
          ..orderBy([
            (b) => OrderingTerm.asc(b.noteId),
            (b) => OrderingTerm.asc(b.position),
          ]))
        .get();
  }

  Future<NoteBlockRow> insertBlock(NoteBlocksCompanion row) async {
    final id = await into(noteBlocks).insert(row);
    return (select(noteBlocks)..where((b) => b.id.equals(id))).getSingle();
  }

  Future<void> updateBlock(NoteBlocksCompanion row) =>
      (update(noteBlocks)..where((b) => b.id.equals(row.id.value))).write(row);

  Future<void> deleteBlock(int id) =>
      (delete(noteBlocks)..where((b) => b.id.equals(id))).go();

  Future<void> deleteByNote(int noteId) =>
      (delete(noteBlocks)..where((b) => b.noteId.equals(noteId))).go();

  /// Reorders blocks by writing the index of each id as its new position.
  Future<void> reorder(int noteId, List<int> orderedIds) async {
    await transaction(() async {
      for (int i = 0; i < orderedIds.length; i++) {
        await (update(noteBlocks)..where(
          (b) => b.id.equals(orderedIds[i]) & b.noteId.equals(noteId),
        )).write(
          NoteBlocksCompanion(
            position: Value(i),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  Future<int> getMaxPosition(int noteId) async {
    final rows =
        await (select(noteBlocks)
              ..where((b) => b.noteId.equals(noteId))
              ..orderBy([(b) => OrderingTerm.desc(b.position)])
              ..limit(1))
            .get();
    if (rows.isEmpty) return -1;
    return rows.first.position;
  }
}
