import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/lab_space.dart';
import '../../domain/models/kanban_card.dart';
import '../../domain/models/kanban_column.dart';
import '../../domain/models/canvas_context_source.dart';
import '../../domain/repositories/task_repository.dart';
import '../../domain/repositories/kanban_card_repository.dart';
import '../../domain/repositories/lab_space_repository.dart';
import 'database_providers.dart';

final activeLabSpacesProvider = StreamProvider<List<LabSpace>>((ref) {
  return ref.watch(labSpaceRepositoryProvider).watchActive();
});

/// Unified context sources owned by a lab space (note/folder/url).
final spaceContextSourcesProvider =
    StreamProvider.family<List<CanvasContextSource>, int>((ref, spaceId) {
      return ref.watch(labSpaceRepositoryProvider).watchContextSources(spaceId);
    });

final labSpaceByIdProvider = FutureProvider.family<LabSpace?, int>((ref, id) {
  return ref.watch(labSpaceRepositoryProvider).getById(id);
});

final kanbanColumnsProvider = StreamProvider.family<List<KanbanColumn>, int>((
  ref,
  labSpaceId,
) {
  return ref.watch(labSpaceRepositoryProvider).watchColumns(labSpaceId);
});

final kanbanCardsByColumnProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, columnId) {
      return ref.watch(kanbanCardRepositoryProvider).watchByColumn(columnId);
    });

final kanbanCardsBySpaceProvider = StreamProvider.family<List<KanbanCard>, int>(
  (ref, labSpaceId) {
    return ref.watch(kanbanCardRepositoryProvider).watchBySpace(labSpaceId);
  },
);

final linkedFolderIdsProvider = FutureProvider.family<List<int>, int>((
  ref,
  spaceId,
) {
  return ref.watch(labSpaceRepositoryProvider).getLinkedFolderIds(spaceId);
});

final kanbanCardsByNoteProvider = StreamProvider.family<List<KanbanCard>, int>((
  ref,
  noteId,
) {
  return ref.watch(kanbanCardRepositoryProvider).watchBySourceNoteId(noteId);
});

/// Single entry point for completing/reopening a task with cross-mode
/// (FIGHT ↔ LAB) propagation. Completing moves the linked kanban card to the
/// terminal column; reopening moves it back to the first non-terminal,
/// non-expired column. Centralized so no UI path can flip a task's done state
/// without syncing its card (the old scattered markDone + sync pattern missed
/// a couple of spots and ignored reopening entirely).
Future<void> setTaskDone(WidgetRef ref, int taskId, {required bool done}) {
  // Resolve the repos synchronously (the ref is alive at call time) and delegate
  // to the repo-based core. The core never touches `ref`, so it's safe even if
  // the caller's widget is disposed mid-flight (e.g. the folder task bar item,
  // which disappears the moment the task is completed → "Cannot use ref after
  // the widget was disposed"). Callers that also need to UNDO later (after the
  // widget is gone) should capture the repos themselves and call
  // [setTaskDoneWith] directly.
  return setTaskDoneWith(
    taskRepo: ref.read(taskRepositoryProvider),
    kanbanRepo: ref.read(kanbanCardRepositoryProvider),
    labRepo: ref.read(labSpaceRepositoryProvider),
    taskId: taskId,
    done: done,
  );
}

/// Repo-based core of [setTaskDone] — holds no widget reference, so it survives
/// the caller's disposal (used for undo from a transient widget).
Future<void> setTaskDoneWith({
  required TaskRepository taskRepo,
  required KanbanCardRepository kanbanRepo,
  required LabSpaceRepository labRepo,
  required int taskId,
  required bool done,
}) async {
  // Flip the task itself first — must happen even with no linked card.
  if (done) {
    await taskRepo.markDone(taskId);
  } else {
    await taskRepo.rescueToday(taskId);
  }

  final cards = await kanbanRepo.getAllByOriginTaskId(taskId);
  for (final card in cards) {
    final columns = await labRepo.getColumns(card.labSpaceId);
    final target = done ? _terminalColumn(columns) : _firstOpenColumn(columns);
    if (target == null || target.id == card.columnId) continue;

    // update() runs the column transition (stamps dueDate/originTaskDoneAt on
    // entering terminal, clears them + reopens the task on leaving) — single
    // source of truth, so we only set the column here.
    await kanbanRepo.update(card.copyWith(columnId: target.id));
  }
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
