import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/lab_spaces_table.dart';
import '../tables/kanban_columns_table.dart';
import '../tables/space_context_sources_table.dart';

part 'lab_spaces_dao.g.dart';

@DriftAccessor(tables: [LabSpaces, KanbanColumns, SpaceContextSources])
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

  // ─── Space context sources (unified: note/folder/url) ────────────────────
  // Replaces the old space_folder_links: a linked folder is just a source of
  // kind 'folder'. Sources of kind 'note'/'url' feed the space AI chat.

  Future<void> addSpaceSource(
    int labSpaceId,
    String kind,
    String ref, {
    String? label,
    DateTime? fetchedAt,
  }) =>
      into(spaceContextSources).insert(
        SpaceContextSourcesCompanion.insert(
          labSpaceId: labSpaceId,
          kind: kind,
          ref: ref,
          label: Value(label),
          fetchedAt: Value(fetchedAt),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> removeSpaceSource(int id) =>
      (delete(spaceContextSources)..where((s) => s.id.equals(id))).go();

  Future<void> updateSpaceSourceFetch(
    int id, {
    String? label,
    DateTime? fetchedAt,
  }) =>
      (update(spaceContextSources)..where((s) => s.id.equals(id))).write(
        SpaceContextSourcesCompanion(
          label: Value(label),
          fetchedAt: Value(fetchedAt),
        ),
      );

  Stream<List<SpaceContextSourceRow>> watchSpaceSources(int labSpaceId) =>
      (select(spaceContextSources)
            ..where((s) => s.labSpaceId.equals(labSpaceId))
            ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
          .watch();

  Future<List<SpaceContextSourceRow>> getSpaceSources(int labSpaceId) =>
      (select(spaceContextSources)
            ..where((s) => s.labSpaceId.equals(labSpaceId))
            ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
          .get();

  // Folder links — now expressed as 'folder' sources on the unified table.
  Future<void> linkFolder(int labSpaceId, int folderId) =>
      addSpaceSource(labSpaceId, 'folder', folderId.toString());

  Future<void> unlinkFolder(int labSpaceId, int folderId) =>
      (delete(spaceContextSources)..where((s) =>
            s.labSpaceId.equals(labSpaceId) &
            s.kind.equals('folder') &
            s.ref.equals(folderId.toString()))).go();

  Future<List<int>> getLinkedFolderIds(int labSpaceId) async {
    final rows = await (select(spaceContextSources)..where(
      (s) => s.labSpaceId.equals(labSpaceId) & s.kind.equals('folder'),
    )).get();
    return rows.map((r) => int.tryParse(r.ref)).whereType<int>().toList();
  }

  Future<List<int>> getLinkedSpaceIds(int folderId) async {
    final rows = await (select(spaceContextSources)..where(
      (s) => s.kind.equals('folder') & s.ref.equals(folderId.toString()),
    )).get();
    return rows.map((r) => r.labSpaceId).toSet().toList();
  }

  Stream<List<int>> watchLinkedSpaceIds(int folderId) =>
      (select(spaceContextSources)..where(
        (s) => s.kind.equals('folder') & s.ref.equals(folderId.toString()),
      )).watch().map(
        (rows) => rows.map((r) => r.labSpaceId).toSet().toList(),
      );
}
