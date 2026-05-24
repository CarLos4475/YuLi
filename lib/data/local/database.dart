import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/tasks_table.dart';
import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/note_images_table.dart';
import 'tables/note_versions_table.dart';
import 'tables/note_task_links_table.dart';
import 'tables/lab_spaces_table.dart';
import 'tables/kanban_columns_table.dart';
import 'tables/kanban_cards_table.dart';
import 'tables/space_folder_links_table.dart';
import 'tables/onboarding_flags_table.dart';
import 'daos/tasks_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/folders_dao.dart';
import 'daos/lab_spaces_dao.dart';
import 'daos/kanban_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Folders,
    Notes,
    NoteImages,
    NoteVersions,
    NoteTaskLinks,
    LabSpaces,
    KanbanColumns,
    KanbanCards,
    SpaceFolderLinks,
    OnboardingFlags,
  ],
  daos: [
    TasksDao,
    NotesDao,
    FoldersDao,
    LabSpacesDao,
    KanbanDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          if (from == 1) {
            await m.addColumn(tasks, tasks.dueDate);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'yuli_db',
      native: const DriftNativeOptions(shareAcrossIsolates: false),
    );
  }

  /// Runs all expiry transitions at app startup.
  /// Returns the number of tasks that moved to trash (step 3),
  /// so the UI can decide whether to show the AppBanner.
  Future<int> runExpiryQueries() async {
    int archivedCount = 0;

    await transaction(() async {
      // 1. pending → yesterday
      await customUpdate(
        "UPDATE tasks SET status = 'yesterday' "
        "WHERE status = 'pending' AND date(created_at, 'unixepoch') < date('now')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 2. yesterday → archived_failed
      await customUpdate(
        "UPDATE tasks SET status = 'archived_failed' "
        "WHERE status = 'yesterday' AND date(created_at, 'unixepoch') < date('now', '-1 day')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 3. archived_failed → trash
      archivedCount = await customUpdate(
        "UPDATE tasks SET status = 'trash', trashed_at = datetime('now') "
        "WHERE status = 'archived_failed'",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 4. trash → permanent delete (7-day grace period)
      await customUpdate(
        "DELETE FROM tasks WHERE status = 'trash' "
        "AND date(trashed_at, 'unixepoch') < date('now', '-7 days')",
        updates: {tasks},
        updateKind: UpdateKind.delete,
      );

      // 5. Folders permanent delete (7-day grace period)
      await customUpdate(
        "DELETE FROM folders WHERE deleted_at IS NOT NULL "
        "AND date(deleted_at, 'unixepoch') < date('now', '-7 days')",
        updates: {folders},
        updateKind: UpdateKind.delete,
      );

      // 6. Lab spaces permanent delete (7-day grace period)
      await customUpdate(
        "DELETE FROM lab_spaces WHERE deleted_at IS NOT NULL "
        "AND date(deleted_at, 'unixepoch') < date('now', '-7 days')",
        updates: {labSpaces},
        updateKind: UpdateKind.delete,
      );
    });

    return archivedCount;
  }

  Future<bool> hasSeenOnboarding(String key) async {
    final row = await (select(onboardingFlags)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> markOnboardingSeen(String key) async {
    await into(onboardingFlags).insertOnConflictUpdate(
      OnboardingFlagsCompanion.insert(
        key: key,
        seenAt: DateTime.now(),
      ),
    );
  }

  Future<void> cleanKanbanAnchors() async {
    final rows = await (select(notes)
          ..where((n) => n.rawMarkdown.like('%<!-- kanban:%')))
        .get();
    for (final row in rows) {
      final cleaned =
          row.rawMarkdown.replaceAll(RegExp(r'\n*<!-- kanban:\d+ -->'), '');
      if (cleaned != row.rawMarkdown) {
        await (update(notes)..where((n) => n.id.equals(row.id))).write(
          NotesCompanion(
            rawMarkdown: Value(cleaned),
            sizeBytes: Value(cleaned.length),
          ),
        );
      }
    }
  }
}
