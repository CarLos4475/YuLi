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
  final int count;

  const KnowledgeMention({
    required this.sourceNoteId,
    required this.targetNoteId,
    required this.count,
  });

  String get directedKey => '$sourceNoteId>$targetNoteId';
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

  List<KnowledgeMention> outgoing(int noteId) =>
      mentions.where((mention) => mention.sourceNoteId == noteId).toList();

  List<KnowledgeMention> incoming(int noteId) =>
      mentions.where((mention) => mention.targetNoteId == noteId).toList();
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

  final aliases = <String, List<Note>>{};
  for (final note in notes) {
    final label = normalizeKnowledgeGraphLabel(note.displayTitle);
    if (label.isEmpty) continue;
    aliases.putIfAbsent(label, () => []).add(note);
  }

  final mentionCounts = <String, int>{};
  for (final source in notes) {
    final segments = <String>{};
    if (source.rawMarkdown.trim().isNotEmpty) {
      segments.add(source.rawMarkdown);
    }
    for (final block in blocksByNote[source.id] ?? const <NoteBlock>[]) {
      final text = knowledgeGraphTextFromBlock(block);
      if (text.trim().isNotEmpty) segments.add(text);
    }
    for (final label in knowledgeGraphLabelsFromText(segments.join('\n'))) {
      final documentLabel = label.split('#').first.trim();
      final matches = aliases[normalizeKnowledgeGraphLabel(documentLabel)];
      if (matches == null || matches.isEmpty) continue;
      final target = matches.firstWhere(
        (note) => note.folderId == source.folderId,
        orElse: () => matches.first,
      );
      if (target.id == source.id) continue;
      final key = '${source.id}>${target.id}';
      mentionCounts[key] = (mentionCounts[key] ?? 0) + 1;
    }
  }

  final allMentions = <KnowledgeMention>[];
  for (final entry in mentionCounts.entries) {
    final separator = entry.key.indexOf('>');
    allMentions.add(
      KnowledgeMention(
        sourceNoteId: int.parse(entry.key.substring(0, separator)),
        targetNoteId: int.parse(entry.key.substring(separator + 1)),
        count: entry.value,
      ),
    );
  }

  final visibleMentions =
      folderId == null
          ? allMentions
          : allMentions.where((mention) {
            final source = noteById[mention.sourceNoteId];
            final target = noteById[mention.targetNoteId];
            return source?.folderId == folderId || target?.folderId == folderId;
          }).toList();
  final relevantIds =
      folderId == null
          ? noteById.keys.toSet()
          : <int>{
            ...notes
                .where((note) => note.folderId == folderId)
                .map((note) => note.id),
            for (final mention in visibleMentions) mention.sourceNoteId,
            for (final mention in visibleMentions) mention.targetNoteId,
          };

  final nodes = <GraphNode>[];
  for (final noteId in relevantIds) {
    final note = noteById[noteId];
    if (note == null) continue;
    final folder = folderById[note.folderId];
    if (folder == null) continue;
    nodes.add(
      GraphNode(
        id: GraphNode.idFor(GraphNodeKind.note, refId: note.id),
        kind: GraphNodeKind.note,
        label:
            note.displayTitle.trim().isEmpty ? 'Sin título' : note.displayTitle,
        color: folder.color,
        refId: note.id,
        noteVariant: switch (note.kind) {
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
      from: GraphNode.idFor(GraphNodeKind.note, refId: mention.sourceNoteId),
      to: GraphNode.idFor(GraphNodeKind.note, refId: mention.targetNoteId),
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
