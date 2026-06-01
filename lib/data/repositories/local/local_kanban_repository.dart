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

  @override
  Future<void> update(KanbanCard card) async {
    final col = await _db.labSpacesDao.getColumn(card.columnId);
    if (col != null && col.name == 'Entregado') {
      if (card.originTaskDoneAt == null) {
        final now = DateTime.now();
        card = card.copyWith(originTaskDoneAt: now, dueDate: now);
        if (card.originTaskId != null) {
          await _db.tasksDao.markDone(card.originTaskId!);
        }
      }
    } else if (card.originTaskDoneAt != null) {
      card = card.copyWith(clearOriginTaskDoneAt: true);
    }
    // "En Proceso" is a system column: entering it stamps the actual start
    // (fecha de inicio) if not already set. A card that skips it (straight to
    // Entregado) keeps startDate null → the timeline falls back to createdAt
    // (fecha de agregado).
    if (col != null && col.name == 'En Proceso' && card.startDate == null) {
      card = card.copyWith(startDate: DateTime.now());
    }
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
    final card = await _db.kanbanDao.getById(cardId);
    if (card == null) return;
    final col = await _db.labSpacesDao.getColumn(newColumnId);
    if (col != null && col.name == 'Entregado') {
      if (card.originTaskDoneAt == null) {
        final now = DateTime.now();
        await _db.kanbanDao.updateCard(
          KanbanCardsCompanion(
            id: Value(cardId),
            columnId: Value(newColumnId),
            position: Value(newPosition),
            dueDate: Value(now),
            originTaskDoneAt: Value(now),
          ),
        );
        if (card.originTaskId != null) {
          await _db.tasksDao.markDone(card.originTaskId!);
        }
        return;
      }
    } else if (card.originTaskDoneAt != null) {
      await _db.kanbanDao.updateCard(
        KanbanCardsCompanion(
          id: Value(cardId),
          columnId: Value(newColumnId),
          position: Value(newPosition),
          originTaskDoneAt: Value(null),
        ),
      );
      return;
    } else if (col != null &&
        col.name == 'En Proceso' &&
        card.startDate == null) {
      // Entering "En Proceso" stamps the actual start date (fecha de inicio).
      await _db.kanbanDao.updateCard(
        KanbanCardsCompanion(
          id: Value(cardId),
          columnId: Value(newColumnId),
          position: Value(newPosition),
          startDate: Value(DateTime.now()),
        ),
      );
      return;
    }
    await _db.kanbanDao.moveToColumn(cardId, newColumnId, newPosition);
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
