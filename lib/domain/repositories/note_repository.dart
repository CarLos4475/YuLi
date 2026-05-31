import 'package:flutter/material.dart';
import '../models/note.dart';
import '../models/canvas_context_source.dart';

abstract class NoteRepository {
  Stream<List<Note>> watchByFolder(int folderId);
  Future<List<Note>> getByFolder(int folderId);
  Future<Note?> getById(int id);
  Future<Note> create(int folderId,
      {String? title,
      String rawMarkdown,
      Color? color,
      NoteKind kind});
  Future<void> update(Note note);
  Future<void> softDelete(int id);
  Future<void> restore(int id);
  Future<void> hardDelete(int id);

  Future<List<NoteVersion>> getVersions(int noteId);
  Future<void> saveVersion(int noteId, String rawMarkdown);

  Future<List<NoteImage>> getImages(int noteId);
  Future<NoteImage> addImage(int noteId, String filename, String filePath, int sizeBytes);
  Future<void> deleteImage(int imageId);

  Future<void> linkTask(int noteId, int taskId);
  Future<void> unlinkTask(int noteId, int taskId);
  Future<List<int>> getLinkedTaskIds(int noteId);
  Stream<List<int>> watchLinkedTaskIds(int noteId);
  Stream<List<int>> watchLinkedNoteIds(int taskId);
  Future<List<int>> getLinkedNoteIds(int taskId);
  Stream<List<Note>> watchAllActive();
  Stream<List<Note>> watchDeleted();

  // Canvas context sources (AI context: linked notes + external urls).
  Future<void> addContextSource(int canvasNoteId, CanvasSourceKind kind,
      String ref, {String? label, DateTime? fetchedAt});
  Future<void> removeContextSource(int id);
  Future<void> updateContextSourceFetch(int id,
      {String? label, DateTime? fetchedAt});
  Stream<List<CanvasContextSource>> watchContextSources(int canvasNoteId);
  Future<List<CanvasContextSource>> getContextSources(int canvasNoteId);
  Future<void> removeNoteSourceRefs(int noteId);
}
