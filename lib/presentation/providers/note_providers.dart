import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/note.dart';
import '../../domain/models/canvas_context_source.dart';
import 'database_providers.dart';

final notesByFolderProvider =
    StreamProvider.family<List<Note>, int>((ref, folderId) {
  return ref.watch(noteRepositoryProvider).watchByFolder(folderId);
});

final noteByIdProvider = FutureProvider.family<Note?, int>((ref, id) {
  return ref.watch(noteRepositoryProvider).getById(id);
});

final recentNotesProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchAllActive();
});

final noteVersionsProvider =
    FutureProvider.family<List<NoteVersion>, int>((ref, noteId) {
  return ref.watch(noteRepositoryProvider).getVersions(noteId);
});

/// Context sources (linked notes + external urls) feeding a canvas's AI chat.
/// Reactive so the header badge + chat context bar update live.
final canvasContextSourcesProvider =
    StreamProvider.family<List<CanvasContextSource>, int>((ref, canvasNoteId) {
  return ref.watch(noteRepositoryProvider).watchContextSources(canvasNoteId);
});
