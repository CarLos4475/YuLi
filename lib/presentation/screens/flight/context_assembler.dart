import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../../data/services/context_cache.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/services/ai_assistant.dart';
import 'ai_chat_session.dart'
    show kAnchorLongChars, kLongDocThreshold, kSynthesizePrompt, kCompactPrompt;

/// Shared context-assembly used by both the canvas chat (Flight) and the lab
/// space chat (Lab). Keeps the "sources → compacted anchor" logic in one place.

/// Flatten a block note's content to markdown text for AI context. Tasks and
/// drawings are skipped.
String extractNoteContext(List<NoteBlock> blocks) {
  final buf = StringBuffer();
  for (final b in blocks) {
    if (b is TextBlock) {
      if (b.markdown.trim().isNotEmpty) buf.writeln('${b.markdown}\n');
    } else if (b is BulletsBlock) {
      for (final it in b.items) {
        if (it.trim().isNotEmpty) buf.writeln('- $it');
      }
      buf.writeln();
    } else if (b is MathBlock) {
      if (b.latex.trim().isNotEmpty) buf.writeln('\$\$${b.latex}\$\$\n');
    }
  }
  return buf.toString().trim();
}

const kAggressiveCompactPrompt =
    'Compacta agresivamente el siguiente contexto para usarlo como apoyo '
    'secundario dentro de un lote de documentos. Conserva solo la información '
    'esencial: conceptos clave, instrucciones, conclusiones, fechas, nombres '
    'propios, fórmulas, listas útiles y términos técnicos. Elimina relleno, '
    'repeticiones, ejemplos extensos, navegación, barras laterales, pies de '
    'página y cualquier detalle ornamental. Conserva el formato markdown. '
    'Mantén el idioma original. Responde SOLO con el contexto compactado.';

/// Cap on how many notes a single linked folder contributes to the AI context:
/// the most-recently-edited block notes win. Folders are secondary support, so
/// an uncapped folder could flood the context and cost one compaction call per
/// long note. Surfaced in the Fuentes sheet so the user knows the folder may not
/// send everything. Explicitly linked notes are never capped (they win dedup).
const kMaxFolderNotes = 20;

/// Compact a single source if it's long, caching the result by content hash
/// (one compaction per source version, reused thereafter). Short → as-is.
Future<String> compactPiece(WidgetRef ref, String key, String raw) async {
  return compactPieceWithPrompt(ref, key, raw, prompt: null);
}

Future<String> compactPieceWithPrompt(
  WidgetRef ref,
  String key,
  String raw, {
  String? prompt,
}) async {
  if (raw.length <= kAnchorLongChars) return raw;
  final cached = await readCompactCache(key, raw);
  if (cached != null) return cached;
  final limiter = ref.read(aiUsageLimiterProvider);
  if (!await limiter.canSend()) {
    return raw.length > 4000 ? raw.substring(0, 4000) : raw;
  }
  await limiter.record();
  final buf = StringBuffer();
  try {
    final resolvedPrompt = prompt ??
        (raw.length > kLongDocThreshold ? kSynthesizePrompt : kCompactPrompt);
    await for (final tok in ref
        .read(aiAssistantProvider)
        .streamReply(
          [AiMessage(AiRole.system, resolvedPrompt), AiMessage(AiRole.user, raw)],
          model: AiModel.flash,
          maxTokens: 4096,
          temperature: 0.2,
        )) {
      buf.write(tok);
    }
  } catch (_) {
    return raw;
  }
  final compacted = buf.toString().trim();
  if (compacted.isEmpty || compacted.length >= raw.length) return raw;
  await writeCompactCache(key, raw, compacted);
  return compacted;
}

class _AssembledSource {
  final String raw;
  final String label;
  final String key;
  final bool aggressive;

  const _AssembledSource({
    required this.raw,
    required this.label,
    required this.key,
    required this.aggressive,
  });
}

Future<_AssembledSource?> _buildExplicitNoteSource(
  WidgetRef ref,
  CanvasContextSource s,
) async {
  final nid = s.noteId;
  if (nid == null) return null;
  final blocks = await ref.read(noteBlocksProvider(nid).future);
  final raw = extractNoteContext(blocks);
  if (raw.trim().isEmpty) return null;
  return _AssembledSource(
    raw: raw,
    label: (s.label?.trim().isEmpty ?? true) ? 'Nota' : s.label!.trim(),
    key: 'note:$nid',
    aggressive: false,
  );
}

Future<Map<int, _AssembledSource>> _buildFolderNoteSources(
  WidgetRef ref,
  CanvasContextSource s,
) async {
  final fid = s.folderId;
  if (fid == null) return const {};
  final noteRepo = ref.read(noteRepositoryProvider);
  // Block notes only (matching the explicit "+ NOTA" picker — canvas/notebook
  // notes carry no useful text), most-recent first, capped at kMaxFolderNotes.
  final notes = (await noteRepo.getByFolder(fid))
      .where((n) => n.isActive && n.kind == NoteKind.block)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final out = <int, _AssembledSource>{};
  for (final note in notes.take(kMaxFolderNotes)) {
    final blocks = await ref.read(noteBlocksProvider(note.id).future);
    final raw = extractNoteContext(blocks);
    if (raw.trim().isEmpty) continue;
    out[note.id] = _AssembledSource(
      raw: raw,
      label: note.displayTitle.trim().isEmpty ? 'Nota' : note.displayTitle.trim(),
      key: 'note:${note.id}:folder',
      aggressive: true,
    );
  }
  return out;
}

/// Assemble the enabled note/url/folder [sources] into a single context block
/// (each source compacted + headed by its label). Folder sources expand to
/// their active notes, deduped by note id; explicitly linked notes win and keep
/// the milder compaction path.
Future<String> assembleEnabledSources(
  WidgetRef ref,
  List<CanvasContextSource> sources,
) async {
  final explicitNotes = <int, _AssembledSource>{};
  final folderNotes = <int, _AssembledSource>{};
  final urlPieces = <_AssembledSource>[];
  for (final s in sources) {
    if (!s.enabled) continue;
    if (s.isNote) {
      final nid = s.noteId;
      final built = await _buildExplicitNoteSource(ref, s);
      if (nid != null && built != null) explicitNotes[nid] = built;
    } else if (s.isUrl) {
      final raw = (await readUrlContent(s.ref)) ?? '';
      if (raw.trim().isEmpty) continue;
      urlPieces.add(_AssembledSource(
        raw: raw,
        label: (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim(),
        key: 'url:${contextStableHash(s.ref)}',
        aggressive: false,
      ));
    } else {
      final expanded = await _buildFolderNoteSources(ref, s);
      expanded.forEach((noteId, source) {
        folderNotes.putIfAbsent(noteId, () => source);
      });
    }
  }
  final notePieces = <_AssembledSource>[
    ...explicitNotes.values,
    ...folderNotes.entries
        .where((e) => !explicitNotes.containsKey(e.key))
        .map((e) => e.value),
  ];
  final pieces = <String>[];
  for (final source in [...notePieces, ...urlPieces]) {
    final piece = await compactPieceWithPrompt(
      ref,
      source.key,
      source.raw,
      prompt: source.aggressive ? kAggressiveCompactPrompt : null,
    );
    pieces.add('## ${source.label}\n\n$piece');
  }
  return pieces.join('\n\n---\n\n');
}
