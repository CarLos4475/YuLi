import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/ai_assistant.dart';
import '../../providers/ai_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'ai_modes.dart';
import 'mode_builder.dart';

/// Floating step-by-step dialog to create OR edit ([editing]) a custom chat
/// mode. YuLi interviews the user (open-ended), proposes a persona in a parseable
/// block, and on approval runs the safety sanitizer before saving — editing rides
/// the same sanitizer, so a benign mode can't be quietly degraded. The persona
/// authored here is only the HOW of the mode; the shared _rules ride on at
/// runtime. Shown via showDialog — a centred card over a scrim, NOT a full screen.
class ModeBuilderDialog extends ConsumerStatefulWidget {
  final Color accent;

  /// When non-null, the dialog EDITS this mode (seeds the icon, hands YuLi the
  /// current persona, and on save keeps the same id) instead of creating one.
  final AiMode? editing;

  const ModeBuilderDialog({super.key, required this.accent, this.editing});

  @override
  ConsumerState<ModeBuilderDialog> createState() => _ModeBuilderDialogState();
}

class _BMsg {
  final AiRole role;
  String text;
  final bool hidden; // kickoff turn: sent for context, not shown
  _BMsg(this.role, this.text, {this.hidden = false});
}

class _ModeBuilderDialogState extends ConsumerState<ModeBuilderDialog> {
  final List<_BMsg> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  AiModeDraft? _draft;
  String _iconKey = 'sparkles';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ed = widget.editing;
    if (ed != null && ed.iconKey.isNotEmpty) _iconKey = ed.iconKey;
    // Kick off the interview: YuLi greets and asks its first question (for an
    // edit, what to change). The kickoff user turn is hidden from the transcript.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _send(
        ed != null
            ? 'Quiero editar el modo "${ed.name}". Salúdame muy breve y '
                'pregúntame qué quiero cambiarle.'
            : 'Quiero crear un modo de chat personalizado. Salúdame breve y '
                'hazme la primera pregunta para diseñarlo.',
        hidden: true,
      );
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String text, {bool hidden = false}) async {
    if (_busy) return;
    final t = text.trim();
    if (!hidden && t.isEmpty) return;

    final limiter = ref.read(aiUsageLimiterProvider);
    if (!await limiter.canSend()) {
      setState(() => _error = 'Límite diario de IA alcanzado. Intenta mañana.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _messages.add(_BMsg(AiRole.user, t, hidden: hidden));
    });
    _input.clear();

    final ed = widget.editing;
    final existing = kAllAiModes
        .where((m) => m.id != ed?.id) // editing can keep its own name
        .map((m) => m.name)
        .toSet()
        .join(', ');
    final sys = StringBuffer(kModeBuilderPrompt);
    if (ed != null) sys.write(modeEditSystemSuffix(ed.name, ed.persona));
    sys.write(
      '\n\nNOMBRES YA EN USO (no repitas ninguno; inventa uno distinto y con '
      'personalidad): $existing.',
    );
    final convo = <AiMessage>[
      AiMessage(AiRole.system, sys.toString()),
      for (final m in _messages) AiMessage(m.role, m.text),
    ];
    final reply = _BMsg(AiRole.assistant, '');
    setState(() => _messages.add(reply));
    _scrollToEnd();

    await limiter.record();
    final assistant = ref.read(aiAssistantProvider);
    try {
      await for (final tok in assistant.streamReply(
        convo,
        model: AiModel.flash,
      )) {
        setState(() => reply.text += tok);
        _scrollToEnd();
      }
    } catch (e) {
      setState(() {
        if (reply.text.isEmpty) reply.text = 'No se pudo responder: $e';
      });
    }

    final draft = parseModeProposal(reply.text);
    setState(() {
      _draft = draft;
      _busy = false;
    });
    _scrollToEnd();
  }

  /// [ME GUSTA] → run the sanitizer; save on accept, show the reason on reject.
  Future<void> _approve() async {
    final draft = _draft;
    if (draft == null || _busy) return;

    final limiter = ref.read(aiUsageLimiterProvider);
    if (!await limiter.canSend()) {
      setState(() => _error = 'Límite diario de IA alcanzado. Intenta mañana.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    await limiter.record();
    final assistant = ref.read(aiAssistantProvider);
    final buf = StringBuffer();
    try {
      await for (final tok in assistant.streamReply([
        const AiMessage(AiRole.system, kModeSanitizerPrompt),
        AiMessage(AiRole.user, draft.persona),
      ], model: AiModel.flash)) {
        buf.write(tok);
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo validar la persona: $e';
      });
      return;
    }

    final result = interpretSanitizerOutput(buf.toString());
    if (!result.accepted) {
      setState(() {
        _busy = false;
        _error = result.rejectionReason;
      });
      return;
    }

    final mode = AiMode(
      id:
          widget.editing?.id ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: draft.name,
      blurb: draft.blurb.isEmpty ? 'Modo personalizado.' : draft.blurb,
      sample: draft.sample,
      icon: iconForKey(_iconKey),
      iconKey: _iconKey,
      persona: result.persona!, // the SANITIZED persona, not the raw draft
      custom: true,
    );
    await ref.read(customModesStoreProvider).add(mode);
    if (mounted) Navigator.of(context).pop(mode);
  }

  void _keepRefining() {
    setState(() {
      _draft = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxH = size.height * 0.82 < 660 ? size.height * 0.82 : 660.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow: const [
              BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    for (final m in _messages)
                      if (!m.hidden) _bubble(m),
                    if (_busy && _draft == null && _streamingEmpty()) _typing(),
                    if (_draft != null) _previewCard(_draft!),
                  ],
                ),
              ),
              if (_error != null) _errorBanner(_error!),
              if (_draft != null) _proposalActions() else _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// YuLi-branded header: dark bar with the accent diamond mark, "YuLi" and a
  /// contextual subtitle (NUEVO MODO / EDITANDO · NAME), plus the close X.
  Widget _header() {
    final ed = widget.editing;
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: AccentMosaic(accent: widget.accent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                _mark(size: 34, onAccent: true),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YuLi',
                        style: ySans(
                          size: 18,
                          weight: FontWeight.w700,
                          color: yCream,
                        ),
                      ),
                      Text(
                        ed != null ? 'EDITANDO · ${ed.name}' : 'NUEVO MODO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: yMono(
                          size: 8,
                          tracking: 1.6,
                          color: yCream.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: yCream, width: yLineMid),
                    ),
                    child: const Icon(YuLiIcons.close, color: yCream, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// YuLi's signature: a rotated diamond mark. On cream (bubbles) it's an accent
  /// square with a cream diamond; [onAccent] inverts it (cream square, accent
  /// diamond) so it reads against the accent header bar.
  Widget _mark({double size = 30, bool onAccent = false}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onAccent ? yCream : widget.accent,
        border:
            onAccent
                ? null
                : Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: size * 0.36,
          height: size * 0.36,
          color: onAccent ? widget.accent : yCream,
        ),
      ),
    );
  }

  Widget _bubble(_BMsg m) {
    if (m.role == AiRole.user) return _userBubble(m.text);
    final display = stripProposalForDisplay(m.text);
    if (display.isEmpty) return const SizedBox.shrink();
    return _yuliBubble(display);
  }

  /// YuLi's turn: diamond mark + "YULI" label + a bordered cream bubble with the
  /// brutalist drop shadow (mirrors the main chat's assistant frame).
  Widget _yuliBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mark(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 5),
                  child: Text(
                    'YULI',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.6,
                      color: yMuted,
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineMid),
                    boxShadow: const [
                      BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
                    ],
                  ),
                  child: Text(text, style: yBody(size: 14, color: yInk)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// User's turn: right-aligned "TÚ" + accent bubble with drop shadow.
  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 5),
            child: Text(
              'TÚ',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.6,
                color: yMuted,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [
                  BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                ],
              ),
              child: Text(
                text,
                style: yBody(size: 14, weight: FontWeight.w500, color: yCream),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True while the latest assistant reply is still empty (just started), so the
  /// typing bubble shows only before text begins streaming (no duplicate).
  bool _streamingEmpty() {
    if (_messages.isEmpty) return false;
    final last = _messages.last;
    return last.role == AiRole.assistant &&
        stripProposalForDisplay(last.text).isEmpty;
  }

  /// Branded "thinking" state: the mark + a small bubble with an ellipsis.
  Widget _typing() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mark(),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child: Text('escribiendo…', style: yBody(size: 13, color: yMuted)),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(AiModeDraft d) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: widget.accent, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YULI PROPONE',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.6,
              color: yMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: Icon(iconForKey(_iconKey), size: 17, color: yCream),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  d.name,
                  style: yMono(size: 14, weight: FontWeight.w800, color: yInk),
                ),
              ),
            ],
          ),
          if (d.blurb.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(d.blurb, style: yBody(size: 13, color: yInk)),
          ],
          if (d.sample.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              d.sample,
              style: yBody(
                size: 12,
                color: yMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'ÍCONO',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kModeIcons.entries)
                _iconChoice(entry.key, entry.value),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'PERSONA',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(d.persona, style: yBody(size: 12, color: yInk)),
        ],
      ),
    );
  }

  Widget _iconChoice(String key, IconData icon) {
    final selected = key == _iconKey;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _iconKey = key),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? widget.accent : yCream,
          border: Border.all(
            color: selected ? widget.accent : yBorderStrong,
            width: selected ? yLineMid : yLineThin,
          ),
        ),
        child: Icon(icon, size: 18, color: selected ? yCream : yInk),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      width: double.infinity,
      color: yCream2,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(YuLiIcons.triangleAlert, size: 16, color: yInk),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: yBody(size: 13, color: yInk))),
        ],
      ),
    );
  }

  Widget _proposalActions() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              label: 'SEGUIR AFINANDO',
              filled: false,
              onTap: _busy ? null : _keepRefining,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              label: _busy ? 'VALIDANDO…' : 'ME GUSTA',
              filled: true,
              onTap: _busy ? null : _approve,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              disabled
                  ? yMuted
                  : filled
                  ? widget.accent
                  : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Text(
          label,
          style: yMono(
            size: 12,
            weight: FontWeight.w800,
            tracking: 1.1,
            color: filled || disabled ? yCream : yInk,
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
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
              enabled: !_busy,
              style: yBody(size: 15, color: yInk),
              onSubmitted: _busy ? null : (v) => _send(v),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Responde a YuLi…',
                hintStyle: yBody(size: 15, color: yMuted),
                filled: true,
                fillColor: yCream,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: yLineThin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: widget.accent, width: yLineMid),
                ),
                disabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: yLineThin,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => _send(_input.text),
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _busy ? yMuted : widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.arrowRight, color: yCream, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
