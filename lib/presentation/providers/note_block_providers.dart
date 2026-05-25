import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/note_block.dart';
import '../../domain/models/task.dart';
import 'database_providers.dart';

/// Blocks of a note, ordered by position.
final noteBlocksProvider =
    StreamProvider.family<List<NoteBlock>, int>((ref, noteId) {
  return ref.watch(noteBlockRepositoryProvider).watchByNote(noteId);
});

/// Live linked task ids for a note (via note_task_links).
final noteLinkedTaskIdsProvider =
    StreamProvider.family<List<int>, int>((ref, noteId) {
  return ref.watch(noteRepositoryProvider).watchLinkedTaskIds(noteId);
});

/// Live task entities linked to a note. Reflects done/trash globally.
final noteLinkedTasksProvider =
    StreamProvider.family<List<Task>, int>((ref, noteId) async* {
  final repo = ref.watch(taskRepositoryProvider);
  await for (final ids in ref.watch(noteRepositoryProvider).watchLinkedTaskIds(noteId)) {
    if (ids.isEmpty) {
      yield const [];
      continue;
    }
    yield* repo.watchByIds(ids);
  }
});
