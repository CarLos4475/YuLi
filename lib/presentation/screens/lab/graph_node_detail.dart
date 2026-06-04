import 'package:flutter/material.dart';

import '../../../domain/models/graph.dart';
import '../../widgets/yuli_design.dart';

/// What the user chose to do from a node's detail sheet. The [GraphTab] owns the
/// Riverpod side-effects (navigation / mark-done) so this sheet stays ref-free.
enum GraphNodeAction { openNote, openFolder, openCard, markTaskDone }

String _kindLabel(GraphNode n) => switch (n.kind) {
      GraphNodeKind.space => 'ESPACIO',
      GraphNodeKind.card => 'TARJETA',
      GraphNodeKind.folder => 'CARPETA',
      GraphNodeKind.note => switch (n.noteVariant) {
          NoteVariant.whiteboard => 'PIZARRA',
          NoteVariant.notebook => 'CUADERNO',
          _ => 'NOTA',
        },
      GraphNodeKind.task => 'TAREA · FIGHT',
      GraphNodeKind.url => 'FUENTE URL',
    };

({String label, Color color}) _taskStateChip(TaskGraphState s) => switch (s) {
      TaskGraphState.fresca => (label: 'FRESCA', color: yLab),
      TaskGraphState.urgente => (label: 'URGENTE', color: yFight),
      TaskGraphState.ayer => (label: 'DE AYER', color: yMuted),
      TaskGraphState.fantasma => (label: 'FANTASMA', color: yMuted),
    };

/// Brutalist bottom sheet for a graph node. [accent] is the rooted space accent
/// (the sheet's identity color — NOT ink). Returns the chosen action or null.
Future<GraphNodeAction?> showGraphNodeDetail(
  BuildContext context,
  GraphNode node,
  GraphData data, {
  required Color accent,
}) {
  final connections =
      data.edges.where((e) => e.from == node.id || e.to == node.id).length;

  return showModalBottomSheet<GraphNodeAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final actions = <Widget>[];
      void act(String label, GraphNodeAction a, Color bg) {
        actions.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _SheetButton(
            label: label,
            bg: bg,
            onTap: () => Navigator.pop(ctx, a),
          ),
        ));
      }

      switch (node.kind) {
        case GraphNodeKind.note:
          act('Abrir nota  →', GraphNodeAction.openNote, node.color);
        case GraphNodeKind.folder:
          act('Abrir carpeta  →', GraphNodeAction.openFolder, node.color);
        case GraphNodeKind.card:
          act('Ver tarjeta  →', GraphNodeAction.openCard, accent);
        case GraphNodeKind.task:
          if (node.taskState != TaskGraphState.fantasma) {
            act('Marcar hecha  ✓', GraphNodeAction.markTaskDone, yLab);
          }
        case GraphNodeKind.space:
        case GraphNodeKind.url:
          break;
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 22,
              color: yInk,
              alignment: Alignment.center,
              child: Container(width: 56, height: 4, color: yCream),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: yCream,
                border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 14, height: 14, color: node.color),
                      const SizedBox(width: 8),
                      Text('> ${_kindLabel(node)}',
                          style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.6,
                              color: accent)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    node.label.isEmpty ? '(sin título)' : node.label,
                    style: ySans(size: 24, weight: FontWeight.w700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (node.taskState != null) ...[
                        _Chip(
                          label: _taskStateChip(node.taskState!).label,
                          color: _taskStateChip(node.taskState!).color,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _Chip(
                          label: '$connections CONEXIONES',
                          color: yMuted,
                          outline: true),
                    ],
                  ),
                  ...actions,
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.outline = false});
  final String label;
  final Color color;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? yCream : color,
        border: Border.all(color: outline ? yMuted : yInk, width: yLineThin),
      ),
      child: Text(label,
          style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: outline ? yMuted : yCream)),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton(
      {required this.label, required this.bg, required this.onTap});
  final String label;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        child: Text(label,
            style: ySans(
                size: 15, weight: FontWeight.w700, color: yCream)),
      ),
    );
  }
}
