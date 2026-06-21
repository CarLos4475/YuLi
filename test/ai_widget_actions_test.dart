import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_folder_repository.dart';
import 'package:yuli/data/repositories/local/local_kanban_repository.dart';
import 'package:yuli/data/repositories/local/local_lab_space_repository.dart';
import 'package:yuli/data/repositories/local/local_note_repository.dart';
import 'package:yuli/data/repositories/local/local_task_repository.dart';
import 'package:yuli/domain/models/kanban_card.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_contracts.dart';
import 'package:yuli/presentation/screens/yuli_ai/ai_widget_renderer.dart';
import 'package:yuli/presentation/widgets/yuli_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late LocalFolderRepository folderRepo;
  late LocalNoteRepository noteRepo;
  late LocalTaskRepository taskRepo;
  late LocalLabSpaceRepository labRepo;
  late LocalKanbanRepository kanbanRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    folderRepo = LocalFolderRepository(db);
    noteRepo = LocalNoteRepository(db);
    taskRepo = LocalTaskRepository(db);
    labRepo = LocalLabSpaceRepository(db);
    kanbanRepo = LocalKanbanRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('TASK_DRAFT creates task, note link, Lab card and memory', (
    tester,
  ) async {
    final folder = await folderRepo.create('Calculo', '#2D4B8E');
    final note = await noteRepo.create(folder.id, title: 'Integrales');
    final space = await labRepo.create('Proyecto Calculo', '#3D6B4F');
    final backlog = (await labRepo.getColumns(
      space.id,
    )).firstWhere((c) => c.name == 'Backlog');
    final results = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          folderRepositoryProvider.overrideWithValue(folderRepo),
          noteRepositoryProvider.overrideWithValue(noteRepo),
          taskRepositoryProvider.overrideWithValue(taskRepo),
          labSpaceRepositoryProvider.overrideWithValue(labRepo),
          kanbanCardRepositoryProvider.overrideWithValue(kanbanRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AiWidgetRenderer(
              text:
                  '<!--YULI_WIDGET:TASK_DRAFT v=1\n'
                  '{"content":"Entregar ejercicios de integrales",'
                  '"folder":{"id":${folder.id},"name":"Calculo","color":"#2D4B8E"},'
                  '"dueDate":"2026-06-26T19:00:00",'
                  '"reminderPreset":"before_1d",'
                  '"labLink":{"space":{"id":${space.id},"name":"Proyecto Calculo"},"column":"Backlog"},'
                  '"temporaryMemory":{"scope":"note:${note.id}","value":"Tiene entrega de integrales","expiresAt":"2026-06-27T23:59:00"}}'
                  '-->',
              accent: yFlight,
              surface: AiWidgetSurface.flight,
              noteId: note.id,
              onActionResult: results.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('CREAR'));
    await tester.pumpAndSettle();

    final tasks = await taskRepo.watchByIds(const []).first;
    expect(tasks, isEmpty);
    final taskRows = await db.select(db.tasks).get();
    expect(taskRows, hasLength(1));
    final task = taskRows.single;
    expect(task.content, 'Entregar ejercicios de integrales');
    expect(task.folderId, folder.id);
    expect(task.dueDate, DateTime(2026, 6, 26, 19));

    expect(await noteRepo.getLinkedTaskIds(note.id), [task.id]);

    final cards = await kanbanRepo.getAllByOriginTaskId(task.id);
    expect(cards, hasLength(1));
    expect(cards.single.sourceNoteId, note.id);
    expect(cards.single.originTaskId, task.id);
    expect(cards.single.columnId, backlog.id);

    await kanbanRepo.create(
      labSpaceId: space.id,
      columnId: backlog.id,
      title: 'Retry',
      priority: CardPriority.high,
      originTaskId: task.id,
      sourceNoteId: note.id,
    );
    expect(await kanbanRepo.getAllByOriginTaskId(task.id), hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('yuli_user_memory_v1'), contains('integrales'));
    expect(results.single, contains('vinculada a esta nota'));
    expect(results.single, contains('Lab'));
  });

  testWidgets('TASK_DRAFT edit dialog shows selectors for real app data', (
    tester,
  ) async {
    final folder = await folderRepo.create('Calculo', '#2D4B8E');
    final space = await labRepo.create('Proyecto Calculo', '#3D6B4F');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          folderRepositoryProvider.overrideWithValue(folderRepo),
          taskRepositoryProvider.overrideWithValue(taskRepo),
          labSpaceRepositoryProvider.overrideWithValue(labRepo),
          kanbanCardRepositoryProvider.overrideWithValue(kanbanRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AiWidgetRenderer(
              text:
                  '<!--YULI_WIDGET:TASK_DRAFT v=1\n'
                  '{"content":"Entregar ejercicios",'
                  '"folder":{"id":${folder.id},"name":"Calculo","color":"#2D4B8E"},'
                  '"labLink":{"space":{"id":${space.id},"name":"Proyecto Calculo"},"column":"Backlog"},'
                  '"reminderPreset":"before_1d"}'
                  '-->',
              accent: yFlight,
              surface: AiWidgetSurface.flight,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('EDITAR'));
    await tester.pumpAndSettle();

    expect(find.text('Editar tarea'), findsOneWidget);
    expect(find.text('Sin folder'), findsOneWidget);
    expect(find.text('Calculo'), findsWidgets);
    expect(find.text('Proyecto Calculo'), findsWidgets);
    expect(find.text('Backlog'), findsWidgets);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Mañana'), findsWidgets);
    expect(find.text('Un día antes'), findsWidgets);
  });
}
