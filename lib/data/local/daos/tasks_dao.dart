import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/tasks_table.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  Stream<List<TaskRow>> watchPending() => (select(tasks)
        ..where((t) => t.status.equals('pending'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();

  Stream<List<TaskRow>> watchYesterday() => (select(tasks)
        ..where((t) => t.status.equals('yesterday'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();

  Stream<List<TaskRow>> watchVencidas() => (select(tasks)
        ..where((t) => t.status.equals('archived_failed'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();

  Stream<List<TaskRow>> watchDoneToday() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    return (select(tasks)
          ..where((t) =>
              t.status.equals('done') &
              t.completedAt.isBiggerOrEqualValue(startOfDay))
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
        .watch();
  }

  Future<List<TaskRow>> getPendingForFolder(int folderId) =>
      (select(tasks)
            ..where((t) =>
                t.status.equals('pending') &
                t.folderId.equals(folderId)))
          .get();

  Stream<List<TaskRow>> watchPendingForFolder(int folderId) =>
      (select(tasks)
            ..where((t) =>
                t.status.equals('pending') &
                t.folderId.equals(folderId)))
          .watch();

  Future<TaskRow> insertTask(TasksCompanion row) async {
    final id = await into(tasks).insert(row);
    return (select(tasks)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTask(TasksCompanion row) =>
      (update(tasks)..where((t) => t.id.equals(row.id.value))).write(row);

  Future<void> markDone(int id) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(DateTime.now()),
        ),
      );

  Future<void> rescueToday(int id) =>
      (update(tasks)..where((t) => t.id.equals(id)))
          .write(const TasksCompanion(status: Value('pending')));

  Future<void> moveToTrash(int id) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          status: const Value('trash'),
          trashedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteFromTrash(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  Stream<List<TaskRow>> watchTrashed() => (select(tasks)
        ..where((t) => t.status.equals('trash'))
        ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]))
      .watch();

  Future<void> updateDueDate(int id, DateTime? dueDate) =>
      (update(tasks)..where((t) => t.id.equals(id)))
          .write(TasksCompanion(dueDate: Value(dueDate)));
}
