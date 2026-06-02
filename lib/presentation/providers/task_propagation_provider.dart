import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/kanban_card.dart';
import 'database_providers.dart';
import 'lab_space_providers.dart';

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

final _linkedNoteIdsProvider = StreamProvider.family<List<int>, int>(
    (ref, taskId) => ref.watch(noteRepositoryProvider).watchLinkedNoteIds(taskId));

final _cardByOriginTaskProvider = StreamProvider.family<KanbanCard?, int>(
    (ref, taskId) =>
        ref.watch(kanbanCardRepositoryProvider).watchByOriginTaskId(taskId));

/// Aggregates a task's links: how many notes reference it + which lab space
/// (if any) holds a kanban card with `origin_task_id == task.id`. Fully
/// reactive — refreshes when note links OR the linked card change (the card
/// part used to be a one-shot read, so the badge could go stale).
final taskPropagationProvider =
    Provider.family<AsyncValue<TaskPropagation>, int>((ref, taskId) {
  final noteIds = ref.watch(_linkedNoteIdsProvider(taskId)).valueOrNull;
  final card = ref.watch(_cardByOriginTaskProvider(taskId)).valueOrNull;
  String? spaceName;
  if (card != null) {
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull;
    if (spaces != null) {
      for (final s in spaces) {
        if (s.id == card.labSpaceId) {
          spaceName = s.name;
          break;
        }
      }
    }
  }
  return AsyncValue.data(TaskPropagation(
    hasNoteLinks: (noteIds ?? const []).isNotEmpty,
    noteCount: noteIds?.length ?? 0,
    spaceName: spaceName,
  ));
});
