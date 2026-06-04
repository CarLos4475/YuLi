import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_task_repository.dart';
import 'package:yuli/data/repositories/local/local_folder_repository.dart';
import 'package:yuli/data/repositories/local/local_note_repository.dart';
import 'package:yuli/data/repositories/local/local_lab_space_repository.dart';
import 'package:yuli/data/repositories/local/local_kanban_repository.dart';
import 'package:yuli/domain/models/graph.dart';
import 'package:yuli/domain/models/task.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/kanban_card.dart';
import 'package:yuli/domain/models/canvas_context_source.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/lab/graph_assembler.dart';

/// Headless verification of the graph assembler + task-state mapping.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('taskGraphState (mapeo de 4 estados)', () {
    Task t(TaskStatus status, {DateTime? due}) => Task(
          id: 1,
          content: 'x',
          status: status,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
          dueDate: due,
        );

    test('pending sin due → fresca', () {
      expect(taskGraphState(t(TaskStatus.pending)), TaskGraphState.fresca);
    });
    test('pending due ≤24h → urgente', () {
      expect(
        taskGraphState(t(TaskStatus.pending,
            due: DateTime.now().add(const Duration(hours: 6)))),
        TaskGraphState.urgente,
      );
    });
    test('pending due ya pasada → urgente', () {
      expect(
        taskGraphState(t(TaskStatus.pending,
            due: DateTime.now().subtract(const Duration(hours: 1)))),
        TaskGraphState.urgente,
      );
    });
    test('pending due lejana (>24h) → fresca', () {
      expect(
        taskGraphState(t(TaskStatus.pending,
            due: DateTime.now().add(const Duration(days: 3)))),
        TaskGraphState.fresca,
      );
    });
    test('yesterday → ayer', () {
      expect(taskGraphState(t(TaskStatus.yesterday)), TaskGraphState.ayer);
    });
    test('archived_failed → fantasma', () {
      expect(
          taskGraphState(t(TaskStatus.archivedFailed)), TaskGraphState.fantasma);
    });
    test('done/trash → omitido (null)', () {
      expect(taskGraphState(t(TaskStatus.done)), isNull);
      expect(taskGraphState(t(TaskStatus.trash)), isNull);
    });
  });

  group('assembleSpaceGraph', () {
    late AppDatabase db;
    late ProviderContainer container;
    late LocalLabSpaceRepository labRepo;
    late LocalFolderRepository folderRepo;
    late LocalNoteRepository noteRepo;
    late LocalTaskRepository taskRepo;
    late LocalKanbanRepository kanbanRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      labRepo = LocalLabSpaceRepository(db);
      folderRepo = LocalFolderRepository(db);
      noteRepo = LocalNoteRepository(db);
      taskRepo = LocalTaskRepository(db);
      kanbanRepo = LocalKanbanRepository(db);
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        taskRepositoryProvider.overrideWithValue(LocalTaskRepository(db)),
        kanbanCardRepositoryProvider.overrideWithValue(LocalKanbanRepository(db)),
      ]);
    });
    tearDown(() {
      container.dispose();
      db.close();
    });

    Task newTask(TaskStatus status, {int? folderId, DateTime? due}) => Task(
          id: 0,
          content: 'task-${status.name}',
          status: status,
          folderId: folderId,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 1)),
          dueDate: due,
        );

    test('arma nodos, aristas, estados y los 3 tipos de arista', () async {
      final space = await labRepo.create('Sexto', '#3D6B4F');
      final cols = await labRepo.getColumns(space.id);
      final backlog = cols.firstWhere((c) => c.name == 'Backlog');

      final folder = await folderRepo.create('Estadistica', '#6B2D8E');
      final n1 = await noteRepo.create(folder.id,
          title: 'Markov', kind: NoteKind.block);
      final n2 = await noteRepo.create(folder.id,
          title: 'Pizarra', kind: NoteKind.whiteboard);

      final tFresh =
          await taskRepo.save(newTask(TaskStatus.pending, folderId: folder.id));
      final tUrgent = await taskRepo.save(newTask(TaskStatus.pending,
          folderId: folder.id, due: DateTime.now().add(const Duration(hours: 6))));
      final tYest =
          await taskRepo.save(newTask(TaskStatus.yesterday, folderId: folder.id));
      final tGhost = await taskRepo.save(newTask(TaskStatus.archivedFailed));
      final tDone = await taskRepo.save(newTask(TaskStatus.done));

      // Card → task bridge, and card → note bridge.
      await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'C1',
        priority: CardPriority.high,
        originTaskId: tFresh.id,
      );
      await kanbanRepo.create(
        labSpaceId: space.id,
        columnId: backlog.id,
        title: 'C2',
        priority: CardPriority.none,
        sourceNoteId: n1.id,
      );

      // note_task_links: N1 links the other live tasks (and a done one).
      await noteRepo.linkTask(n1.id, tUrgent.id);
      await noteRepo.linkTask(n1.id, tYest.id);
      await noteRepo.linkTask(n1.id, tGhost.id);
      await noteRepo.linkTask(n1.id, tDone.id);

      // Space sources: a note + a url (the url must NOT become a node).
      await labRepo.addContextSource(
          space.id, CanvasSourceKind.note, '${n2.id}');
      await labRepo.addContextSource(
          space.id, CanvasSourceKind.url, 'https://ex.com',
          label: 'Ejemplo');
      // AI link between notes (N1 feeds on N2).
      await noteRepo.addContextSource(n1.id, CanvasSourceKind.note, '${n2.id}');

      final data = await container.read(graphDataProvider(space.id).future);

      String id(GraphNodeKind k, [int? r]) => GraphNode.idFor(k, refId: r);
      final ids = {for (final n in data.nodes) n.id};
      GraphNode node(String i) => data.nodes.firstWhere((n) => n.id == i);
      bool edge(String a, String b, GraphEdgeKind k) => data.edges.any((e) =>
          ((e.from == a && e.to == b) || (e.from == b && e.to == a)) &&
          e.kind == k);

      final spaceId = id(GraphNodeKind.space, space.id);
      final folderId = id(GraphNodeKind.folder, folder.id);
      final n1Id = id(GraphNodeKind.note, n1.id);
      final n2Id = id(GraphNodeKind.note, n2.id);
      final freshId = id(GraphNodeKind.task, tFresh.id);
      final urgentId = id(GraphNodeKind.task, tUrgent.id);
      final yestId = id(GraphNodeKind.task, tYest.id);
      final ghostId = id(GraphNodeKind.task, tGhost.id);

      // Root
      expect(node(spaceId).isRoot, isTrue);
      expect(node(spaceId).color, space.accentColor);

      // Cards + structure edges
      expect(data.nodes.where((n) => n.kind == GraphNodeKind.card).length, 2);
      for (final c in data.nodes.where((n) => n.kind == GraphNodeKind.card)) {
        expect(edge(spaceId, c.id, GraphEdgeKind.structure), isTrue);
      }

      // Bridge: card→task (fresh), task→folder (@folder)
      final c1 = data.nodes.firstWhere(
          (n) => n.kind == GraphNodeKind.card && n.label == 'C1');
      expect(edge(c1.id, freshId, GraphEdgeKind.bridge), isTrue);
      expect(node(freshId).taskState, TaskGraphState.fresca);
      expect(edge(freshId, folderId, GraphEdgeKind.bridge), isTrue);

      // Bridge: card→note
      final c2 = data.nodes.firstWhere(
          (n) => n.kind == GraphNodeKind.card && n.label == 'C2');
      expect(edge(c2.id, n1Id, GraphEdgeKind.bridge), isTrue);

      // Notes + variant + containment
      expect(node(n1Id).noteVariant, NoteVariant.block);
      expect(node(n2Id).noteVariant, NoteVariant.whiteboard);
      expect(edge(folderId, n1Id, GraphEdgeKind.structure), isTrue);
      expect(edge(folderId, n2Id, GraphEdgeKind.structure), isTrue);
      // A space context source (note) is an AI-context link, not structure.
      expect(edge(spaceId, n2Id, GraphEdgeKind.ai), isTrue);

      // AI edge between notes
      expect(edge(n1Id, n2Id, GraphEdgeKind.ai), isTrue);
      // URLs are not represented as nodes
      expect(data.nodes.any((n) => n.kind == GraphNodeKind.url), isFalse);

      // note_task_links bridges + states
      expect(edge(n1Id, urgentId, GraphEdgeKind.bridge), isTrue);
      expect(node(urgentId).taskState, TaskGraphState.urgente);
      expect(node(yestId).taskState, TaskGraphState.ayer);
      expect(node(ghostId).taskState, TaskGraphState.fantasma);

      // done task omitted entirely
      expect(ids.contains(id(GraphNodeKind.task, tDone.id)), isFalse);

      // 3 edge kinds present
      expect(data.edges.any((e) => e.kind == GraphEdgeKind.structure), isTrue);
      expect(data.edges.any((e) => e.kind == GraphEdgeKind.bridge), isTrue);
      expect(data.edges.any((e) => e.kind == GraphEdgeKind.ai), isTrue);
      expect(data.hasUrgentTask, isTrue);
      expect(data.hasAiEdges, isTrue);
    });

    test('carpeta vinculada: arista IA sol→carpeta + tareas @carpeta',
        () async {
      final space = await labRepo.create('S', '#3D6B4F');
      final folder = await folderRepo.create('Mate', '#6B2D8E');
      await noteRepo.create(folder.id, title: 'N', kind: NoteKind.block);
      // Fight task con @folder, NUNCA enviada a Lab (sin card)
      final t = await taskRepo.save(newTask(TaskStatus.pending, folderId: folder.id));
      // vincular la carpeta al espacio (kind=folder)
      await labRepo.addContextSource(
          space.id, CanvasSourceKind.folder, '${folder.id}',
          label: folder.name);

      final data = await container.read(graphDataProvider(space.id).future);
      final spaceId = GraphNode.idFor(GraphNodeKind.space, refId: space.id);
      final folderId = GraphNode.idFor(GraphNodeKind.folder, refId: folder.id);
      final taskId = GraphNode.idFor(GraphNodeKind.task, refId: t.id);
      bool edge(String a, String b, GraphEdgeKind k) => data.edges.any((e) =>
          ((e.from == a && e.to == b) || (e.from == b && e.to == a)) &&
          e.kind == k);

      // sol→carpeta como fuente de contexto = arista IA (la carpeta nutre la IA)
      expect(edge(spaceId, folderId, GraphEdgeKind.ai), isTrue);
      // notas de la carpeta por contención
      expect(data.nodes.any((n) => n.kind == GraphNodeKind.note), isTrue);
      // la tarea @carpeta aparece y queda conectada a la carpeta (puente)
      expect(data.nodes.any((n) => n.id == taskId), isTrue);
      expect(edge(folderId, taskId, GraphEdgeKind.bridge), isTrue);
    });

    test('global incluye el space y sus carpetas/notas', () async {
      final space = await labRepo.create('S', '#3D6B4F');
      final folder = await folderRepo.create('F', '#6B2D8E');
      await noteRepo.create(folder.id, title: 'N', kind: NoteKind.block);

      final data = await container.read(graphDataProvider(null).future);
      expect(
          data.nodes.any((n) =>
              n.kind == GraphNodeKind.space && n.refId == space.id),
          isTrue);
      expect(
          data.nodes.any((n) =>
              n.kind == GraphNodeKind.folder && n.refId == folder.id),
          isTrue);
      expect(data.nodes.any((n) => n.kind == GraphNodeKind.note), isTrue);
    });

    test('space vacío → solo el sol, sin crash', () async {
      final space = await labRepo.create('Vacio', '#3D6B4F');
      final data = await container.read(graphDataProvider(space.id).future);
      expect(data.nodes.length, 1);
      expect(data.nodes.single.isRoot, isTrue);
      expect(data.edges, isEmpty);
    });
  });
}
