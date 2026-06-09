import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/graph.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/task.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

class GraphNodeInspector extends ConsumerStatefulWidget {
  const GraphNodeInspector({
    super.key,
    required this.node,
    required this.data,
    required this.accent,
    required this.onClose,
    required this.onOpenNote,
    required this.onOpenFolder,
    required this.onOpenCard,
    required this.onMarkTaskDone,
    required this.onSelectNode,
  });

  final GraphNode node;
  final GraphData data;
  final Color accent;
  final VoidCallback onClose;
  final Future<void> Function(int noteId) onOpenNote;
  final Future<void> Function(int folderId) onOpenFolder;
  final Future<void> Function(int cardId) onOpenCard;
  final Future<void> Function(int taskId) onMarkTaskDone;
  final ValueChanged<GraphNode> onSelectNode;

  @override
  ConsumerState<GraphNodeInspector> createState() => _GraphNodeInspectorState();
}

class _GraphNodeInspectorState extends ConsumerState<GraphNodeInspector> {
  // Cached so the inspector doesn't re-query the DB (spinner flicker) on every
  // unrelated rebuild — only when the node changes or the underlying graph data
  // is replaced (real-time update).
  late Future<_InspectorData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(GraphNodeInspector old) {
    super.didUpdateWidget(old);
    if (old.node.id != widget.node.id || !identical(old.data, widget.data)) {
      _future = _load();
    }
  }

  Future<_InspectorData> _load() => _loadInspector(
        ref,
        widget.node,
        widget.data,
        _relatedNodes(widget.node, widget.data),
      );

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final panelWidth = math.min(MediaQuery.sizeOf(context).width * 0.34, 336.0);
    return Align(
      alignment: Alignment.centerRight,
      // Absorb pointers so taps/drags on the panel don't fall through to the
      // graph's gesture detector behind it (which would pan / deselect).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: panelWidth,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: yCream,
              border: Border(
                  left: BorderSide(color: yBorderStrong, width: yLineHeavy)),
            ),
            child: FutureBuilder<_InspectorData>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return _InspectorShell(
                    headerColor:
                        node.kind == GraphNodeKind.space ? widget.accent : node.color,
                    kindLabel: _kindLabel(node),
                    title: node.label.isEmpty ? '(SIN TITULO)' : node.label,
                    onClose: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    ),
                  );
                }
                final loaded = snap.data!;
                return _InspectorShell(
                  headerColor: loaded.headerColor,
                  kindLabel: loaded.kindLabel,
                  title: loaded.title,
                  onClose: widget.onClose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: _bodyForLoaded(loaded),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyForLoaded(_InspectorData loaded) {
    switch (loaded) {
      case _TaskInspectorData task:
        return _TaskInspectorBody(
          data: task,
          onMarkDone: task.taskState == TaskGraphState.fantasma
              ? null
              : () async => widget.onMarkTaskDone(task.task.id),
          onOpenFolder:
              task.folder == null ? null : () async => widget.onOpenFolder(task.folder!.id),
          onSelectFolder: task.folder == null
              ? null
              : () => _selectNode(GraphNodeKind.folder, task.folder!.id),
          onSelectNote: (noteId) => _selectNode(GraphNodeKind.note, noteId),
        );
      case _FolderInspectorData folder:
        return _FolderInspectorBody(
          data: folder,
          onOpenFolder: () async => widget.onOpenFolder(folder.folder.id),
          onSelectNote: (noteId) => _selectNode(GraphNodeKind.note, noteId),
        );
      case _NoteInspectorData note:
        return _NoteInspectorBody(
          data: note,
          onOpenNote: () async => widget.onOpenNote(note.note.id),
          onSelectFolder:
              note.folder == null ? null : () => _selectNode(GraphNodeKind.folder, note.folder!.id),
          onSelectRelatedNode: widget.onSelectNode,
        );
      case _CardInspectorData card:
        return _CardInspectorBody(
          data: card,
          onOpenCard: () async => widget.onOpenCard(card.card.id),
          onSelectSourceNote: card.sourceNote == null
              ? null
              : () => _selectNode(GraphNodeKind.note, card.sourceNote!.id),
          onSelectOriginTask: card.originTask == null
              ? null
              : () => _selectNode(GraphNodeKind.task, card.originTask!.id),
        );
      case _SpaceInspectorData space:
        return _SpaceInspectorBody(data: space);
      case _BasicInspectorData basic:
        return _BasicInspectorBody(data: basic);
    }
    throw StateError('UNREACHABLE');
  }

  void _selectNode(GraphNodeKind kind, int refId) {
    for (final candidate in widget.data.nodes) {
      if (candidate.kind == kind && candidate.refId == refId) {
        widget.onSelectNode(candidate);
        break;
      }
    }
  }
}

Future<_InspectorData> _loadInspector(
  WidgetRef ref,
  GraphNode node,
  GraphData data,
  List<GraphNode> related,
) async {
  final taskRepo = ref.read(taskRepositoryProvider);
  final folderRepo = ref.read(folderRepositoryProvider);
  final noteRepo = ref.read(noteRepositoryProvider);
  final blockRepo = ref.read(noteBlockRepositoryProvider);
  final cardRepo = ref.read(kanbanCardRepositoryProvider);
  final labRepo = ref.read(labSpaceRepositoryProvider);

  switch (node.kind) {
    case GraphNodeKind.task:
      final task = node.refId == null ? null : await taskRepo.getById(node.refId!);
      if (task == null) return _BasicInspectorData.fromNode(node, related.length);
      final folder = task.folderId == null ? null : await folderRepo.getById(task.folderId!);
      final linkedCard = await cardRepo.getByOriginTaskId(task.id);
      final linkedNoteIds = await noteRepo.getLinkedNoteIds(task.id);
      final linkedNotes = <Note>[];
      for (final id in linkedNoteIds) {
        final note = await noteRepo.getById(id);
        if (note != null && note.isActive) linkedNotes.add(note);
      }
      LabSpace? linkedSpace;
      if (linkedCard != null) linkedSpace = await labRepo.getById(linkedCard.labSpaceId);
      return _TaskInspectorData(
        node: node,
        task: task,
        folder: folder,
        linkedCard: linkedCard,
        linkedSpace: linkedSpace,
        linkedNotes: linkedNotes,
        taskState: node.taskState,
        connections: related.length,
      );
    case GraphNodeKind.folder:
      final folder = node.refId == null ? null : await folderRepo.getById(node.refId!);
      if (folder == null) return _BasicInspectorData.fromNode(node, related.length);
      final notes = await noteRepo.getByFolder(folder.id);
      final activeNotes = [...notes.where((n) => n.isActive)]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final tasks = await taskRepo.getPendingForFolder(folder.id);
      final spaceIds = await labRepo.getLinkedSpaceIdsForFolder(folder.id);
      final spaces = await labRepo.getActive();
      final linkedSpaces = spaces.where((s) => spaceIds.contains(s.id)).toList();
      final aiFeeds = data.edges.where((e) => e.kind == GraphEdgeKind.ai && e.to == node.id).length;
      return _FolderInspectorData(
        node: node,
        folder: folder,
        notes: activeNotes,
        pendingTasks: tasks,
        linkedSpaces: linkedSpaces,
        aiFeeds: aiFeeds,
        connections: related.length,
      );
    case GraphNodeKind.note:
      final note = node.refId == null ? null : await noteRepo.getById(node.refId!);
      if (note == null) return _BasicInspectorData.fromNode(node, related.length);
      final folder = await folderRepo.getById(note.folderId);
      final blocks = await blockRepo.watchByNote(note.id).first;
      final linkedTasks = await noteRepo.getLinkedTaskIds(note.id);
      final linkedCards = await cardRepo.watchBySourceNoteId(note.id).first;
      final aiRelated = related
          .where((n) => data.edges.any((e) =>
              e.kind == GraphEdgeKind.ai &&
              ((e.from == node.id && e.to == n.id) || (e.to == node.id && e.from == n.id))))
          .toList();
      return _NoteInspectorData(
        node: node,
        note: note,
        folder: folder,
        blockCount: blocks.length,
        linkedTaskCount: linkedTasks.length,
        linkedCardCount: linkedCards.length,
        aiRelated: aiRelated,
        connections: related.length,
      );
    case GraphNodeKind.card:
      final card = node.refId == null ? null : await cardRepo.getById(node.refId!);
      if (card == null) return _BasicInspectorData.fromNode(node, related.length);
      final space = await labRepo.getById(card.labSpaceId);
      final columns = await labRepo.getColumns(card.labSpaceId);
      KanbanColumn? column;
      for (final c in columns) {
        if (c.id == card.columnId) {
          column = c;
          break;
        }
      }
      final sourceNote =
          card.sourceNoteId == null ? null : await noteRepo.getById(card.sourceNoteId!);
      final originTask =
          card.originTaskId == null ? null : await taskRepo.getById(card.originTaskId!);
      return _CardInspectorData(
        node: node,
        card: card,
        space: space,
        column: column,
        sourceNote: sourceNote,
        originTask: originTask,
        connections: related.length,
      );
    case GraphNodeKind.space:
      return _SpaceInspectorData(
        node: node,
        folderCount: data.nodes.where((n) => n.kind == GraphNodeKind.folder).length,
        noteCount: data.nodes.where((n) => n.kind == GraphNodeKind.note).length,
        taskCount: data.nodes.where((n) => n.kind == GraphNodeKind.task).length,
        cardCount: data.nodes.where((n) => n.kind == GraphNodeKind.card).length,
        aiConnections: data.edges.where((e) => e.kind == GraphEdgeKind.ai).length,
        connections: related.length,
      );
    case GraphNodeKind.url:
      return _BasicInspectorData.fromNode(node, related.length);
  }
}

List<GraphNode> _relatedNodes(GraphNode node, GraphData data) {
  final ids = <String>{};
  for (final e in data.edges) {
    if (e.from == node.id) ids.add(e.to);
    if (e.to == node.id) ids.add(e.from);
  }
  return data.nodes.where((n) => ids.contains(n.id)).toList();
}

String _kindLabel(GraphNode n) => switch (n.kind) {
      GraphNodeKind.space => 'ESPACIO',
      GraphNodeKind.card => 'TARJETA',
      GraphNodeKind.folder => 'CARPETA',
      GraphNodeKind.note => switch (n.noteVariant) {
          NoteVariant.whiteboard => 'PIZARRA',
          NoteVariant.notebook => 'CUADERNO',
          _ => 'NOTA',
        },
      GraphNodeKind.task => 'TAREA',
      GraphNodeKind.url => 'FUENTE',
    };

String _fmtDate(DateTime dt, {bool withTime = false}) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year.toString();
  if (!withTime) return '$dd/$mm/$yyyy';
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$dd/$mm/$yyyy · $hh:$min';
}

String _fmtSince(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return 'HACE ${diff.inMinutes} M';
  if (diff.inHours < 24) return 'HACE ${diff.inHours} H';
  if (diff.inDays < 7) return 'HACE ${diff.inDays} D';
  return _fmtDate(dt);
}

String _priorityLabel(CardPriority p) => switch (p) {
      CardPriority.none => 'SIN PRIORIDAD',
      CardPriority.low => 'BAJA',
      CardPriority.medium => 'MEDIA',
      CardPriority.high => 'ALTA',
    };

({String label, Color color}) _taskStateChip(TaskGraphState s) => switch (s) {
      TaskGraphState.fresca => (label: 'FRESCA', color: yLab),
      TaskGraphState.urgente => (label: 'URGENTE', color: yFight),
      TaskGraphState.ayer => (label: 'DE AYER', color: yMuted),
      TaskGraphState.fantasma => (label: 'FANTASMA', color: yMuted),
    };

abstract class _InspectorData {
  const _InspectorData({
    required this.node,
    required this.connections,
    required this.headerColor,
  });

  final GraphNode node;
  final int connections;
  final Color headerColor;

  String get kindLabel => _kindLabel(node);
  String get title => node.label.isEmpty ? '(SIN TITULO)' : node.label;
}

class _BasicInspectorData extends _InspectorData {
  const _BasicInspectorData({
    required super.node,
    required super.connections,
    required super.headerColor,
  });

  factory _BasicInspectorData.fromNode(GraphNode node, int connections) =>
      _BasicInspectorData(
        node: node,
        connections: connections,
        headerColor: node.color,
      );
}

class _TaskInspectorData extends _InspectorData {
  _TaskInspectorData({
    required super.node,
    required this.task,
    required this.folder,
    required this.linkedCard,
    required this.linkedSpace,
    required this.linkedNotes,
    required this.taskState,
    required super.connections,
  }) : super(headerColor: node.color);

  final Task task;
  final Folder? folder;
  final KanbanCard? linkedCard;
  final LabSpace? linkedSpace;
  final List<Note> linkedNotes;
  final TaskGraphState? taskState;
}

class _FolderInspectorData extends _InspectorData {
  _FolderInspectorData({
    required super.node,
    required this.folder,
    required this.notes,
    required this.pendingTasks,
    required this.linkedSpaces,
    required this.aiFeeds,
    required super.connections,
  }) : super(headerColor: node.color);

  final Folder folder;
  final List<Note> notes;
  final List<Task> pendingTasks;
  final List<LabSpace> linkedSpaces;
  final int aiFeeds;
}

class _NoteInspectorData extends _InspectorData {
  _NoteInspectorData({
    required super.node,
    required this.note,
    required this.folder,
    required this.blockCount,
    required this.linkedTaskCount,
    required this.linkedCardCount,
    required this.aiRelated,
    required super.connections,
  }) : super(headerColor: node.color);

  final Note note;
  final Folder? folder;
  final int blockCount;
  final int linkedTaskCount;
  final int linkedCardCount;
  final List<GraphNode> aiRelated;
}

class _CardInspectorData extends _InspectorData {
  _CardInspectorData({
    required super.node,
    required this.card,
    required this.space,
    required this.column,
    required this.sourceNote,
    required this.originTask,
    required super.connections,
  }) : super(headerColor: node.color);

  final KanbanCard card;
  final LabSpace? space;
  final KanbanColumn? column;
  final Note? sourceNote;
  final Task? originTask;
}

class _SpaceInspectorData extends _InspectorData {
  _SpaceInspectorData({
    required super.node,
    required this.folderCount,
    required this.noteCount,
    required this.taskCount,
    required this.cardCount,
    required this.aiConnections,
    required super.connections,
  }) : super(headerColor: node.color);

  final int folderCount;
  final int noteCount;
  final int taskCount;
  final int cardCount;
  final int aiConnections;
}

class _InspectorShell extends StatelessWidget {
  const _InspectorShell({
    required this.headerColor,
    required this.kindLabel,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final Color headerColor;
  final String kindLabel;
  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: headerColor,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kindLabel,
                      style: yMono(
                        size: 10,
                        weight: FontWeight.w700,
                        tracking: 1.8,
                        color: yCream.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: ySans(
                        size: 17,
                        weight: FontWeight.w700,
                        color: yCream,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: yCream, width: yLineThin),
                  ),
                  child: const Icon(YuLiIcons.close, size: 18, color: yCream),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _TaskInspectorBody extends StatelessWidget {
  const _TaskInspectorBody({
    required this.data,
    required this.onMarkDone,
    required this.onOpenFolder,
    required this.onSelectFolder,
    required this.onSelectNote,
  });

  final _TaskInspectorData data;
  final Future<void> Function()? onMarkDone;
  final Future<void> Function()? onOpenFolder;
  final VoidCallback? onSelectFolder;
  final ValueChanged<int> onSelectNote;

  @override
  Widget build(BuildContext context) {
    final state = data.taskState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state != null) _chip(_taskStateChip(state).label, _taskStateChip(state).color),
        const SizedBox(height: 14),
        if (data.folder != null)
          _linkedBox(
            data.folder!.name,
            swatch: data.folder!.color,
            onTap: onSelectFolder,
          ),
        const SizedBox(height: 16),
        _metaLine('CAPTURADA', _fmtDate(data.task.createdAt, withTime: true)),
        if (data.task.dueDate != null)
          _metaLine(
            'VENCE',
            _fmtDate(data.task.dueDate!, withTime: true),
            valueColor: state == TaskGraphState.urgente ? yFight : yInk,
          ),
        _metaLine('CONEXIONES GRAFO', '${data.connections}'),
        _metaLine('NOTAS LINKED', '${data.linkedNotes.length}'),
        if (data.linkedSpace != null) _metaLine('EN LAB', data.linkedSpace!.name),
        const SizedBox(height: 18),
        if (data.linkedNotes.isNotEmpty) ...[
          _sectionLabel('> NOTAS RELACIONADAS'),
          const SizedBox(height: 10),
          ...data.linkedNotes.take(3).map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _linkedBox(n.displayTitle, onTap: () => onSelectNote(n.id)),
              )),
          const SizedBox(height: 8),
        ],
        if (onMarkDone != null) _cta('MARCAR HECHA', onMarkDone!, bg: yInk),
        if (onOpenFolder != null) ...[
          const SizedBox(height: 10),
          _cta('ABRIR CARPETA', onOpenFolder!, bg: data.folder!.color),
        ],
      ],
    );
  }
}

class _FolderInspectorBody extends StatelessWidget {
  const _FolderInspectorBody({
    required this.data,
    required this.onOpenFolder,
    required this.onSelectNote,
  });

  final _FolderInspectorData data;
  final Future<void> Function() onOpenFolder;
  final ValueChanged<int> onSelectNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statBox('${data.notes.length}', 'NOTAS')),
            const SizedBox(width: 10),
            Expanded(child: _statBox('${data.pendingTasks.length}', 'TAREAS')),
          ],
        ),
        const SizedBox(height: 16),
        _metaLine(
          'ULTIMA EDICION',
          data.notes.isEmpty ? '-' : _fmtSince(data.notes.first.updatedAt),
        ),
        _metaLine(
          'EN ESPACIOS',
          data.linkedSpaces.isEmpty ? '-' : data.linkedSpaces.map((s) => s.name).join(' · '),
        ),
        _metaLine('NUTRE IA', data.aiFeeds > 0 ? 'SI · ${data.aiFeeds}' : 'NO'),
        const SizedBox(height: 18),
        _sectionLabel('> NOTAS RECIENTES'),
        const SizedBox(height: 10),
        if (data.notes.isEmpty)
          _emptyBox('SIN NOTAS ACTIVAS')
        else
          ...data.notes.take(3).map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _linkedBox(
                  n.displayTitle,
                  swatch: data.folder.color,
                  onTap: () => onSelectNote(n.id),
                ),
              )),
        const SizedBox(height: 16),
        _cta('ABRIR CARPETA', onOpenFolder, bg: yInk),
      ],
    );
  }
}

class _NoteInspectorBody extends StatelessWidget {
  const _NoteInspectorBody({
    required this.data,
    required this.onOpenNote,
    required this.onSelectFolder,
    required this.onSelectRelatedNode,
  });

  final _NoteInspectorData data;
  final Future<void> Function() onOpenNote;
  final VoidCallback? onSelectFolder;
  final ValueChanged<GraphNode> onSelectRelatedNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.folder != null)
          _linkedBox(
            data.folder!.name,
            swatch: data.folder!.color,
            onTap: onSelectFolder,
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _statBox(_fmtSince(data.note.updatedAt), 'EDITADA'),
        ),
        const SizedBox(height: 16),
        _metaLine('TIPO', _kindLabel(data.node)),
        _metaLine('BLOQUES', '${data.blockCount}'),
        _metaLine('TAREAS LINKED', '${data.linkedTaskCount}'),
        _metaLine('TARJETAS LINKED', '${data.linkedCardCount}'),
        const SizedBox(height: 18),
        _sectionLabel('> CONEXIONES IA'),
        const SizedBox(height: 10),
        if (data.aiRelated.isEmpty)
          _emptyBox('SIN CONEXIONES SEMANTICAS')
        else
          ...data.aiRelated.take(4).map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _linkedBox(
                  n.label,
                  dashed: true,
                  swatch: n.kind == GraphNodeKind.folder ? n.color : null,
                  onTap: () => onSelectRelatedNode(n),
                ),
              )),
        const SizedBox(height: 16),
        _cta('ABRIR NOTA', onOpenNote, bg: yFight),
      ],
    );
  }
}

class _CardInspectorBody extends StatelessWidget {
  const _CardInspectorBody({
    required this.data,
    required this.onOpenCard,
    required this.onSelectSourceNote,
    required this.onSelectOriginTask,
  });

  final _CardInspectorData data;
  final Future<void> Function() onOpenCard;
  final VoidCallback? onSelectSourceNote;
  final VoidCallback? onSelectOriginTask;

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (data.card.priority) {
      CardPriority.high => yFight,
      CardPriority.medium => yAmber,
      CardPriority.low => yLab,
      CardPriority.none => yMuted,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chip(_priorityLabel(data.card.priority), priorityColor),
        const SizedBox(height: 14),
        if (data.space != null) _linkedBox(data.space!.name, swatch: data.space!.accentColor),
        const SizedBox(height: 16),
        _metaLine('COLUMNA', data.column?.name ?? '-'),
        if (data.card.startDate != null) _metaLine('INICIO', _fmtDate(data.card.startDate!)),
        if (data.card.dueDate != null) _metaLine('VENCE', _fmtDate(data.card.dueDate!)),
        _metaLine('DESDE TASK', data.originTask == null ? 'NO' : 'SI'),
        _metaLine('DESDE NOTA', data.sourceNote == null ? 'NO' : 'SI'),
        const SizedBox(height: 18),
        if (data.sourceNote != null || data.originTask != null) ...[
          _sectionLabel('> ORIGEN'),
          const SizedBox(height: 10),
          if (data.sourceNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _linkedBox(
                data.sourceNote!.displayTitle,
                onTap: onSelectSourceNote,
              ),
            ),
          if (data.originTask != null)
            _linkedBox(
              data.originTask!.content,
              onTap: onSelectOriginTask,
            ),
          const SizedBox(height: 16),
        ],
        _cta('VER TARJETA', onOpenCard, bg: yInk),
      ],
    );
  }
}

class _SpaceInspectorBody extends StatelessWidget {
  const _SpaceInspectorBody({required this.data});

  final _SpaceInspectorData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statBox('${data.noteCount}', 'NOTAS')),
            const SizedBox(width: 10),
            Expanded(child: _statBox('${data.taskCount}', 'TAREAS')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _statBox('${data.folderCount}', 'CARPETAS')),
            const SizedBox(width: 10),
            Expanded(child: _statBox('${data.cardCount}', 'TARJETAS')),
          ],
        ),
        const SizedBox(height: 18),
        _metaLine('CONEXIONES IA', '${data.aiConnections}'),
        _metaLine('VISIBLES', '${data.connections} CONEXIONES'),
      ],
    );
  }
}

class _BasicInspectorBody extends StatelessWidget {
  const _BasicInspectorBody({required this.data});

  final _BasicInspectorData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _metaLine('CONEXIONES', '${data.connections}'),
      ],
    );
  }
}

Widget _chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Text(
        label,
        style: yMono(
          size: 9,
          weight: FontWeight.w700,
          tracking: 1.4,
          color: yCream,
        ),
      ),
    );

Widget _statBox(String value, String label) => Container(
      height: 82,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: ySans(
              size: 22,
              weight: FontWeight.w700,
              color: yInk,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.5,
              color: yMuted,
            ),
          ),
        ],
      ),
    );

Widget _linkedBox(String label,
        {Color? swatch, bool dashed = false, VoidCallback? onTap}) =>
    GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(
            color: dashed ? yFlight.withValues(alpha: 0.6) : yBorderStrong,
            width: yLineThin,
          ),
        ),
        child: Row(
          children: [
            if (swatch != null) ...[
              Container(width: 10, height: 10, color: swatch),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ySans(size: 12, weight: FontWeight.w600, color: yInk),
              ),
            ),
          ],
        ),
      ),
    );

Widget _emptyBox(String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderSoft, width: yLineThin),
      ),
      child: Text(text, style: yBody(size: 12, color: yMuted)),
    );

Widget _sectionLabel(String label) => Text(
      label,
      style: yMono(
        size: 10,
        weight: FontWeight.w700,
        tracking: 1.8,
        color: yMuted,
      ),
    );

Widget _metaLine(String label, String value, {Color? valueColor}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.8,
              color: yMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: ySans(
              size: 13,
              weight: FontWeight.w700,
              color: valueColor ?? yInk,
            ),
          ),
        ],
      ),
    );

Widget _cta(String label, Future<void> Function() onTap, {required Color bg}) =>
    GestureDetector(
      onTap: () => onTap(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yBorderStrong, width: yLineHeavy),
      ),
        child: Text(
          label,
          style: ySans(size: 15, weight: FontWeight.w700, color: yCream),
        ),
      ),
    );
