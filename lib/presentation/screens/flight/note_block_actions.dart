// Helpers that translate UI gestures on a TareasBlock into the right
// repository calls. Tasks created from notes live in the same pool as
// FIGHT, propagating done/trash globally via Task.status.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';

class NoteBlockActions {
  final WidgetRef ref;
  final int noteId;
  final int? folderId;

  const NoteBlockActions({
    required this.ref,
    required this.noteId,
    this.folderId,
  });

  /// Create a real Task from a TareasBlock + link it (note_task_links +
  /// block.taskIds payload). Inherits folder from note.
  Future<Task> createTaskInBlock(
      TareasBlock block, String content) async {
    final now = DateTime.now();
    final task = await ref.read(taskRepositoryProvider).save(
          Task(
            id: 0,
            content: content,
            status: TaskStatus.pending,
            folderId: folderId,
            createdAt: now,
            expiresAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
          ),
        );
    await ref.read(noteRepositoryProvider).linkTask(noteId, task.id);
    final updatedIds = [...block.taskIds, task.id];
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(block.id, {'taskIds': updatedIds});
    return task;
  }

  /// Toggle done globally. Propagates to FIGHT and the linked kanban card
  /// (moves it to/from the terminal column) in both directions.
  Future<void> toggleDone(Task task) =>
      setTaskDone(ref, task.id, done: task.status != TaskStatus.done);

  /// Link the task to a lab space's first non-terminal column (Backlog when
  /// present). Creates a KanbanCard with `originTaskId` so the link is
  /// bidirectional.
  Future<KanbanCard?> linkTaskToSpace(Task task, int labSpaceId) async {
    final existing =
        await ref.read(kanbanCardRepositoryProvider).getByOriginTaskId(task.id);
    if (existing != null) return existing;

    final labRepo = ref.read(labSpaceRepositoryProvider);
    final columns = await labRepo.getColumns(labSpaceId);
    if (columns.isEmpty) return null;
    final backlog = columns.firstWhere(
      (c) => c.name == 'Backlog' || c.name.toLowerCase() == 'backlog',
      orElse: () => columns.firstWhere((c) => !c.isTerminal && !c.isExpired,
          orElse: () => columns.first),
    );

    return ref.read(kanbanCardRepositoryProvider).create(
          labSpaceId: labSpaceId,
          columnId: backlog.id,
          title: task.content,
          dueDate: task.dueDate,
          originTaskId: task.id,
        );
  }

  /// Unlink only: removes from block payload + note_task_links. Task entity
  /// stays alive in FIGHT.
  Future<void> unlinkFromBlock(TareasBlock block, Task task) async {
    await ref.read(noteRepositoryProvider).unlinkTask(noteId, task.id);
    final updatedIds = block.taskIds.where((id) => id != task.id).toList();
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(block.id, {'taskIds': updatedIds});
  }

  /// Hard delete: moves task to trash globally. note_task_links rows cascade
  /// when the row is finally hard-deleted (7d trash grace period).
  Future<void> hardDeleteTask(TareasBlock block, Task task) async {
    await ref.read(taskRepositoryProvider).moveToTrash(task.id);
    final updatedIds = block.taskIds.where((id) => id != task.id).toList();
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(block.id, {'taskIds': updatedIds});
  }
}
