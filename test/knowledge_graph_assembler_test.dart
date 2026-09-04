import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/graph.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/presentation/screens/flight/knowledge_graph_assembler.dart';

void main() {
  final now = DateTime(2026, 9, 3);

  Folder folder(int id, String name, Color color) =>
      Folder(id: id, name: name, color: color, createdAt: now);

  Note note(
    int id,
    int folderId,
    String title, {
    String markdown = '',
    NoteKind kind = NoteKind.block,
    Color? color,
  }) => Note(
    id: id,
    folderId: folderId,
    title: title,
    rawMarkdown: markdown,
    sizeBytes: markdown.length,
    createdAt: now,
    updatedAt: now,
    color: color,
    kind: kind,
  );

  test(
    'Arma aristas dirigidas, agrega repeticiones y usa color de carpeta',
    () {
      const blue = Color(0xFF2D3F8C);
      const amber = Color(0xFFC7822F);
      final snapshot = assembleKnowledgeGraph(
        notes: [
          note(
            1,
            1,
            'Álgebra',
            markdown: 'Consulta [[Límites]] y otra vez [[Límites]].',
            color: const Color(0xFFFF0000),
          ),
          note(2, 1, 'Límites'),
          note(3, 2, 'Derivadas'),
          note(4, 2, 'Isla'),
        ],
        folders: [folder(1, 'Cálculo', blue), folder(2, 'Física', amber)],
        blocks: const [
          TextBlock(
            id: 20,
            noteId: 2,
            position: 0,
            markdown: 'Regresa a [[Álgebra]].',
          ),
          DrawingBlock(
            id: 30,
            noteId: 3,
            position: 0,
            height: 300,
            strokesJson: '[]',
            textBlocksJson: '[{"md":"[[Álgebra]]"}]',
          ),
        ],
        folderId: null,
      );

      expect(snapshot.mentions, hasLength(3));
      expect(
        snapshot.mentions
            .firstWhere(
              (mention) =>
                  mention.sourceNoteId == 1 && mention.targetNoteId == 2,
            )
            .count,
        2,
      );
      expect(snapshot.edges, hasLength(2));
      expect(snapshot.nodes.firstWhere((node) => node.refId == 1).color, blue);
      expect(snapshot.graph(includeIslands: false).nodes, hasLength(3));
      expect(snapshot.graph(includeIslands: true).nodes, hasLength(4));
      expect(
        snapshot.edges.every((edge) => edge.kind == GraphEdgeKind.mention),
        isTrue,
      );
    },
  );

  test(
    'El mapa de carpeta incluye vecinos externos pero no islas externas',
    () {
      const blue = Color(0xFF2D3F8C);
      const amber = Color(0xFFC7822F);
      final snapshot = assembleKnowledgeGraph(
        notes: [
          note(1, 1, 'Álgebra', markdown: '[[Derivadas#Pizarra 2]]'),
          note(2, 1, 'Límites'),
          note(3, 2, 'Derivadas', kind: NoteKind.whiteboard),
          note(4, 2, 'Isla'),
        ],
        folders: [folder(1, 'Cálculo', blue), folder(2, 'Física', amber)],
        blocks: const [],
        folderId: 1,
      );

      expect(snapshot.nodes.map((node) => node.refId), containsAll([1, 2, 3]));
      expect(snapshot.nodes.map((node) => node.refId), isNot(contains(4)));
      expect(snapshot.graph(includeIslands: false).nodes, hasLength(2));
      expect(snapshot.graph(includeIslands: true).nodes, hasLength(3));
    },
  );
}
