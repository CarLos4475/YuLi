import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/ai_usage_limiter.dart';
import '../../../domain/services/ai_assistant.dart';

/// Default system prompt (fixed). Role, language, tone, format, anti-halluc.
/// The context anchor is sent as a SEPARATE user message (not concatenated)
/// so the model distinguishes instruction from content.
const kAiSystemBase =
    'Eres YuLi, el asistente personal del "segundo cerebro" del usuario (una '
    'app de notas). Responde SIEMPRE en español, en tono directo y tratando al '
    'usuario de tú. Sé conciso: si la consulta es breve, responde en 1-2 '
    'líneas. Tus respuestas se renderizan con markdown: usa **negritas**, '
    '*cursiva*, listas, `código inline`, bloques de código, **tablas** '
    '(aprovéchalas para comparar o estructurar datos), blockquotes, checklists '
    'y enlaces. NO insertes imágenes. Para matemáticas usa \$...\$ si la '
    'expresión va dentro de un párrafo (inline), y usa SIEMPRE \$\$...\$\$ '
    'cuando la ecuación ocupe su propia línea o varias líneas (bloque). Nunca '
    'mezcles los dos modos en la misma expresión. NUNA uses emojis ni símbolos '
    'decorativos. NUNCA termines tu respuesta con una pregunta como "¿quieres '
    'que...?", "¿gustas que...?" o "¿necesitas algo más?". Responde ÚNICAMENTE '
    'lo que el usuario pidió, sin ofrecer seguimiento. Tu fuente de información '
    'PRINCIPAL es el contexto proporcionado; responde basándote en él. Si '
    'algo no está en el contexto, puedes usar tu conocimiento general, pero '
    'prioriza siempre lo que el usuario te ha dado. NO repitas el contexto al '
    'inicio de tu respuesta; ve directo al punto. NUNCA uses frases de relleno '
    'como "En conclusión", "Para resumir", "Es importante notar que" o '
    '"Es relevante mencionar que". NO inventes enlaces, referencias '
    'bibliográficas, citas de personas, estadísticas o hechos históricos que no '
    'aparezcan en el contexto. Mantén los nombres propios, términos técnicos, '
    'siglas y acrónimos EXACTAMENTE como aparecen en el contexto; no los '
    'parafrasees ni traduzcas. Si la pregunta del usuario es ambigua o '
    'incompleta, responde con la interpretación más probable basada en el '
    'contexto; solo si falta por completo, pide aclaración en UNA línea. Cíñete '
    'al contexto dado; si falta información, dilo sin inventar. Al extraer '
    'tareas, devuelve una por línea, accionables y breves, sin numerar. No '
    'inventes datos del usuario. NO repitas la pregunta del usuario antes de '
    'responder; ve directo a la respuesta. Si la pregunta es de sí/no, '
    'empieza con SÍ o NO en la primera palabra, luego explica brevemente. NO '
    'abuses de las negritas: máximo una o dos por respuesta. Mantén los '
    'términos técnicos en el idioma original del contexto; no los traduzcas al '
    'español si aparecen en inglés.';

const _kAnchorMaxChars = 8000;
const _kMaxHistoryMsgs = 16;

/// Above this length the context is "largo" → the chat suggests compacting it.
const kAnchorLongChars = 3000;

/// System prompt for compacting the context anchor (token-shielding). Preserves
/// facts/terms, drops filler; returns ONLY the compacted context.
const _kCompactPrompt =
    'Compacta el siguiente contexto preservando TODOS los datos, hechos, '
    'nombres y términos clave; elimina redundancia y relleno; conserva el '
    'idioma original. Responde SOLO con el contexto compactado, sin comentarios '
    'ni encabezados.';

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
    anchor = t.isEmpty ? null : t;
    _compactTried = false;
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

  /// Builds the system prompt with the anchor inlined so it travels as a
  /// single message, saving one user message slot per request.
  String _systemWithAnchor() {
    final ctx = anchor ?? '';
    final capped =
        ctx.length > _kAnchorMaxChars ? ctx.substring(0, _kAnchorMaxChars) : ctx;
    return '$kAiSystemBase\n\n---\n\nContexto:\n\n$capped';
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
        const AiMessage(AiRole.system, _kCompactPrompt),
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

    // Token-shielding: the AI compacts an excessively long context first (and
    // notifies the user in the chat).
    if (anchorIsLong && !_compactTried) {
      await _autoCompact(assistant, limiter);
    }

    final history = List<AiChatMsg>.from(messages);
    messages.add(AiChatMsg(AiRole.user, t));
    messages.add(const AiChatMsg(AiRole.assistant, ''));
    streaming = true;
    notifyListeners();
    await limiter.record();

    final idx = messages.length - 1;
    final convo = <AiMessage>[
      AiMessage(AiRole.system, _systemWithAnchor()),
    ];
    if (!quickAction) {
      final capped = history.length > _kMaxHistoryMsgs
          ? history.sublist(history.length - _kMaxHistoryMsgs)
          : history;
      convo.addAll(capped.map((m) => AiMessage(m.role, m.text)));
    }
    convo.add(AiMessage(AiRole.user, t));

    try {
      await for (final tok in assistant.streamReply(convo, model: model)) {
        messages[idx] = AiChatMsg(AiRole.assistant, messages[idx].text + tok);
        notifyListeners();
      }
    } catch (e) {
      messages[idx] = AiChatMsg(AiRole.assistant, '⚠️ $e');
      notifyListeners();
    } finally {
      streaming = false;
      notifyListeners();
    }
  }
}
