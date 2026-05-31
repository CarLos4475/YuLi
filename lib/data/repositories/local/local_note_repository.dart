import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/note.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../../domain/repositories/note_repository.dart';
import '../../local/database.dart';

class LocalNoteRepository implements NoteRepository {
  final AppDatabase _db;

  LocalNoteRepository(this._db);

  @override
  Stream<List<Note>> watchByFolder(int folderId) =>
      _db.notesDao.watchByFolder(folderId).map((rows) => rows.map(_rowToNote).toList());

  @override
  Future<List<Note>> getByFolder(int folderId) async {
    final rows = await _db.notesDao.getByFolder(folderId);
    return rows.map(_rowToNote).toList();
  }

  @override
  Future<Note?> getById(int id) async {
    final row = await _db.notesDao.getById(id);
    return row != null ? _rowToNote(row) : null;
  }

  @override
  Future<Note> create(int folderId,
      {String? title,
      String rawMarkdown = '',
      Color? color,
      NoteKind kind = NoteKind.block}) async {
    final row = await _db.notesDao.insertNote(
      NotesCompanion.insert(
        folderId: folderId,
        title: Value(title),
        rawMarkdown: Value(rawMarkdown),
        sizeBytes: Value(rawMarkdown.length),
        color: Value(color != null ? _colorToHex(color) : null),
        kind: Value(kind.toDbString()),
      ),
    );
    return _rowToNote(row);
  }

  @override
  Future<void> update(Note note) async {
    await _db.notesDao.updateNote(
      NotesCompanion(
        id: Value(note.id),
        folderId: Value(note.folderId),
        title: Value(note.title),
        rawMarkdown: Value(note.rawMarkdown),
        sizeBytes: Value(note.sizeBytes),
        updatedAt: Value(DateTime.now()),
        deletedAt: Value(note.deletedAt),
        color: Value(note.color != null ? _colorToHex(note.color!) : null),
        kind: Value(note.kind.toDbString()),
      ),
    );
  }

  @override
  Future<void> softDelete(int id) async {
    await _db.notesDao.softDelete(id);
    // Trashing a note removes it as a context source from any canvas.
    await _db.notesDao.removeNoteSourceRefs(id);
  }

  @override
  Future<void> restore(int id) => _db.notesDao.restore(id);

  @override
  Future<void> hardDelete(int id) async {
    await _db.notesDao.hardDelete(id);
    await _db.notesDao.removeNoteSourceRefs(id);
  }

  @override
  Stream<List<Note>> watchAllActive() =>
      _db.notesDao.watchAllActive().map((rows) => rows.map(_rowToNote).toList());

  @override
  Stream<List<Note>> watchDeleted() =>
      _db.notesDao.watchDeleted().map((rows) => rows.map(_rowToNote).toList());

  @override
  Future<List<NoteVersion>> getVersions(int noteId) async {
    final rows = await _db.notesDao.getVersions(noteId);
    return rows.map(_rowToVersion).toList();
  }

  @override
  Future<void> saveVersion(int noteId, String rawMarkdown) =>
      _db.notesDao.saveVersion(noteId, rawMarkdown);

  @override
  Future<List<NoteImage>> getImages(int noteId) async {
    final rows = await _db.notesDao.getImages(noteId);
    return rows.map(_rowToImage).toList();
  }

  @override
  Future<NoteImage> addImage(
      int noteId, String filename, String filePath, int sizeBytes) async {
    final row = await _db.notesDao.insertImage(
      NoteImagesCompanion.insert(
        noteId: noteId,
        filename: filename,
        filePath: filePath,
        sizeBytes: sizeBytes,
      ),
    );
    return _rowToImage(row);
  }

  @override
  Future<void> deleteImage(int imageId) => _db.notesDao.deleteImage(imageId);

  @override
  Future<void> linkTask(int noteId, int taskId) =>
      _db.notesDao.linkTask(noteId, taskId);

  @override
  Future<void> unlinkTask(int noteId, int taskId) =>
      _db.notesDao.unlinkTask(noteId, taskId);

  @override
  Future<List<int>> getLinkedTaskIds(int noteId) =>
      _db.notesDao.getLinkedTaskIds(noteId);

  @override
  Stream<List<int>> watchLinkedTaskIds(int noteId) =>
      _db.notesDao.watchLinkedTaskIds(noteId);

  @override
  Stream<List<int>> watchLinkedNoteIds(int taskId) =>
      _db.notesDao.watchLinkedNoteIds(taskId);

  @override
  Future<List<int>> getLinkedNoteIds(int taskId) =>
      _db.notesDao.getLinkedNoteIds(taskId);

  @override
  Future<void> addContextSource(int canvasNoteId, CanvasSourceKind kind,
          String ref, {String? label, DateTime? fetchedAt}) =>
      _db.notesDao.addContextSource(canvasNoteId, kind.toDbString(), ref,
          label: label, fetchedAt: fetchedAt);

  @override
  Future<void> removeContextSource(int id) =>
      _db.notesDao.removeContextSource(id);

  @override
  Future<void> updateContextSourceFetch(int id,
          {String? label, DateTime? fetchedAt}) =>
      _db.notesDao
          .updateContextSourceFetch(id, label: label, fetchedAt: fetchedAt);

  @override
  Stream<List<CanvasContextSource>> watchContextSources(int canvasNoteId) =>
      _db.notesDao
          .watchContextSources(canvasNoteId)
          .map((rows) => rows.map(_rowToSource).toList());

  @override
  Future<List<CanvasContextSource>> getContextSources(int canvasNoteId) async {
    final rows = await _db.notesDao.getContextSources(canvasNoteId);
    return rows.map(_rowToSource).toList();
  }

  @override
  Future<void> removeNoteSourceRefs(int noteId) =>
      _db.notesDao.removeNoteSourceRefs(noteId);

  CanvasContextSource _rowToSource(CanvasContextSourceRow row) =>
      CanvasContextSource(
        id: row.id,
        canvasNoteId: row.canvasNoteId,
        kind: CanvasSourceKind.fromString(row.kind),
        ref: row.ref,
        label: row.label,
        fetchedAt: row.fetchedAt,
        createdAt: row.createdAt,
      );

  Note _rowToNote(NoteRow row) => Note(
        id: row.id,
        folderId: row.folderId,
        title: row.title,
        rawMarkdown: row.rawMarkdown,
        sizeBytes: row.sizeBytes,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        color: row.color != null ? _hexToColor(row.color!) : null,
        kind: NoteKind.fromString(row.kind),
      );

  Color _hexToColor(String hex) {
    final val = hex.replaceFirst('#', '');
    return Color(int.parse('FF$val', radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  NoteVersion _rowToVersion(NoteVersionRow row) => NoteVersion(
        id: row.id,
        noteId: row.noteId,
        rawMarkdown: row.rawMarkdown,
        savedAt: row.savedAt,
      );

  NoteImage _rowToImage(NoteImageRow row) => NoteImage(
        id: row.id,
        noteId: row.noteId,
        filename: row.filename,
        filePath: row.filePath,
        sizeBytes: row.sizeBytes,
        createdAt: row.createdAt,
      );
}
