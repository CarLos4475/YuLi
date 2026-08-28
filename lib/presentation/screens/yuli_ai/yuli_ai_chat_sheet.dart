import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers/ai_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_ai_fab.dart' show YuliCubeMark;
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ai_assistant.dart';
import '../flight/ai_chat_session.dart'
    show AiChatMsg, AiChatSession, kConsultingLabel;
import '../flight/ai_chat_visuals.dart' show AiThinkingIndicator;
import '../flight/note_block_widgets.dart'
    show NoteMarkdownPreview, fixMarkdownTables;
import 'ai_knowledge_contracts.dart';
import 'ai_widget_contracts.dart';
import 'ai_widget_renderer.dart';
import 'yuli_ai_tools.dart';

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
  YuliAiSurfaceContext? surfaceContext,
}) async {
  if (surfaceContext != null) {
    ref.read(yuliAiSurfaceContextProvider.notifier).state = surfaceContext;
  }
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configura tu API key de YuLi AI en Ajustes'),
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

class _YuliAiPatchwork extends StatelessWidget {
  final Color accent;

  const _YuliAiPatchwork({required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _YuliAiPatchworkPainter(accent),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _YuliAssistantBubbleMark extends StatefulWidget {
  final Color accent;

  const _YuliAssistantBubbleMark({required this.accent});

  @override
  State<_YuliAssistantBubbleMark> createState() =>
      _YuliAssistantBubbleMarkState();
}

const _kSvgTemplate =
    '''<svg width="91" height="82" viewBox="0 0 91 82" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M25.5932 78V21.7745L5 4V59.0375L25.5932 78Z" fill="{ACCENT}"/>
<path d="M25.5932 21.7745V21.575H86L64.9492 4L5 4L25.5932 21.7745Z" fill="{ACCENT}"/>
<path d="M25.5932 21.575V21.7745V78H86V21.575H25.5932Z" fill="{ACCENT}"/>
<path d="M25.5932 21.575V78M25.5932 21.7745V21.575H86M5 4L64.9492 4L86 21.575V78H25.5932L5 59.0375V4ZM25.5932 78V21.7745M25.5932 21.7745L5 4M68.8922 31.75V49M54.5776 31.75V49M69.5254 31.75V49M53.9661 31.75V49" stroke="black" stroke-width="4" fill="none"/>
</svg>''';

class _YuliAssistantBubbleMarkState extends State<_YuliAssistantBubbleMark>
    with SingleTickerProviderStateMixin {
  static const _cycleMs = 30000;
  static const _bobs = 3;
  static const _size = 42.0;

  late final AnimationController _ctrl;
  double _bob = 0;
  String _svg = '';

  String _accentHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  void _onTick() {
    final t = (DateTime.now().millisecondsSinceEpoch % _cycleMs) / _cycleMs;
    final bob = math.sin(t * _bobs * 2 * math.pi) * _size * 0.06;
    if (bob != _bob) {
      setState(() => _bob = bob);
    }
  }

  @override
  void initState() {
    super.initState();
    _svg = _kSvgTemplate.replaceAll('{ACCENT}', _accentHex(widget.accent));
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    )..repeat();
    _ctrl.addListener(_onTick);
    _onTick();
  }

  @override
  void didUpdateWidget(_YuliAssistantBubbleMark old) {
    super.didUpdateWidget(old);
    if (old.accent != widget.accent) {
      _svg = _kSvgTemplate.replaceAll('{ACCENT}', _accentHex(widget.accent));
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Transform.translate(
        offset: Offset(0, _bob),
        child: SvgPicture.string(_svg, width: _size, height: _size),
      ),
    );
  }
}

class _YuliAiPatchworkPainter extends CustomPainter {
  final Color accent;

  const _YuliAiPatchworkPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    const rows = 2;
    final cell = size.height / rows;
    final cols = (size.width / cell).ceil();
    canvas.drawRect(Offset.zero & size, Paint()..color = accent);

    final accentHsl = HSLColor.fromColor(accent);
    final palette = <Color>[
      accentHsl
          .withLightness((accentHsl.lightness - 0.08).clamp(0.0, 1.0))
          .withSaturation((accentHsl.saturation - 0.02).clamp(0.0, 1.0))
          .toColor(),
      accentHsl
          .withLightness((accentHsl.lightness + 0.12).clamp(0.0, 1.0))
          .withSaturation((accentHsl.saturation + 0.04).clamp(0.0, 1.0))
          .toColor(),
      const Color(0xFFE85E55),
      const Color(0xFFF3B648),
      const Color(0xFF53BDC1),
      const Color(0xFF413B8A),
      yCream,
      accent,
    ];

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        _paintTile(canvas, rect, row, col, palette);
      }
    }
    final calmBand =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              yInk.withValues(alpha: 0.10),
              yCream.withValues(alpha: 0.16),
              yCream.withValues(alpha: 0.16),
              yInk.withValues(alpha: 0.10),
            ],
            stops: const [0.0, 0.18, 0.82, 1.0],
          ).createShader(
            Rect.fromLTWH(
              0,
              size.height * 0.18,
              size.width,
              size.height * 0.64,
            ),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.18, size.width, size.height * 0.64),
      calmBand,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.22,
        size.width * 0.40,
        size.height * 0.56,
      ),
      Paint()..color = yInk.withValues(alpha: 0.16),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.69,
        size.height * 0.24,
        size.width * 0.14,
        size.height * 0.52,
      ),
      Paint()..color = yInk.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = accent.withValues(alpha: 0.08),
    );
    canvas.restore();
  }

  void _paintTile(
    Canvas canvas,
    Rect rect,
    int row,
    int col,
    List<Color> palette,
  ) {
    final seed = row * 17 + col * 7;
    final bgColor = palette[seed % palette.length];
    final fgColor = palette[(seed * 3 + 2) % palette.length];
    final accentColor = palette[(seed * 5 + 1) % palette.length];
    canvas.drawRect(rect, Paint()..color = bgColor);
    final inner = rect.deflate(rect.width * 0.04);
    switch ((row + col) % 8) {
      case 0:
        _circles(canvas, inner, fgColor, accentColor);
        break;
      case 1:
        _triangles(canvas, inner, fgColor, accentColor);
        break;
      case 2:
        _diamond(canvas, inner, fgColor, accentColor);
        break;
      case 3:
        _petals(canvas, inner, fgColor);
        break;
      case 4:
        _sun(canvas, inner, fgColor, accentColor);
        break;
      case 5:
        _stripes(canvas, inner, fgColor);
        break;
      case 6:
        _arcs(canvas, inner, fgColor);
        break;
      default:
        _leaves(canvas, inner, fgColor);
        break;
    }
  }

  void _circles(Canvas canvas, Rect rect, Color a, Color b) {
    final r = rect.width * 0.34;
    canvas.drawCircle(rect.center, r, Paint()..color = a);
    canvas.drawCircle(rect.center, r * 0.42, Paint()..color = b);
  }

  void _triangles(Canvas canvas, Rect rect, Color a, Color b) {
    final p1 =
        Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..close();
    final p2 =
        Path()
          ..moveTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
    canvas.drawPath(p1, Paint()..color = a);
    canvas.drawPath(p2, Paint()..color = b);
  }

  void _diamond(Canvas canvas, Rect rect, Color a, Color b) {
    final d =
        Path()
          ..moveTo(rect.center.dx, rect.top + rect.height * 0.12)
          ..lineTo(rect.right - rect.width * 0.12, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom - rect.height * 0.12)
          ..lineTo(rect.left + rect.width * 0.12, rect.center.dy)
          ..close();
    canvas.drawPath(d, Paint()..color = a);
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: rect.width * 0.24,
        height: rect.height * 0.24,
      ),
      Paint()..color = b,
    );
  }

  void _petals(Canvas canvas, Rect rect, Color color) {
    final p = Paint()..color = color;
    final rx = rect.width * 0.24;
    final ry = rect.height * 0.24;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.top + rect.height * 0.30),
        width: rx,
        height: ry * 1.4,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.bottom - rect.height * 0.30),
        width: rx,
        height: ry * 1.4,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.left + rect.width * 0.30, rect.center.dy),
        width: rx * 1.4,
        height: ry,
      ),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.right - rect.width * 0.30, rect.center.dy),
        width: rx * 1.4,
        height: ry,
      ),
      p,
    );
  }

  void _sun(Canvas canvas, Rect rect, Color a, Color b) {
    final path = Path();
    final c = rect.center;
    final outer = rect.width * 0.34;
    final inner = rect.width * 0.17;
    for (var i = 0; i < 16; i++) {
      final ang = (math.pi * 2 * i) / 16;
      final r = i.isEven ? outer : inner;
      final x = c.dx + r * math.cos(ang);
      final y = c.dy + r * math.sin(ang);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = a);
    canvas.drawCircle(c, rect.width * 0.10, Paint()..color = b);
  }

  void _stripes(Canvas canvas, Rect rect, Color a) {
    final p = Paint()..color = a;
    final stripe = rect.width / 6;
    for (var i = 0; i < 6; i++) {
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left + stripe * i, rect.top, stripe, rect.height),
          p,
        );
      }
    }
  }

  void _arcs(Canvas canvas, Rect rect, Color a) {
    final p = Paint()..color = a;
    final radius = rect.width * 0.42;
    canvas.drawArc(
      Rect.fromCircle(center: rect.topLeft, radius: radius),
      0,
      math.pi / 2,
      true,
      p,
    );
    canvas.drawArc(
      Rect.fromCircle(center: rect.bottomRight, radius: radius),
      math.pi,
      math.pi / 2,
      true,
      p,
    );
  }

  void _leaves(Canvas canvas, Rect rect, Color a) {
    final p =
        Paint()
          ..color = a
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    final stemX = rect.center.dx;
    canvas.drawLine(
      Offset(stemX, rect.top + rect.height * 0.15),
      Offset(stemX, rect.bottom - rect.height * 0.15),
      p,
    );
    for (var i = 0; i < 3; i++) {
      final y = rect.top + rect.height * (0.28 + i * 0.22);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(stemX - rect.width * 0.12, y),
          width: rect.width * 0.24,
          height: rect.height * 0.16,
        ),
        Paint()..color = a,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(stemX + rect.width * 0.12, y),
          width: rect.width * 0.24,
          height: rect.height * 0.16,
        ),
        Paint()..color = a,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _YuliAiPatchworkPainter oldDelegate) =>
      oldDelegate.accent != accent;
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
    unawaited(_sendAsync(text));
  }

  Future<void> _sendAsync(String text) async {
    if (text.trim().isEmpty || _s.streaming) return;
    _input.clear();
    final retrievalQuery = _retrievalQuery(text);
    final widgetSpecs = ref
        .read(aiWidgetRetrieverProvider)
        .retrieve(text, surface: AiWidgetSurface.yuli, context: retrievalQuery);
    final widgetPrompt = aiWidgetPrompt(
      widgetSpecs,
      surface: AiWidgetSurface.yuli,
    );
    final knowledgePrompt = aiKnowledgePrompt(
      ref
          .read(aiKnowledgeRetrieverProvider)
          .retrieve(retrievalQuery, surface: AiKnowledgeSurface.yuli),
      surface: AiKnowledgeSurface.yuli,
    );
    final surfacePrompt = ref.read(yuliAiSurfaceContextProvider)?.prompt ?? '';
    final memoryPrompt = await ref
        .read(aiMemoryStoreProvider)
        .promptForTurn(retrievalQuery);
    _s.send(
      ref.read(aiAssistantProvider),
      ref.read(aiUsageLimiterProvider),
      text,
      tools: yuliToolDefs,
      toolGuidance: yuliToolSystem(),
      onToolCall: (c) => runYuliTool(ref, c),
      knowledgeDocs: [
        if (knowledgePrompt.isNotEmpty) knowledgePrompt,
        if (surfacePrompt.isNotEmpty) surfacePrompt,
      ],
      memoryDocs: memoryPrompt.isEmpty ? const [] : [memoryPrompt],
      widgetDocs: widgetPrompt.isEmpty ? const [] : [widgetPrompt],
    );
  }

  String _retrievalQuery(String text) {
    final recent = _s.messages.reversed
        .where((m) => m.role != AiRole.system)
        .take(4)
        .map((m) => m.text)
        .toList()
        .reversed
        .join('\n');
    return '$recent\n$text';
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

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _header() {
    final used =
        _remaining == null
            ? null
            : (_kDailyCap - _remaining!).clamp(0, _kDailyCap);
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _YuliAiPatchwork(accent: widget.accent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: yInk.withValues(alpha: 0.30),
                    ),
                    child: Row(
                      children: [
                        const Icon(YuLiIcons.box, size: 34, color: yCream),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YuLi AI',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ySans(
                                  size: 28,
                                  weight: FontWeight.w700,
                                  color: yCream,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'ASISTENTE · SEGUNDO CEREBRO',
                                    maxLines: 1,
                                    style: ySans(
                                      size: 10,
                                      weight: FontWeight.w500,
                                      letterSpacing: 1.2,
                                      color: yCream.withValues(alpha: 0.92),
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (used != null) ...[
                  const SizedBox(width: 10),
                  _headerUsage(used),
                ],
                const Spacer(),
                _headerActionButton(
                  icon: YuLiIcons.close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerUsage(int used) {
    return Container(
      width: 118,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: yInk.withValues(alpha: 0.24)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$used/$_kDailyCap',
            textAlign: TextAlign.center,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 0.2,
              color: yCream,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 12,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              border: Border.all(color: yCream, width: yLineThin),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (used / _kDailyCap).clamp(0.0, 1.0),
                child: Container(color: yCream),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'LIMITE USO',
            textAlign: TextAlign.center,
            style: yMono(
              size: 6.5,
              weight: FontWeight.w500,
              tracking: 0.8,
              color: yCream.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yInk.withValues(alpha: 0.24),
          border: Border.all(
            color: yCream.withValues(alpha: 0.65),
            width: yLineMid,
          ),
        ),
        child: Icon(icon, size: 14, color: yCream),
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [
                  BoxShadow(color: yBorderStrong, offset: Offset(5, 5)),
                ],
              ),
              child: YuliCubeMark(color: widget.accent, size: 72),
            ),
            const SizedBox(height: 28),
            Text(
              'PREGÚNTALE A',
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 2.0,
                color: yMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'YuLi',
              style: ySans(
                size: 42,
                weight: FontWeight.w800,
                color: yInk,
                height: 0.9,
              ),
            ),
            const SizedBox(height: 12),
            Container(width: 64, height: 3, color: widget.accent),
            const SizedBox(height: 18),
            Text(
              'Tu segundo cerebro. Consulta tareas, proyectos y más.',
              textAlign: TextAlign.center,
              style: yBody(size: 15, color: yMuted),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                _quickPromptCard(
                  icon: YuLiIcons.squareCheck,
                  label: 'Qué tengo pendiente hoy?',
                  prompt: 'Qué tengo pendiente hoy?',
                ),
                _quickPromptCard(
                  icon: YuLiIcons.folder,
                  label: 'Resume mis proyectos',
                  prompt:
                      'Resume mis proyectos y dime en qué debería enfocarme.',
                ),
                _quickPromptCard(
                  icon: YuLiIcons.sparkles,
                  label: 'Dame ideas para ser más productivo',
                  prompt:
                      'Dame ideas para ser más productivo con lo que ya tengo en YuLi.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickPromptCard({
    required IconData icon,
    required String label,
    required String prompt,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _send(prompt),
      child: Container(
        width: 210,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: yInk),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: yBody(size: 15, weight: FontWeight.w600, color: yInk),
              ),
            ),
          ],
        ),
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
    final Widget content;

    if (m.text == kConsultingLabel) {
      content = ConsultingIndicator(accent: widget.accent);
    } else if (m.text.isEmpty && streaming) {
      content = AiThinkingIndicator(accent: widget.accent);
    } else if (streaming) {
      final visible = AiWidgetParser.stripStreamingWidgetDraft(m.text);
      content =
          AiWidgetParser.isStreamingWidgetDraft(m.text)
              ? _streamingWidgetPreview(visible)
              : SelectableText(m.text, style: yBody(size: 14, color: yInk));
    } else if (m.truncated) {
      content = SelectableText(m.text, style: yBody(size: 14, color: yInk));
    } else if (AiWidgetParser.hasWidgets(m.text)) {
      content = AiWidgetRenderer(
        text: m.text,
        accent: widget.accent,
        surface: AiWidgetSurface.yuli,
        onSendMessage: _send,
        onActionResult: _s.addLocalAssistant,
      );
    } else {
      content = NoteMarkdownPreview(
        data: fixMarkdownTables(m.text),
        accent: widget.accent,
      );
    }
    return _aiMsgFrame(content);
  }

  Widget _streamingWidgetPreview(String visible) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visible.trim().isNotEmpty)
          SelectableText(visible, style: yBody(size: 14, color: yInk)),
        if (visible.trim().isNotEmpty) const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: 0.12),
            border: Border.all(color: widget.accent, width: yLineThin),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: widget.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Preparando widget',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w800,
                  tracking: 0.8,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiMsgFrame(Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _YuliAssistantBubbleMark(accent: widget.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 6),
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineHeavy),
                    boxShadow: const [
                      BoxShadow(color: yBorderStrong, offset: Offset(5, 5)),
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
      padding: const EdgeInsets.only(bottom: 22),
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
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineHeavy),
                boxShadow: const [
                  BoxShadow(color: yBorderStrong, offset: Offset(5, 5)),
                ],
              ),
              child: SelectableText(
                text,
                style: yBody(size: 14, weight: FontWeight.w600, color: yCream),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemNotice(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: yBorderStrong, width: 1.5),
          ),
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
      ),
    );
  }

  // ─── Input ──────────────────────────────────────────────────────────────

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(
          top: BorderSide(color: yBorderStrong, width: yLineHeavy),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                style: yBody(size: 16, color: yInk),
                onSubmitted: _s.streaming ? null : _send,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                  hintText: 'Escribe…',
                  hintStyle: yBody(size: 15, color: yMuted),
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
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _s.streaming ? null : () => _send(_input.text),
              child: Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _s.streaming ? yMuted : widget.accent,
                  border: Border.all(color: yBorderStrong, width: yLineHeavy),
                  boxShadow:
                      _s.streaming
                          ? null
                          : const [
                            BoxShadow(
                              color: yBorderStrong,
                              offset: Offset(4, 4),
                            ),
                          ],
                ),
                child:
                    _s.streaming
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: yCream,
                          ),
                        )
                        : const Icon(
                          YuLiIcons.arrowUp,
                          color: yCream,
                          size: 24,
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
