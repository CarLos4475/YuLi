import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/kanban_cards_table.dart';

part 'kanban_dao.g.dart';

@DriftAccessor(tables: [KanbanCards])
class KanbanDao extends DatabaseAccessor<AppDatabase> with _$KanbanDaoMixin {
  KanbanDao(super.db);

  Stream<List<KanbanCardRow>> watchByColumn(int columnId) =>
      (select(kanbanCards)
            ..where((c) => c.columnId.equals(columnId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .watch();

  Stream<List<KanbanCardRow>> watchBySpace(int labSpaceId) =>
      (select(kanbanCards)
            ..where((c) => c.labSpaceId.equals(labSpaceId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .watch();

  Future<KanbanCardRow?> getById(int id) =>
      (select(kanbanCards)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<KanbanCardRow> insertCard(KanbanCardsCompanion row) async {
    final id = await into(kanbanCards).insert(row);
    return (select(kanbanCards)..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> updateCard(KanbanCardsCompanion row) =>
      (update(kanbanCards)..where((c) => c.id.equals(row.id.value)))
          .write(row);

  Future<void> deleteCard(int id) =>
      (delete(kanbanCards)..where((c) => c.id.equals(id))).go();

  Future<void> deleteCards(List<int> ids) =>
      (delete(kanbanCards)..where((c) => c.id.isIn(ids))).go();

  Future<void> moveToColumn(
      int cardId, int newColumnId, int newPosition) async {
    await (update(kanbanCards)..where((c) => c.id.equals(cardId))).write(
      KanbanCardsCompanion(
        columnId: Value(newColumnId),
        position: Value(newPosition),
      ),
    );
  }

  Future<void> reorderInColumn(int columnId, List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(kanbanCards)
              ..where((c) => c.id.equals(orderedIds[i])))
            .write(KanbanCardsCompanion(position: Value(i)));
      }
    });
  }

  Future<int> getNextPositionInColumn(int columnId) async {
    final count = await (select(kanbanCards)
          ..where((c) => c.columnId.equals(columnId)))
        .get();
    return count.length;
  }

  Stream<List<KanbanCardRow>> watchBySourceNoteId(int noteId) =>
      (select(kanbanCards)
            ..where((c) => c.sourceNoteId.equals(noteId)))
          .watch();

  Future<KanbanCardRow?> getByOriginTaskId(int taskId) =>
      (select(kanbanCards)..where((c) => c.originTaskId.equals(taskId)))
          .getSingleOrNull();
}
