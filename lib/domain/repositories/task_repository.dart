import '../models/task.dart';

abstract class TaskRepository {
  Stream<List<Task>> watchPending();
  Stream<List<Task>> watchYesterday();
  Stream<List<Task>> watchVencidas();
  Stream<List<Task>> watchDoneToday();
  Stream<List<Task>> watchByIds(List<int> ids);
  Future<Task?> getById(int id);
  Future<List<Task>> getPendingForFolder(int folderId);
  Stream<List<Task>> watchPendingForFolder(int folderId);
  Future<Task> save(Task task);
  Future<void> update(Task task);
  Future<void> markDone(int id);
  Future<void> rescueToday(int id);
  Future<void> moveToTrash(int id);
  Future<void> deleteFromTrash(int id);
  Future<int> runExpiryQueries();
  Stream<List<Task>> watchTrashed();
  Future<void> updateDueDate(int id, DateTime? dueDate);
}
