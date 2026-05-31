import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ai_assistant.dart';
import 'ai_chat_session.dart';
// Reuse the notes' markdown renderer (markdown_widget + flutter_math_fork) so
// the assistant's markdown/LaTeX renders exactly like a note.
import 'note_block_widgets.dart' show NoteMarkdownPreview;

/// Open the AI chat for a note view. The conversation is the per-note
/// [AiChatSession] (persists while you're in the view; the sheet is a window).
/// [newContext] (from OCR / a note) sets the anchor, or — if one already
/// exists — asks **Añadir o Reemplazar**. Cold (no context, no anchor) → asks
/// "¿De qué es esto?".
Future<void> showAiChat(
  BuildContext context,
  WidgetRef ref, {
  required int noteId,
  String? newContext,
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

  final session = ref.read(aiSessionProvider(noteId));
  final ctx = newContext?.trim();
  if (ctx != null && ctx.isNotEmpty) {
    if (!session.hasAnchor) {
      session.setAnchor(ctx);
    } else if (ctx != session.anchor) {
      // Different incoming context → ask. (Unchanged → just reopen, no prompt.)
      final choice = await _chooseContextAction(context, accent);
      if (!context.mounted) return;
      if (choice == _CtxAction.add) {
        session.appendAnchor(ctx);
      } else if (choice == _CtxAction.replace) {
        session.setAnchor(ctx);
      }
      // cancel → keep current anchor, still open the chat.
    }
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiChatSheet(session: session, accent: accent),
  );
}

enum _CtxAction { add, replace }

Future<_CtxAction?> _chooseContextAction(BuildContext context, Color accent) {
  return showModalBottomSheet<_CtxAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('YA HAY CONTEXTO',
                style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk)),
            const SizedBox(height: 4),
            Text('¿Qué hago con el contexto nuevo?',
                style: yBody(size: 13, color: yMuted)),
            const SizedBox(height: 14),
            _bigChoice('AÑADIR AL CONTEXTO', accent, true,
                () => Navigator.pop(context, _CtxAction.add)),
            const SizedBox(height: 8),
            _bigChoice('REEMPLAZAR CONTEXTO', accent, false,
                () => Navigator.pop(context, _CtxAction.replace)),
          ],
        ),
      ),
    ),
  );
}

Widget _bigChoice(String label, Color accent, bool filled, VoidCallback onTap) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? accent : yCream,
        border: Border.all(color: filled ? yInk : accent, width: yLineMid),
      ),
      child: Text(label,
          style: yMono(
              size: 12,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: filled ? yCream : yInk)),
    ),
  );
}

class _AiChatSheet extends ConsumerStatefulWidget {
  final AiChatSession session;
  final Color accent;
  const _AiChatSheet({required this.session, required this.accent});

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet> {
  final _input = TextEditingController();
  final _anchorInput = TextEditingController();
  final _scroll = ScrollController();
  int? _remaining;

  AiChatSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _loadRemaining();
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    _input.dispose();
    _anchorInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    _scrollToBottom();
    if (!_s.streaming) _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final r = await ref.read(aiUsageLimiterProvider).remaining();
    if (mounted) setState(() => _remaining = r);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty || _s.streaming || !_s.hasAnchor) return;
    _input.clear();
    _s.send(ref.read(aiAssistantProvider), ref.read(aiUsageLimiterProvider),
        text);
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
            child: AnimatedBuilder(
              animation: _s,
              builder: (_, _) =>
                  _s.hasAnchor ? _buildChat() : _buildAnchorGate(),
            ),
          ),
        ),
      ),
    );
  }

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
            'Dale un punto de partida (ej. "Proceso de Markov"). Queda como '
            'contexto de la conversación; puedes editarlo luego.',
            style: yMono(size: 10, tracking: 0.4, color: yMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _anchorInput,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            style: yBody(size: 15, color: yInk),
            onSubmitted: (v) => _s.setAnchor(v),
            decoration: _fieldDeco('¿Sobre qué quieres hablar?'),
          ),
          const SizedBox(height: 12),
          _primaryButton('EMPEZAR', () => _s.setAnchor(_anchorInput.text)),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _header(),
        ),
        // Context anchor preview — tap to edit / replace / clear.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _editContext,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: yCream2,
                border: Border.all(color: yInk, width: yLineThin),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'CONTEXTO: ${_s.anchor}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: yMono(size: 9, tracking: 0.4, color: yMuted),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit, size: 13, color: yMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _s.messages.length,
            itemBuilder: (_, i) => _bubble(_s.messages[i], i),
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
        Text('IA · ${_s.model == AiModel.flash ? 'FLASH' : 'PRO'}',
            style: yMono(
                size: 11, weight: FontWeight.w700, tracking: 1.4, color: yInk)),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _s.setModel(
              _s.model == AiModel.flash ? AiModel.pro : AiModel.flash),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration:
                BoxDecoration(border: Border.all(color: yInk, width: yLineThin)),
            child: Text(_s.model == AiModel.flash ? 'usar PRO' : 'usar FLASH',
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

  Widget _bubble(AiChatMsg m, int i) {
    final isUser = m.role == AiRole.user;
    final streaming = _s.streaming && i == _s.messages.length - 1 && !isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? widget.accent : yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // User text + the live streaming text stay plain (markdown only
            // makes sense once complete); finished assistant replies render as
            // markdown/LaTeX with the notes' renderer.
            if (isUser || streaming)
              SelectableText(
                m.text.isEmpty && streaming ? '…' : m.text,
                style: yBody(size: 14, color: isUser ? yCream : yInk),
              )
            else
              NoteMarkdownPreview(data: m.text),
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
                onTap: _s.streaming ? null : () => _send(e.value),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _s.streaming ? yCream2 : yCream,
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
              enabled: !_s.streaming,
              style: yBody(size: 14, color: yInk),
              onSubmitted: _s.streaming ? null : _send,
              textInputAction: TextInputAction.send,
              decoration: _fieldDeco('Escribe…'),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _s.streaming ? null : () => _send(_input.text),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _s.streaming ? yMuted : widget.accent,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: _s.streaming
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

  void _editContext() {
    _anchorInput.text = _s.anchor ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: insets),
          child: Container(
            decoration: const BoxDecoration(
              color: yCream,
              border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('CONTEXTO',
                      style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk)),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: TextField(
                      controller: _anchorInput,
                      maxLines: null,
                      style: yBody(size: 14, color: yInk),
                      decoration: _fieldDeco('Contexto de la conversación'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _primaryButton('GUARDAR', () {
                          _s.setAnchor(_anchorInput.text);
                          Navigator.pop(sheetCtx);
                        }),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _s.setAnchor('');
                          Navigator.pop(sheetCtx);
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: yCream,
                            border: Border.all(color: yInk, width: yLineMid),
                          ),
                          child: Text('LIMPIAR',
                              style: yMono(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  tracking: 1.2,
                                  color: yInk)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                size: 12,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yCream)),
      ),
    );
  }
}
