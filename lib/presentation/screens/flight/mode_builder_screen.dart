import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/ai_assistant.dart';
import '../../providers/ai_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'ai_chat_visuals.dart';
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
    final maxH = size.height * 0.86 < 700 ? size.height * 0.86 : 700.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 590, maxHeight: maxH),
        child: AiFrostedSurface(
          accent: widget.accent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
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

  Widget _header() {
    final ed = widget.editing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              YuLiIcons.sparkles,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ed != null ? 'EDITAR PERSONALIDAD' : 'NUEVA PERSONALIDAD',
                  style: ySans(size: 18, weight: FontWeight.w700, color: aiInk),
                ),
                const SizedBox(height: 2),
                Text(
                  ed != null
                      ? 'Cuéntale a YuLi qué quieres cambiar de ${ed.name}.'
                      : 'Diseñen juntos cómo quieres que te responda.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: yBody(size: 11.5, color: aiMuted),
                ),
              ],
            ),
          ),
          AiSoftIconButton(
            icon: YuLiIcons.close,
            tooltip: 'Cerrar',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _mark({double size = 30}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: size * 0.36,
          height: size * 0.36,
          color: widget.accent,
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
                    'YuLi',
                    style: yBody(
                      size: 11,
                      weight: FontWeight.w700,
                      color: aiMuted,
                    ),
                  ),
                ),
                Text(text, style: yBody(size: 14, color: aiInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 5),
            child: Text(
              'Tú',
              style: yBody(size: 11, weight: FontWeight.w700, color: aiMuted),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: widget.accent.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                text,
                style: yBody(size: 14, weight: FontWeight.w500, color: aiInk),
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
              color: Colors.white.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: aiHairline),
            ),
            child: Text('Escribiendo…', style: yBody(size: 13, color: aiMuted)),
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
        color: Colors.white.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YULI PROPONE',
            style: yBody(size: 11, weight: FontWeight.w700, color: aiMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconForKey(_iconKey),
                  size: 17,
                  color: widget.accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  d.name,
                  style: ySans(size: 16, weight: FontWeight.w700, color: aiInk),
                ),
              ),
            ],
          ),
          if (d.blurb.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(d.blurb, style: yBody(size: 13, color: aiInk)),
          ],
          if (d.sample.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              d.sample,
              style: yBody(
                size: 12,
                color: aiMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'ÍCONO',
            style: yBody(size: 10.5, weight: FontWeight.w700, color: aiMuted),
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
            style: yBody(size: 10.5, weight: FontWeight.w700, color: aiMuted),
          ),
          const SizedBox(height: 4),
          Text(d.persona, style: yBody(size: 12, color: aiInk)),
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
          color:
              selected ? widget.accent : Colors.white.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? widget.accent : aiHairline),
        ),
        child: Icon(icon, size: 18, color: selected ? Colors.white : aiInk),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.08),
        border: const Border(top: BorderSide(color: aiHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(YuLiIcons.triangleAlert, size: 16, color: widget.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: yBody(size: 13, color: aiInk))),
        ],
      ),
    );
  }

  Widget _proposalActions() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: aiHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
                  ? aiMuted
                  : filled
                  ? widget.accent
                  : Colors.white.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: filled ? widget.accent : aiHairline),
        ),
        child: Text(
          label,
          style: yBody(
            size: 12,
            weight: FontWeight.w800,
            color: filled || disabled ? Colors.white : aiInk,
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: aiHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: aiHairline),
              ),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                enabled: !_busy,
                style: yBody(size: 15, color: aiInk),
                onSubmitted: _busy ? null : (v) => _send(v),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Responde a YuLi…',
                  hintStyle: yBody(size: 15, color: aiMuted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: true,
                  fillColor: Colors.transparent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => _send(_input.text),
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _busy ? aiMuted : widget.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                YuLiIcons.arrowRight,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
