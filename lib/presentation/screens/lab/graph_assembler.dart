import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/graph.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart' show yMuted, yFight;
import 'lab_card_colors.dart';

/// Assembles the connections graph ([GraphData]) from the existing repositories.
/// Snapshot-based (no streams kept alive) so re-running the force simulation
/// only happens on explicit refresh — see the heat-aware notes in the plan.
///
/// `spaceId == null` → the global "ver todo" graph (every active space as its
/// own sun). Otherwise a per-space graph rooted at that space, expanded via a
/// bounded BFS (cards → their task/note origins; space sources; schedule
/// folders; folders → notes; notes → linked tasks + AI-context links).
///
/// autoDispose: this is a SNAPSHOT (no streams kept alive), so while the tab is
/// open it only stays fresh via the GraphTab's explicit invalidations. The
/// moment the tab unmounts those invalidations stop — if the result were cached
/// (the keepAlive default), any change made elsewhere (new task, due date, card
/// moved) would never reach the cache and you'd see a stale graph until an app
/// restart rebuilt the container. autoDispose drops the cache when nobody is
/// watching, so re-entering the tab recomputes from the live DB.
final graphDataProvider =
    FutureProvider.autoDispose.family<GraphData, int?>((ref, spaceId) {
  final builder = _GraphBuilder(ref);
  return spaceId == null
      ? builder.buildGlobal()
      : builder.buildSpace(spaceId);
});

/// Maps a FIGHT [Task] to its 4-state graph lifecycle. Returns null for
/// done/trash tasks (omitted — the kanban card already carries the done state).
TaskGraphState? taskGraphState(Task t) {
  switch (t.status) {
    case TaskStatus.pending:
      final due = t.dueDate;
      if (due != null) {
        final diff = due.difference(DateTime.now());
        if (diff.isNegative || diff <= const Duration(hours: 24)) {
          return TaskGraphState.urgente;
        }
      }
      return TaskGraphState.fresca;
    case TaskStatus.yesterday:
      return TaskGraphState.ayer;
    case TaskStatus.archivedFailed:
      return TaskGraphState.fantasma;
    case TaskStatus.done:
    case TaskStatus.trash:
      return null;
  }
}

NoteVariant _variant(NoteKind k) => switch (k) {
      NoteKind.block => NoteVariant.block,
      NoteKind.whiteboard => NoteVariant.whiteboard,
      NoteKind.notebook => NoteVariant.notebook,
    };

class _GraphBuilder {
  _GraphBuilder(this.ref);
  final Ref ref;

  late final _labRepo = ref.read(labSpaceRepositoryProvider);
  late final _cardRepo = ref.read(kanbanCardRepositoryProvider);
  late final _folderRepo = ref.read(folderRepositoryProvider);
  late final _noteRepo = ref.read(noteRepositoryProvider);
  late final _taskRepo = ref.read(taskRepositoryProvider);
  late final _scheduleRepo = ref.read(scheduleRepositoryProvider);

  final Map<String, GraphNode> _nodes = {};
  final Map<String, GraphEdge> _edges = {};
  final Map<int, Folder?> _folderCache = {};

  GraphData _result() =>
      GraphData(nodes: _nodes.values.toList(), edges: _edges.values.toList());

  void _edge(String from, String to, GraphEdgeKind kind) {
    if (from == to) return;
    final e = GraphEdge(from: from, to: to, kind: kind);
    _edges.putIfAbsent(e.key, () => e);
  }

  Future<Folder?> _folder(int id) async =>
      _folderCache[id] ??= await _folderRepo.getById(id);

  Future<Color> _folderColor(int id) async =>
      (await _folder(id))?.color ?? yMuted;

  // ── Entry points ──────────────────────────────────────────────────────────

  Future<GraphData> buildSpace(int spaceId) async {
    final space = await _labRepo.getById(spaceId);
    if (space == null) return GraphData.empty;
    await _addSpaceUniverse(space, isRoot: true);
    await _expandFoldersAndNotes();
    await _addFolderTasks();
    return _result();
  }

  Future<GraphData> buildGlobal() async {
    final spaces = await _labRepo.getActive();
    for (final s in spaces) {
      await _addSpaceUniverse(s, isRoot: true);
    }
    // Whole brain: every active folder + its notes, even unlinked to a space.
    final folders = await _folderRepo.getActive();
    for (final f in folders) {
      _addFolderNode(f);
    }
    await _expandFoldersAndNotes();
    // Every live FIGHT task, so standalone captures show their @folder cluster.
    final live = [
      ...await _taskRepo.watchPending().first,
      ...await _taskRepo.watchYesterday().first,
      ...await _taskRepo.watchVencidas().first,
    ];
    for (final t in live) {
      await _addTaskEntity(t);
    }
    return _result();
  }

  // ── Space universe (hop 0–1 + card bridges + sources + schedule) ──────────

  Future<void> _addSpaceUniverse(LabSpace space, {required bool isRoot}) async {
    final rootId = GraphNode.idFor(GraphNodeKind.space, refId: space.id);
    _nodes.putIfAbsent(
      rootId,
      () => GraphNode(
        id: rootId,
        kind: GraphNodeKind.space,
        label: space.name,
        color: space.accentColor,
        refId: space.id,
        isRoot: isRoot,
      ),
    );

    final columns = await _labRepo.getColumns(space.id);
    final terminalColIds =
        columns.where((c) => c.isTerminal).map((c) => c.id).toSet();
    final expiredColIds =
        columns.where((c) => c.isExpired).map((c) => c.id).toSet();

    final cards = await _cardRepo.watchBySpace(space.id).first;
    for (final card in cards) {
      if (terminalColIds.contains(card.columnId) ||
          expiredColIds.contains(card.columnId)) continue;
      await _addCard(card, rootId, false);
    }

    final sources = await _labRepo.getContextSources(space.id);
    for (final s in sources) {
      await _addSource(s, rootId, GraphEdgeKind.ai);
    }

    final blocks = await _scheduleRepo.watchBySpace(space.id).first;
    for (final blk in blocks) {
      final fid = blk.folderId;
      if (fid != null) await _addFolder(fid, rootId, GraphEdgeKind.structure);
    }
  }

  Future<void> _addCard(
      KanbanCard card, String rootId, bool inExpired) async {
    final cardId = GraphNode.idFor(GraphNodeKind.card, refId: card.id);
    _nodes.putIfAbsent(
      cardId,
      () => GraphNode(
        id: cardId,
        kind: GraphNodeKind.card,
        label: card.title,
        color: labCardAccent(card, inExpiredColumn: inExpired),
        refId: card.id,
        cardPriority: card.priority,
      ),
    );
    _edge(rootId, cardId, GraphEdgeKind.structure);

    if (card.originTaskId != null) {
      await _addTaskById(card.originTaskId!, cardId, GraphEdgeKind.bridge);
    }
    if (card.sourceNoteId != null) {
      final n = await _noteRepo.getById(card.sourceNoteId!);
      if (n != null && n.isActive) {
        final noteId = await _addNote(n);
        _edge(cardId, noteId, GraphEdgeKind.bridge);
      }
    }
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────

  Future<void> _addTaskById(int id, String fromId, GraphEdgeKind kind) async {
    final t = await _taskRepo.getById(id);
    if (t != null) await _addTaskEntity(t, fromId: fromId, edgeKind: kind);
  }

  Future<void> _addTaskEntity(Task t,
      {String? fromId, GraphEdgeKind? edgeKind}) async {
    final state = taskGraphState(t);
    if (state == null) return; // done/trash → omitted
    final taskId = GraphNode.idFor(GraphNodeKind.task, refId: t.id);
    final color = t.folderId != null ? await _folderColor(t.folderId!) : yFight;
    _nodes.putIfAbsent(
      taskId,
      () => GraphNode(
        id: taskId,
        kind: GraphNodeKind.task,
        label: t.content,
        color: color,
        refId: t.id,
        taskState: state,
      ),
    );
    if (fromId != null && edgeKind != null) _edge(fromId, taskId, edgeKind);
    final hasLinkedNotes = (await _noteRepo.getLinkedNoteIds(t.id)).isNotEmpty;
    if (t.folderId != null && !hasLinkedNotes) {
      await _addFolder(t.folderId!, taskId, GraphEdgeKind.bridge);
    }
  }

  // ── Folders & notes ─────────────────────────────────────────────────────

  void _addFolderNode(Folder f) {
    if (!f.isActive) return;
    final id = GraphNode.idFor(GraphNodeKind.folder, refId: f.id);
    _nodes.putIfAbsent(
      id,
      () => GraphNode(
        id: id,
        kind: GraphNodeKind.folder,
        label: f.name,
        color: f.color,
        refId: f.id,
      ),
    );
  }

  Future<void> _addFolder(int fid, String fromId, GraphEdgeKind kind) async {
    final f = await _folder(fid);
    if (f == null || !f.isActive) return;
    _addFolderNode(f);
    _edge(fromId, GraphNode.idFor(GraphNodeKind.folder, refId: fid), kind);
  }

  Future<String> _addNote(Note n) async {
    final id = GraphNode.idFor(GraphNodeKind.note, refId: n.id);
    if (!_nodes.containsKey(id)) {
      _nodes[id] = GraphNode(
        id: id,
        kind: GraphNodeKind.note,
        label: n.displayTitle,
        color: await _folderColor(n.folderId),
        refId: n.id,
        noteVariant: _variant(n.kind),
      );
    }
    return id;
  }

  Future<void> _addSource(
      CanvasContextSource s, String fromId, GraphEdgeKind kind) async {
    switch (s.kind) {
      case CanvasSourceKind.note:
        final nid = s.noteId;
        if (nid == null) return;
        final n = await _noteRepo.getById(nid);
        if (n == null || !n.isActive) return;
        _edge(fromId, await _addNote(n), kind);
      case CanvasSourceKind.folder:
        final fid = s.folderId;
        if (fid != null) await _addFolder(fid, fromId, kind);
      case CanvasSourceKind.url:
        // URLs are intentionally not represented in the graph.
        return;
    }
  }

  /// Hop 2–3: expand every folder currently in the graph to its notes, then
  /// every note to its linked tasks (`note_task_links`) and AI-context links.
  /// AI targets are added as leaves (not further expanded) → bounded BFS.
  Future<void> _expandFoldersAndNotes() async {
    final folderIds = _nodes.values
        .where((n) => n.kind == GraphNodeKind.folder)
        .map((n) => n.refId!)
        .toList();
    for (final fid in folderIds) {
      final folderNodeId = GraphNode.idFor(GraphNodeKind.folder, refId: fid);
      final notes = await _noteRepo.getByFolder(fid);
      for (final n in notes) {
        if (!n.isActive) continue;
        _edge(folderNodeId, await _addNote(n), GraphEdgeKind.structure);
      }
    }

    final noteIds = _nodes.values
        .where((n) => n.kind == GraphNodeKind.note)
        .map((n) => n.refId!)
        .toList();
    for (final nid in noteIds) {
      final noteNodeId = GraphNode.idFor(GraphNodeKind.note, refId: nid);
      for (final tid in await _noteRepo.getLinkedTaskIds(nid)) {
        await _addTaskById(tid, noteNodeId, GraphEdgeKind.bridge);
      }
      for (final s in await _noteRepo.getContextSources(nid)) {
        await _addSource(s, noteNodeId, GraphEdgeKind.ai);
      }
    }
  }

  /// For every folder already in the graph, pull in its live FIGHT tasks (the
  /// `@folder` capture) — even if they were never sent to Lab. They attach to
  /// the folder via a bridge edge (added inside [_addTaskEntity]).
  Future<void> _addFolderTasks() async {
    final folderIds = _nodes.values
        .where((n) => n.kind == GraphNodeKind.folder)
        .map((n) => n.refId!)
        .toSet();
    if (folderIds.isEmpty) return;
    final live = [
      ...await _taskRepo.watchPending().first,
      ...await _taskRepo.watchYesterday().first,
      ...await _taskRepo.watchVencidas().first,
    ];
    for (final t in live) {
      if (t.folderId != null && folderIds.contains(t.folderId)) {
        await _addTaskEntity(t);
      }
    }
  }
}
