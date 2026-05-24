import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/note.dart';
import 'database_providers.dart';

final notesByFolderProvider =
    StreamProvider.family<List<Note>, int>((ref, folderId) {
  return ref.watch(noteRepositoryProvider).watchByFolder(folderId);
});

final noteByIdProvider = FutureProvider.family<Note?, int>((ref, id) {
  return ref.watch(noteRepositoryProvider).getById(id);
});

final noteVersionsProvider =
    FutureProvider.family<List<NoteVersion>, int>((ref, noteId) {
  return ref.watch(noteRepositoryProvider).getVersions(noteId);
});
