import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/canvas_ocr.dart';
import '../../../domain/repositories/canvas_ocr_repository.dart';
import '../../local/database.dart';

class LocalCanvasOcrRepository implements CanvasOcrRepository {
  final AppDatabase db;
  LocalCanvasOcrRepository(this.db);

  static Future<void> invalidate(AppDatabase db, Iterable<int> blockIds) async {
    for (final id in blockIds.toSet()) {
      await db.customUpdate(
        'INSERT INTO canvas_ocr_pages (block_id, revision) '
        'SELECT id, 1 FROM note_blocks WHERE id = ? AND type = ? '
        'ON CONFLICT(block_id) DO UPDATE SET revision = revision + 1',
        variables: [Variable.withInt(id), Variable.withString('drawing')],
        updates: {db.canvasOcrPages},
      );
    }
  }

  @override
  Future<CanvasOcrPage?> read(int blockId) => db.transaction(() async {
    await db.customUpdate(
      'INSERT INTO canvas_ocr_pages (block_id) '
      'SELECT b.id FROM note_blocks b JOIN notes n ON n.id = b.note_id '
      'JOIN folders f ON f.id = n.folder_id '
      'WHERE b.id = ? AND b.type = ? AND n.deleted_at IS NULL '
      'AND f.deleted_at IS NULL ON CONFLICT(block_id) DO NOTHING',
      variables: [Variable.withInt(blockId), Variable.withString('drawing')],
      updates: {db.canvasOcrPages},
    );
    final rows = await _rows(blockId: blockId, currentOnly: false);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CanvasOcrPage(
      blockId,
      row.read<int>('revision'),
      row.read<int>('revision') == row.readNullable<int>('indexed_revision'),
      _segments(row.read<String>('segments')),
    );
  });

  @override
  Future<bool> save(
    int blockId,
    int revision,
    List<CanvasOcrSegment> segments,
  ) async {
    if (segments.length > 10000 ||
        segments.any(
          (s) =>
              s.text.length > 8000 ||
              s.effectiveText.length > 8000 ||
              s.words.length > 64 ||
              s.words.any(
                (w) =>
                    w.start < 0 ||
                    w.end <= w.start ||
                    w.end > s.effectiveText.length ||
                    !w.bounds.isFinite ||
                    w.bounds.isEmpty,
              ) ||
              s.spelling.any(
                (v) =>
                    v.start < 0 ||
                    v.end <= v.start ||
                    v.end > s.effectiveText.length ||
                    v.alternatives.length > 4 ||
                    v.alternatives.any((a) => a.length > 128),
              ) ||
              !s.bounds.isFinite,
        )) {
      return false;
    }
    final changed = await db.customUpdate(
      'UPDATE canvas_ocr_pages SET indexed_revision = ?, segments = ?, search_text = ? '
      'WHERE block_id = ? AND revision = ? AND EXISTS '
      '(SELECT 1 FROM note_blocks b JOIN notes n ON n.id = b.note_id '
      'JOIN folders f ON f.id = n.folder_id WHERE b.id = ? '
      'AND n.deleted_at IS NULL AND f.deleted_at IS NULL)',
      variables: [
        Variable.withInt(revision),
        Variable.withString(
          jsonEncode(segments.map((s) => s.toJson()).toList()),
        ),
        Variable.withString(
          normalizeCanvasSearch(
            segments.map((s) => '${s.text}\n${s.effectiveText}').join('\n'),
          ),
        ),
        Variable.withInt(blockId),
        Variable.withInt(revision),
        Variable.withInt(blockId),
      ],
      updates: {db.canvasOcrPages},
    );
    return changed == 1;
  }

  Future<List<QueryRow>> _rows({
    int? blockId,
    int? noteId,
    String? query,
    bool currentOnly = true,
  }) =>
      db
          .customSelect(
            'SELECT p.*, b.note_id, b.position FROM canvas_ocr_pages p '
            'JOIN note_blocks b ON b.id = p.block_id JOIN notes n ON n.id = b.note_id '
            'JOIN folders f ON f.id = n.folder_id '
            'WHERE n.deleted_at IS NULL AND f.deleted_at IS NULL '
            '${currentOnly ? 'AND p.indexed_revision = p.revision ' : ''}'
            '${blockId != null ? 'AND p.block_id = ? ' : ''}'
            '${noteId != null ? 'AND n.id = ? ' : ''}'
            '${query != null ? 'AND instr(p.search_text, ?) > 0 ' : ''}'
            'ORDER BY b.position LIMIT 200',
            variables: [
              if (blockId != null) Variable.withInt(blockId),
              if (noteId != null) Variable.withInt(noteId),
              if (query != null) Variable.withString(query),
            ],
            readsFrom: {db.canvasOcrPages, db.noteBlocks, db.notes, db.folders},
          )
          .get();

  List<CanvasOcrSegment> _segments(String raw) =>
      (jsonDecode(raw) as List)
          .map(
            (s) =>
                CanvasOcrSegment.fromJson(Map<String, dynamic>.from(s as Map)),
          )
          .toList();

  @override
  Future<List<CanvasOcrHit>> search(String query) async {
    final q = normalizeCanvasSearch(query.trim());
    if (q.isEmpty || q.length > 256) return [];
    final rows = await _rows(query: q);
    return [
      for (final r in rows)
        for (final s in _segments(r.read<String>('segments')))
          if (normalizeCanvasSearch(
            '${s.text}\n${s.effectiveText}',
          ).contains(q))
            CanvasOcrHit(r.read<int>('note_id'), r.read<int>('block_id'), s),
    ].take(200).toList();
  }

  @override
  Future<String> contextForNote(int noteId, {int? blockId}) async {
    final rows = await _rows(noteId: noteId, blockId: blockId);
    final text = rows
        .map(
          (r) =>
              'Página/Lienzo ${r.read<int>('position') + 1}:\n'
              '${_segments(r.read<String>('segments')).map((s) => s.effectiveText).where((s) => s.isNotEmpty).join('\n')}',
        )
        .join('\n\n');
    return text.length > 32000
        ? '${text.substring(0, 32000)}\n[Contenido truncado]'
        : text;
  }
}
