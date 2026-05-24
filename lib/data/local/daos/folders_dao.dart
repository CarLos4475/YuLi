import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/folders_table.dart';

part 'folders_dao.g.dart';

@DriftAccessor(tables: [Folders])
class FoldersDao extends DatabaseAccessor<AppDatabase> with _$FoldersDaoMixin {
  FoldersDao(super.db);

  Stream<List<FolderRow>> watchActive() => (select(folders)
        ..where((f) => f.deletedAt.isNull())
        ..orderBy([(f) => OrderingTerm.asc(f.createdAt)]))
      .watch();

  Future<List<FolderRow>> getActive() =>
      (select(folders)..where((f) => f.deletedAt.isNull())).get();

  Future<FolderRow?> getById(int id) =>
      (select(folders)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<FolderRow> insertFolder(FoldersCompanion row) async {
    final id = await into(folders).insert(row);
    return (select(folders)..where((f) => f.id.equals(id))).getSingle();
  }

  Future<void> updateFolder(FoldersCompanion row) =>
      (update(folders)..where((f) => f.id.equals(row.id.value))).write(row);

  Future<void> softDelete(int id) =>
      (update(folders)..where((f) => f.id.equals(id)))
          .write(FoldersCompanion(deletedAt: Value(DateTime.now())));

  Future<void> restore(int id) =>
      (update(folders)..where((f) => f.id.equals(id)))
          .write(const FoldersCompanion(deletedAt: Value(null)));

  Future<void> hardDelete(int id) =>
      (delete(folders)..where((f) => f.id.equals(id))).go();

  Stream<List<FolderRow>> watchDeleted() => (select(folders)
        ..where((f) => f.deletedAt.isNotNull())
        ..orderBy([(f) => OrderingTerm.desc(f.deletedAt)]))
      .watch();
}
