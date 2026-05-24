import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notes_table.dart';
import '../tables/note_images_table.dart';
import '../tables/note_versions_table.dart';
import '../tables/note_task_links_table.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [Notes, NoteImages, NoteVersions, NoteTaskLinks])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  Stream<List<NoteRow>> watchAllActive() =>
      (select(notes)
            ..where((n) => n.deletedAt.isNull())
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .watch();

  Stream<List<NoteRow>> watchByFolder(int folderId) =>
      (select(notes)
            ..where((n) =>
                n.folderId.equals(folderId) & n.deletedAt.isNull())
            ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]))
          .watch();

  Future<List<NoteRow>> getByFolder(int folderId) =>
      (select(notes)
            ..where((n) =>
                n.folderId.equals(folderId) & n.deletedAt.isNull()))
          .get();

  Future<NoteRow?> getById(int id) =>
      (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<NoteRow> insertNote(NotesCompanion row) async {
    final id = await into(notes).insert(row);
    return (select(notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<void> updateNote(NotesCompanion row) =>
      (update(notes)..where((n) => n.id.equals(row.id.value))).write(row);

  Future<void> softDelete(int id) =>
      (update(notes)..where((n) => n.id.equals(id)))
          .write(NotesCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(int id) =>
      (update(notes)..where((n) => n.id.equals(id)))
          .write(const NotesCompanion(deletedAt: Value(null)));

  Future<void> hardDelete(int id) =>
      (delete(notes)..where((n) => n.id.equals(id))).go();

  Stream<List<NoteRow>> watchDeleted() => (select(notes)
        ..where((n) => n.deletedAt.isNotNull())
        ..orderBy([(n) => OrderingTerm.desc(n.deletedAt)]))
      .watch();

  // Versions (max 10, FIFO)
  Future<List<NoteVersionRow>> getVersions(int noteId) =>
      (select(noteVersions)
            ..where((v) => v.noteId.equals(noteId))
            ..orderBy([(v) => OrderingTerm.desc(v.savedAt)]))
          .get();

  Future<void> saveVersion(int noteId, String rawMarkdown) async {
    await into(noteVersions).insert(
      NoteVersionsCompanion.insert(
        noteId: noteId,
        rawMarkdown: rawMarkdown,
      ),
    );
    // Enforce max 10 versions FIFO
    final all = await getVersions(noteId);
    if (all.length > 10) {
      final toDelete = all.skip(10).map((v) => v.id).toList();
      await (delete(noteVersions)
            ..where((v) => v.id.isIn(toDelete)))
          .go();
    }
  }

  // Images
  Future<List<NoteImageRow>> getImages(int noteId) =>
      (select(noteImages)..where((i) => i.noteId.equals(noteId))).get();

  Future<NoteImageRow> insertImage(NoteImagesCompanion row) async {
    final id = await into(noteImages).insert(row);
    return (select(noteImages)..where((i) => i.id.equals(id))).getSingle();
  }

  Future<void> deleteImage(int imageId) =>
      (delete(noteImages)..where((i) => i.id.equals(imageId))).go();

  // Task links
  Future<void> linkTask(int noteId, int taskId) =>
      into(noteTaskLinks).insertOnConflictUpdate(
        NoteTaskLinksCompanion.insert(noteId: noteId, taskId: taskId),
      );

  Future<void> unlinkTask(int noteId, int taskId) =>
      (delete(noteTaskLinks)
            ..where((l) =>
                l.noteId.equals(noteId) & l.taskId.equals(taskId)))
          .go();

  Future<List<int>> getLinkedTaskIds(int noteId) async {
    final rows = await (select(noteTaskLinks)
          ..where((l) => l.noteId.equals(noteId)))
        .get();
    return rows.map((r) => r.taskId).toList();
  }
}
