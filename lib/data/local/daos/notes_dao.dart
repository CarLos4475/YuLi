import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notes_table.dart';
import '../tables/note_images_table.dart';
import '../tables/note_versions_table.dart';
import '../tables/note_task_links_table.dart';
import '../tables/canvas_context_sources_table.dart';

part 'notes_dao.g.dart';

@DriftAccessor(tables: [
  Notes,
  NoteImages,
  NoteVersions,
  NoteTaskLinks,
  CanvasContextSources
])
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

  /// All note ids (active + soft-deleted), for image garbage-collection.
  Future<List<int>> getAllNoteIds() => select(notes).map((n) => n.id).get();

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

  Stream<List<int>> watchLinkedTaskIds(int noteId) =>
      (select(noteTaskLinks)..where((l) => l.noteId.equals(noteId)))
          .watch()
          .map((rows) => rows.map((r) => r.taskId).toList());

  Stream<List<int>> watchLinkedNoteIds(int taskId) =>
      (select(noteTaskLinks)..where((l) => l.taskId.equals(taskId)))
          .watch()
          .map((rows) => rows.map((r) => r.noteId).toList());

  Future<List<int>> getLinkedNoteIds(int taskId) async {
    final rows = await (select(noteTaskLinks)
          ..where((l) => l.taskId.equals(taskId)))
        .get();
    return rows.map((r) => r.noteId).toList();
  }

  // ─── Canvas context sources (AI context: notes + urls) ───────────────────

  /// Add a source (deduped by canvas+kind+ref). Returns silently if it exists.
  Future<void> addContextSource(int canvasNoteId, String kind, String ref,
          {String? label, DateTime? fetchedAt}) =>
      into(canvasContextSources).insert(
        CanvasContextSourcesCompanion.insert(
          canvasNoteId: canvasNoteId,
          kind: kind,
          ref: ref,
          label: Value(label),
          fetchedAt: Value(fetchedAt),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> removeContextSource(int id) =>
      (delete(canvasContextSources)..where((s) => s.id.equals(id))).go();

  Future<void> setContextSourceEnabled(int id, bool enabled) =>
      (update(canvasContextSources)..where((s) => s.id.equals(id)))
          .write(CanvasContextSourcesCompanion(enabled: Value(enabled)));

  /// Update a url source's cached label + fetch time after a re-fetch.
  Future<void> updateContextSourceFetch(int id,
          {String? label, DateTime? fetchedAt}) =>
      (update(canvasContextSources)..where((s) => s.id.equals(id))).write(
        CanvasContextSourcesCompanion(
          label: Value(label),
          fetchedAt: Value(fetchedAt),
        ),
      );

  Stream<List<CanvasContextSourceRow>> watchContextSources(int canvasNoteId) =>
      (select(canvasContextSources)
            ..where((s) => s.canvasNoteId.equals(canvasNoteId))
            ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
          .watch();

  Future<List<CanvasContextSourceRow>> getContextSources(int canvasNoteId) =>
      (select(canvasContextSources)
            ..where((s) => s.canvasNoteId.equals(canvasNoteId))
            ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
          .get();

  /// Remove every source row referencing a deleted note (cleanup).
  Future<void> removeNoteSourceRefs(int noteId) =>
      (delete(canvasContextSources)
            ..where((s) =>
                s.kind.equals('note') & s.ref.equals(noteId.toString())))
          .go();
}
