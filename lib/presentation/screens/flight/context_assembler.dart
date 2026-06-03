import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../../data/services/context_cache.dart';
import '../../../domain/models/canvas_context_source.dart';
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

/// Compact a single source if it's long, caching the result by content hash
/// (one compaction per source version, reused thereafter). Short → as-is.
Future<String> compactPiece(WidgetRef ref, String key, String raw) async {
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
    final prompt =
        raw.length > kLongDocThreshold ? kSynthesizePrompt : kCompactPrompt;
    await for (final tok in ref
        .read(aiAssistantProvider)
        .streamReply(
          [AiMessage(AiRole.system, prompt), AiMessage(AiRole.user, raw)],
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

/// Assemble the enabled note/url [sources] into a single context block (each
/// source compacted + headed by its label). Folder sources are ignored here
/// (under A1 a folder is just a picker that adds note sources). Used by the lab
/// space chat on top of its board.
Future<String> assembleEnabledSources(
  WidgetRef ref,
  List<CanvasContextSource> sources,
) async {
  final pieces = <String>[];
  for (final s in sources) {
    if (!s.enabled) continue;
    String raw;
    String label;
    String key;
    if (s.isNote) {
      final nid = s.noteId;
      if (nid == null) continue;
      final blocks = await ref.read(noteBlocksProvider(nid).future);
      raw = extractNoteContext(blocks);
      label = (s.label?.trim().isEmpty ?? true) ? 'Nota' : s.label!.trim();
      key = 'note:$nid';
    } else if (s.isUrl) {
      raw = (await readUrlContent(s.ref)) ?? '';
      label = (s.label?.trim().isEmpty ?? true) ? s.ref : s.label!.trim();
      key = 'url:${contextStableHash(s.ref)}';
    } else {
      continue; // folder kind: not fed to AI (A1)
    }
    if (raw.trim().isEmpty) continue;
    final piece = await compactPiece(ref, key, raw);
    pieces.add('## $label\n\n$piece');
  }
  return pieces.join('\n\n---\n\n');
}
