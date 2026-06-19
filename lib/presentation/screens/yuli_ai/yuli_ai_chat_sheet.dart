import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_ai_fab.dart' show YuliCubeMark;
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ai_assistant.dart';
import '../flight/ai_chat_session.dart' show AiChatMsg, AiChatSession;
import '../flight/note_block_widgets.dart'
    show NoteMarkdownPreview, fixMarkdownTables;

/// YuLi AI chat (YuLi AI 2). Opened from the floating cube FAB across Fight /
/// Lab / Flight-general / folder-detail. [accent] is the view's colour so the
/// sheet themes itself to the context it was opened from (same as the cube).
///
/// Deliberately simpler than the FLIGHT note chat (kept separate, that file is
/// untouched): one global conversation, always base mode + flash, no note
/// context / modes. Its power will come from function-calling later.
Future<void> showYuliAiChat(
  BuildContext context,
  WidgetRef ref, {
  required Color accent,
}) async {
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configura tu API key de DeepSeek en Ajustes'),
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _YuliAiChat(accent: accent),
  );
}

class _YuliAiChat extends ConsumerStatefulWidget {
  final Color accent;
  const _YuliAiChat({required this.accent});

  @override
  ConsumerState<_YuliAiChat> createState() => _YuliAiChatState();
}

class _YuliAiChatState extends ConsumerState<_YuliAiChat> {
  static const _kDailyCap = 150;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  int? _remaining;
  bool _wasStreaming = false;

  AiChatSession get _s => ref.read(yuliAiSessionProvider);

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _loadRemaining();
    if (_s.messages.isNotEmpty) _scrollToBottom();
  }

  @override
  void dispose() {
    _s.removeListener(_onSession);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
    if (_wasStreaming && !_s.streaming) _loadRemaining();
    _wasStreaming = _s.streaming;
  }

  Future<void> _loadRemaining() async {
    final r = await ref.read(aiUsageLimiterProvider).remaining();
    if (mounted) setState(() => _remaining = r);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty || _s.streaming) return;
    _input.clear();
    _s.send(
      ref.read(aiAssistantProvider),
      ref.read(aiUsageLimiterProvider),
      text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: screenH * 0.92,
        child: Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          child: Column(
            children: [
              _header(),
              Expanded(child: _s.messages.isEmpty ? _empty() : _list()),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header (brutalist accent band: framed cube + wordmark + usage) ───────

  Widget _header() {
    final used =
        _remaining == null
            ? null
            : (_kDailyCap - _remaining!).clamp(0, _kDailyCap);
    return Container(
      color: widget.accent,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          // Hard near-black baseline: the brutalist edge between band and body.
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: yBorderStrong, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: yCream, width: 2),
                ),
                child: YuliCubeMark(color: yCream, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YuLi · AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ySans(
                        size: 27,
                        weight: FontWeight.w800,
                        color: yCream,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _tag('FLASH'),
                        const SizedBox(width: 6),
                        _tag('BASE'),
                      ],
                    ),
                  ],
                ),
              ),
              if (used != null) ...[
                _headerUsage(used),
                const SizedBox(width: 10),
              ],
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: yCream, width: 2),
                  ),
                  child: const Icon(YuLiIcons.close, color: yCream, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: yCream, width: 1.5)),
      child: Text(
        label,
        style: yMono(
          size: 8,
          weight: FontWeight.w700,
          tracking: 1.2,
          color: yCream,
        ),
      ),
    );
  }

  Widget _headerUsage(int used) {
    return Container(
      width: 80,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(border: Border.all(color: yCream, width: 2)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$used/$_kDailyCap',
            textAlign: TextAlign.center,
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              tracking: 0.3,
              color: yCream,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 8,
            decoration: BoxDecoration(
              border: Border.all(color: yCream, width: 1.5),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (used / _kDailyCap).clamp(0.0, 1.0),
                child: Container(color: yCream),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'USOS HOY',
            textAlign: TextAlign.center,
            style: yMono(
              size: 7,
              weight: FontWeight.w700,
              tracking: 0.8,
              color: yCream,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YuliCubeMark(color: widget.accent, size: 72),
          const SizedBox(height: 18),
          Text(
            'Pregúntale a YuLi',
            style: ySans(size: 18, weight: FontWeight.w700, color: yInk),
          ),
          const SizedBox(height: 6),
          Text(
            'Escribe abajo para empezar.',
            style: yBody(size: 13, color: yMuted),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      itemCount: _s.messages.length,
      itemBuilder: (_, i) => _bubble(_s.messages[i], i),
    );
  }

  Widget _bubble(AiChatMsg m, int i) {
    if (m.role == AiRole.system) return _systemNotice(m.text);
    if (m.role == AiRole.user) return _userBubble(m.text);

    final streaming = _s.streaming && i == _s.messages.length - 1;
    final Widget content =
        (m.text.isEmpty && streaming)
            ? Text('…', style: yBody(size: 14, color: yInk))
            : streaming
            ? SelectableText(m.text, style: yBody(size: 14, color: yInk))
            : NoteMarkdownPreview(
              data: fixMarkdownTables(m.text),
              accent: widget.accent,
            );
    return _aiMsgFrame(content);
  }

  Widget _aiMsgFrame(Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YuliCubeMark(color: widget.accent, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
                  child: Text(
                    'YULI · IA',
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
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineMid),
                    boxShadow: const [
                      BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
                    ],
                  ),
                  child: content,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 6),
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
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [
                  BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
                ],
              ),
              child: SelectableText(
                text,
                style: yBody(size: 15, weight: FontWeight.w500, color: yCream),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemNotice(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: yMono(
            size: 10,
            tracking: 0.5,
            color: yMuted,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }

  // ─── Input ──────────────────────────────────────────────────────────────

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: SafeArea(
        top: false,
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
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                  hintText: 'Escribe a YuLi…',
                  hintStyle: yBody(size: 14, color: yMuted),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderStrong,
                      width: yLineMid,
                    ),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderStrong,
                      width: yLineMid,
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderStrong,
                      width: yLineMid,
                    ),
                  ),
                ),
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
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                  boxShadow:
                      _s.streaming
                          ? null
                          : const [
                            BoxShadow(
                              color: yBorderStrong,
                              offset: Offset(3, 3),
                            ),
                          ],
                ),
                child:
                    _s.streaming
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: yCream,
                          ),
                        )
                        : const Icon(
                          YuLiIcons.arrowUp,
                          color: yCream,
                          size: 22,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
