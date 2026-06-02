import 'package:drift/drift.dart';

import '../../../domain/models/kanban_card.dart';
import '../../../domain/repositories/kanban_card_repository.dart';
import '../../local/database.dart';

class LocalKanbanRepository implements KanbanCardRepository {
  final AppDatabase _db;

  LocalKanbanRepository(this._db);

  @override
  Stream<List<KanbanCard>> watchByColumn(int columnId) =>
      _db.kanbanDao.watchByColumn(columnId).map((rows) => rows.map(_rowToCard).toList());

  @override
  Stream<List<KanbanCard>> watchBySpace(int labSpaceId) =>
      _db.kanbanDao.watchBySpace(labSpaceId).map((rows) => rows.map(_rowToCard).toList());

  @override
  Future<KanbanCard?> getById(int id) async {
    final row = await _db.kanbanDao.getById(id);
    return row != null ? _rowToCard(row) : null;
  }

  @override
  Future<KanbanCard> create({
    required int labSpaceId,
    required int columnId,
    required String title,
    String? description,
    CardPriority priority = CardPriority.none,
    DateTime? dueDate,
    DateTime? startDate,
    int? sourceNoteId,
    String? sourceAnchor,
    int? originTaskId,
    int? originFolderColor,
  }) async {
    final position = await _db.kanbanDao.getNextPositionInColumn(columnId);
    final row = await _db.kanbanDao.insertCard(
      KanbanCardsCompanion.insert(
        labSpaceId: labSpaceId,
        columnId: columnId,
        title: title,
        description: Value(description),
        priority: Value(priority.toDbString()),
        position: position,
        dueDate: Value(dueDate),
        startDate: Value(startDate),
        sourceNoteId: Value(sourceNoteId),
        sourceAnchor: Value(sourceAnchor),
        originTaskId: Value(originTaskId),
        originFolderColor: Value(originFolderColor),
      ),
    );
    return _rowToCard(row);
  }

  // Single source of truth for system-column side effects. Driven by the
  // column FLAGS (isTerminal / isInProgress), never by literal names, so the
  // user can rename or reassign system columns without breaking the cross-mode
  // (Fight ↔ Lab) automation. Returns the card with its date/done fields
  // adjusted and performs the matching task-side effect.
  Future<KanbanCard> _applyColumnTransition(
      KanbanCard card, KanbanColumnRow targetCol) async {
    final now = DateTime.now();
    if (targetCol.isTerminal) {
      // Entering a terminal column: stamp the real delivery date and mark the
      // linked task done. dueDate is overwritten on purpose — it records when
      // the card was actually delivered.
      if (card.originTaskDoneAt == null) {
        card = card.copyWith(originTaskDoneAt: now, dueDate: now);
        if (card.originTaskId != null) {
          await _db.tasksDao.markDone(card.originTaskId!);
        }
      }
    } else if (card.originTaskDoneAt != null) {
      // Leaving a terminal column: revert the done state on BOTH sides and
      // reopen the linked task. The card's dueDate was overwritten to the
      // delivery time on entering terminal; on reopen, re-sync it from the
      // linked task (whose original due survives markDone/unmarkDone) so card
      // and task agree again. With no task, clear it (otherwise the expiry
      // would later sweep the card to the expired column).
      card = card.copyWith(clearOriginTaskDoneAt: true);
      if (card.originTaskId != null) {
        final task = await _db.tasksDao.getById(card.originTaskId!);
        await _db.tasksDao.unmarkDone(card.originTaskId!);
        card = task?.dueDate != null
            ? card.copyWith(dueDate: task!.dueDate)
            : card.copyWith(clearDueDate: true);
      } else {
        card = card.copyWith(clearDueDate: true);
      }
    }
    // Entering the "in progress" column stamps the actual start date (fecha de
    // inicio) if not already set. A card that skips it (straight to a terminal
    // column) keeps startDate null → the timeline falls back to createdAt.
    if (targetCol.isInProgress && card.startDate == null) {
      card = card.copyWith(startDate: now);
    }
    return card;
  }

  @override
  Future<void> update(KanbanCard card) async {
    final col = await _db.labSpacesDao.getColumn(card.columnId);
    if (col != null) card = await _applyColumnTransition(card, col);
    await _db.kanbanDao.updateCard(
      KanbanCardsCompanion(
        id: Value(card.id),
        columnId: Value(card.columnId),
        title: Value(card.title),
        description: Value(card.description),
        priority: Value(card.priority.toDbString()),
        position: Value(card.position),
        dueDate: Value(card.dueDate),
        startDate: Value(card.startDate),
        sourceNoteId: Value(card.sourceNoteId),
        sourceAnchor: Value(card.sourceAnchor),
        originTaskId: Value(card.originTaskId),
        originFolderColor: Value(card.originFolderColor),
        originTaskDoneAt: Value(card.originTaskDoneAt),
      ),
    );
  }

  @override
  Future<void> delete(int id) => _db.kanbanDao.deleteCard(id);

  @override
  Future<void> deleteMultiple(List<int> ids) => _db.kanbanDao.deleteCards(ids);

  @override
  Future<void> moveToColumn(int cardId, int newColumnId, int newPosition) async {
    final row = await _db.kanbanDao.getById(cardId);
    if (row == null) return;
    var card = _rowToCard(row).copyWith(
      columnId: newColumnId,
      position: newPosition,
    );
    final col = await _db.labSpacesDao.getColumn(newColumnId);
    if (col != null) card = await _applyColumnTransition(card, col);
    await _db.kanbanDao.updateCard(
      KanbanCardsCompanion(
        id: Value(card.id),
        columnId: Value(card.columnId),
        position: Value(card.position),
        dueDate: Value(card.dueDate),
        startDate: Value(card.startDate),
        originTaskDoneAt: Value(card.originTaskDoneAt),
      ),
    );
  }

  @override
  Future<void> reorderInColumn(int columnId, List<int> orderedIds) =>
      _db.kanbanDao.reorderInColumn(columnId, orderedIds);

  @override
  Future<KanbanCard?> getByOriginTaskId(int taskId) async {
    final row = await _db.kanbanDao.getByOriginTaskId(taskId);
    return row != null ? _rowToCard(row) : null;
  }

  @override
  Stream<KanbanCard?> watchByOriginTaskId(int taskId) => _db.kanbanDao
      .watchByOriginTaskId(taskId)
      .map((row) => row != null ? _rowToCard(row) : null);

  @override
  Stream<List<KanbanCard>> watchBySourceNoteId(int noteId) =>
      _db.kanbanDao.watchBySourceNoteId(noteId).map((rows) => rows.map(_rowToCard).toList());

  KanbanCard _rowToCard(KanbanCardRow row) => KanbanCard(
        id: row.id,
        labSpaceId: row.labSpaceId,
        columnId: row.columnId,
        title: row.title,
        description: row.description,
        priority: CardPriority.fromString(row.priority),
        position: row.position,
        dueDate: row.dueDate,
        startDate: row.startDate,
        sourceNoteId: row.sourceNoteId,
        sourceAnchor: row.sourceAnchor,
        originTaskId: row.originTaskId,
        originFolderColor: row.originFolderColor,
        originTaskDoneAt: row.originTaskDoneAt,
        createdAt: row.createdAt,
      );
}
