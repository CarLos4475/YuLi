import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/graph.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../providers/database_providers.dart';

const knowledgeGraphNodeLimit = 300;

final _knowledgeNotesProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchAllActive();
});

final _knowledgeFoldersProvider = StreamProvider.autoDispose<List<Folder>>((
  ref,
) {
  return ref.watch(folderRepositoryProvider).watchActive();
});

final knowledgeGraphProvider = FutureProvider.autoDispose
    .family<KnowledgeGraphSnapshot, int?>((ref, folderId) async {
      final notes = await ref.watch(_knowledgeNotesProvider.future);
      final folders = await ref.watch(_knowledgeFoldersProvider.future);
      final ordered = [...notes]
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final scoped =
          folderId == null
              ? ordered.take(knowledgeGraphNodeLimit).toList()
              : <Note>[
                ...ordered.where((note) => note.folderId == folderId),
                ...ordered.where((note) => note.folderId != folderId),
              ].take(knowledgeGraphNodeLimit).toList();
      final blocks = await ref
          .watch(noteBlockRepositoryProvider)
          .getByNoteIds(scoped.map((note) => note.id).toList());
      return assembleKnowledgeGraph(
        notes: scoped,
        folders: folders,
        blocks: blocks,
        folderId: folderId,
        totalActiveNotes: notes.length,
      );
    });

class KnowledgeMention {
  final int sourceNoteId;
  final int targetNoteId;
  final String sourceNodeId;
  final String targetNodeId;
  final int count;

  const KnowledgeMention({
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.count,
  });

  String get directedKey => '$sourceNodeId>$targetNodeId';
}

class KnowledgeGraphSnapshot {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<KnowledgeMention> mentions;
  final Map<int, Note> notesById;
  final Map<int, Folder> foldersById;
  final int totalActiveNotes;
  final int scannedNotes;

  const KnowledgeGraphSnapshot({
    required this.nodes,
    required this.edges,
    required this.mentions,
    required this.notesById,
    required this.foldersById,
    required this.totalActiveNotes,
    required this.scannedNotes,
  });

  bool get wasLimited => scannedNotes < totalActiveNotes;

  GraphData graph({required bool includeIslands}) {
    if (includeIslands) return GraphData(nodes: nodes, edges: edges);
    final connected = <String>{};
    for (final edge in edges) {
      connected
        ..add(edge.from)
        ..add(edge.to);
    }
    return GraphData(
      nodes: nodes.where((node) => connected.contains(node.id)).toList(),
      edges: edges,
    );
  }

  List<KnowledgeMention> outgoing(String nodeId) =>
      mentions.where((mention) => mention.sourceNodeId == nodeId).toList();

  List<KnowledgeMention> incoming(String nodeId) =>
      mentions.where((mention) => mention.targetNodeId == nodeId).toList();

  GraphNode? nodeFor(String nodeId) {
    for (final node in nodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }
}

KnowledgeGraphSnapshot assembleKnowledgeGraph({
  required List<Note> notes,
  required List<Folder> folders,
  required List<NoteBlock> blocks,
  required int? folderId,
  int? totalActiveNotes,
}) {
  final noteById = {for (final note in notes) note.id: note};
  final folderById = {for (final folder in folders) folder.id: folder};
  final blocksByNote = <int, List<NoteBlock>>{};
  for (final block in blocks) {
    blocksByNote.putIfAbsent(block.noteId, () => []).add(block);
  }

  final documents = <_KnowledgeGraphDocument>[];
  for (final note in notes) {
    final title = note.displayTitle.trim();
    final drawings =
        (blocksByNote[note.id] ?? const <NoteBlock>[])
            .whereType<DrawingBlock>()
            .toList()
          ..sort((left, right) => left.position.compareTo(right.position));
    if (note.kind != NoteKind.whiteboard || drawings.isEmpty) {
      documents.add(
        _KnowledgeGraphDocument.note(note, label: _graphNoteLabel(note)),
      );
      continue;
    }
    documents.add(
      _KnowledgeGraphDocument.container(note, label: _graphNoteLabel(note)),
    );
    for (var index = 0; index < drawings.length; index++) {
      final canvas = drawings[index];
      final canvasLabel =
          canvas.name?.trim().isNotEmpty == true
              ? canvas.name!.trim()
              : 'Pizarra ${index + 1}';
      documents.add(
        _KnowledgeGraphDocument.canvas(
          note,
          canvas,
          label: title.isEmpty ? canvasLabel : '$title · $canvasLabel',
          canvasLabel: canvasLabel,
        ),
      );
    }
  }
  final documentById = {
    for (final document in documents) document.nodeId: document,
  };
  final aliases = <String, List<_KnowledgeGraphDocument>>{};
  for (final document in documents) {
    for (final alias in document.aliases) {
      final normalized = normalizeKnowledgeGraphLabel(alias);
      if (normalized.isEmpty) continue;
      aliases.putIfAbsent(normalized, () => []).add(document);
    }
    final folderLabel = folderById[document.note.folderId]?.name.trim();
    if (folderLabel != null && folderLabel.isNotEmpty) {
      final normalized = normalizeKnowledgeGraphLabel(
        '${document.label} · $folderLabel',
      );
      aliases.putIfAbsent(normalized, () => []).add(document);
    }
  }

  final mentionCounts = <String, _KnowledgeMentionSeed>{};
  for (final source in documents.where((document) => !document.isContainer)) {
    final text = source.text(blocksByNote[source.note.id] ?? const []);
    for (final label in knowledgeGraphLabelsFromText(text)) {
      final matches =
          aliases[normalizeKnowledgeGraphLabel(label)] ??
          aliases[normalizeKnowledgeGraphLabel(label.split('#').first)];
      if (matches == null || matches.isEmpty) continue;
      final target = matches.firstWhere(
        (document) => document.note.folderId == source.note.folderId,
        orElse: () => matches.first,
      );
      if (target.nodeId == source.nodeId) continue;
      final key = '${source.nodeId}>${target.nodeId}';
      final current = mentionCounts[key];
      mentionCounts[key] = _KnowledgeMentionSeed(
        source: source,
        target: target,
        count: (current?.count ?? 0) + 1,
      );
    }
  }

  final allMentions = [
    for (final seed in mentionCounts.values)
      KnowledgeMention(
        sourceNoteId: seed.source.note.id,
        targetNoteId: seed.target.note.id,
        sourceNodeId: seed.source.nodeId,
        targetNodeId: seed.target.nodeId,
        count: seed.count,
      ),
  ];

  final visibleMentions =
      folderId == null
          ? allMentions
          : allMentions.where((mention) {
            final source = documentById[mention.sourceNodeId];
            final target = documentById[mention.targetNodeId];
            return source?.note.folderId == folderId ||
                target?.note.folderId == folderId;
          }).toList();
  final relevantNodeIds =
      folderId == null
          ? <String>{
            ...documents
                .where((document) => document.showsAsIsland)
                .map((document) => document.nodeId),
            for (final mention in visibleMentions) mention.sourceNodeId,
            for (final mention in visibleMentions) mention.targetNodeId,
          }
          : <String>{
            ...documents
                .where(
                  (document) =>
                      document.showsAsIsland &&
                      document.note.folderId == folderId,
                )
                .map((document) => document.nodeId),
            for (final mention in visibleMentions) mention.sourceNodeId,
            for (final mention in visibleMentions) mention.targetNodeId,
          };

  final nodes = <GraphNode>[];
  for (final nodeId in relevantNodeIds) {
    final document = documentById[nodeId];
    if (document == null) continue;
    final folder = folderById[document.note.folderId];
    if (folder == null) continue;
    nodes.add(
      GraphNode(
        id: document.nodeId,
        kind: GraphNodeKind.note,
        label: document.label,
        color: folder.color,
        refId: document.note.id,
        canvasBlockId: document.canvas?.id,
        noteVariant: switch (document.note.kind) {
          NoteKind.block => NoteVariant.block,
          NoteKind.whiteboard => NoteVariant.whiteboard,
          NoteKind.notebook => NoteVariant.notebook,
        },
      ),
    );
  }
  nodes.sort(
    (left, right) =>
        left.label.toLowerCase().compareTo(right.label.toLowerCase()),
  );

  final edgeKeys = <String>{};
  final edges = <GraphEdge>[];
  for (final mention in visibleMentions) {
    final edge = GraphEdge(
      from: mention.sourceNodeId,
      to: mention.targetNodeId,
      kind: GraphEdgeKind.mention,
    );
    if (edgeKeys.add(edge.key)) edges.add(edge);
  }

  return KnowledgeGraphSnapshot(
    nodes: nodes,
    edges: edges,
    mentions: visibleMentions,
    notesById: noteById,
    foldersById: folderById,
    totalActiveNotes: totalActiveNotes ?? notes.length,
    scannedNotes: notes.length,
  );
}

String knowledgeGraphTextFromBlock(NoteBlock block) => switch (block) {
  TextBlock text => text.markdown,
  BulletsBlock bullets => bullets.items.join('\n'),
  DrawingBlock drawing => knowledgeGraphCanvasText(drawing.textBlocksJson),
  _ => '',
};

String _graphNoteLabel(Note note) =>
    note.displayTitle.trim().isEmpty ? 'Sin título' : note.displayTitle.trim();

class _KnowledgeGraphDocument {
  final Note note;
  final DrawingBlock? canvas;
  final String nodeId;
  final String label;
  final String? canvasLabel;
  final bool isContainer;

  const _KnowledgeGraphDocument._({
    required this.note,
    required this.canvas,
    required this.nodeId,
    required this.label,
    required this.canvasLabel,
    required this.isContainer,
  });

  factory _KnowledgeGraphDocument.note(Note note, {required String label}) =>
      _KnowledgeGraphDocument._(
        note: note,
        canvas: null,
        nodeId: GraphNode.idFor(GraphNodeKind.note, refId: note.id),
        label: label,
        canvasLabel: null,
        isContainer: false,
      );

  factory _KnowledgeGraphDocument.container(
    Note note, {
    required String label,
  }) => _KnowledgeGraphDocument._(
    note: note,
    canvas: null,
    nodeId: GraphNode.idFor(GraphNodeKind.note, refId: note.id),
    label: label,
    canvasLabel: null,
    isContainer: true,
  );

  factory _KnowledgeGraphDocument.canvas(
    Note note,
    DrawingBlock canvas, {
    required String label,
    required String canvasLabel,
  }) => _KnowledgeGraphDocument._(
    note: note,
    canvas: canvas,
    nodeId: 'canvas:${note.id}:${canvas.id}',
    label: label,
    canvasLabel: canvasLabel,
    isContainer: false,
  );

  bool get showsAsIsland => !isContainer;

  Iterable<String> get aliases sync* {
    yield label;
    if (canvasLabel != null) {
      yield canvasLabel!;
      yield '$canvasLabel · ${_graphNoteLabel(note)}';
      yield '${_graphNoteLabel(note)}#$canvasLabel';
    }
  }

  String text(List<NoteBlock> noteBlocks) {
    if (canvas != null) return knowledgeGraphTextFromBlock(canvas!);
    final segments = <String>{};
    if (note.rawMarkdown.trim().isNotEmpty) segments.add(note.rawMarkdown);
    for (final block in noteBlocks) {
      final value = knowledgeGraphTextFromBlock(block);
      if (value.trim().isNotEmpty) segments.add(value);
    }
    return segments.join('\n');
  }
}

class _KnowledgeMentionSeed {
  final _KnowledgeGraphDocument source;
  final _KnowledgeGraphDocument target;
  final int count;

  const _KnowledgeMentionSeed({
    required this.source,
    required this.target,
    required this.count,
  });
}

String knowledgeGraphCanvasText(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return '';
    return decoded
        .whereType<Map>()
        .map((item) => item['md']?.toString() ?? '')
        .join('\n');
  } catch (_) {
    return '';
  }
}

Iterable<String> knowledgeGraphLabelsFromText(String text) sync* {
  for (final match in RegExp(r'\[\[([^\]\n]{1,120})\]\]').allMatches(text)) {
    final label = match.group(1)?.trim();
    if (label != null && label.isNotEmpty) yield label;
  }
}

String normalizeKnowledgeGraphLabel(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
