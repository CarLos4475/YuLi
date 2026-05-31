import 'package:flutter/foundation.dart';

import '../../../data/services/ai_usage_limiter.dart';
import '../../../domain/services/ai_assistant.dart';

/// Default system prompt (fixed). Role, language, tone, format, anti-halluc.
/// The context anchor is sent as a SEPARATE user message (not concatenated)
/// so the model distinguishes instruction from content.
const kAiSystemBase =
    'Eres el asistente personal del "segundo cerebro" del usuario (una app de '
    'notas). Responde SIEMPRE en español, en tono directo y tratando al usuario '
    'de tú. Sé conciso: si la consulta es breve, responde en 1-2 líneas. Usa '
    'markdown solo para listas, negritas y bloques de código; evita tablas y '
    'cabeceras largas. Cíñete al contexto dado; si falta información, dilo sin '
    'inventar. Al extraer tareas, devuelve una por línea, accionables y breves, '
    'sin numerar. No inventes datos del usuario.';

const _kAnchorMaxChars = 8000;
const _kMaxHistoryMsgs = 16;

class AiChatMsg {
  final AiRole role;
  final String text;
  const AiChatMsg(this.role, this.text);
}

/// Per-note chat conversation. Lives in an autoDispose provider keyed by note
/// id, so it **persists while you're in that note/pizarra/cuaderno** (the sheet
/// is just a window over it) and is **discarded when you leave the view**.
class AiChatSession extends ChangeNotifier {
  String? anchor; // context anchor; null until set
  final List<AiChatMsg> messages = [];
  AiModel model = AiModel.flash;
  bool streaming = false;

  bool get hasAnchor => (anchor?.trim().isNotEmpty) ?? false;

  void setModel(AiModel m) {
    model = m;
    notifyListeners();
  }

  void setAnchor(String value) {
    final t = value.trim();
    anchor = t.isEmpty ? null : t;
    notifyListeners();
  }

  /// Append [value] to the existing anchor (accumulate context).
  void appendAnchor(String value) {
    final t = value.trim();
    if (t.isEmpty) return;
    anchor = hasAnchor ? '${anchor!}\n\n---\n\n$t' : t;
    notifyListeners();
  }

  String _anchorContent() {
    final ctx = anchor ?? '';
    final capped =
        ctx.length > _kAnchorMaxChars ? ctx.substring(0, _kAnchorMaxChars) : ctx;
    return 'Contexto:\n\n$capped';
  }

  /// Send [text] and stream the reply into [messages]. Runs on the session, so
  /// it survives the sheet closing. Counts against the daily [limiter].
  Future<void> send(
      AiAssistant assistant, AiUsageLimiter limiter, String text) async {
    final t = text.trim();
    if (streaming || t.isEmpty || !hasAnchor) return;

    if (!await limiter.canSend()) {
      messages.add(const AiChatMsg(AiRole.assistant,
          '⚠️ Límite diario de IA alcanzado (150/día). Se reinicia mañana.'));
      notifyListeners();
      return;
    }

    final history = List<AiChatMsg>.from(messages);
    messages.add(AiChatMsg(AiRole.user, t));
    messages.add(const AiChatMsg(AiRole.assistant, ''));
    streaming = true;
    notifyListeners();
    await limiter.record();

    final idx = messages.length - 1;
    final capped = history.length > _kMaxHistoryMsgs
        ? history.sublist(history.length - _kMaxHistoryMsgs)
        : history;
    final convo = <AiMessage>[
      const AiMessage(AiRole.system, kAiSystemBase),
      AiMessage(AiRole.user, _anchorContent()),
      ...capped.map((m) => AiMessage(m.role, m.text)),
      AiMessage(AiRole.user, t),
    ];

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
