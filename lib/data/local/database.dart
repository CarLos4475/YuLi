import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/tasks_table.dart';
import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/note_images_table.dart';
import 'tables/note_versions_table.dart';
import 'tables/note_task_links_table.dart';
import 'tables/note_blocks_table.dart';
import 'tables/drawing_strokes_table.dart';
import 'tables/lab_spaces_table.dart';
import 'tables/kanban_columns_table.dart';
import 'tables/kanban_cards_table.dart';
import 'tables/space_folder_links_table.dart';
import 'tables/note_canvas_links_table.dart';
import 'tables/canvas_context_sources_table.dart';
import 'tables/space_context_sources_table.dart';
import 'tables/onboarding_flags_table.dart';
import 'tables/notifications_table.dart';
import 'tables/schedule_blocks_table.dart';
import 'tables/schedule_settings_table.dart';
import 'tables/schedule_week_notes_table.dart';
import 'daos/tasks_dao.dart';
import 'daos/notes_dao.dart';
import 'daos/note_blocks_dao.dart';
import 'daos/drawing_strokes_dao.dart';
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
    DrawingStrokes,
    LabSpaces,
    KanbanColumns,
    KanbanCards,
    SpaceFolderLinks,
    NoteCanvasLinks,
    CanvasContextSources,
    SpaceContextSources,
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
    DrawingStrokesDao,
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
  int get schemaVersion => 22;

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
            "DELETE FROM note_task_links WHERE note_id IN (SELECT id FROM notes)",
          );
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
            "WHERE name IN ('Entregado', 'Vencido')",
          );
        } catch (_) {}
      }
      if (from <= 13) {
        try {
          await m.addColumn(kanbanColumns, kanbanColumns.isExpired);
          await customStatement(
            "UPDATE kanban_columns SET is_expired = 1, is_terminal = 0 "
            "WHERE name = 'Vencido'",
          );
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
            "FROM note_canvas_links",
          );
        } catch (_) {}
      }
      if (from <= 16) {
        try {
          await m.addColumn(kanbanCards, kanbanCards.startDate);
        } catch (_) {}
      }
      if (from <= 17) {
        try {
          await m.addColumn(kanbanColumns, kanbanColumns.isInProgress);
          await customStatement(
            "UPDATE kanban_columns SET is_in_progress = 1 "
            "WHERE name = 'En Proceso'",
          );
        } catch (_) {}
      }
      if (from <= 18) {
        try {
          await m.addColumn(tasks, tasks.remindAt);
          await m.addColumn(tasks, tasks.reminderPreset);
          await m.addColumn(kanbanCards, kanbanCards.remindAt);
          await m.addColumn(kanbanCards, kanbanCards.reminderPreset);
        } catch (_) {}
      }
      if (from <= 19) {
        // Fuentes unificadas: tabla de sources del lab space + migración de los
        // vínculos carpeta→space existentes a fuentes de tipo 'folder'.
        try {
          await m.createTable(spaceContextSources);
          await customStatement(
            "INSERT INTO space_context_sources "
            "(lab_space_id, kind, ref, created_at) "
            "SELECT lab_space_id, 'folder', CAST(folder_id AS TEXT), "
            "strftime('%s','now') FROM space_folder_links",
          );
        } catch (_) {}
      }
      if (from <= 20) {
        // Toggle por fuente: incluir/excluir del contexto de IA.
        try {
          await m.addColumn(canvasContextSources, canvasContextSources.enabled);
          await m.addColumn(spaceContextSources, spaceContextSources.enabled);
        } catch (_) {}
      }
      if (from <= 21) {
        try {
          await m.createTable(drawingStrokes);
          await customStatement(
            "UPDATE note_blocks SET payload = '{\"s\":[]}' WHERE type = 'drawing'",
          );
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
      final toTrashRows =
          await customSelect(
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
          final msg =
              t.content.length > 80
                  ? '${t.content.substring(0, 80)}...'
                  : t.content;
          await into(notifications).insert(
            NotificationsCompanion.insert(message: 'Tarea a la papelera: $msg'),
          );
        }
        // Move linked KanbanCards to the expired column when linked task
        // expires. Identified by the is_expired flag, not the literal name,
        // so renaming "Vencido" does not break the automation.
        await customUpdate(
          "UPDATE kanban_cards SET column_id = ("
          "SELECT kc.id FROM kanban_columns kc "
          "WHERE kc.lab_space_id = kanban_cards.lab_space_id AND kc.is_expired = 1 LIMIT 1"
          ") WHERE kanban_cards.origin_task_id IN ("
          "SELECT id FROM tasks WHERE status = 'archived_failed'"
          ") AND kanban_cards.origin_task_done_at IS NULL "
          "AND EXISTS ("
          "SELECT 1 FROM kanban_columns kc "
          "WHERE kc.lab_space_id = kanban_cards.lab_space_id AND kc.is_expired = 1"
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
      // Clean up note↔task links pointing at the tasks about to be deleted
      // (FK is off, so these would otherwise dangle).
      await customUpdate(
        "DELETE FROM note_task_links WHERE task_id IN ("
        "SELECT id FROM tasks WHERE status = 'trash' "
        "AND date(trashed_at, 'unixepoch') < date('now', '-7 days')"
        ")",
        updates: {noteTaskLinks},
        updateKind: UpdateKind.delete,
      );
      await customUpdate(
        "DELETE FROM tasks WHERE status = 'trash' "
        "AND date(trashed_at, 'unixepoch') < date('now', '-7 days')",
        updates: {tasks},
        updateKind: UpdateKind.delete,
      );

      // 5. Kanban cards: move overdue, not-done cards to their space's expired
      // column. Done in Dart (not SQL) for two reasons: SQLite's 'localtime'
      // modifier returns NULL in this build, and the overdue rule must mirror
      // KanbanCard.isOverdue EXACTLY (single source of truth) — a date-only
      // deadline (local midnight) means "end of that day", so a card due "today"
      // is not swept during its own day; a deadline with a real time is exact.
      // Cards already done (origin_task_done_at set, incl. cards completed with
      // no linked task) or sitting in a terminal/expired column are skipped.
      final now = DateTime.now();
      bool deadlinePassed(DateTime due) {
        final midnight = due.hour == 0 && due.minute == 0 && due.second == 0;
        final deadline =
            midnight ? DateTime(due.year, due.month, due.day + 1) : due;
        return now.isAfter(deadline);
      }

      final systemCols =
          await (select(kanbanColumns)..where(
            (c) => c.isExpired.equals(true) | c.isTerminal.equals(true),
          )).get();
      final expiredBySpace = {
        for (final c in systemCols.where((c) => c.isExpired))
          c.labSpaceId: c.id,
      };
      final blockedColIds = systemCols.map((c) => c.id).toSet();

      final candidates =
          await (select(kanbanCards)..where(
            (c) => c.dueDate.isNotNull() & c.originTaskDoneAt.isNull(),
          )).get();
      for (final c in candidates) {
        final target = expiredBySpace[c.labSpaceId];
        if (target == null || blockedColIds.contains(c.columnId)) continue;
        final due = c.dueDate;
        if (due != null && deadlinePassed(due)) {
          await (update(kanbanCards)..where(
            (x) => x.id.equals(c.id),
          )).write(KanbanCardsCompanion(columnId: Value(target)));
        }
      }

      // 6. Folders permanent delete (7-day grace period) — cascade to notes
      // (+ their children) and detach tasks.
      final folderIdsToPurge =
          (await customSelect(
                "SELECT id FROM folders WHERE deleted_at IS NOT NULL "
                "AND date(deleted_at, 'unixepoch') < date('now', '-7 days')",
                readsFrom: {folders},
              ).get())
              .map((r) => r.read<int>('id'))
              .toList();
      for (final id in folderIdsToPurge) {
        await hardDeleteFolderCascade(id);
      }

      // 7. Lab spaces permanent delete (7-day grace period) — cascade to
      // columns, cards, schedule rows and folder links.
      final spaceIdsToPurge =
          (await customSelect(
                "SELECT id FROM lab_spaces WHERE deleted_at IS NOT NULL "
                "AND date(deleted_at, 'unixepoch') < date('now', '-7 days')",
                readsFrom: {labSpaces},
              ).get())
              .map((r) => r.read<int>('id'))
              .toList();
      for (final id in spaceIdsToPurge) {
        await hardDeleteSpaceCascade(id);
      }

      // 8. Cap the notifications inbox to the 50 most recent. They are
      // user-dismissable (dismiss/clearAll), but nothing bounded their growth
      // if left untouched while tasks keep expiring.
      await customUpdate(
        "DELETE FROM notifications WHERE id NOT IN ("
        "SELECT id FROM notifications ORDER BY created_at DESC LIMIT 50)",
        updates: {notifications},
        updateKind: UpdateKind.delete,
      );
    });

    return archivedCount;
  }

  // ─── Cascading deletes ──────────────────────────────────────────────────
  // FK enforcement is OFF (no PRAGMA foreign_keys), so child rows are cleaned
  // explicitly here. Centralized so the manual path (trash screen → repos) and
  // the automatic path (runExpiryQueries) stay in sync. See KNOWN_ISSUES for
  // the future "enable FK + onDelete" alternative.

  Future<void> _deleteNoteChildren(int noteId) async {
    await customUpdate(
      "DELETE FROM drawing_strokes WHERE block_id IN "
      "(SELECT id FROM note_blocks WHERE note_id = ?)",
      variables: [Variable.withInt(noteId)],
      updates: {drawingStrokes},
      updateKind: UpdateKind.delete,
    );
    await (delete(noteBlocks)..where((b) => b.noteId.equals(noteId))).go();
    await (delete(noteVersions)..where((v) => v.noteId.equals(noteId))).go();
    await (delete(noteImages)..where((i) => i.noteId.equals(noteId))).go();
    await (delete(noteTaskLinks)..where((l) => l.noteId.equals(noteId))).go();
    // Canvas context sources: both when this note IS a canvas and when it is
    // used as a source by another canvas.
    await (delete(canvasContextSources)
      ..where((s) => s.canvasNoteId.equals(noteId))).go();
    await (delete(canvasContextSources)..where(
      (s) => s.kind.equals('note') & s.ref.equals(noteId.toString()),
    )).go();
    // Same note used as a source by a lab space.
    await (delete(spaceContextSources)..where(
      (s) => s.kind.equals('note') & s.ref.equals(noteId.toString()),
    )).go();
    await (delete(noteCanvasLinks)..where(
      (l) => l.canvasNoteId.equals(noteId) | l.sourceNoteId.equals(noteId),
    )).go();
    // Drop the now-dangling source link on any kanban card.
    await (update(kanbanCards)
      ..where((c) => c.sourceNoteId.equals(noteId))).write(
      const KanbanCardsCompanion(
        sourceNoteId: Value(null),
        sourceAnchor: Value(null),
      ),
    );
  }

  /// Permanently deletes a note and every row that references it.
  Future<void> hardDeleteNoteCascade(int noteId) => transaction(() async {
    await _deleteNoteChildren(noteId);
    await (delete(notes)..where((n) => n.id.equals(noteId))).go();
  });

  /// Soft-deletes a folder together with its active notes, so they hide and can
  /// be restored as a unit. Tasks keep showing in FIGHT (their folder badge
  /// just goes stale until the folder is restored or purged).
  Future<void> softDeleteFolderCascade(int folderId) => transaction(() async {
    final now = DateTime.now();
    await (update(notes)..where(
      (n) => n.folderId.equals(folderId) & n.deletedAt.isNull(),
    )).write(NotesCompanion(deletedAt: Value(now)));
    await (update(folders)..where(
      (f) => f.id.equals(folderId),
    )).write(FoldersCompanion(deletedAt: Value(now)));
  });

  /// Restores a folder and the notes that were hidden with it.
  Future<void> restoreFolderCascade(int folderId) => transaction(() async {
    await (update(notes)..where(
      (n) => n.folderId.equals(folderId) & n.deletedAt.isNotNull(),
    )).write(const NotesCompanion(deletedAt: Value(null)));
    await (update(folders)..where(
      (f) => f.id.equals(folderId),
    )).write(const FoldersCompanion(deletedAt: Value(null)));
  });

  /// Permanently deletes a folder and its notes (+ their children); detaches
  /// its tasks (folder_id → NULL) so the user's tasks survive as folderless.
  Future<void> hardDeleteFolderCascade(int folderId) => transaction(() async {
    final noteIds =
        await (select(notes)
          ..where((n) => n.folderId.equals(folderId))).map((n) => n.id).get();
    for (final nid in noteIds) {
      await _deleteNoteChildren(nid);
    }
    await (delete(notes)..where((n) => n.folderId.equals(folderId))).go();
    await (update(tasks)..where(
      (t) => t.folderId.equals(folderId),
    )).write(const TasksCompanion(folderId: Value(null)));
    // Detach the folder from any lab space and from schedule blocks that
    // referenced it (both hold a folder_id with no FK).
    await (delete(spaceFolderLinks)
      ..where((l) => l.folderId.equals(folderId))).go();
    // Folder sources (unified model) referencing this folder, on any owner.
    await (delete(spaceContextSources)..where(
      (s) => s.kind.equals('folder') & s.ref.equals(folderId.toString()),
    )).go();
    await (delete(canvasContextSources)..where(
      (s) => s.kind.equals('folder') & s.ref.equals(folderId.toString()),
    )).go();
    await (update(scheduleBlocks)..where(
      (s) => s.folderId.equals(folderId),
    )).write(const ScheduleBlocksCompanion(folderId: Value(null)));
    await (delete(folders)..where((f) => f.id.equals(folderId))).go();
  });

  /// Permanently deletes a lab space and everything scoped to it.
  Future<void> hardDeleteSpaceCascade(int spaceId) => transaction(() async {
    await (delete(kanbanCards)
      ..where((c) => c.labSpaceId.equals(spaceId))).go();
    await (delete(kanbanColumns)
      ..where((c) => c.labSpaceId.equals(spaceId))).go();
    await (delete(scheduleBlocks)
      ..where((s) => s.labSpaceId.equals(spaceId))).go();
    await (delete(scheduleSettings)
      ..where((s) => s.labSpaceId.equals(spaceId))).go();
    await (delete(scheduleWeekNotes)
      ..where((s) => s.labSpaceId.equals(spaceId))).go();
    await (delete(spaceFolderLinks)
      ..where((s) => s.labSpaceId.equals(spaceId))).go();
    await (delete(spaceContextSources)
      ..where((s) => s.labSpaceId.equals(spaceId))).go();
    await (delete(labSpaces)..where((s) => s.id.equals(spaceId))).go();
  });

  /// Re-syncs the snapshot `origin_folder_color` on every kanban card linked to
  /// a task of [folderId]. Cards copy the folder color at creation; call this
  /// when the folder's color changes so existing cards don't keep the old one.
  Future<void> syncFolderColorToCards(int folderId, int colorArgb) =>
      customUpdate(
        "UPDATE kanban_cards SET origin_folder_color = ? "
        "WHERE origin_task_id IN (SELECT id FROM tasks WHERE folder_id = ?)",
        variables: [Variable.withInt(colorArgb), Variable.withInt(folderId)],
        updates: {kanbanCards},
        updateKind: UpdateKind.update,
      );

  Future<bool> hasSeenOnboarding(String key) async {
    final row =
        await (select(onboardingFlags)
          ..where((t) => t.key.equals(key))).getSingleOrNull();
    return row != null;
  }

  Future<void> markOnboardingSeen(String key) async {
    await into(onboardingFlags).insertOnConflictUpdate(
      OnboardingFlagsCompanion.insert(key: key, seenAt: DateTime.now()),
    );
  }

  Future<void> cleanKanbanAnchors() async {
    final rows =
        await (select(notes)
          ..where((n) => n.rawMarkdown.like('%<!-- kanban:%'))).get();
    for (final row in rows) {
      final cleaned = row.rawMarkdown.replaceAll(
        RegExp(r'\n*<!-- kanban:\d+ -->'),
        '',
      );
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
