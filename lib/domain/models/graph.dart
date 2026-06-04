import 'package:flutter/material.dart';
import 'kanban_card.dart';

/// Visual graph model (the "Grafo de Conexiones"). Pure data: an assembler
/// builds [GraphData] from the existing repositories and the render layer
/// (CustomPainter) draws it. No persistence — a snapshot of how a project's
/// things connect across the three modes.

enum GraphNodeKind { space, card, folder, note, task, url }

/// Note editor variant — drives the node glyph (block vs canvas notes).
enum NoteVariant { block, whiteboard, notebook }

/// The 4 lifecycle states of a FIGHT task, mapped from [TaskStatus]:
/// fresca=pending, urgente=pending+due≤24h, ayer=yesterday, fantasma=archived_failed.
/// Done/trash tasks are omitted from the graph (their card carries the done state).
enum TaskGraphState { fresca, urgente, ayer, fantasma }

/// 3 visual edge families:
/// - [structure]: "contains / lives in" (space→card, folder→note, space→source…)
/// - [bridge]: cross-mode "became / derived from" (card↔task, card→note, note→task, task→folder)
/// - [ai]: "feeds the AI context of" (note↔note/folder/url) — rendered with glow.
enum GraphEdgeKind { structure, bridge, ai }

class GraphNode {
  /// Stable string id, e.g. `space:1`, `card:3`, `note:5`, `url:https://…`.
  final String id;
  final GraphNodeKind kind;
  final String label;
  final Color color;

  /// Underlying DB id (null for url nodes).
  final int? refId;

  /// Set only for [GraphNodeKind.task].
  final TaskGraphState? taskState;

  /// Set only for [GraphNodeKind.card].
  final CardPriority? cardPriority;

  /// Set only for [GraphNodeKind.note].
  final NoteVariant? noteVariant;

  /// The root "sun" (the lab space the graph is rooted at).
  final bool isRoot;

  const GraphNode({
    required this.id,
    required this.kind,
    required this.label,
    required this.color,
    this.refId,
    this.taskState,
    this.cardPriority,
    this.noteVariant,
    this.isRoot = false,
  });

  static String idFor(GraphNodeKind kind, {int? refId, String? raw}) =>
      switch (kind) {
        GraphNodeKind.space => 'space:$refId',
        GraphNodeKind.card => 'card:$refId',
        GraphNodeKind.folder => 'folder:$refId',
        GraphNodeKind.note => 'note:$refId',
        GraphNodeKind.task => 'task:$refId',
        GraphNodeKind.url => 'url:${raw ?? ''}',
      };
}

class GraphEdge {
  final String from;
  final String to;
  final GraphEdgeKind kind;

  const GraphEdge({required this.from, required this.to, required this.kind});

  /// Direction-agnostic dedup key (an AI link note↔note is the same edge either
  /// way; structure/bridge edges never appear in both directions in practice).
  String get key {
    final a = from.compareTo(to) <= 0 ? from : to;
    final b = from.compareTo(to) <= 0 ? to : from;
    return '$a|$b|${kind.name}';
  }
}

class GraphData {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  const GraphData({required this.nodes, required this.edges});

  static const empty = GraphData(nodes: [], edges: []);

  bool get isEmpty => nodes.isEmpty;

  /// Node ids that are referenced by at least one AI edge (used to know whether
  /// the AI-glow layer / its animation is needed at all).
  bool get hasAiEdges => edges.any((e) => e.kind == GraphEdgeKind.ai);

  bool get hasUrgentTask =>
      nodes.any((n) => n.taskState == TaskGraphState.urgente);

  Set<String> get aiSourceNodeIds {
    final eligibleKinds = {
      for (final n in nodes)
        if (n.kind == GraphNodeKind.note || n.kind == GraphNodeKind.folder) n.id,
    };
    final ids = <String>{};
    for (final e in edges) {
      if (e.kind != GraphEdgeKind.ai) continue;
      if (!eligibleKinds.contains(e.to)) continue;
      if (e.from == e.to) continue;
      ids.add(e.to);
    }
    return ids;
  }
}
