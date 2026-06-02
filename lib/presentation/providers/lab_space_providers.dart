import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/lab_space.dart';
import '../../domain/models/kanban_card.dart';
import '../../domain/models/kanban_column.dart';
import 'database_providers.dart';

final activeLabSpacesProvider = StreamProvider<List<LabSpace>>((ref) {
  return ref.watch(labSpaceRepositoryProvider).watchActive();
});

final labSpaceByIdProvider = FutureProvider.family<LabSpace?, int>((ref, id) {
  return ref.watch(labSpaceRepositoryProvider).getById(id);
});

final kanbanColumnsProvider =
    StreamProvider.family<List<KanbanColumn>, int>((ref, labSpaceId) {
  return ref.watch(labSpaceRepositoryProvider).watchColumns(labSpaceId);
});

final kanbanCardsByColumnProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, columnId) {
  return ref.watch(kanbanCardRepositoryProvider).watchByColumn(columnId);
});

final kanbanCardsBySpaceProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, labSpaceId) {
  return ref.watch(kanbanCardRepositoryProvider).watchBySpace(labSpaceId);
});

final linkedFolderIdsProvider = FutureProvider.family<List<int>, int>((ref, spaceId) {
  return ref.watch(labSpaceRepositoryProvider).getLinkedFolderIds(spaceId);
});

final kanbanCardsByNoteProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, noteId) {
  return ref.watch(kanbanCardRepositoryProvider).watchBySourceNoteId(noteId);
});

/// Single entry point for completing/reopening a task with cross-mode
/// (FIGHT ↔ LAB) propagation. Completing moves the linked kanban card to the
/// terminal column; reopening moves it back to the first non-terminal,
/// non-expired column. Centralized so no UI path can flip a task's done state
/// without syncing its card (the old scattered markDone + sync pattern missed
/// a couple of spots and ignored reopening entirely).
Future<void> setTaskDone(WidgetRef ref, int taskId,
    {required bool done}) async {
  final taskRepo = ref.read(taskRepositoryProvider);
  // Flip the task itself first — must happen even with no linked card.
  if (done) {
    await taskRepo.markDone(taskId);
  } else {
    await taskRepo.rescueToday(taskId);
  }

  final kanbanRepo = ref.read(kanbanCardRepositoryProvider);
  final card = await kanbanRepo.getByOriginTaskId(taskId);
  if (card == null) return;

  final columns =
      await ref.read(labSpaceRepositoryProvider).getColumns(card.labSpaceId);
  final target = done ? _terminalColumn(columns) : _firstOpenColumn(columns);
  if (target == null || target.id == card.columnId) return;

  // update() runs the column transition (stamps dueDate/originTaskDoneAt on
  // entering terminal, clears them + reopens the task on leaving) — single
  // source of truth, so we only set the column here.
  await kanbanRepo.update(card.copyWith(columnId: target.id));
}

KanbanColumn? _terminalColumn(List<KanbanColumn> cols) {
  for (final c in cols) {
    if (c.isTerminal) return c;
  }
  for (final c in cols) {
    if (c.name == 'Entregado') return c;
  }
  return null;
}

KanbanColumn? _firstOpenColumn(List<KanbanColumn> cols) {
  for (final c in cols) {
    if (!c.isTerminal && !c.isExpired) return c;
  }
  return null;
}
