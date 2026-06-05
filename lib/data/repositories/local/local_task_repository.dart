import 'package:drift/drift.dart';
import '../../../domain/models/reminder_preset.dart';
import '../../../domain/models/task.dart';
import '../../../domain/repositories/task_repository.dart';
import '../../local/database.dart';
import '../../services/reminder_coordinator.dart';

class LocalTaskRepository implements TaskRepository {
  final AppDatabase _db;
  final ReminderCoordinator? _reminders;

  LocalTaskRepository(this._db, {ReminderCoordinator? reminders})
    : _reminders = reminders;

  @override
  Stream<List<Task>> watchPending() =>
      _db.tasksDao.watchPending().map((rows) => rows.map(_rowToTask).toList());

  @override
  Stream<List<Task>> watchYesterday() => _db.tasksDao.watchYesterday().map(
    (rows) => rows.map(_rowToTask).toList(),
  );

  @override
  Stream<List<Task>> watchVencidas() =>
      _db.tasksDao.watchVencidas().map((rows) => rows.map(_rowToTask).toList());

  @override
  Stream<List<Task>> watchByIds(List<int> ids) =>
      _db.tasksDao.watchByIds(ids).map((rows) => rows.map(_rowToTask).toList());

  @override
  Future<Task?> getById(int id) async {
    final row = await _db.tasksDao.getById(id);
    return row == null ? null : _rowToTask(row);
  }

  @override
  Stream<List<Task>> watchDoneToday() => _db.tasksDao.watchDoneToday().map(
    (rows) => rows.map(_rowToTask).toList(),
  );

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
        dueDate: Value(task.dueDate),
        remindAt: Value(task.remindAt),
        reminderPreset: Value(task.reminderPreset?.toDbString()),
        completedAt: Value(task.completedAt),
      ),
    );
    await _reminders?.syncTask(row.id);
    return _rowToTask(row);
  }

  @override
  Future<void> update(Task task) async {
    final previous = await _db.tasksDao.getById(task.id);
    await _db.tasksDao.updateTask(
      TasksCompanion(
        id: Value(task.id),
        content: Value(task.content),
        status: Value(task.status.toDbString()),
        folderId: Value(task.folderId),
        expiresAt: Value(task.expiresAt),
        trashedAt: Value(task.trashedAt),
        dueDate: Value(task.dueDate),
        remindAt: Value(task.remindAt),
        reminderPreset: Value(task.reminderPreset?.toDbString()),
        completedAt: Value(task.completedAt),
      ),
    );
    await _syncLinkedCardFromTask(
      task.id,
      dueDate: task.dueDate,
      remindAt: task.remindAt,
      reminderPreset: task.reminderPreset,
    );
    if (previous?.dueDate != task.dueDate) {
      await _reminders?.taskDueDateChanged(task.id, task.dueDate);
    } else {
      await _reminders?.syncTask(task.id);
    }
  }

  @override
  Future<void> markDone(int id) async {
    await _db.tasksDao.markDone(id);
    await _reminders?.syncTask(id);
  }

  @override
  Future<void> rescueToday(int id) async {
    await _db.tasksDao.rescueToday(id);
    await _reminders?.syncTask(id);
  }

  @override
  Future<void> moveToTrash(int id) async {
    await _db.tasksDao.moveToTrash(id);
    await _reminders?.syncTask(id);
  }

  @override
  Future<void> deleteFromTrash(int id) async {
    await _db.tasksDao.deleteFromTrash(id);
    await _reminders?.syncTask(id);
  }

  @override
  Stream<List<Task>> watchTrashed() =>
      _db.tasksDao.watchTrashed().map((rows) => rows.map(_rowToTask).toList());

  @override
  Future<int> runExpiryQueries() => _db.runExpiryQueries();

  @override
  Future<void> updateDueDate(int id, DateTime? dueDate) async {
    await _db.tasksDao.updateDueDate(id, dueDate);
    final row = await _db.tasksDao.getById(id);
    await _syncLinkedCardFromTask(
      id,
      dueDate: dueDate,
      remindAt: row?.remindAt,
      reminderPreset: ReminderPreset.fromDb(row?.reminderPreset),
    );
    await _reminders?.taskDueDateChanged(id, dueDate);
  }

  @override
  Future<void> updateReminder(
    int id,
    DateTime? remindAt,
    ReminderPreset? preset,
  ) async {
    await _db.tasksDao.updateReminder(id, remindAt, preset?.toDbString());
    final row = await _db.tasksDao.getById(id);
    await _syncLinkedCardFromTask(
      id,
      dueDate: row?.dueDate,
      remindAt: remindAt,
      reminderPreset: preset,
    );
    await _reminders?.syncTask(id);
  }

  Future<void> _syncLinkedCardFromTask(
    int taskId, {
    required DateTime? dueDate,
    required DateTime? remindAt,
    required ReminderPreset? reminderPreset,
  }) async {
    final reminderPresetDb = reminderPreset?.toDbString();
    final cards = await _db.kanbanDao.getAllByOriginTaskId(taskId);
    if (cards.isEmpty) return;

    for (final card in cards) {
      final dueChanged = card.dueDate != dueDate;
      final reminderChanged =
          card.remindAt != remindAt || card.reminderPreset != reminderPresetDb;
      if (!dueChanged && !reminderChanged) continue;

      await _db.kanbanDao.updateCard(
        KanbanCardsCompanion(
          id: Value(card.id),
          dueDate: Value(dueDate),
          remindAt: Value(remindAt),
          reminderPreset: Value(reminderPresetDb),
        ),
      );

      if (dueChanged) {
        await _reminders?.cardDueDateChanged(card.id, dueDate);
      } else {
        await _reminders?.syncCard(card.id);
      }
    }
  }

  Task _rowToTask(TaskRow row) => Task(
    id: row.id,
    content: row.content,
    status: TaskStatus.fromString(row.status),
    folderId: row.folderId,
    createdAt: row.createdAt,
    expiresAt: row.expiresAt,
    trashedAt: row.trashedAt,
    dueDate: row.dueDate,
    remindAt: row.remindAt,
    reminderPreset: ReminderPreset.fromDb(row.reminderPreset),
    completedAt: row.completedAt,
  );
}
