import 'dart:async';

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
///
/// `watchByIds` is an infinite watch stream, so a naive `await for (ids) {
/// yield* watchByIds(ids); }` blocks on the first non-empty ids forever and
/// never reacts to later link/unlink changes. We switch the inner subscription
/// manually so adding/removing a linked task updates live.
final noteLinkedTasksProvider =
    StreamProvider.family<List<Task>, int>((ref, noteId) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final noteRepo = ref.watch(noteRepositoryProvider);
  final controller = StreamController<List<Task>>();
  StreamSubscription<List<Task>>? inner;

  void emit(List<Task> tasks) {
    if (!controller.isClosed) controller.add(tasks);
  }

  final outer = noteRepo.watchLinkedTaskIds(noteId).listen(
    (ids) {
      inner?.cancel();
      inner = null;
      if (ids.isEmpty) {
        emit(const []);
      } else {
        inner = taskRepo.watchByIds(ids).listen(
          emit,
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );
      }
    },
    onError: (Object e, StackTrace st) {
      if (!controller.isClosed) controller.addError(e, st);
    },
  );

  ref.onDispose(() {
    inner?.cancel();
    outer.cancel();
    controller.close();
  });

  return controller.stream;
});
