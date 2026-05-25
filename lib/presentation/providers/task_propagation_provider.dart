import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_providers.dart';

class TaskPropagation {
  final bool hasNoteLinks;
  final int noteCount;
  final String? spaceName;

  const TaskPropagation({
    required this.hasNoteLinks,
    required this.noteCount,
    required this.spaceName,
  });

  static const empty =
      TaskPropagation(hasNoteLinks: false, noteCount: 0, spaceName: null);
}

/// Aggregates a task's links: how many notes reference it + which lab space
/// (if any) holds a kanban card with `origin_task_id == task.id`.
final taskPropagationProvider =
    StreamProvider.family<TaskPropagation, int>((ref, taskId) async* {
  final noteRepo = ref.watch(noteRepositoryProvider);
  final kanbanRepo = ref.watch(kanbanCardRepositoryProvider);
  final labRepo = ref.watch(labSpaceRepositoryProvider);

  await for (final noteIds in noteRepo.watchLinkedNoteIds(taskId)) {
    final card = await kanbanRepo.getByOriginTaskId(taskId);
    String? spaceName;
    if (card != null) {
      final space = await labRepo.getById(card.labSpaceId);
      spaceName = space?.name;
    }
    yield TaskPropagation(
      hasNoteLinks: noteIds.isNotEmpty,
      noteCount: noteIds.length,
      spaceName: spaceName,
    );
  }
});
