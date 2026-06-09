import '../models/kanban_card.dart';
import '../models/reminder_preset.dart';

abstract class KanbanCardRepository {
  Stream<List<KanbanCard>> watchByColumn(int columnId);
  Stream<List<KanbanCard>> watchBySpace(int labSpaceId);
  Future<KanbanCard?> getById(int id);
  Future<KanbanCard> create({
    required int labSpaceId,
    required int columnId,
    required String title,
    String? description,
    CardPriority priority,
    DateTime? dueDate,
    DateTime? remindAt,
    ReminderPreset? reminderPreset,
    DateTime? startDate,
    int? sourceNoteId,
    String? sourceAnchor,
    int? originTaskId,
    int? originFolderColor,
  });
  Future<void> update(KanbanCard card);
  Future<void> updateReminder(
    int id,
    DateTime? remindAt,
    ReminderPreset? preset,
  );
  Future<void> delete(int id);
  Future<void> deleteMultiple(List<int> ids);

  /// Re-insert a just-deleted card faithfully (same id and ALL fields, incl.
  /// [KanbanCard.originTaskDoneAt] / [KanbanCard.createdAt] / position) and
  /// re-sync its reminder. Powers the "DESHACER" snackbar; does NOT run column
  /// transitions (it's a verbatim restore of the prior state).
  Future<void> restore(KanbanCard card);
  Future<KanbanCard?> getByOriginTaskId(int taskId);
  Future<List<KanbanCard>> getAllByOriginTaskId(int taskId);
  Stream<KanbanCard?> watchByOriginTaskId(int taskId);
  Future<void> moveToColumn(int cardId, int newColumnId, int newPosition);
  Future<void> reorderInColumn(int columnId, List<int> orderedIds);
  Stream<List<KanbanCard>> watchBySourceNoteId(int noteId);
}
