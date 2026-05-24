import 'package:drift/drift.dart';
import '../../../domain/models/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../local/database.dart';

class LocalTaskRepository implements TaskRepository {
  final AppDatabase _db;

  LocalTaskRepository(this._db);

  @override
  Stream<List<Task>> watchPending() =>
      _db.tasksDao.watchPending().map((rows) => rows.map(_rowToTask).toList());

  @override
  Stream<List<Task>> watchYesterday() =>
      _db.tasksDao.watchYesterday().map((rows) => rows.map(_rowToTask).toList());

  @override
  Stream<List<Task>> watchDoneToday() =>
      _db.tasksDao.watchDoneToday().map((rows) => rows.map(_rowToTask).toList());

  @override
  Future<List<Task>> getPendingForFolder(int folderId) async {
    final rows = await _db.tasksDao.getPendingForFolder(folderId);
    return rows.map(_rowToTask).toList();
  }

  @override
  Stream<List<Task>> watchPendingForFolder(int folderId) {
    return _db.tasksDao
        .watchPendingForFolder(folderId)
        .map((rows) => rows.map(_rowToTask).toList());
  }

  @override
  Future<Task> save(Task task) async {
    final row = await _db.tasksDao.insertTask(
      TasksCompanion.insert(
        content: task.content,
        status: task.status.toDbString(),
        folderId: Value(task.folderId),
        createdAt: Value(task.createdAt),
        expiresAt: task.expiresAt,
        trashedAt: Value(task.trashedAt),
      ),
    );
    return _rowToTask(row);
  }

  @override
  Future<void> update(Task task) async {
    await _db.tasksDao.updateTask(
      TasksCompanion(
        id: Value(task.id),
        content: Value(task.content),
        status: Value(task.status.toDbString()),
        folderId: Value(task.folderId),
        expiresAt: Value(task.expiresAt),
        trashedAt: Value(task.trashedAt),
      ),
    );
  }

  @override
  Future<void> markDone(int id) => _db.tasksDao.markDone(id);

  @override
  Future<void> rescueToday(int id) => _db.tasksDao.rescueToday(id);

  @override
  Future<void> moveToTrash(int id) => _db.tasksDao.moveToTrash(id);

  @override
  Future<void> deleteFromTrash(int id) => _db.tasksDao.deleteFromTrash(id);

  @override
  Stream<List<Task>> watchTrashed() =>
      _db.tasksDao.watchTrashed().map((rows) => rows.map(_rowToTask).toList());

  @override
  Future<int> runExpiryQueries() => _db.runExpiryQueries();

  Task _rowToTask(TaskRow row) => Task(
        id: row.id,
        content: row.content,
        status: TaskStatus.fromString(row.status),
        folderId: row.folderId,
        createdAt: row.createdAt,
        expiresAt: row.expiresAt,
        trashedAt: row.trashedAt,
      );
}
