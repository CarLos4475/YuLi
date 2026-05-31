import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ai_assistant.dart';
import '../../../domain/models/note_block.dart';
import 'ai_chat_session.dart';
import 'ocr_send_to_note.dart' show sendTextToNote;
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
  String? prefillMessage,
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
    builder: (_) => _AiChatSheet(
      session: session,
      accent: accent,
      prefillMessage: prefillMessage,
    ),
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
  final String? prefillMessage;
  const _AiChatSheet({
    required this.session,
    required this.accent,
    this.prefillMessage,
  });

  @override
  ConsumerState<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<_AiChatSheet>
    with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _anchorInput = TextEditingController();
  final _scroll = ScrollController();
  int? _remaining;
  late final AnimationController _aiSpinCtrl;

  AiChatSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _loadRemaining();
    // Drives the erratic rotation of the diamond inside the AI mark.
    _aiSpinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    // If there are existing messages, jump to the latest one on first open.
    if (_s.messages.isNotEmpty) _scrollToBottom();
    final prefill = widget.prefillMessage?.trim();
    if (prefill != null && prefill.isNotEmpty) _input.text = prefill;
  }

  @override
  void dispose() {
    _aiSpinCtrl.dispose();
    _s.removeListener(_onSession);
    _input.dispose();
    _anchorInput.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// No-op for v3 actions not wired yet — tells the user it's coming.
  void _v3Soon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label — disponible en v3'),
      duration: const Duration(milliseconds: 1200),
    ));
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

  void _send(String text, {bool quickAction = false}) {
    if (text.trim().isEmpty || _s.streaming || !_s.hasAnchor) return;
    if (!quickAction) _input.clear();
    _s.send(ref.read(aiAssistantProvider), ref.read(aiUsageLimiterProvider),
        text,
        quickAction: quickAction);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: FractionallySizedBox(
        heightFactor: 0.95,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showNotePicker,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: Text('IMPORTAR NOTA',
                  style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk)),
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }

  /// Open a bottom sheet listing the other notes in the same folder so the
  /// user can pick one to import as the chat anchor.
  void _showNotePicker() async {
    final noteAsync = ref.read(noteByIdProvider(_s.noteId));
    final note = noteAsync.valueOrNull;
    if (note == null) return;
    final folderId = note.folderId;
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final notesAsync = ref.watch(notesByFolderProvider(folderId));
        final notes = notesAsync.valueOrNull ?? [];
        // Exclude the current note itself (pizarra / cuaderno / nota).
        final others = notes.where((n) => n.id != _s.noteId).toList();

        return Container(
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
                Text('IMPORTAR NOTA',
                    style: yMono(
                        size: 11,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yInk)),
                const SizedBox(height: 10),
                if (others.isEmpty)
                  Text('No hay otras notas en esta carpeta.',
                      style: yBody(size: 13, color: yMuted))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: others.length,
                      itemBuilder: (_, i) {
                        final n = others[i];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final blocksAsync =
                                await ref.read(noteBlocksProvider(n.id).future);
                            final ctxText = _extractNoteContext(blocksAsync);
                            if (ctxText.isNotEmpty) {
                              _s.setAnchor(ctxText);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: yInk, width: yLineThin)),
                            ),
                            child: Text(
                              (n.title?.isEmpty ?? true) ? 'Sin título' : n.title!,
                              style: ySans(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: yInk),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Extract a plain-text context from a note's blocks (same rules as the
  /// note editor: text + bullets + math; skip tasks & drawings).
  String _extractNoteContext(List<NoteBlock> blocks) {
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
      // TareasBlock and DrawingBlock are skipped.
    }
    return buf.toString().trim();
  }

  Widget _buildChat() {
    return Column(
      children: [
        _header(),
        _contextBar(),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
            children: [
              // Canned greeting (UI-only, no request) when the thread is empty.
              if (_s.messages.isEmpty) _greeting(),
              for (int i = 0; i < _s.messages.length; i++)
                _bubble(_s.messages[i], i),
            ],
          ),
        ),
        _quickActions(),
        _inputBar(),
      ],
    );
  }

  /// CONTEXTO ▸ [texto del ancla]  ✎  ✕
  Widget _contextBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
      child: Row(
        children: [
          Text('CONTEXTO ▸',
              style: yMono(
                  size: 10, weight: FontWeight.w700, tracking: 1.4, color: yMuted)),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _editContext,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yInk, width: yLineMid),
                ),
                child: Text(
                  _s.anchor ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(size: 13, weight: FontWeight.w600, color: yInk),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ghostIcon(Icons.edit, 'Editar contexto', _editContext),
          const SizedBox(width: 6),
          _ghostIcon(Icons.close, 'Quitar contexto', () => _s.setAnchor('')),
        ],
      ),
    );
  }

  Widget _ghostIcon(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yInk, width: yLineMid),
          ),
          child: Icon(icon, size: 14, color: yInk),
        ),
      ),
    );
  }

  /// UI-only greeting bubble shown when the conversation is empty.
  Widget _greeting() => _aiMsgFrame(
        const Text(
          'Hola. Tengo tu contexto cargado, ¿qué hacemos con él?',
          style: TextStyle(fontSize: 15, height: 1.5, color: yInk),
        ),
      );

  static const _kDailyCap = 150;

  /// Command bar: ink background, mark + wordmark + FLASH|PRO segmented control
  /// + usage meter + close. Accent = the note's accent (everything is accent).
  Widget _header() {
    final used =
        _remaining == null ? null : (_kDailyCap - _remaining!).clamp(0, _kDailyCap);
    return Container(
      decoration: const BoxDecoration(
        color: yInk,
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          // Mark: accent square with a cream diamond.
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accent,
              border: Border.all(color: yCream, width: yLineMid),
            ),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 12, height: 12, color: yCream),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YuLi · IA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                        size: 18, weight: FontWeight.w700, color: yCream)),
                Text('ASISTENTE DE NOTAS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yMono(
                        size: 8,
                        tracking: 1.6,
                        color: yCream.withValues(alpha: 0.6))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // FLASH | PRO segmented control.
          Container(
            decoration: BoxDecoration(border: Border.all(color: yCream, width: yLineMid)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _seg('FLASH', _s.model == AiModel.flash,
                  () => _s.setModel(AiModel.flash)),
              Container(width: yLineThin, height: 24, color: yCream),
              _seg('PRO', _s.model == AiModel.pro,
                  () => _s.setModel(AiModel.pro)),
            ]),
          ),
          if (used != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('$used/$_kDailyCap',
                      textAlign: TextAlign.right,
                      style: yMono(
                          size: 9, tracking: 0.6, color: yCream)),
                  const SizedBox(height: 4),
                  Container(
                    height: 5,
                    decoration:
                        BoxDecoration(border: Border.all(color: yCream, width: 1)),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (used / _kDailyCap).clamp(0.0, 1.0),
                      child: Container(color: widget.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(border: Border.all(color: yCream, width: yLineMid)),
              child: const Icon(Icons.close, size: 16, color: yCream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        color: active ? widget.accent : Colors.transparent,
        child: Text(label,
            style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.0,
                color: yCream)),
      ),
    );
  }

  /// Returns the complementary colour of [c] (180° hue shift).
  /// AI avatar: square accent-coloured tile that spins erratically.
  /// AI mark: ink square containing a rotating accent diamond (keeps the
  /// erratic animation).
  Widget _aiAvatar() {
    final erratic = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 0.4)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 12),
      TweenSequenceItem(
          tween: Tween(begin: 0.4, end: -0.6)
              .chain(CurveTween(curve: Curves.easeInOutBack)),
          weight: 18),
      TweenSequenceItem(
          tween: Tween(begin: -0.6, end: 0.8)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 18),
      TweenSequenceItem(
          tween: Tween(begin: 0.8, end: -0.3)
              .chain(CurveTween(curve: Curves.easeInOutExpo)),
          weight: 22),
      TweenSequenceItem(
          tween: Tween(begin: -0.3, end: 0.5)
              .chain(CurveTween(curve: Curves.bounceInOut)),
          weight: 15),
      TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 0.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 15),
    ]).animate(_aiSpinCtrl);

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: yInk,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      child: AnimatedBuilder(
        animation: erratic,
        builder: (_, _) => Transform.rotate(
          angle: math.pi / 4 + erratic.value,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: widget.accent,
              border: Border.all(color: yCream, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  /// Assistant message frame: mark + "YULI · IA" label + cream bubble (hard
  /// shadow) holding [content], with optional [actions] under a divider.
  Widget _aiMsgFrame(Widget content, {List<Widget>? actions}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _aiAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text('YULI · IA',
                      style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 1.6,
                          color: yMuted)),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yInk, width: yLineMid),
                    boxShadow: const [BoxShadow(color: yInk, offset: Offset(4, 4))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      content,
                      if (actions != null && actions.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Container(
                            height: yLineThin,
                            color: yInk.withValues(alpha: 0.25)),
                        const SizedBox(height: 11),
                        Wrap(spacing: 6, runSpacing: 6, children: actions),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgActionBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: yInk, width: yLineThin)),
        child: Text(label.toUpperCase(),
            style: yMono(
                size: 9, weight: FontWeight.w700, tracking: 0.8, color: yInk)),
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copiado'), duration: Duration(milliseconds: 700)));
  }

  Widget _bubble(AiChatMsg m, int i) {
    if (m.role == AiRole.system) return _systemNotice(m, i);
    if (m.role == AiRole.user) return _userBubble(m.text);

    // Assistant.
    final streaming = _s.streaming && i == _s.messages.length - 1;
    final Widget content = (m.text.isEmpty && streaming)
        ? Text('…', style: yBody(size: 14, color: yInk))
        : streaming
            ? SelectableText(m.text, style: yBody(size: 14, color: yInk))
            : NoteMarkdownPreview(data: m.text);
    final actions = (!streaming && m.text.isNotEmpty)
        ? <Widget>[
            _msgActionBtn('Copiar', () => _copy(m.text)),
            _msgActionBtn('Guardar en nota', () {
              final note = ref.read(noteByIdProvider(_s.noteId)).valueOrNull;
              sendTextToNote(context, ref, m.text,
                  defaultFolderId: note?.folderId, accent: widget.accent);
            }),
            _msgActionBtn(
                'Rehacer',
                () => _s.regenerate(i, ref.read(aiAssistantProvider),
                    ref.read(aiUsageLimiterProvider))),
            _msgActionBtn('Extraer tareas', () => _v3Soon('Extraer tareas')),
          ]
        : null;
    return _aiMsgFrame(content, actions: actions);
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 6),
            child: Text('TÚ',
                style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.6,
                    color: yMuted)),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yInk, width: yLineMid),
                boxShadow: const [BoxShadow(color: yInk, offset: Offset(4, 4))],
              ),
              child: SelectableText(text,
                  style: yBody(size: 15, weight: FontWeight.w500, color: yCream)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemNotice(AiChatMsg m, int i) {
    final canUndo = _s.canUndoCompact && i == _s.compactNoticeIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m.text,
                textAlign: TextAlign.center,
                style: yMono(size: 10, tracking: 0.5, color: yMuted)
                    .copyWith(fontStyle: FontStyle.italic)),
            if (canUndo) ...[
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _s.undoCompact(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.undo, size: 11, color: yMuted),
                  const SizedBox(width: 3),
                  Text('DESHACER',
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
    // (glyph, label, prompt, sendWithHistory)
    final items = <(String, String, String, bool)>[
      ('≡', 'Resumir', 'Resume el contexto en pocas líneas.', false),
      ('☑', 'Extraer tareas',
          'Lista las tareas accionables del contexto, una por línea, sin numerar.',
          false),
      ('A', 'Título', 'Sugiere 3 títulos cortos para el contexto.', false),
      ('⇄', 'Traducir', 'Traduce el contexto al inglés.', false),
      ('⌫', 'Limpiar',
          'Reescribe y limpia el contexto: corrige ortografía y redacción, '
              'mantén el significado.',
          false),
      // Uses full chat history (not a one-shot quick action).
      ('❝', 'Resumir chat',
          'Resume nuestra conversación hasta ahora en 3-4 puntos clave.', true),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yInk, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hair('// ACCIONES SOBRE LA NOTA'),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _qaChip(it.$1, it.$2, it.$3, withHistory: it.$4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hair(String label) {
    return Row(
      children: [
        Text(label,
            style: yMono(
                size: 10, weight: FontWeight.w700, tracking: 1.6, color: yMuted)),
        const SizedBox(width: 10),
        Expanded(
            child: Container(height: 2, color: yInk.withValues(alpha: 0.14))),
      ],
    );
  }

  Widget _qaChip(String glyph, String label, String prompt,
      {required bool withHistory}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _s.streaming ? null : () => _send(prompt, quickAction: !withHistory),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _s.streaming ? yCream2 : yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(glyph,
                style: yMono(
                    size: 12, weight: FontWeight.w700, color: widget.accent)),
            const SizedBox(width: 7),
            Text(label.toUpperCase(),
                style: yMono(
                    size: 10, weight: FontWeight.w700, tracking: 0.8, color: yInk)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              enabled: !_s.streaming,
              style: yBody(size: 15, color: yInk),
              onSubmitted: _s.streaming ? null : _send,
              textInputAction: TextInputAction.send,
              decoration: _fieldDeco('Escribe a YuLi…'),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _s.streaming ? null : () => _send(_input.text),
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _s.streaming ? yMuted : widget.accent,
                border: Border.all(color: yInk, width: yLineMid),
                boxShadow: _s.streaming
                    ? null
                    : const [BoxShadow(color: yInk, offset: Offset(3, 3))],
              ),
              child: _s.streaming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: yCream))
                  : const Icon(Icons.arrow_upward, color: yCream, size: 22),
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
