import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/graph.dart';
import '../../../domain/models/lab_space.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/task_providers.dart';
import '../../widgets/yuli_design.dart';
import 'graph_assembler.dart';
import 'graph_simulation.dart';
import 'graph_node_detail.dart';

/// The "Grafo de Conexiones" tab. A live force-directed poster of how a lab
/// space connects across the three modes. Heat-aware: the simulation ticks only
/// while warm (load settle + during/after a drag) and STOPS at rest; the only
/// perpetual animation is the urgent-task pulse, isolated in its own painter.
/// Dragging a node pulls the whole graph with it (springs).
class GraphTab extends ConsumerStatefulWidget {
  const GraphTab({super.key, required this.space, this.onOpenCard});
  final LabSpace space;
  final void Function(int cardId)? onOpenCard;

  @override
  ConsumerState<GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends ConsumerState<GraphTab>
    with TickerProviderStateMixin {
  bool _global = false;
  bool _showAi = true;

  final _xf = _ViewTransform();
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  AnimationController? _pulse;

  GraphData? _rendered;
  GraphSimulation? _sim;

  // gesture state
  Size _size = Size.zero;
  String? _dragId;
  bool _moved = false;
  double _scaleStart = 1;
  bool _needsFit = false; // frame the whole graph once it settles

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final sim = _sim;
    if (sim == null) return;
    final hot = sim.step();
    if (!hot && _needsFit && _dragId == null) {
      _fitToView();
      _needsFit = false;
    }
    _repaint.value++;
    if (!hot && _dragId == null) _ticker.stop();
  }

  /// Frame the whole settled graph in the viewport (so the spread is visible
  /// without manually zooming out). Skipped once the user pans/zooms/drags.
  void _fitToView() {
    final sim = _sim;
    final data = _rendered;
    if (sim == null || data == null || _size == Size.zero) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in data.nodes) {
      final p = sim.posOf(n.id);
      if (p == null) continue;
      final r = graphNodeRadius(n.kind) + 22; // include label room
      minX = math.min(minX, p.dx - r);
      minY = math.min(minY, p.dy - r);
      maxX = math.max(maxX, p.dx + r);
      maxY = math.max(maxY, p.dy + r);
    }
    if (minX > maxX) return;
    final gw = math.max(maxX - minX, 1.0);
    final gh = math.max(maxY - minY, 1.0);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final s = math
        .min(_size.width * 0.86 / gw, _size.height * 0.86 / gh)
        .clamp(0.3, 1.5);
    _xf.scale = s;
    _xf.pan = Offset(-cx * s, -cy * s);
  }

  void _ensureTicking() {
    if (!_ticker.isTicking) _ticker.start();
  }

  void _applyData(GraphData data) {
    if (identical(data, _rendered)) return;
    // Carry positions over so real-time data updates nudge the layout instead
    // of teleporting everything (the sim reheats gently when given `previous`).
    final previous = _sim?.positions;
    _rendered = data;
    _sim = GraphSimulation(data, previous: previous);
    _dragId = null;
    if (previous == null) _needsFit = true; // frame a freshly-built graph
    _ticker.stop();
    if (data.nodes.length > 1) _ensureTicking(); // animate the settle/reflow
    if (data.hasUrgentTask) {
      _pulse ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1500))
        ..repeat();
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  Color get _accent => widget.space.accentColor;

  Offset _screenToWorld(Offset s) => Offset(
        (s.dx - _size.width / 2 - _xf.pan.dx) / _xf.scale,
        (s.dy - _size.height / 2 - _xf.pan.dy) / _xf.scale,
      );

  String? _hitNode(Offset world) {
    final sim = _sim;
    if (sim == null) return null;
    String? best;
    double bestD = double.infinity;
    for (final n in _rendered!.nodes) {
      final p = sim.posOf(n.id);
      if (p == null) continue;
      final d = (p - world).distance;
      final hit = graphNodeRadius(n.kind) + 8;
      if (d <= hit && d < bestD) {
        bestD = d;
        best = n.id;
      }
    }
    return best;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _moved = false;
    _scaleStart = _xf.scale;
    if (_sim == null) return;
    final world = _screenToWorld(d.localFocalPoint);
    _dragId = _hitNode(world);
    if (_dragId != null) {
      _needsFit = false;
      _sim!.dragActive = true;
      _sim!.pin(_dragId!, world);
      _sim!.reheat(0.55);
      _ensureTicking();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.scale != 1.0 || d.focalPointDelta.distance > 0.5) _moved = true;
    if (_dragId != null && d.pointerCount == 1) {
      _sim!.movePinned(_dragId!, _screenToWorld(d.localFocalPoint));
      _sim!.reheat(0.4);
      _ensureTicking();
      return;
    }
    // pan + zoom around the focal point
    _needsFit = false;
    _xf.pan += d.focalPointDelta;
    if (d.scale != 1.0) {
      final focal = d.localFocalPoint;
      final worldFocal = _screenToWorld(focal);
      _xf.scale = (_scaleStart * d.scale).clamp(0.3, 4.0);
      _xf.pan = focal -
          Offset(_size.width / 2, _size.height / 2) -
          worldFocal * _xf.scale;
    }
    _repaint.value++;
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final dragged = _dragId;
    _dragId = null;
    if (dragged != null) {
      if (!_moved) {
        final node = _rendered!.nodes.firstWhere((n) => n.id == dragged);
        _handleTap(node, _rendered!);
      }
      _sim?.dragActive = false; // full forces resume → graph re-settles
      _sim?.unpin(dragged);
      _sim?.reheat(0.32);
      _ensureTicking();
    }
  }

  Future<void> _handleTap(GraphNode node, GraphData data) async {
    final action =
        await showGraphNodeDetail(context, node, data, accent: _accent);
    if (action == null || !mounted) return;
    switch (action) {
      case GraphNodeAction.openNote:
        ref.read(pendingNoteNavigationProvider.notifier).state = node.refId;
        Navigator.of(context).pop();
      case GraphNodeAction.openFolder:
        ref.read(pendingFolderNavigationProvider.notifier).state = node.refId;
        Navigator.of(context).pop();
      case GraphNodeAction.openCard:
        widget.onOpenCard?.call(node.refId!);
      case GraphNodeAction.markTaskDone:
        await setTaskDone(ref, node.refId!, done: true);
        ref.invalidate(graphDataProvider(_global ? null : widget.space.id));
    }
  }

  void _refresh(int? scope) => ref.invalidate(graphDataProvider(scope));

  @override
  Widget build(BuildContext context) {
    final scope = _global ? null : widget.space.id;
    // Real-time: re-assemble the graph the moment underlying data changes while
    // the tab is open (cards moved/added/done, columns, sources, spaces).
    if (_global) {
      ref.listen(activeLabSpacesProvider, (_, _) => _refresh(scope));
    } else {
      ref.listen(
          kanbanCardsBySpaceProvider(widget.space.id), (_, _) => _refresh(scope));
      ref.listen(
          kanbanColumnsProvider(widget.space.id), (_, _) => _refresh(scope));
      ref.listen(spaceContextSourcesProvider(widget.space.id),
          (_, _) => _refresh(scope));
    }
    // Fight task changes (new @folder capture, status flip) refresh too.
    ref.listen(pendingTasksProvider, (_, _) => _refresh(scope));
    ref.listen(yesterdayTasksProvider, (_, _) => _refresh(scope));
    ref.listen(vencidasTasksProvider, (_, _) => _refresh(scope));
    final async = ref.watch(graphDataProvider(scope));
    return ClipRect(
      child: Container(
        color: yCream,
        child: async.when(
          loading: () => const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4))),
          error: (e, _) => Center(
              child: Text('No se pudo armar el grafo',
                  style: yMono(size: 12, color: yMuted))),
          data: (data) {
            _applyData(data);
            return _buildStack(data);
          },
        ),
      ),
    );
  }

  Widget _buildStack(GraphData data) {
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(builder: (ctx, c) {
            _size = c.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GraphPainter(
                        data: data,
                        sim: _sim!,
                        xf: _xf,
                        showAi: _showAi,
                        repaint: _repaint,
                      ),
                    ),
                  ),
                  if (_pulse != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _UrgentPainter(
                            data: data,
                            sim: _sim!,
                            xf: _xf,
                            anim: _pulse!,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        if (data.isEmpty) _emptyState(),
        Positioned(top: 12, right: 12, child: _controls()),
        Positioned(
            left: 12,
            bottom: 12,
            child: _Legend(showAi: _showAi, accent: _accent)),
      ],
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 26, height: 26, color: _accent),
              const SizedBox(height: 14),
              Text('AÚN SIN CONEXIONES',
                  style: yMono(
                      size: 12, weight: FontWeight.w700, tracking: 1.6)),
              const SizedBox(height: 6),
              Text(
                'Vincula notas, carpetas o tareas a este espacio\ny míralas tejerse aquí.',
                textAlign: TextAlign.center,
                style: yBody(size: 13, color: yMuted),
              ),
            ],
          ),
        ),
      );

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ToggleBtn(
          label: _global ? 'TODO' : 'ESTE',
          active: _global,
          activeColor: _accent,
          onTap: () => setState(() => _global = !_global),
        ),
        const SizedBox(height: 8),
        _ToggleBtn(
          label: 'IA',
          active: _showAi,
          activeColor: yFlight,
          onTap: () => setState(() {
            _showAi = !_showAi;
            _repaint.value++;
          }),
        ),
      ],
    );
  }
}

// ─── Painters ────────────────────────────────────────────────────────────────

class _ViewTransform {
  Offset pan = Offset.zero;
  double scale = 1.0;
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.sim,
    required this.xf,
    required this.showAi,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GraphData data;
  final GraphSimulation sim;
  final _ViewTransform xf;
  final bool showAi;

  final Map<String, TextPainter> _labelCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + xf.pan.dx, size.height / 2 + xf.pan.dy);
    canvas.scale(xf.scale);

    _grid(canvas, size);
    for (final e in data.edges) {
      if (e.kind == GraphEdgeKind.ai && !showAi) continue;
      final a = sim.posOf(e.from);
      final b = sim.posOf(e.to);
      if (a == null || b == null) continue;
      _edge(canvas, a, b, e.kind);
    }
    for (final n in data.nodes) {
      final p = sim.posOf(n.id);
      if (p != null) _node(canvas, n, p);
    }
    for (final n in data.nodes) {
      final p = sim.posOf(n.id);
      if (p != null) _label(canvas, n, p);
    }
    canvas.restore();
  }

  Offset _s2w(Offset s, Size size) => Offset(
        (s.dx - size.width / 2 - xf.pan.dx) / xf.scale,
        (s.dy - size.height / 2 - xf.pan.dy) / xf.scale,
      );

  void _grid(Canvas canvas, Size size) {
    const step = 36.0;
    if (step * xf.scale < 9) return; // too dense → skip
    final tl = _s2w(Offset.zero, size);
    final br = _s2w(Offset(size.width, size.height), size);
    final paint = Paint()..color = yInk.withValues(alpha: 0.06);
    final startX = (tl.dx / step).floor() * step;
    final startY = (tl.dy / step).floor() * step;
    for (var x = startX; x < br.dx; x += step) {
      for (var y = startY; y < br.dy; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  void _label(Canvas canvas, GraphNode n, Offset p) {
    if (n.kind == GraphNodeKind.url || n.label.trim().isEmpty) return;
    final tp = _labelCache.putIfAbsent(n.id, () => _buildLabel(n));
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  TextPainter _buildLabel(GraphNode n) {
    final filled = switch (n.kind) {
      GraphNodeKind.space ||
      GraphNodeKind.folder ||
      GraphNodeKind.card =>
        true,
      GraphNodeKind.task => n.taskState == TaskGraphState.fresca ||
          n.taskState == TaskGraphState.urgente,
      _ => false,
    };
    final Color col;
    if (n.kind == GraphNodeKind.note) {
      col = n.color;
    } else if (n.taskState == TaskGraphState.fantasma) {
      col = yMuted;
    } else if (n.taskState == TaskGraphState.ayer) {
      col = yInk.withValues(alpha: 0.7);
    } else if (filled) {
      col = yCream;
    } else {
      col = yInk;
    }
    final size = switch (n.kind) {
      GraphNodeKind.space => 10.5,
      GraphNodeKind.folder => 10.0,
      _ => 8.5,
    };
    return TextPainter(
      text: TextSpan(
          text: n.label,
          style: yMono(
              size: size, weight: FontWeight.w700, tracking: 0.2, color: col)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: graphNodeRadius(n.kind) * 1.85);
  }

  void _edge(Canvas canvas, Offset a, Offset b, GraphEdgeKind kind) {
    switch (kind) {
      case GraphEdgeKind.structure:
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = yInk.withValues(alpha: 0.22)
              ..strokeWidth = 1.4);
      case GraphEdgeKind.bridge:
        // Reference: task connections are dashed.
        _dashedLine(
            canvas,
            a,
            b,
            Paint()
              ..color = yInk.withValues(alpha: 0.5)
              ..strokeWidth = 1.7,
            dash: 5,
            gap: 4);
      case GraphEdgeKind.ai:
        // Reference style: subtle dashed blue line (no glow blob).
        _dashedLine(
            canvas,
            a,
            b,
            Paint()
              ..color = yFlight.withValues(alpha: 0.85)
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round,
            dash: 6,
            gap: 5);
    }
  }

  void _node(Canvas canvas, GraphNode n, Offset p) {
    final r = _r(n.kind);
    switch (n.kind) {
      case GraphNodeKind.space:
        _sun(canvas, p, r, n.color);
      case GraphNodeKind.folder:
        _slab(canvas, p, r, n.color);
      case GraphNodeKind.card:
        _slab(canvas, p, r, n.color);
        canvas.drawRect(
            Rect.fromLTWH(p.dx - r * 0.6, p.dy - r * 0.6, r * 1.2, r * 0.24),
            Paint()..color = yCream.withValues(alpha: 0.9));
      case GraphNodeKind.note:
        _note(canvas, n, p, r);
      case GraphNodeKind.task:
        _task(canvas, n, p, r);
      case GraphNodeKind.url:
        break; // URLs are not drawn
    }
  }

  double _r(GraphNodeKind k) => graphNodeRadius(k);

  void _slab(Canvas canvas, Offset p, double r, Color fill,
      {Color? border, double bw = 3}) {
    final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bw
          ..color = border ?? yInk);
  }

  void _sun(Canvas canvas, Offset p, double r, Color accent) {
    // Square glow: two soft blurred SQUARES (not a circle).
    canvas.drawRect(
        Rect.fromCenter(center: p, width: r * 3.0, height: r * 3.0),
        Paint()
          ..color = accent.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawRect(
        Rect.fromCenter(center: p, width: r * 2.3, height: r * 2.3),
        Paint()
          ..color = accent.withValues(alpha: 0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    _slab(canvas, p, r, accent, bw: 3.5);
  }

  void _note(Canvas canvas, GraphNode n, Offset p, double r) {
    _slab(canvas, p, r, yCream, border: n.color, bw: 3);
  }

  void _task(Canvas canvas, GraphNode n, Offset p, double r) {
    final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
    switch (n.taskState) {
      case TaskGraphState.fantasma:
        _dashedRect(canvas, rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = yMuted.withValues(alpha: 0.55));
      case TaskGraphState.ayer:
        final gray = Color.lerp(n.color, yMuted, 0.7)!;
        canvas.drawRect(rect, Paint()..color = gray.withValues(alpha: 0.48));
        canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = yMuted.withValues(alpha: 0.6));
      case TaskGraphState.urgente:
        _slab(canvas, p, r, n.color, border: yFight, bw: 4);
      case TaskGraphState.fresca:
      case null:
        _slab(canvas, p, r, n.color, bw: 3);
    }
    if (n.taskState != TaskGraphState.fantasma) {
      final path = Path()
        ..moveTo(p.dx + r * 0.45, p.dy - r)
        ..lineTo(p.dx + r, p.dy - r)
        ..lineTo(p.dx + r, p.dy - r * 0.45)
        ..close();
      canvas.drawPath(path, Paint()..color = yFight);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 6, double gap = 4}) {
    final total = (b - a).distance;
    if (total < 0.5) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    for (final seg in [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ]) {
      _dashedLine(canvas, seg[0], seg[1], paint, dash: 5, gap: 3);
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.showAi != showAi || !identical(old.data, data);
}

class _UrgentPainter extends CustomPainter {
  _UrgentPainter({
    required this.data,
    required this.sim,
    required this.xf,
    required this.anim,
  }) : super(repaint: anim);

  final GraphData data;
  final GraphSimulation sim;
  final _ViewTransform xf;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    // Reference: scale 1→1.10, opacity .35→.9, 1.5s.
    final pulse = (math.sin(anim.value * 2 * math.pi) + 1) / 2; // 0..1
    canvas.save();
    canvas.translate(size.width / 2 + xf.pan.dx, size.height / 2 + xf.pan.dy);
    canvas.scale(xf.scale);
    for (final n in data.nodes) {
      if (n.taskState != TaskGraphState.urgente) continue;
      final p = sim.posOf(n.id);
      if (p == null) continue;
      final half = 17 * (1.05 + 0.10 * pulse);
      canvas.drawRect(
          Rect.fromCenter(center: p, width: half * 2, height: half * 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = yFight.withValues(alpha: 0.35 + 0.55 * pulse));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UrgentPainter old) => true;
}

// ─── Overlay chrome ──────────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? activeColor : yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Text(label,
            style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: active ? yCream : yInk)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showAi, required this.accent});
  final bool showAi;
  final Color accent;

  Widget _row(Widget swatch, String label) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 15, height: 15, child: Center(child: swatch)),
          const SizedBox(width: 9),
          Text(label, style: yMono(size: 9, tracking: 0.6, color: yInk)),
        ]),
      );

  Widget _box({Color? fill, Color border = yInk, double bw = 1.5}) => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
            color: fill ?? yCream, border: Border.all(color: border, width: bw)),
      );

  @override
  Widget build(BuildContext context) {
    final gray = Color.lerp(accent, yMuted, 0.7)!.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 16, 11),
      decoration: BoxDecoration(
        color: yCream.withValues(alpha: 0.96),
        border: Border.all(color: yInk, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('> LEYENDA',
            style: yMono(size: 9, weight: FontWeight.w700, tracking: 1.6)),
        const SizedBox(height: 3),
        _row(_box(fill: accent), 'Espacio · carpeta'),
        _row(_box(border: accent, bw: 2), 'Nota'),
        _row(
            SizedBox(
                width: 13,
                height: 13,
                child: CustomPaint(painter: _SwatchPainter(_SwatchKind.task, accent))),
            'Tarea fresca'),
        _row(_box(fill: accent, border: yFight, bw: 2), 'Tarea urgente'),
        _row(_box(fill: gray, border: yMuted), 'Tarea de ayer'),
        _row(
            SizedBox(
                width: 13,
                height: 13,
                child: CustomPaint(painter: _SwatchPainter(_SwatchKind.ghost, accent))),
            'Tarea fantasma'),
        const SizedBox(height: 6),
        _row(
            CustomPaint(
                size: const Size(15, 8),
                painter: _SwatchPainter(_SwatchKind.solid, yInk)),
            'Estructura'),
        _row(
            CustomPaint(
                size: const Size(15, 8),
                painter: _SwatchPainter(_SwatchKind.dashed, yInk)),
            'Conexión de tarea'),
        if (showAi)
          _row(
              CustomPaint(
                  size: const Size(15, 8),
                  painter: _SwatchPainter(_SwatchKind.dashed, yFlight)),
              'Conexión IA'),
      ]),
    );
  }
}

enum _SwatchKind { task, ghost, solid, dashed }

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.kind, this.color);
  final _SwatchKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _SwatchKind.task:
        final r = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
        canvas.drawRect(r, Paint()..color = color);
        canvas.drawRect(
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = yInk);
        final tri = Path()
          ..moveTo(size.width * 0.55, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.45)
          ..close();
        canvas.drawPath(tri, Paint()..color = yFight);
      case _SwatchKind.ghost:
        final r = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
        _dash(canvas, r.topLeft, r.topRight);
        _dash(canvas, r.topRight, r.bottomRight);
        _dash(canvas, r.bottomRight, r.bottomLeft);
        _dash(canvas, r.bottomLeft, r.topLeft);
      case _SwatchKind.solid:
        canvas.drawLine(
            Offset(0, size.height / 2),
            Offset(size.width, size.height / 2),
            Paint()
              ..color = color
              ..strokeWidth = 2);
      case _SwatchKind.dashed:
        _dash(canvas, Offset(0, size.height / 2),
            Offset(size.width, size.height / 2));
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final total = (b - a).distance;
    final dir = total == 0 ? Offset.zero : (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * (d + 3 < total ? d + 3 : total);
      canvas.drawLine(s, e, paint);
      d += 5;
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.kind != kind || old.color != color;
}
