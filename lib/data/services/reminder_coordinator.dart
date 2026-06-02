import 'package:drift/drift.dart';

import '../../domain/models/reminder_preset.dart';
import '../../domain/services/reminder_scheduler.dart';
import '../local/database.dart';
import 'reminder_preferences.dart';

class ReminderCoordinator {
  static const taskBase = 1000000;
  static const cardBase = 2000000;
  static const summaryBase = 3000000;
  static const _summaryDays = 7;
  static const _summaryCancelWindow = 14;

  final AppDatabase _db;
  final ReminderScheduler _scheduler;
  final ReminderPreferences _prefs;

  ReminderCoordinator(this._db, this._scheduler, this._prefs);

  Stream<String> get taps => _scheduler.taps;

  Future<void> initialize() => _scheduler.initialize();

  Future<bool> requestNotificationPermission() =>
      _scheduler.requestNotificationPermission();

  Future<bool> requestExactPermission() => _scheduler.requestExactPermission();

  Future<bool> areNotificationsEnabled() =>
      _scheduler.areNotificationsEnabled();

  Future<void> openNotificationSettings() =>
      _scheduler.openNotificationSettings();

  Future<void> setDailySummaryEnabled(bool enabled) async {
    await _prefs.setDailySummaryEnabled(enabled);
    await syncDailySummary();
  }

  Future<void> setDailySummaryTime(int hour, int minute) async {
    await _prefs.setDailySummaryTime(hour, minute);
    await syncDailySummary();
  }

  Future<void> setExactRemindersEnabled(bool enabled) async {
    if (enabled) {
      final granted = await _scheduler.requestExactPermission();
      await _prefs.setExactRemindersEnabled(granted);
    } else {
      await _prefs.setExactRemindersEnabled(false);
    }
    await reconcileAll();
  }

  Future<void> reconcileAll() async {
    await initialize();
    final live = <int>{};
    final taskRows =
        await (_db.select(_db.tasks)
          ..where((t) => t.remindAt.isNotNull())).get();
    for (final task in taskRows) {
      final id = await _syncTaskRow(task);
      if (id != null) live.add(id);
    }
    final cardRows =
        await (_db.select(_db.kanbanCards)
          ..where((c) => c.remindAt.isNotNull())).get();
    for (final card in cardRows) {
      final id = await _syncCardRow(card);
      if (id != null) live.add(id);
    }
    await syncDailySummary();
    await _cancelOrphans(live);
  }

  // Cancela notificaciones programadas para tareas/cards que ya no existen o
  // dejaron de tener recordatorio (p.ej. borrados en cascada de un space/folder,
  // que no pasan por syncTask/syncCard). Solo toca nuestro id-space; el rango de
  // resumen lo gestiona [syncDailySummary] aparte.
  Future<void> _cancelOrphans(Set<int> live) async {
    final pending = await _scheduler.pendingIds();
    for (final id in pending) {
      if (id < taskBase || id >= summaryBase) continue;
      if (live.contains(id)) continue;
      await _scheduler.cancel(id);
    }
  }

  Future<void> syncAfterMutation() => syncDailySummary();

  Future<void> syncTask(int id) async {
    final row = await _db.tasksDao.getById(id);
    if (row == null) {
      await _scheduler.cancel(taskId(id));
      await syncDailySummary();
      return;
    }
    await _syncTaskRow(row);
    await syncDailySummary();
  }

  Future<void> syncCard(int id) async {
    final row = await _db.kanbanDao.getById(id);
    if (row == null) {
      await _scheduler.cancel(cardId(id));
      await syncDailySummary();
      return;
    }
    await _syncCardRow(row);
    await syncDailySummary();
  }

  Future<void> taskDueDateChanged(int id, DateTime? dueDate) async {
    final row = await _db.tasksDao.getById(id);
    if (row == null) return;
    final preset = ReminderPreset.fromDb(row.reminderPreset);
    if (preset == null) {
      await syncTask(id);
      return;
    }
    if (preset == ReminderPreset.custom) {
      await syncTask(id);
      return;
    }
    final remindAt =
        dueDate == null ? null : reminderTimeForPreset(preset, dueDate);
    await _db.tasksDao.updateReminder(
      id,
      remindAt,
      remindAt == null ? null : preset.toDbString(),
    );
    await syncTask(id);
  }

  Future<void> cardDueDateChanged(int id, DateTime? dueDate) async {
    final row = await _db.kanbanDao.getById(id);
    if (row == null) return;
    final preset = ReminderPreset.fromDb(row.reminderPreset);
    if (preset == null) {
      await syncCard(id);
      return;
    }
    if (preset == ReminderPreset.custom) {
      await syncCard(id);
      return;
    }
    final remindAt =
        dueDate == null ? null : reminderTimeForPreset(preset, dueDate);
    await _db.kanbanDao.updateReminder(
      id,
      remindAt,
      remindAt == null ? null : preset.toDbString(),
    );
    await syncCard(id);
  }

  Future<int?> _syncTaskRow(TaskRow row) async {
    final at = row.remindAt;
    if (row.status == 'done' ||
        row.status == 'trash' ||
        at == null ||
        !at.isAfter(DateTime.now())) {
      await _scheduler.cancel(taskId(row.id));
      return null;
    }
    final id = taskId(row.id);
    await _scheduler.schedule(
      ReminderRequest(
        id: id,
        title: 'YuLi · Fight',
        body: _trim(row.content),
        scheduledAt: at,
        payload: 'task:${row.id}',
        exact: await _prefs.exactRemindersEnabled(),
      ),
    );
    return id;
  }

  Future<int?> _syncCardRow(KanbanCardRow row) async {
    final at = row.remindAt;
    final col = await _db.labSpacesDao.getColumn(row.columnId);
    if (row.originTaskDoneAt != null ||
        col?.isTerminal == true ||
        col?.isExpired == true ||
        at == null ||
        !at.isAfter(DateTime.now())) {
      await _scheduler.cancel(cardId(row.id));
      return null;
    }
    final id = cardId(row.id);
    await _scheduler.schedule(
      ReminderRequest(
        id: id,
        title: 'YuLi · Lab',
        body: _trim(row.title),
        scheduledAt: at,
        payload: 'card:${row.labSpaceId}:${row.id}',
        exact: await _prefs.exactRemindersEnabled(),
      ),
    );
    return id;
  }

  Future<void> syncDailySummary() async {
    for (var i = 0; i < _summaryCancelWindow; i++) {
      await _scheduler.cancel(summaryBase + i);
    }
    if (!await _prefs.dailySummaryEnabled()) return;
    final time = await _prefs.dailySummaryTime();
    final now = DateTime.now();
    var scheduled = 0;
    for (var i = 0; i < _summaryDays; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (!at.isAfter(now)) continue;
      final summary = await _summaryFor(day);
      await _scheduler.schedule(
        ReminderRequest(
          id: summaryBase + scheduled,
          title: 'YuLi · Resumen',
          body: summary,
          scheduledAt: at,
          payload: 'summary',
          exact: await _prefs.exactRemindersEnabled(),
        ),
      );
      scheduled++;
    }
  }

  Future<String> _summaryFor(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final now = DateTime.now();
    final fightRows =
        await (_db.select(_db.tasks)..where(
          (t) => t.status.isIn(['pending', 'yesterday', 'archived_failed']),
        )).get();
    final fightPending = fightRows.length;
    final fightToday =
        fightRows.where((t) => _sameDay(t.dueDate, start)).length;
    final fightLate =
        fightRows.where((t) {
          final due = t.dueDate;
          if (due == null) return t.status == 'archived_failed';
          return due.isBefore(now) && due.isBefore(end);
        }).length;

    final blockedCols =
        await (_db.select(_db.kanbanColumns)..where(
          (c) => c.isTerminal.equals(true) | c.isExpired.equals(true),
        )).get();
    final blockedIds = blockedCols.map((c) => c.id).toSet();
    final cards =
        await (_db.select(_db.kanbanCards)
          ..where((c) => c.originTaskDoneAt.isNull())).get();
    final openCards = cards.where((c) => !blockedIds.contains(c.columnId));
    final labToday = openCards.where((c) => _sameDay(c.dueDate, start)).length;
    final labLate =
        openCards.where((c) {
          final due = c.dueDate;
          if (due == null) return false;
          final midnight = due.hour == 0 && due.minute == 0 && due.second == 0;
          final deadline =
              midnight ? DateTime(due.year, due.month, due.day + 1) : due;
          return now.isAfter(deadline);
        }).length;

    return 'Fight: $fightPending pendientes · $fightToday vencen hoy · '
        '$fightLate vencidas. Lab: $labToday cards hoy · $labLate vencidas.';
  }

  bool _sameDay(DateTime? value, DateTime day) {
    if (value == null) return false;
    return value.year == day.year &&
        value.month == day.month &&
        value.day == day.day;
  }

  String _trim(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 96 ? '${clean.substring(0, 96)}...' : clean;
  }

  static int taskId(int id) => taskBase + id;
  static int cardId(int id) => cardBase + id;
}
