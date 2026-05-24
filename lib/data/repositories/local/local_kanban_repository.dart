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
    int? sourceNoteId,
    String? sourceAnchor,
    int? originTaskId,
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
        sourceNoteId: Value(sourceNoteId),
        sourceAnchor: Value(sourceAnchor),
        originTaskId: Value(originTaskId),
      ),
    );
    return _rowToCard(row);
  }

  @override
  Future<void> update(KanbanCard card) async {
    await _db.kanbanDao.updateCard(
      KanbanCardsCompanion(
        id: Value(card.id),
        columnId: Value(card.columnId),
        title: Value(card.title),
        description: Value(card.description),
        priority: Value(card.priority.toDbString()),
        position: Value(card.position),
        dueDate: Value(card.dueDate),
        sourceNoteId: Value(card.sourceNoteId),
        sourceAnchor: Value(card.sourceAnchor),
        originTaskId: Value(card.originTaskId),
      ),
    );
  }

  @override
  Future<void> delete(int id) => _db.kanbanDao.deleteCard(id);

  @override
  Future<void> moveToColumn(int cardId, int newColumnId, int newPosition) =>
      _db.kanbanDao.moveToColumn(cardId, newColumnId, newPosition);

  @override
  Future<void> reorderInColumn(int columnId, List<int> orderedIds) =>
      _db.kanbanDao.reorderInColumn(columnId, orderedIds);

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
        sourceNoteId: row.sourceNoteId,
        sourceAnchor: row.sourceAnchor,
        originTaskId: row.originTaskId,
        createdAt: row.createdAt,
      );
}
