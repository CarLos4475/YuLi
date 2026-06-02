import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/services/reminder_coordinator.dart';
import 'package:yuli/data/services/reminder_preferences.dart';
import 'package:yuli/domain/services/reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeReminderScheduler scheduler;
  late ReminderCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'reminders_daily_enabled_v1': false,
      'reminders_exact_enabled_v1': true,
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scheduler = _FakeReminderScheduler();
    coordinator = ReminderCoordinator(db, scheduler, ReminderPreferences());
  });

  tearDown(() => db.close());

  test('syncTask programa task pendiente futura', () async {
    final now = DateTime.now().add(const Duration(hours: 2));
    final remindAt = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    final taskId = await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            content: 'Entrega de proyecto final',
            status: 'pending',
            expiresAt: DateTime.now().add(const Duration(hours: 48)),
            remindAt: Value(remindAt),
          ),
        );

    await coordinator.syncTask(taskId);

    expect(scheduler.scheduled, hasLength(1));
    final request = scheduler.scheduled.single;
    expect(request.id, ReminderCoordinator.taskId(taskId));
    expect(request.title, 'Entrega de proyecto final');
    expect(request.subText, 'YuLi · Fight');
    expect(request.body, 'Toca para abrir tu recordatorio');
    expect(request.scheduledAt, remindAt);
    expect(request.payload, 'task:$taskId');
    expect(request.exact, isTrue);
  });

  test('syncTask cancela task hecha', () async {
    final taskId = await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            content: 'Lista',
            status: 'done',
            expiresAt: DateTime.now().add(const Duration(hours: 48)),
            remindAt: Value(DateTime.now().add(const Duration(hours: 2))),
          ),
        );

    await coordinator.syncTask(taskId);

    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains(ReminderCoordinator.taskId(taskId)));
  });

  test('reconcileAll cancela recordatorio huérfano de task borrada', () async {
    final taskId = await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            content: 'Tarea con recordatorio',
            status: 'pending',
            expiresAt: DateTime.now().add(const Duration(hours: 48)),
            remindAt: Value(DateTime.now().add(const Duration(hours: 2))),
          ),
        );
    await coordinator.syncTask(taskId);
    expect(scheduler.pending, contains(ReminderCoordinator.taskId(taskId)));

    // Borrado directo (simula cascada de space/folder que no pasa por syncTask).
    await (db.delete(db.tasks)..where((t) => t.id.equals(taskId))).go();
    await coordinator.reconcileAll();

    expect(scheduler.pending, isEmpty);
    expect(scheduler.cancelled, contains(ReminderCoordinator.taskId(taskId)));
  });
}

class _FakeReminderScheduler implements ReminderScheduler {
  final scheduled = <ReminderRequest>[];
  final cancelled = <int>[];
  final pending = <int>{};

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestExactPermission() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> schedule(ReminderRequest request) async {
    scheduled.add(request);
    pending.add(request.id);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<List<int>> pendingIds() async => pending.toList();

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<void> openNotificationSettings() async {}
}
