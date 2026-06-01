import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/tasks_table.dart';
import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/note_images_table.dart';
import 'tables/note_versions_table.dart';
import 'tables/note_task_links_table.dart';
import 'tables/note_blocks_table.dart';
import 'tables/lab_spaces_table.dart';
import 'tables/kanban_columns_table.dart';
import 'tables/kanban_cards_table.dart';
import 'tables/space_folder_links_table.dart';
import 'tables/note_canvas_links_table.dart';
import 'tables/canvas_context_sources_table.dart';
import 'tables/onboarding_flags_table.dart';
import 'tables/notifications_table.dart';
import 'tables/schedule_blocks_table.dart';
import 'tables/schedule_settings_table.dart';
import 'tables/schedule_week_notes_table.dart';
import 'daos/tasks_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/note_blocks_dao.dart';
import 'daos/folders_dao.dart';
import 'daos/lab_spaces_dao.dart';
import 'daos/kanban_dao.dart';
import 'daos/notifications_dao.dart';
import 'daos/schedule_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Tasks,
    Folders,
    Notes,
    NoteImages,
    NoteVersions,
    NoteTaskLinks,
    NoteBlocks,
    LabSpaces,
    KanbanColumns,
    KanbanCards,
    SpaceFolderLinks,
    NoteCanvasLinks,
    CanvasContextSources,
    OnboardingFlags,
    Notifications,
    ScheduleBlocks,
    ScheduleSettings,
    ScheduleWeekNotes,
  ],
  daos: [
    TasksDao,
    NotesDao,
    NoteBlocksDao,
    FoldersDao,
    LabSpacesDao,
    KanbanDao,
    NotificationsDao,
    ScheduleDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 17;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from == 1) {
            await m.addColumn(tasks, tasks.dueDate);
          }
          if (from == 1 || from == 2) {
            await m.addColumn(tasks, tasks.completedAt);
          }
          if (from <= 3) {
            await m.addColumn(notes, notes.color);
          }
          if (from <= 4) {
            await m.addColumn(kanbanCards, kanbanCards.originTaskDoneAt);
          }
          if (from <= 6) {
            await m.createTable(scheduleBlocks);
            await m.createTable(scheduleSettings);
            await m.createTable(scheduleWeekNotes);
          }
          if (from <= 8) {
            try {
              await m.addColumn(kanbanCards, kanbanCards.originFolderColor);
            } catch (_) {}
          }
          if (from <= 9) {
            try {
              await m.addColumn(scheduleSettings, scheduleSettings.showSaturday);
              await m.addColumn(scheduleSettings, scheduleSettings.showSunday);
            } catch (_) {}
          }
          if (from <= 10) {
            // Block editor migration: wipe legacy markdown notes (single-user
            // app, no production data) and create the typed-block table.
            try {
              await customStatement(
                  "DELETE FROM note_task_links WHERE note_id IN (SELECT id FROM notes)");
              await customStatement("DELETE FROM note_images");
              await customStatement("DELETE FROM note_versions");
              await customStatement("DELETE FROM notes");
            } catch (_) {}
            await m.createTable(noteBlocks);
          }
          if (from <= 11) {
            try {
              await m.addColumn(notes, notes.kind);
            } catch (_) {}
          }
          if (from <= 12) {
            try {
              await m.addColumn(kanbanColumns, kanbanColumns.isTerminal);
              await customStatement(
                  "UPDATE kanban_columns SET is_terminal = 1 "
                  "WHERE name IN ('Entregado', 'Vencido')");
            } catch (_) {}
          }
          if (from <= 13) {
            try {
              await m.addColumn(kanbanColumns, kanbanColumns.isExpired);
              await customStatement(
                  "UPDATE kanban_columns SET is_expired = 1, is_terminal = 0 "
                  "WHERE name = 'Vencido'");
            } catch (_) {}
          }
          if (from <= 14) {
            try {
              await m.createTable(noteCanvasLinks);
            } catch (_) {}
          }
          if (from <= 15) {
            try {
              await m.createTable(canvasContextSources);
              // Carry over any existing single-source links as note sources.
              await customStatement(
                  "INSERT INTO canvas_context_sources "
                  "(canvas_note_id, kind, ref, created_at) "
                  "SELECT canvas_note_id, 'note', "
                  "CAST(source_note_id AS TEXT), created_at "
                  "FROM note_canvas_links");
            } catch (_) {}
          }
          if (from <= 16) {
            try {
              await m.addColumn(kanbanCards, kanbanCards.startDate);
            } catch (_) {}
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
      // 1a. pending → yesterday (sin dueDate: basado en created_at)
      await customUpdate(
        "UPDATE tasks SET status = 'yesterday' "
        "WHERE status = 'pending' AND due_date IS NULL "
        "AND date(created_at, 'unixepoch') < date('now')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 1b. pending → yesterday (con dueDate: basado en due_date, compara timestamp exacto)
      await customUpdate(
        "UPDATE tasks SET status = 'yesterday' "
        "WHERE status = 'pending' AND due_date IS NOT NULL "
        "AND datetime(due_date, 'unixepoch') < datetime('now')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 2a. yesterday → archived_failed (sin dueDate: basado en created_at)
      await customUpdate(
        "UPDATE tasks SET status = 'archived_failed' "
        "WHERE status = 'yesterday' AND due_date IS NULL "
        "AND date(created_at, 'unixepoch') < date('now', '-1 day')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 2b. yesterday → archived_failed (con dueDate: basado en due_date, compara timestamp exacto)
      await customUpdate(
        "UPDATE tasks SET status = 'archived_failed' "
        "WHERE status = 'yesterday' AND due_date IS NOT NULL "
        "AND datetime(due_date, 'unixepoch') < datetime('now', '-1 day')",
        updates: {tasks},
        updateKind: UpdateKind.update,
      );

      // 3. archived_failed → trash + notificar
      //    Grace period: 24h after entering archived_failed (= 2 days past
      //    created_at without due_date, or 2 days past due_date) so the
      //    FIGHT view can render them in the VENCIDAS bucket with a
      //    countdown before final move to trash.
      final toTrashRows = await customSelect(
        "SELECT content FROM tasks "
        "WHERE status = 'archived_failed' AND ("
        "  (due_date IS NULL AND "
        "    date(created_at, 'unixepoch') <= date('now', '-2 days')) OR "
        "  (due_date IS NOT NULL AND "
        "    datetime(due_date, 'unixepoch') <= datetime('now', '-2 days'))"
        ")",
        readsFrom: {tasks},
      ).get();
      final toTrash =
          toTrashRows.map((r) => (content: r.read<String>('content'))).toList();
      if (toTrash.isNotEmpty) {
        for (final t in toTrash) {
          final msg = t.content.length > 80
              ? '${t.content.substring(0, 80)}...'
              : t.content;
          await into(notifications).insert(
            NotificationsCompanion.insert(message: 'Tarea a la papelera: $msg'),
          );
        }
        // Move linked KanbanCards to Vencido when linked task expires
        await customUpdate(
          "UPDATE kanban_cards SET column_id = ("
          "SELECT kc.id FROM kanban_columns kc "
          "WHERE kc.lab_space_id = kanban_cards.lab_space_id AND kc.name = 'Vencido'"
          ") WHERE kanban_cards.origin_task_id IN ("
          "SELECT id FROM tasks WHERE status = 'archived_failed'"
          ") AND kanban_cards.origin_task_done_at IS NULL "
          "AND EXISTS ("
          "SELECT 1 FROM kanban_columns kc "
          "WHERE kc.lab_space_id = kanban_cards.lab_space_id AND kc.name = 'Vencido'"
          ")",
          updates: {kanbanCards},
          updateKind: UpdateKind.update,
        );
        archivedCount = await customUpdate(
          "UPDATE tasks SET status = 'trash', trashed_at = datetime('now') "
          "WHERE status = 'archived_failed' AND ("
          "  (due_date IS NULL AND "
          "    date(created_at, 'unixepoch') <= date('now', '-2 days')) OR "
          "  (due_date IS NOT NULL AND "
          "    datetime(due_date, 'unixepoch') <= datetime('now', '-2 days'))"
          ")",
          updates: {tasks},
          updateKind: UpdateKind.update,
        );
      }

      // 4. trash → permanent delete (7-day grace period)
      // First, clear origin fields on KanbanCards linked to tasks about to be deleted
      await customUpdate(
        "UPDATE kanban_cards SET origin_task_id = NULL, origin_task_done_at = NULL "
        "WHERE origin_task_id IN ("
        "SELECT id FROM tasks WHERE status = 'trash' "
        "AND date(trashed_at, 'unixepoch') < date('now', '-7 days')"
        ")",
        updates: {kanbanCards},
        updateKind: UpdateKind.update,
      );
      await customUpdate(
        "DELETE FROM tasks WHERE status = 'trash' "
        "AND date(trashed_at, 'unixepoch') < date('now', '-7 days')",
        updates: {tasks},
        updateKind: UpdateKind.delete,
      );

      // 5. Kanban cards: move overdue cards to "Vencido" column
      await customUpdate(
        "UPDATE kanban_cards SET column_id = ("
        "SELECT kc.id FROM kanban_columns kc "
        "WHERE kc.lab_space_id = kanban_cards.lab_space_id AND kc.name = 'Vencido'"
        ") WHERE kanban_cards.due_date IS NOT NULL "
        "AND datetime(kanban_cards.due_date, 'unixepoch') < datetime('now') "
        "AND kanban_cards.column_id NOT IN ("
        "SELECT kc2.id FROM kanban_columns kc2 "
        "WHERE kc2.lab_space_id = kanban_cards.lab_space_id AND kc2.name = 'Vencido'"
        ") AND EXISTS ("
        "SELECT 1 FROM kanban_columns kc3 "
        "WHERE kc3.lab_space_id = kanban_cards.lab_space_id AND kc3.name = 'Vencido'"
        ")",
        updates: {kanbanCards},
        updateKind: UpdateKind.update,
      );

      // 6. Folders permanent delete (7-day grace period)
      await customUpdate(
        "DELETE FROM folders WHERE deleted_at IS NOT NULL "
        "AND date(deleted_at, 'unixepoch') < date('now', '-7 days')",
        updates: {folders},
        updateKind: UpdateKind.delete,
      );

      // 7. Lab spaces permanent delete (7-day grace period)
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
