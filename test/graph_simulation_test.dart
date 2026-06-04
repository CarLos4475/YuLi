import 'package:flutter/material.dart' show Color, Offset;
import 'package:flutter_test/flutter_test.dart';

import 'package:yuli/domain/models/graph.dart';
import 'package:yuli/presentation/screens/lab/graph_simulation.dart';

GraphData _sample({int notes = 10, int roots = 1}) {
  final nodes = <GraphNode>[];
  final edges = <GraphEdge>[];
  for (var r = 0; r < roots; r++) {
    nodes.add(GraphNode(
      id: 'space:$r',
      kind: GraphNodeKind.space,
      label: 'S$r',
      color: const Color(0xFF3D6B4F),
      refId: r,
      isRoot: true,
    ));
  }
  for (var i = 0; i < notes; i++) {
    nodes.add(GraphNode(
      id: 'note:$i',
      kind: GraphNodeKind.note,
      label: 'n$i',
      color: const Color(0xFF6B2D8E),
      refId: i,
      noteVariant: NoteVariant.block,
    ));
    edges.add(GraphEdge(
        from: 'space:${i % roots}', to: 'note:$i', kind: GraphEdgeKind.structure));
    if (i > 0) {
      edges.add(GraphEdge(
          from: 'note:${i - 1}', to: 'note:$i', kind: GraphEdgeKind.ai));
    }
  }
  return GraphData(nodes: nodes, edges: edges);
}

void main() {
  test('settle: posiciones finitas, sin NaN', () {
    final pos = GraphSimulation(_sample(notes: 20)).settle();
    for (final p in pos.values) {
      expect(p.dx.isFinite, isTrue);
      expect(p.dy.isFinite, isTrue);
    }
  });

  test('determinista: mismo seed → mismas posiciones', () {
    final a = GraphSimulation(_sample(), seed: 7).settle();
    final b = GraphSimulation(_sample(), seed: 7).settle();
    for (final id in a.keys) {
      expect(a[id]!.dx, b[id]!.dx);
      expect(a[id]!.dy, b[id]!.dy);
    }
  });

  test('raíz única pinneada en el origen', () {
    final pos = GraphSimulation(_sample()).settle();
    expect(pos['space:0'], Offset.zero);
  });

  test('se enfría: step termina devolviendo false', () {
    final sim = GraphSimulation(_sample(notes: 8));
    var steps = 0;
    while (sim.step()) {
      if (++steps > 2000) fail('no convergió');
    }
    expect(sim.step(), isFalse);
  });

  test('drag jala vecinos: fijar un nodo lejos mueve a su vecino', () {
    final sim = GraphSimulation(_sample(notes: 6))..settle();
    final neighborBefore = sim.posOf('note:1')!;
    // note:0 ↔ note:1 are linked; drag note:0 far away and re-run.
    sim.pin('note:0', const Offset(1200, 0));
    sim.reheat(0.6);
    var i = 0;
    while (i++ < 400 && sim.step()) {}
    final neighborAfter = sim.posOf('note:1')!;
    expect((neighborAfter - neighborBefore).distance, greaterThan(50));
  });

  test('colisión: tras asentar, ningún par de nodos se encima', () {
    final g = _sample(notes: 16);
    final sim = GraphSimulation(g)..settle();
    final nodes = g.nodes;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final pa = sim.posOf(nodes[i].id)!;
        final pb = sim.posOf(nodes[j].id)!;
        final minD = graphNodeRadius(nodes[i].kind) +
            graphNodeRadius(nodes[j].kind);
        // allow a little numerical slack; the key is they don't overlap
        expect((pa - pb).distance, greaterThan(minD * 0.85),
            reason: '${nodes[i].id} y ${nodes[j].id} encimados');
      }
    }
  });

  test('multi-raíz separadas', () {
    final pos = GraphSimulation(_sample(notes: 12, roots: 3)).settle();
    expect(pos['space:0'] != pos['space:1'], isTrue);
    expect(pos['space:1'] != pos['space:2'], isTrue);
  });
}
