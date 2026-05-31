import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ai_assistant.dart';

/// Default system prompt (fixed). Defines role, language, tone, format, and
/// anti-hallucination rules. The context anchor is sent as a SEPARATE user
/// message (not concatenated here) so the model distinguishes instruction from
/// content.
const _kAiSystemBase =
    'Eres el asistente personal del "segundo cerebro" del usuario (una app de '
    'notas). Responde SIEMPRE en español, en tono directo y tratando al usuario '
    'de tú. Sé conciso: si la consulta es breve, responde en 1-2 líneas. Usa '
    'markdown solo para listas, negritas y bloques de código; evita tablas y '
    'cabeceras largas. Cíñete al contexto dado; si falta información, dilo sin '
    'inventar. Al extraer tareas, devuelve una por línea, accionables y breves, '
    'sin numerar. No inventes datos del usuario.';

/// Cost guards: cap the anchor context and how many past turns are resent.
const _kAnchorMaxChars = 8000;
const _kMaxHistoryMsgs = 16;

/// Open the AI chat. v2 is **read-only**: the assistant talks and you copy; it
/// never edits notes/tasks (that's v3). The conversation is **ephemeral** (dies
/// with the sheet) and **always anchored** to a context: [initialContext] when
/// launched from the OCR sheet / a note, or a "¿De qué es esto?" prompt on a
/// cold start (null context).
Future<void> showAiChat(
  BuildContext context,
  WidgetRef ref, {
  String? initialContext,
  required Color accent,
}) async {
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Configura tu API key de DeepSeek en Ajustes'),
      duration: Duration(seconds: 3),
    ));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(initialContext: initialContext, accent: accent),
  );
}

class _ChatMsg {
  final AiRole role;
  final String text;
  const _ChatMsg(this.role, this.text);
}

class _AiChatSheet extends ConsumerStatefulWidget {
  final String? initialContext;
  final Color accent;
  const _AiChatSheet({required this.initialContext, required this.accent});

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet> {
  final _input = TextEditingController();
  final _anchorInput = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMsg> _msgs = [];

  String? _anchor; // context anchor; null until set (cold start)
  bool _streaming = false;
  AiModel _model = AiModel.flash;
  int? _remaining; // requests left today (daily cap)

  @override
  void initState() {
    super.initState();
    final ctx = widget.initialContext?.trim();
    if (ctx != null && ctx.isNotEmpty) _anchor = ctx;
    _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final r = await ref.read(aiUsageLimiterProvider).remaining();
    if (mounted) setState(() => _remaining = r);
  }

  @override
  void dispose() {
    _input.dispose();
    _anchorInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The context anchor as a standalone user message (capped for token cost).
  String _anchorContent() {
    final ctx = _anchor ?? '';
    final capped =
        ctx.length > _kAnchorMaxChars ? ctx.substring(0, _kAnchorMaxChars) : ctx;
    return 'Contexto:\n\n$capped';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (_streaming || t.isEmpty || _anchor == null) return;

    final limiter = ref.read(aiUsageLimiterProvider);
    if (!await limiter.canSend()) {
      if (!mounted) return;
      setState(() => _msgs.add(const _ChatMsg(AiRole.assistant,
          '⚠️ Límite diario de IA alcanzado (150/día). Se reinicia mañana.')));
      _scrollToBottom();
      return;
    }

    final history = List<_ChatMsg>.from(_msgs);
    setState(() {
      _msgs.add(_ChatMsg(AiRole.user, t));
      _msgs.add(const _ChatMsg(AiRole.assistant, ''));
      _streaming = true;
      _input.clear();
    });
    await limiter.record();
    _loadRemaining();
    final assistantIdx = _msgs.length - 1;
    _scrollToBottom();

    // Cap resent history to bound token cost.
    final capped = history.length > _kMaxHistoryMsgs
        ? history.sublist(history.length - _kMaxHistoryMsgs)
        : history;
    final convo = <AiMessage>[
      const AiMessage(AiRole.system, _kAiSystemBase),
      AiMessage(AiRole.user, _anchorContent()),
      ...capped.map((m) => AiMessage(m.role, m.text)),
      AiMessage(AiRole.user, t),
    ];

    try {
      await for (final tok
          in ref.read(aiAssistantProvider).streamReply(convo, model: _model)) {
        if (!mounted) return;
        setState(() => _msgs[assistantIdx] =
            _ChatMsg(AiRole.assistant, _msgs[assistantIdx].text + tok));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _msgs[assistantIdx] = _ChatMsg(AiRole.assistant, '⚠️ $e'));
      }
    } finally {
      if (mounted) setState(() => _streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
          ),
          child: SafeArea(
            top: false,
            child: _anchor == null ? _buildAnchorGate() : _buildChat(),
          ),
        ),
      ),
    );
  }

  // Cold start: require a context anchor before chatting.
  Widget _buildAnchorGate() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 16),
          Text('¿DE QUÉ ES ESTO?',
              style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yInk)),
          const SizedBox(height: 6),
          Text(
            'Dale un punto de partida (ej. "Proceso de Markov"). Se queda como '
            'contexto de la conversación.',
            style: yMono(size: 10, tracking: 0.4, color: yMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _anchorInput,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            style: yBody(size: 15, color: yInk),
            onSubmitted: (v) => _setAnchor(v),
            decoration: _fieldDeco('¿Sobre qué quieres hablar?'),
          ),
          const SizedBox(height: 12),
          _primaryButton('EMPEZAR', () => _setAnchor(_anchorInput.text)),
        ],
      ),
    );
  }

  void _setAnchor(String v) {
    final t = v.trim();
    if (t.isEmpty) return;
    setState(() => _anchor = t);
  }

  Widget _buildChat() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _header(),
        ),
        // Context anchor preview.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: yCream2,
              border: Border.all(color: yInk, width: yLineThin),
            ),
            child: Text(
              'CONTEXTO: ${_anchor!}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: yMono(size: 9, tracking: 0.4, color: yMuted),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _msgs.length,
            itemBuilder: (_, i) => _bubble(_msgs[i], i),
          ),
        ),
        _quickActions(),
        _inputBar(),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        Text('IA · ${_model == AiModel.flash ? 'FLASH' : 'PRO'}',
            style: yMono(
                size: 11, weight: FontWeight.w700, tracking: 1.4, color: yInk)),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _model =
              _model == AiModel.flash ? AiModel.pro : AiModel.flash),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: yInk, width: yLineThin)),
            child: Text(_model == AiModel.flash ? 'usar PRO' : 'usar FLASH',
                style: yMono(size: 8, tracking: 0.8, color: yInk)),
          ),
        ),
        if (_remaining != null) ...[
          const SizedBox(width: 8),
          Text('$_remaining hoy',
              style: yMono(size: 8, tracking: 0.6, color: yMuted)),
        ],
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, size: 20, color: yInk),
        ),
      ],
    );
  }

  Widget _bubble(_ChatMsg m, int i) {
    final isUser = m.role == AiRole.user;
    final streaming = _streaming && i == _msgs.length - 1 && !isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? widget.accent : yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SelectableText(
              m.text.isEmpty && streaming ? '…' : m.text,
              style: yBody(size: 14, color: isUser ? yCream : yInk),
            ),
            if (!isUser && m.text.isNotEmpty && !streaming) ...[
              const SizedBox(height: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Copiado'),
                      duration: Duration(milliseconds: 700)));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.copy, size: 11, color: yMuted),
                  const SizedBox(width: 3),
                  Text('Copiar',
                      style: yMono(size: 8, tracking: 0.8, color: yMuted)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    const actions = {
      'Resumir': 'Resume el contexto en pocas líneas.',
      'Limpiar': 'Reescribe y limpia el contexto: corrige ortografía y '
          'redacción, mantén el significado.',
      'Extraer tareas':
          'Lista las tareas accionables del contexto, una por línea, sin numerar.',
      'Título': 'Sugiere 3 títulos cortos para el contexto.',
      'Traducir': 'Traduce el contexto al inglés.',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: yInk, width: yLineThin)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final e in actions.entries) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _streaming ? null : () => _send(e.value),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _streaming ? yCream2 : yCream,
                    border: Border.all(color: yInk, width: yLineThin),
                  ),
                  child: Text(e.key.toUpperCase(),
                      style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 0.8,
                          color: yInk)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: yInk, width: yLineThin)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !_streaming,
              style: yBody(size: 14, color: yInk),
              onSubmitted: _streaming ? null : _send,
              textInputAction: TextInputAction.send,
              decoration: _fieldDeco('Escribe…'),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _streaming ? null : () => _send(_input.text),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _streaming ? yMuted : widget.accent,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: _streaming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: yCream))
                  : const Icon(Icons.arrow_upward, color: yCream, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String hint) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
        hintText: hint,
        hintStyle: yBody(size: 14, color: yMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yInk, width: yLineMid),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yInk, width: yLineMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yInk, width: yLineMid),
        ),
      );

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.accent,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Text(label,
            style: yMono(
                size: 12, weight: FontWeight.w700, tracking: 1.4, color: yCream)),
      ),
    );
  }
}
