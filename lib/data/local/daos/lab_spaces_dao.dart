import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/lab_spaces_table.dart';
import '../tables/kanban_columns_table.dart';
import '../tables/space_folder_links_table.dart';

part 'lab_spaces_dao.g.dart';

@DriftAccessor(tables: [LabSpaces, KanbanColumns, SpaceFolderLinks])
class LabSpacesDao extends DatabaseAccessor<AppDatabase>
    with _$LabSpacesDaoMixin {
  LabSpacesDao(super.db);

  Stream<List<LabSpaceRow>> watchActive() => (select(labSpaces)
        ..where((s) => s.deletedAt.isNull())
        ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
      .watch();

  Future<List<LabSpaceRow>> getActive() =>
      (select(labSpaces)..where((s) => s.deletedAt.isNull())).get();

  Future<LabSpaceRow?> getById(int id) =>
      (select(labSpaces)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<LabSpaceRow> insertSpace(LabSpacesCompanion row) async {
    final id = await into(labSpaces).insert(row);
    return (select(labSpaces)..where((s) => s.id.equals(id))).getSingle();
  }

  Future<void> updateSpace(LabSpacesCompanion row) =>
      (update(labSpaces)..where((s) => s.id.equals(row.id.value)))
          .write(row);

  Future<void> softDelete(int id) =>
      (update(labSpaces)..where((s) => s.id.equals(id)))
          .write(LabSpacesCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(int id) =>
      (update(labSpaces)..where((s) => s.id.equals(id)))
          .write(const LabSpacesCompanion(deletedAt: Value(null)));

  Future<void> hardDelete(int id) =>
      (delete(labSpaces)..where((s) => s.id.equals(id))).go();

  Stream<List<LabSpaceRow>> watchDeleted() => (select(labSpaces)
        ..where((s) => s.deletedAt.isNotNull())
        ..orderBy([(s) => OrderingTerm.desc(s.deletedAt)]))
      .watch();

  // Columns
  Stream<List<KanbanColumnRow>> watchColumns(int labSpaceId) =>
      (select(kanbanColumns)
            ..where((c) => c.labSpaceId.equals(labSpaceId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .watch();

  Future<List<KanbanColumnRow>> getColumns(int labSpaceId) =>
      (select(kanbanColumns)
            ..where((c) => c.labSpaceId.equals(labSpaceId))
            ..orderBy([(c) => OrderingTerm.asc(c.position)]))
          .get();

  Future<KanbanColumnRow?> getColumn(int columnId) =>
      (select(kanbanColumns)..where((c) => c.id.equals(columnId))).getSingleOrNull();

  Future<KanbanColumnRow> insertColumn(KanbanColumnsCompanion row) async {
    final id = await into(kanbanColumns).insert(row);
    return (select(kanbanColumns)..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> updateColumn(KanbanColumnsCompanion row) =>
      (update(kanbanColumns)..where((c) => c.id.equals(row.id.value)))
          .write(row);

  Future<void> deleteColumn(int columnId) =>
      (delete(kanbanColumns)..where((c) => c.id.equals(columnId))).go();

  Future<void> reorderColumns(int labSpaceId, List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(kanbanColumns)
              ..where((c) => c.id.equals(orderedIds[i])))
            .write(KanbanColumnsCompanion(position: Value(i)));
      }
    });
  }

  // Folder links
  Future<void> linkFolder(int labSpaceId, int folderId) =>
      into(spaceFolderLinks).insertOnConflictUpdate(
        SpaceFolderLinksCompanion.insert(
          labSpaceId: labSpaceId,
          folderId: folderId,
        ),
      );

  Future<void> unlinkFolder(int labSpaceId, int folderId) =>
      (delete(spaceFolderLinks)
            ..where((l) =>
                l.labSpaceId.equals(labSpaceId) &
                l.folderId.equals(folderId)))
          .go();

  Future<List<int>> getLinkedFolderIds(int labSpaceId) async {
    final rows = await (select(spaceFolderLinks)
          ..where((l) => l.labSpaceId.equals(labSpaceId)))
        .get();
    return rows.map((r) => r.folderId).toList();
  }

  Future<List<int>> getLinkedSpaceIds(int folderId) async {
    final rows = await (select(spaceFolderLinks)
          ..where((l) => l.folderId.equals(folderId)))
        .get();
    return rows.map((r) => r.labSpaceId).toList();
  }

  Stream<List<int>> watchLinkedSpaceIds(int folderId) =>
      (select(spaceFolderLinks)
            ..where((l) => l.folderId.equals(folderId)))
          .watch()
          .map((rows) => rows.map((r) => r.labSpaceId).toList());
}
