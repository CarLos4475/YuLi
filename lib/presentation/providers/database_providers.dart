import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database.dart';
import '../../data/repositories/local/local_task_repository.dart';
import '../../data/repositories/local/local_folder_repository.dart';
import '../../data/repositories/local/local_note_repository.dart';
import '../../data/repositories/local/local_note_block_repository.dart';
import '../../data/repositories/local/local_drawing_stroke_repository.dart';
import '../../data/repositories/local/local_lab_space_repository.dart';
import '../../data/repositories/local/local_kanban_repository.dart';
import '../../data/repositories/local/local_notification_repository.dart';
import '../../data/repositories/local/local_schedule_repository.dart';
import '../../data/repositories/local/local_floating_pin_repository.dart';
import '../../data/services/local_reminder_scheduler.dart';
import '../../data/services/reminder_coordinator.dart';
import '../../data/services/reminder_preferences.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../../domain/repositories/task_repository.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/note_block_repository.dart';
import '../../domain/repositories/drawing_stroke_repository.dart';
import '../../domain/repositories/lab_space_repository.dart';
import '../../domain/repositories/kanban_card_repository.dart';
import '../../domain/repositories/floating_pin_repository.dart';
import '../../domain/models/notification_item.dart';
import '../../domain/services/reminder_scheduler.dart';
import '../../domain/models/task.dart' as domain_task;
import '../../domain/models/folder.dart';
import '../../domain/models/note.dart' as domain_note;
import '../../domain/models/lab_space.dart';

// ─── App mode ─────────────────────────────────────────────────────────────────

enum AppMode { home, fight, flight, lab }

final currentModeProvider = StateProvider<AppMode>((ref) => AppMode.home);

// ─── Database ─────────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ─── Repositories ─────────────────────────────────────────────────────────────

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return LocalTaskRepository(
    ref.watch(databaseProvider),
    reminders: ref.watch(reminderCoordinatorProvider),
  );
});

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return LocalFolderRepository(ref.watch(databaseProvider));
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return LocalNoteRepository(ref.watch(databaseProvider));
});

final noteBlockRepositoryProvider = Provider<NoteBlockRepository>((ref) {
  return LocalNoteBlockRepository(ref.watch(databaseProvider));
});

final drawingStrokeRepositoryProvider = Provider<DrawingStrokeRepository>((
  ref,
) {
  return LocalDrawingStrokeRepository(ref.watch(databaseProvider));
});

final labSpaceRepositoryProvider = Provider<LabSpaceRepository>((ref) {
  return LocalLabSpaceRepository(ref.watch(databaseProvider));
});

final kanbanCardRepositoryProvider = Provider<KanbanCardRepository>((ref) {
  return LocalKanbanRepository(
    ref.watch(databaseProvider),
    reminders: ref.watch(reminderCoordinatorProvider),
  );
});

final floatingPinRepositoryProvider = Provider<FloatingPinRepository>((ref) {
  return LocalFloatingPinRepository(ref.watch(databaseProvider));
});

final reminderPreferencesProvider = Provider<ReminderPreferences>((ref) {
  return ReminderPreferences();
});

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return LocalReminderScheduler();
});

final reminderCoordinatorProvider = Provider<ReminderCoordinator>((ref) {
  return ReminderCoordinator(
    ref.watch(databaseProvider),
    ref.watch(reminderSchedulerProvider),
    ref.watch(reminderPreferencesProvider),
  );
});

// ─── Trash ────────────────────────────────────────────────────────────────────

final trashedTasksProvider = StreamProvider<List<domain_task.Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTrashed();
});

final deletedFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchDeleted();
});

final deletedNotesProvider = StreamProvider<List<domain_note.Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchDeleted();
});

final deletedLabSpacesProvider = StreamProvider<List<LabSpace>>((ref) {
  return ref.watch(labSpaceRepositoryProvider).watchDeleted();
});

// ─── Notifications ────────────────────────────────────────────────────────────

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return LocalNotificationRepository(ref.watch(databaseProvider));
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return LocalScheduleRepository(ref.watch(databaseProvider));
});

final notificationsProvider = StreamProvider<List<NotificationItem>>((ref) {
  return ref.watch(notificationRepositoryProvider).watchAll();
});

// ─── Expiry ───────────────────────────────────────────────────────────────────

/// Runs expiry queries and returns the number of tasks archived.
/// Used at startup to decide whether to show the AppBanner.
final expiryResultProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  try {
    final result = await db.runExpiryQueries().timeout(
      const Duration(seconds: 8),
      onTimeout: () => 0,
    );
    if (!await db.hasSeenOnboarding('kanban_anchor_cleanup')) {
      await db.cleanKanbanAnchors();
      await db.markOnboardingSeen('kanban_anchor_cleanup');
    }
    await ref.read(reminderCoordinatorProvider).reconcileAll();
    return result;
  } catch (_) {
    return 0;
  }
});
