import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_folder_repository.dart';
import 'package:yuli/data/repositories/local/local_kanban_repository.dart';
import 'package:yuli/data/repositories/local/local_lab_space_repository.dart';
import 'package:yuli/data/repositories/local/local_note_repository.dart';
import 'package:yuli/data/repositories/local/local_task_repository.dart';
import 'package:yuli/domain/models/kanban_card.dart';
import 'package:yuli/domain/models/reminder_preset.dart';
import 'package:yuli/domain/models/task.dart';
import 'package:yuli/presentation/providers/lab_space_providers.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/note_block_actions.dart';

/// Headless verification of the audit fixes (no GUI / no Windows toolchain).
/// Exercises the data + cross-mode logic against an in-memory SQLite DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KanbanCard card({DateTime? dueDate, DateTime? originTaskDoneAt}) =>
      KanbanCard(
        id: 1,
        labSpaceId: 1,
        columnId: 1,
        title: 't',
        priority: CardPriority.none,
        position: 0,
        createdAt: DateTime.now(),
        dueDate: dueDate,
        originTaskDoneAt: originTaskDoneAt,
      );

  group('KanbanCard.isOverdue (regla unificada)', () {
    final now = DateTime.now();

    test('done nunca está vencida', () {
      final c = card(
        dueDate: now.subtract(const Duration(days: 5)),
        originTaskDoneAt: now,
      );
      expect(c.isOverdue(), isFalse);
    });

    test('en columna expired → vencida (aunque no tenga due)', () {
      expect(card().isOverdue(inExpiredColumn: true), isTrue);
    });

    test('due con hora ya pasada → vencida', () {
      expect(
        card(dueDate: now.subtract(const Duration(hours: 1))).isOverdue(),
        isTrue,
      );
    });

    test('due con hora futura → no vencida', () {
      expect(
        card(dueDate: now.add(const Duration(hours: 1))).isOverdue(),
        isFalse,
      );
    });

    test('solo-fecha HOY (medianoche) → NO vencida durante su día', () {
      final todayMidnight = DateTime(now.year, now.month, now.day);
      expect(card(dueDate: todayMidnight).isOverdue(), isFalse);
    });

    test('solo-fecha AYER (medianoche) → vencida', () {
      final yesterdayMidnight = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));
      expect(card(dueDate: yesterdayMidnight).isOverdue(), isTrue);
    });

    test('sin due → no vencida', () {
      expect(card().isOverdue(), isFalse);
    });
  });

  group('Columnas de sistema + transición tarea↔card', () {
    late AppDatabase db;
    late LocalLabSpaceRepository labRepo;
    late LocalKanbanRepository kanbanRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      labRepo = LocalLabSpaceRepository(db);
      kanbanRepo = LocalKanbanRepository(db);
    });
    tearDown(() => db.close());

    test('create() siembra los 4 flags de sistema', () async {
      final space = await labRepo.create('S', '#FF0000');
      final cols = await labRepo.getColumns(space.id);
      expect(cols.where((c) => c.isTerminal).single.name, 'Entregado');
      expect(cols.where((c) => c.isExpired).single.name, 'Vencido');
      expect(cols.where((c) => c.isInProgress).single.name, 'En Proceso');
      expect(cols.where((c) => c.name == 'Backlog').single.isTerminal, isFalse);
    });

    test('completar/reabrir propaga card↔task en ambos sentidos', () async {
      final space = await labRepo.create('S', '#00FF00');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final entregado = cols.firstWhere((c) => c.isTerminal);
      final enProceso = cols.firstWhere((c) => c.isInProgress);

      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'tarea',
              status: 'pending',
              expiresAt: DateTime.now(),
            ),
          );
      final c0 = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'card',
        originTaskId: taskId,
      );

      // → En Proceso: sella startDate
      await kanbanRepo.moveToColumn(c0.id, enProceso.id, 0);
      expect((await kanbanRepo.getById(c0.id))!.startDate, isNotNull);

      // → Entregado: done + dueDate + task done
      await kanbanRepo.moveToColumn(c0.id, entregado.id, 0);
      var c = (await kanbanRepo.getById(c0.id))!;
      expect(c.originTaskDoneAt, isNotNull);
      expect(c.dueDate, isNotNull);
      var t =
          await (db.select(db.tasks)
            ..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, 'done');

      // ← salir de Entregado: limpia done/dueDate + reabre la task
      await kanbanRepo.moveToColumn(c0.id, backlog.id, 0);
      c = (await kanbanRepo.getById(c0.id))!;
      expect(c.originTaskDoneAt, isNull);
      expect(c.dueDate, isNull);
      t =
          await (db.select(db.tasks)
            ..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.status, 'pending');
      expect(t.completedAt, isNull);
    });

    test('reabrir re-sincroniza el due de la card desde la tarea', () async {
      final space = await labRepo.create('S', '#ABCDEF');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final entregado = cols.firstWhere((c) => c.isTerminal);
      final taskDue = DateTime(2026, 7, 15, 9, 30);
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'con due',
              status: 'pending',
              dueDate: Value(taskDue),
              expiresAt: DateTime.now(),
            ),
          );
      final c0 = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'card',
        originTaskId: taskId,
        dueDate: taskDue,
      );

      // → Entregado: el due se pisa con "ahora" (entrega real).
      await kanbanRepo.moveToColumn(c0.id, entregado.id, 0);
      expect((await kanbanRepo.getById(c0.id))!.dueDate == taskDue, isFalse);

      // ← reabrir: el due se restaura desde la tarea (15/07).
      await kanbanRepo.moveToColumn(c0.id, backlog.id, 0);
      expect((await kanbanRepo.getById(c0.id))!.dueDate, taskDue);
    });
  });

  group('Expiry — barrido a Vencido (el fix crítico)', () {
    late AppDatabase db;
    late LocalLabSpaceRepository labRepo;
    late LocalKanbanRepository kanbanRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      labRepo = LocalLabSpaceRepository(db);
      kanbanRepo = LocalKanbanRepository(db);
    });
    tearDown(() => db.close());

    test(
      'card completada con due pasado NO salta a Vencido; vencida sí',
      () async {
        final space = await labRepo.create('S', '#0000FF');
        final cols = await labRepo.getColumns(space.id);
        final backlog = cols.firstWhere((c) => c.name == 'Backlog');
        final entregado = cols.firstWhere((c) => c.isTerminal);
        final vencido = cols.firstWhere((c) => c.isExpired);
        final past = DateTime.now().subtract(const Duration(days: 2));

        // Completada (en Entregado) con due en el pasado.
        final done = await kanbanRepo.create(
          labSpaceId: space.id,
          columnId: backlog.id,
          title: 'hecha',
        );
        await kanbanRepo.moveToColumn(done.id, entregado.id, 0);
        await (db.update(db.kanbanCards)..where(
          (c) => c.id.equals(done.id),
        )).write(KanbanCardsCompanion(dueDate: Value(past)));

        // No hecha, con due en el pasado, en Backlog.
        final overdue = await kanbanRepo.create(
          labSpaceId: space.id,
          columnId: backlog.id,
          title: 'vencida',
          dueDate: past,
        );

        await db.runExpiryQueries();

        final doneAfter = (await kanbanRepo.getById(done.id))!;
        final overdueAfter = (await kanbanRepo.getById(overdue.id))!;
        expect(
          doneAfter.columnId,
          entregado.id,
          reason: 'la completada debe quedarse en Entregado',
        );
        expect(
          overdueAfter.columnId,
          vencido.id,
          reason: 'la vencida no-hecha sí va a Vencido',
        );
      },
    );
  });

  group('Cascadas de borrado (huérfanos)', () {
    late AppDatabase db;
    late LocalLabSpaceRepository labRepo;
    late LocalKanbanRepository kanbanRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      labRepo = LocalLabSpaceRepository(db);
      kanbanRepo = LocalKanbanRepository(db);
    });
    tearDown(() => db.close());

    test(
      'hardDeleteNoteCascade borra hijos y limpia sourceNoteId de la card',
      () async {
        final folderId = await db
            .into(db.folders)
            .insert(FoldersCompanion.insert(name: 'F', color: '#FFFFFF'));
        final noteId = await db
            .into(db.notes)
            .insert(NotesCompanion.insert(folderId: folderId));
        await db
            .into(db.noteImages)
            .insert(
              NoteImagesCompanion.insert(
                noteId: noteId,
                filename: 'a.jpg',
                filePath: '/x/a.jpg',
                sizeBytes: 10,
              ),
            );
        final space = await labRepo.create('S', '#FF00FF');
        final cols = await labRepo.getColumns(space.id);
        final card = await kanbanRepo.create(
          labSpaceId: space.id,
          columnId: cols.first.id,
          title: 'c',
          sourceNoteId: noteId,
        );

        await db.hardDeleteNoteCascade(noteId);

        expect(
          await (db.select(db.notes)
            ..where((n) => n.id.equals(noteId))).getSingleOrNull(),
          isNull,
        );
        expect(
          await (db.select(db.noteImages)
            ..where((i) => i.noteId.equals(noteId))).get(),
          isEmpty,
        );
        expect((await kanbanRepo.getById(card.id))!.sourceNoteId, isNull);
      },
    );

    test('hardDeleteFolderCascade borra notas y desvincula tareas', () async {
      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'F', color: '#FFFFFF'));
      final noteId = await db
          .into(db.notes)
          .insert(NotesCompanion.insert(folderId: folderId));
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 't',
              status: 'pending',
              folderId: Value(folderId),
              expiresAt: DateTime.now(),
            ),
          );

      await db.hardDeleteFolderCascade(folderId);

      expect(
        await (db.select(db.folders)
          ..where((f) => f.id.equals(folderId))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (db.select(db.notes)
          ..where((n) => n.id.equals(noteId))).getSingleOrNull(),
        isNull,
        reason: 'las notas del folder se borran',
      );
      final t =
          await (db.select(db.tasks)
            ..where((x) => x.id.equals(taskId))).getSingle();
      expect(t.folderId, isNull, reason: 'la tarea sobrevive sin carpeta');
    });

    test('hardDeleteSpaceCascade borra columnas y cards del espacio', () async {
      final space = await labRepo.create('S', '#123456');
      final cols = await labRepo.getColumns(space.id);
      await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: cols.first.id,
        title: 'c',
      );

      await db.hardDeleteSpaceCascade(space.id);

      expect(
        await (db.select(db.labSpaces)
          ..where((s) => s.id.equals(space.id))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (db.select(db.kanbanColumns)
          ..where((c) => c.labSpaceId.equals(space.id))).get(),
        isEmpty,
      );
      expect(
        await (db.select(db.kanbanCards)
          ..where((c) => c.labSpaceId.equals(space.id))).get(),
        isEmpty,
      );
    });
  });

  test(
    'editar due y recordatorio en la task resynca la card vinculada',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final labRepo = LocalLabSpaceRepository(db);
      final kanbanRepo = LocalKanbanRepository(db);
      final taskRepo = LocalTaskRepository(db);
      addTearDown(() => db.close());

      final space = await labRepo.create('S', '#ABCDEF');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'sync',
              status: 'pending',
              expiresAt: DateTime.now(),
            ),
          );
      final card = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'card',
        originTaskId: taskId,
      );

      final due = DateTime(2026, 8, 20, 14, 45);
      final remindAt = due.subtract(const Duration(minutes: 30));

      await taskRepo.updateDueDate(taskId, due);
      await taskRepo.updateReminder(taskId, remindAt, ReminderPreset.before30m);

      final updated = (await kanbanRepo.getById(card.id))!;
      expect(updated.dueDate, due);
      expect(updated.remindAt, remindAt);
      expect(updated.reminderPreset, ReminderPreset.before30m);
    },
  );

  test(
    'reenviar una task ya vinculada reutiliza la card en vez de duplicarla',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final labRepo = LocalLabSpaceRepository(db);
      final kanbanRepo = LocalKanbanRepository(db);
      addTearDown(() => db.close());

      final space = await labRepo.create('S', '#ABCDEF');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final enProceso = cols.firstWhere((c) => c.isInProgress);
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'sync',
              status: 'pending',
              expiresAt: DateTime.now(),
            ),
          );

      final first = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'uno',
        originTaskId: taskId,
      );

      final second = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: enProceso.id,
        title: 'dos',
        originTaskId: taskId,
      );

      final cards =
          await (db.select(db.kanbanCards)
            ..where((c) => c.originTaskId.equals(taskId))).get();
      expect(cards.length, 1);
      expect(second.id, first.id);
      expect((await kanbanRepo.getById(first.id))!.columnId, enProceso.id);
      expect((await kanbanRepo.getById(first.id))!.title, 'dos');
    },
  );

  test(
    'duplicados viejos de originTaskId no crashean y completar propaga a todas',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final labRepo = LocalLabSpaceRepository(db);
      final kanbanRepo = LocalKanbanRepository(db);
      final taskRepo = LocalTaskRepository(db);
      addTearDown(() => db.close());

      final space = await labRepo.create('S', '#ABCDEF');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final entregado = cols.firstWhere((c) => c.isTerminal);
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'dup',
              status: 'pending',
              expiresAt: DateTime.now(),
            ),
          );

      await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'a',
        originTaskId: taskId,
      );
      await db
          .into(db.kanbanCards)
          .insert(
            KanbanCardsCompanion.insert(
              labSpaceId: space.id,
              columnId: backlog.id,
              title: 'b',
              priority: const Value('none'),
              position: 99,
              originTaskId: Value(taskId),
            ),
          );

      final linked = await kanbanRepo.getByOriginTaskId(taskId);
      expect(linked, isNotNull);

      await setTaskDoneWith(
        taskRepo: taskRepo,
        kanbanRepo: kanbanRepo,
        labRepo: labRepo,
        taskId: taskId,
        done: true,
      );

      final cards =
          await (db.select(db.kanbanCards)
            ..where((c) => c.originTaskId.equals(taskId))).get();
      expect(cards.length, 2);
      for (final card in cards) {
        expect(card.columnId, entregado.id);
        expect(card.originTaskDoneAt, isNotNull);
      }
    },
  );

  test(
    'task ligada a una sola nota siembra sourceNoteId al crear card en Lab',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final noteRepo = LocalNoteRepository(db);
      final labRepo = LocalLabSpaceRepository(db);
      final kanbanRepo = LocalKanbanRepository(db);
      addTearDown(() => db.close());

      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'F', color: '#FFFFFF'));
      final note = await noteRepo.create(folderId, title: 'N');
      final taskId = await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              content: 'desde nota',
              status: 'pending',
              expiresAt: DateTime.now(),
            ),
          );
      await noteRepo.linkTask(note.id, taskId);

      final linkedNoteIds = await noteRepo.getLinkedNoteIds(taskId);
      final sourceNoteId =
          linkedNoteIds.length == 1 ? linkedNoteIds.first : null;

      final space = await labRepo.create('S', '#ABCDEF');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');
      final card = await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'desde nota',
        sourceNoteId: sourceNoteId,
        originTaskId: taskId,
      );

      expect(card.sourceNoteId, note.id);
    },
  );

  testWidgets(
    'enviar desde Flight siembra nota, carpeta y mention en la card',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final folderRepo = LocalFolderRepository(db);
      final noteRepo = LocalNoteRepository(db);
      final taskRepo = LocalTaskRepository(db);
      final labRepo = LocalLabSpaceRepository(db);
      final kanbanRepo = LocalKanbanRepository(db);
      addTearDown(() => db.close());

      final folder = await folderRepo.create('Materia', '#112233');
      final note = await noteRepo.create(folder.id, title: 'N');
      final task = await taskRepo.save(
        Task(
          id: 0,
          content: 'Estudiar tema',
          status: TaskStatus.pending,
          folderId: folder.id,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now(),
        ),
      );
      await noteRepo.linkTask(note.id, task.id);

      final space = await labRepo.create('S', '#ABCDEF');
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          folderRepositoryProvider.overrideWithValue(folderRepo),
          noteRepositoryProvider.overrideWithValue(noteRepo),
          taskRepositoryProvider.overrideWithValue(taskRepo),
          labSpaceRepositoryProvider.overrideWithValue(labRepo),
          kanbanCardRepositoryProvider.overrideWithValue(kanbanRepo),
        ],
      );
      addTearDown(container.dispose);

      WidgetRef? widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                widgetRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final actions = NoteBlockActions(
        ref: widgetRef!,
        noteId: note.id,
        folderId: folder.id,
      );
      final linked = await actions.linkTaskToSpace(task, space.id);

      expect(linked, isNotNull);
      expect(linked!.sourceNoteId, note.id);
      expect(linked.originFolderColor, folder.color.toARGB32());
      expect(linked.title.startsWith('@${folder.name} '), isTrue);
    },
  );
}
