import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/ai_usage_limiter.dart';
import '../../../domain/services/ai_assistant.dart';

/// Default system prompt (fixed). Role, language, tone, format, anti-halluc.
/// The context anchor is sent as a SEPARATE user message (not concatenated)
/// so the model distinguishes instruction from content.
const kAiSystemBase =
    'Eres YuLi, el asistente personal del "segundo cerebro" del usuario (una '
    'app de notas). Responde SIEMPRE en español, en tono directo pero amable, '
    'tratando al usuario de tú. Sé conciso pero no seco: si la consulta es '
    'breve, responde en 1-3 líneas. Ve al punto sin rodeos. Puedes empezar '
    'con afirmaciones cortas '
    'como "Claro", "Sí", "Entiendo". Tus respuestas se renderizan con '
    'markdown: usa **negritas**, *cursiva*, listas, `código inline`, bloques '
    'de código, **tablas** (formato GFM: encabezado, separador |---|---|, '
    'columnas consistentes; mantenlas simples), blockquotes, checklists y '
    'enlaces. NO insertes imágenes. Para matemáticas usa \$...\$ si la '
    'expresión va dentro de un párrafo (inline), y usa SIEMPRE \$\$...\$\$ '
    'cuando la ecuación ocupe su propia línea o varias líneas (bloque). '
    'No intentes meter matemáticas en algo que no sea \$ o \$\$, no va a '
    'funcionar. No mezcles los dos modos en la misma expresión. NUNCA uses '
    'emojis ni '
    'símbolos decorativos. No uses frases de relleno extensas. No termines tu '
    'respuesta con una pregunta. Tu fuente de información PRINCIPAL es '
    'el contexto proporcionado; responde basándote en él. Si algo no está en '
    'el contexto, puedes usar tu conocimiento general, pero prioriza siempre '
    'lo que el usuario te ha dado. No inventes enlaces, referencias '
    'bibliográficas, citas, estadísticas o hechos históricos que no aparezcan '
    'en el contexto. Mantén los nombres propios, términos técnicos, siglas y '
    'acrónimos EXACTAMENTE como aparecen en el contexto; no los parafrasees '
    'ni traduzcas. Si la pregunta es ambigua o incompleta, responde con la '
    'interpretación más probable basada en el contexto; solo si falta por '
    'completo, pide aclaración breve. Si falta información, dilo sin inventar. '
    'Al extraer tareas, devuelve una por línea, accionables y breves, sin '
    'numerar. No repitas la pregunta del usuario antes de responder; ve '
    'directo a la respuesta. Si la pregunta es de sí/no, empieza con SÍ o NO '
    'en la primera palabra, luego explica brevemente. No abuses de las '
    'negritas: máximo una o dos por respuesta. Mantén los términos técnicos '
    'en el idioma original del contexto; no los traduzcas al español si '
    'aparecen en inglés.';

const _kAnchorMaxChars = 8000;


/// Above this length the context is "largo" → the chat suggests compacting it.
const kAnchorLongChars = 3000;

/// Above this raw-source length, the compactor switches from "compacta" to
/// "sintetiza en detalle" so huge Wikipedia-style articles don't become
/// superficial.
const kLongDocThreshold = 50000;

/// System prompt for compacting the context anchor (token-shielding). Preserves
/// facts/terms; drops web noise (nav, sidebar, footer). Returns ONLY the
/// compacted context.
const kCompactPrompt =
    'Compacta el siguiente contexto. Elimina elementos de navegación, '
    'enlaces del sitio, barras laterales, pies de página, comentarios de '
    'usuarios, reseñas y cabeceras irrelevantes. Preserva TODO el '
    'contenido útil: instrucciones paso a paso, listas, tablas, código, '
    'datos, fechas, nombres propios y términos técnicos. Conserva el '
    'formato markdown. Mantén el idioma original. Responde SOLO con el '
    'contexto compactado, sin comentarios ni encabezados adicionales.';

/// Alternate prompt for very long documents (>[kLongDocThreshold] chars).
/// Instead of "compact", asks for a detailed technical synthesis so the AI
/// doesn't over-compress out of necessity.
const kSynthesizePrompt =
    'Este es un documento extenso. Extrae una síntesis técnica detallada '
    'preservando TODOS los puntos clave, teoremas, fórmulas, datos '
    'numéricos, fechas, nombres propios y términos técnicos. Elimina '
    'navegación, enlaces del sitio, barras laterales, pies de página, '
    'comentarios de usuarios y cabeceras irrelevantes. Conserva el '
    'formato markdown. Mantén el idioma original. Responde SOLO con la '
    'síntesis, sin comentarios ni encabezados adicionales.';

class AiChatMsg {
  final AiRole role;
  final String text;
  const AiChatMsg(this.role, this.text);
}

/// Per-note chat conversation. Lives in an autoDispose provider keyed by note
/// id. **Messages are ephemeral** (discarded when you leave the view); the
/// **context anchor persists per note** (SharedPreferences keyed by [noteId]),
/// so it survives leaving the view — even an app restart. The sheet is just a
/// window over this.
class AiChatSession extends ChangeNotifier {
  final int noteId;
  AiChatSession(this.noteId) {
    _loadAnchor();
  }

  static const _kAnchorPrefix = 'ai_ctx_v1_';

  String? anchor; // context anchor; null until set
  final List<AiChatMsg> messages = [];
  AiModel model = AiModel.flash;
  bool streaming = false;

  // Token-shielding: previous anchor kept for a one-step undo after the AI
  // auto-compacts; [_compactTried] avoids re-compacting on every send.
  String? _previousAnchor;
  bool _compactTried = false;
  /// Index in [messages] of the latest compaction notice (for showing UNDO on
  /// just that one).
  int? compactNoticeIndex;

  bool get hasAnchor => (anchor?.trim().isNotEmpty) ?? false;
  bool get anchorIsLong => (anchor?.length ?? 0) > kAnchorLongChars;
  bool get canUndoCompact => _previousAnchor != null;

  Future<void> _loadAnchor() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('$_kAnchorPrefix$noteId');
    // Don't clobber an anchor that was set meanwhile (e.g. incoming OCR).
    if (saved != null && saved.isNotEmpty && anchor == null) {
      anchor = saved;
      notifyListeners();
    }
  }

  Future<void> _saveAnchor() async {
    final p = await SharedPreferences.getInstance();
    final key = '$_kAnchorPrefix$noteId';
    if (anchor == null || anchor!.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, anchor!);
    }
  }

  void setModel(AiModel m) {
    model = m;
    notifyListeners();
  }

  void setAnchor(String value) {
    final t = value.trim();
    _applyAnchor(t.isEmpty ? null : t, compactTried: false);
  }

  /// Set the anchor from the assembled multi-source context. The assembler has
  /// already compacted each source (cached), so skip the lazy whole-blob
  /// compaction ([compactTried] = true). Resets the thread if the context
  /// actually changed (see [_applyAnchor]).
  void setSyncedAnchor(String combined) {
    final t = combined.trim();
    _applyAnchor(t.isEmpty ? null : t, compactTried: true);
  }

  /// Replace the anchor, resetting the thread if the context actually changed
  /// mid-conversation (the prior turns are about the OLD context and would
  /// mislead the model — it trusts history over the changed anchor; resetting
  /// is the same as leaving + re-entering the view, but automatic).
  void _applyAnchor(String? next, {required bool compactTried}) {
    final changed = next != anchor;
    anchor = next;
    _compactTried = compactTried;
    if (changed && messages.isNotEmpty) {
      messages.clear();
      _previousAnchor = null;
      compactNoticeIndex = null;
      if (next != null) {
        messages.add(const AiChatMsg(
            AiRole.system, '✦ Contexto actualizado — empecé de cero.'));
      }
    }
    _saveAnchor();
    notifyListeners();
  }

  /// Append [value] to the existing anchor (accumulate context).
  void appendAnchor(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    anchor = hasAnchor ? '${anchor!}\n\n---\n\n$t' : t;
    _compactTried = false;
    _saveAnchor();
    notifyListeners();
  }

  /// The context anchor as a standalone user message (capped for token cost),
  /// kept SEPARATE from the system prompt so the model distinguishes the
  /// instruction (system) from the content (this).
  String _anchorContent() {
    final ctx = anchor ?? '';
    final capped =
        ctx.length > _kAnchorMaxChars ? ctx.substring(0, _kAnchorMaxChars) : ctx;
    return '<context_documents>\n$capped\n</context_documents>';
  }

  /// Undo the last AI auto-compaction, restoring the previous context.
  void undoCompact() {
    final p = _previousAnchor;
    if (p == null) return;
    anchor = p;
    _previousAnchor = null;
    _compactTried = true; // don't auto-recompact right away
    _saveAnchor();
    notifyListeners();
  }

  /// If the context is excessively long, the AI compacts it (preserving key
  /// facts) and posts a notice to the chat. Counts as one request. Best-effort:
  /// on failure or no real gain, keeps the original.
  Future<void> _autoCompact(
      AiAssistant assistant, AiUsageLimiter limiter) async {
    _compactTried = true;
    final before = anchor;
    if (before == null) return;
    if (!await limiter.canSend()) return;
    await limiter.record();
    final buf = StringBuffer();
    try {
      await for (final tok in assistant.streamReply([
        const AiMessage(AiRole.system, kCompactPrompt),
        AiMessage(AiRole.user, before),
      ], model: AiModel.flash)) {
        buf.write(tok);
      }
    } catch (_) {
      return; // keep original on failure
    }
    final compacted = buf.toString().trim();
    if (compacted.isEmpty || compacted.length >= before.length) return;
    _previousAnchor = before;
    anchor = compacted;
    _saveAnchor();
    messages.add(AiChatMsg(
      AiRole.system,
      '✦ Compacté el contexto para ahorrar tokens '
      '(${before.length} → ${compacted.length} caracteres).',
    ));
    compactNoticeIndex = messages.length - 1;
    notifyListeners();
  }

  /// Send [text] and stream the reply into [messages]. Runs on the session, so
  /// it survives the sheet closing. Counts against the daily [limiter].
  /// [quickAction] skips chat history — used for one-shot operations like
  /// "Resumir" or "Extraer tareas" so the model focuses only on the anchor.
  Future<void> send(
      AiAssistant assistant, AiUsageLimiter limiter, String text,
      {bool quickAction = false}) async {
    final t = text.trim();
    if (streaming || t.isEmpty || !hasAnchor) return;

    if (!await limiter.canSend()) {
      messages.add(const AiChatMsg(AiRole.assistant,
          '⚠️ Límite diario de IA alcanzado (150/día). Se reinicia mañana.'));
      notifyListeners();
      return;
    }

    // Mark busy NOW (before the auto-compact await) so the input is disabled
    // and a second send can't run concurrently during compaction.
    streaming = true;
    notifyListeners();

    // Token-shielding: the AI compacts an excessively long context first (and
    // notifies the user in the chat).
    if (anchorIsLong && !_compactTried) {
      await _autoCompact(assistant, limiter);
    }

    final history = List<AiChatMsg>.from(messages);
    messages.add(AiChatMsg(AiRole.user, t));
    messages.add(const AiChatMsg(AiRole.assistant, ''));
    notifyListeners();
    await limiter.record();

    final idx = messages.length - 1;
    final convo = <AiMessage>[
      const AiMessage(AiRole.system, kAiSystemBase),
      AiMessage(AiRole.user, _anchorContent()),
    ];
    if (!quickAction) {
      final relevant = history.where((m) => m.role != AiRole.system).toList();
      final maxHistory = model == AiModel.flash ? 8 : 16;
      final capped = relevant.length > maxHistory
          ? relevant.sublist(relevant.length - maxHistory)
          : relevant;
      convo.addAll(capped.map((m) => AiMessage(m.role, m.text)));
    }
    convo.add(AiMessage(AiRole.user, t));

    // Retry transient failures (network / 429 / 5xx) with backoff, but ONLY
    // before any token has streamed in this attempt — once text starts flowing
    // a retry would duplicate it. Shows a "Reintentando…" hint between tries.
    const maxRetries = 2;
    var attempt = 0;
    while (true) {
      var yielded = false;
      try {
        await for (final tok in assistant.streamReply(convo, model: model)) {
          yielded = true;
          messages[idx] = AiChatMsg(AiRole.assistant, messages[idx].text + tok);
          notifyListeners();
        }
        break; // completed cleanly
      } catch (e) {
        final retryable = e is AiException && e.retryable;
        if (!yielded && retryable && attempt < maxRetries) {
          attempt++;
          messages[idx] =
              AiChatMsg(AiRole.assistant, '⟳ Reintentando… ($attempt)');
          notifyListeners();
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          messages[idx] = const AiChatMsg(AiRole.assistant, '');
          notifyListeners();
          continue; // retry
        }
        messages[idx] = AiChatMsg(AiRole.assistant, '⚠️ $e');
        notifyListeners();
        break;
      }
    }
    streaming = false;
    notifyListeners();
  }

  /// Regenerate the assistant reply at [assistantIndex]: drop it and everything
  /// after, then re-send the user turn that produced it. (Regenerating an older
  /// reply discards the turns below it — it's an explicit "redo from here".)
  Future<void> regenerate(
      int assistantIndex, AiAssistant assistant, AiUsageLimiter limiter) async {
    if (streaming) return;
    if (assistantIndex < 0 || assistantIndex >= messages.length) return;
    if (messages[assistantIndex].role != AiRole.assistant) return;
    int ui = -1;
    for (int i = assistantIndex - 1; i >= 0; i--) {
      if (messages[i].role == AiRole.user) {
        ui = i;
        break;
      }
    }
    if (ui < 0) return;
    final prompt = messages[ui].text;
    messages.removeRange(ui, messages.length);
    notifyListeners();
    await send(assistant, limiter, prompt);
  }
}
