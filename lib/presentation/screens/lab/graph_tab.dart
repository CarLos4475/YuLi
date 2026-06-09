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
import '../../theme/lab_icons.dart';
import 'graph_assembler.dart';
import 'graph_simulation.dart';
import 'graph_node_detail.dart';
import 'lab_card_colors.dart';

const _urgentStroke = Color(0xFFC8332C);

/// The full "everything visible" filter state. Node kinds exclude `url` (never
/// rendered). Single source of truth for the default sets, the "show all" reset
/// and the "are filters narrowed?" check.
const _kAllNodeKinds = {
  GraphNodeKind.space,
  GraphNodeKind.card,
  GraphNodeKind.folder,
  GraphNodeKind.note,
  GraphNodeKind.task,
};
const _kAllEdgeKinds = {
  GraphEdgeKind.structure,
  GraphEdgeKind.bridge,
  GraphEdgeKind.ai,
};

/// The "Grafo de Conexiones" tab. A live force-directed poster of how a lab
/// space connects across the three modes. Heat-aware: the simulation ticks only
/// while warm (load settle + during/after a drag) and STOPS at rest; the only
/// perpetual animation is the alert pulse layer, isolated in its own painter.
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
  GraphNode? _selectedNode;
  final Set<GraphNodeKind> _visibleNodeKinds = {..._kAllNodeKinds};
  final Set<GraphEdgeKind> _visibleEdgeKinds = {..._kAllEdgeKinds};

  final _xf = _ViewTransform();
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  AnimationController? _pulse;

  GraphData? _rendered; // full graph from the provider
  GraphData _filtered = GraphData.empty; // visible subset the sim is built on
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
    final data = _filtered;
    if (sim == null || _size == Size.zero) return;
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
    _rendered = data;
    // Keep the selection pointing at the fresh node instance (or drop it if the
    // node vanished after a real-time update — e.g. a task that got completed).
    if (_selectedNode != null) {
      GraphNode? selected;
      for (final node in data.nodes) {
        if (node.id == _selectedNode!.id) {
          selected = node;
          break;
        }
      }
      _selectedNode = selected;
    }
    _rebuildSim(reframe: _sim == null);
  }

  /// (Re)build the simulation from the *filtered* view so the layout reflows to
  /// exactly what's visible (no gaps where hidden nodes used to be). Carries
  /// previous positions so the change is a gentle nudge, not a teleport. Called
  /// on data updates AND on filter changes — filtering IS a re-layout.
  void _rebuildSim({bool reframe = false}) {
    final rendered = _rendered;
    if (rendered == null) return;
    final previous = _sim?.positions;
    _filtered = _filteredData(rendered);
    _sim = GraphSimulation(_filtered, previous: previous);
    _dragId = null;
    if (reframe || previous == null) _needsFit = true; // frame a fresh graph
    _ticker.stop();
    if (_filtered.nodes.length > 1) _ensureTicking(); // animate the settle
    _updatePulse();
  }

  void _updatePulse() {
    // Runs while there's anything to pulse (sun/AI-source/urgent → effectively
    // whenever the graph is non-empty). Cheap: the pulse layer is isolated in a
    // RepaintBoundary, so this perpetual repaint doesn't touch the main graph.
    if (_filtered.nodes.isNotEmpty) {
      _pulse ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1500))
        ..repeat();
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  Color get _accent => widget.space.accentColor;
  bool get _showAi => _visibleEdgeKinds.contains(GraphEdgeKind.ai);
  bool get _hasCustomFilters =>
      _visibleNodeKinds.length != _kAllNodeKinds.length ||
      _visibleEdgeKinds.length != _kAllEdgeKinds.length;

  /// WYSIWYG filter: keep every node whose kind is enabled, and every edge whose
  /// kind is enabled that joins two visible nodes. No orphan-pruning — a kind you
  /// enable always shows (even with no visible edges); [_rebuildSim] reflows the
  /// layout so isolated nodes settle cleanly instead of leaving holes.
  GraphData _filteredData(GraphData data) {
    final nodes = [
      for (final n in data.nodes)
        if (_visibleNodeKinds.contains(n.kind)) n,
    ];
    final ids = {for (final n in nodes) n.id};
    final edges = [
      for (final e in data.edges)
        if (_visibleEdgeKinds.contains(e.kind) &&
            ids.contains(e.from) &&
            ids.contains(e.to))
          e,
    ];
    return GraphData(nodes: nodes, edges: edges);
  }

  Offset _screenToWorld(Offset s) => Offset(
        (s.dx - _size.width / 2 - _xf.pan.dx) / _xf.scale,
        (s.dy - _size.height / 2 - _xf.pan.dy) / _xf.scale,
      );

  String? _hitNode(Offset world) {
    final sim = _sim;
    if (sim == null) return null;
    final filtered = _filtered;
    String? best;
    double bestD = double.infinity;
    for (final n in filtered.nodes) {
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
        _handleTap(node);
      }
      _sim?.dragActive = false; // full forces resume → graph re-settles
      _sim?.unpin(dragged);
      _sim?.reheat(0.32);
      _ensureTicking();
      return;
    }
    if (!_moved && _selectedNode != null) {
      setState(() {
        _selectedNode = null;
      });
    }
  }

  void _handleTap(GraphNode node) {
    setState(() {
      _selectedNode = node;
    });
  }

  Future<void> _showFilters() async {
    final result = await showModalBottomSheet<_GraphFilterSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // size to content (was clipping in landscape)
      builder: (ctx) => _GraphFilterSheet(
        initialNodes: _visibleNodeKinds,
        initialEdges: _visibleEdgeKinds,
        accent: _accent,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _visibleNodeKinds
        ..clear()
        ..addAll(result.nodeKinds);
      _visibleEdgeKinds
        ..clear()
        ..addAll(result.edgeKinds);
      if (_selectedNode != null &&
          !_visibleNodeKinds.contains(_selectedNode!.kind)) {
        _selectedNode = null;
      }
      _rebuildSim(); // reflow the visible subset
    });
  }

  Future<void> _openNoteFromInspector(int noteId) async {
    ref.read(pendingNoteNavigationProvider.notifier).state = noteId;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openFolderFromInspector(int folderId) async {
    ref.read(pendingFolderNavigationProvider.notifier).state = folderId;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openCardFromInspector(int cardId) async {
    setState(() {
      _selectedNode = null;
    });
    widget.onOpenCard?.call(cardId);
  }

  Future<void> _markTaskDoneFromInspector(int taskId) async {
    await setTaskDone(ref, taskId, done: true);
    ref.invalidate(graphDataProvider(_global ? null : widget.space.id));
  }

  void _refresh(int? scope) => ref.invalidate(graphDataProvider(scope));

  @override
  Widget build(BuildContext context) {
    final scope = _global ? null : widget.space.id;
    // Real-time: re-assemble the graph the moment underlying data changes while
    // the tab is open (cards moved/added/done, columns, sources, spaces).
    if (_global) {
      // Global graph pulls cards/columns/sources from EVERY active space, so
      // listen to each space's reactive providers (the family ones are per-id —
      // there's no single global stream). The space list itself is watched so
      // adding/removing a space re-registers the set and refreshes.
      ref.listen(activeLabSpacesProvider, (_, _) => _refresh(scope));
      final spaces =
          ref.watch(activeLabSpacesProvider).valueOrNull ?? const <LabSpace>[];
      for (final s in spaces) {
        ref.listen(kanbanCardsBySpaceProvider(s.id), (_, _) => _refresh(scope));
        ref.listen(kanbanColumnsProvider(s.id), (_, _) => _refresh(scope));
        ref.listen(spaceContextSourcesProvider(s.id), (_, _) => _refresh(scope));
      }
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
            return _buildStack();
          },
        ),
      ),
    );
  }

  Widget _buildStack() {
    final filtered = _filtered;
    final full = _rendered;
    // The inspector resolves against the FULL graph (so it shows real totals and
    // stays open even when you navigate to a node whose kind is filtered off the
    // canvas). The canvas selection outline only applies when it's visible.
    GraphNode? selectedForPanel;
    String? selectedVisibleId;
    if (_selectedNode != null) {
      final id = _selectedNode!.id;
      for (final node in (full ?? filtered).nodes) {
        if (node.id == id) {
          selectedForPanel = node;
          break;
        }
      }
      if (filtered.nodes.any((n) => n.id == id)) selectedVisibleId = id;
    }
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
                        data: filtered,
                        sim: _sim!,
                        xf: _xf,
                        selectedNodeId: selectedVisibleId,
                        accent: _accent,
                        repaint: _repaint,
                      ),
                    ),
                  ),
                  if (_pulse != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        // Isolated layer: the 60fps pulse repaint stays here and
                        // doesn't re-rasterise the main graph painter behind it.
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _AlertPainter(
                              data: filtered,
                              sim: _sim!,
                              xf: _xf,
                              anim: _pulse!,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        if (filtered.isEmpty)
          (full == null || full.isEmpty)
              ? _emptyState()
              : _filteredEmptyState(),
        Positioned(top: 12, right: 12, child: _controls()),
        Positioned(
            left: 12,
            bottom: 12,
            child: _Legend(showAi: _showAi, accent: _accent)),
        if (selectedForPanel != null && full != null)
          GraphNodeInspector(
            node: selectedForPanel,
            data: full,
            accent: _accent,
            onClose: () => setState(() {
              _selectedNode = null;
            }),
            onOpenNote: _openNoteFromInspector,
            onOpenFolder: _openFolderFromInspector,
            onOpenCard: _openCardFromInspector,
            onMarkTaskDone: _markTaskDoneFromInspector,
            onSelectNode: (node) => setState(() {
              _selectedNode = node;
            }),
          ),
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

  // Shown when the graph HAS nodes but the active filter hides them all — so the
  // user knows it's the filter, not an empty space, and can clear it in one tap.
  Widget _filteredEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('NADA CON ESTE FILTRO',
                  style: yMono(
                      size: 12, weight: FontWeight.w700, tracking: 1.6)),
              const SizedBox(height: 12),
              _ToggleBtn(
                label: 'QUITAR FILTROS',
                active: true,
                activeColor: _accent,
                onTap: _resetFilters,
              ),
            ],
          ),
        ),
      );

  /// Re-frame the whole graph in the viewport (no way to do this otherwise once
  /// the user has panned/zoomed). Applies immediately — no need to reheat.
  void _recenter() {
    _fitToView();
    _repaint.value++;
  }

  void _resetFilters() {
    setState(() {
      _visibleNodeKinds
        ..clear()
        ..addAll(_kAllNodeKinds);
      _visibleEdgeKinds
        ..clear()
        ..addAll(_kAllEdgeKinds);
      _rebuildSim();
    });
  }

  Widget _controls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: yInk, width: yLineMid),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => setState(() => _global = false),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: !_global ? _accent : yCream,
                  child: Text('ESTE',
                      style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: !_global ? yCream : yInk)),
                ),
              ),
              Container(width: yLineMid, color: yInk),
              GestureDetector(
                onTap: () => setState(() => _global = true),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: _global ? _accent : yCream,
                  child: Text('TODO',
                      style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: _global ? yCream : yInk)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ToggleBtn(
          label: 'FILTRO',
          active: _hasCustomFilters,
          activeColor: yInk,
          icon: Icon(
            YuLiIcons.slidersHorizontal,
            size: 16,
            color: _hasCustomFilters ? yCream : yInk,
          ),
          onTap: _showFilters,
        ),
        const SizedBox(height: 8),
        _ToggleBtn(
          label: 'CENTRAR',
          active: false,
          activeColor: _accent,
          icon: const Icon(YuLiIcons.scan, size: 16, color: yInk),
          onTap: _recenter,
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
    required this.selectedNodeId,
    required this.accent,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GraphData data;
  final GraphSimulation sim;
  final _ViewTransform xf;
  final String? selectedNodeId;
  final Color accent;

  final Map<String, TextPainter> _labelCache = {};
  late final Set<String> _aiSourceNodeIds = data.aiSourceNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2 + xf.pan.dx, size.height / 2 + xf.pan.dy);
    canvas.scale(xf.scale);

    _grid(canvas, size);
    for (final e in data.edges) {
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
    final tp =
        _labelCache.putIfAbsent(n.id, () => _buildLabel(n, isAiSource: _isAiSourceNode(n.id)));
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
  }

  bool _isAiSourceNode(String id) => _aiSourceNodeIds.contains(id);

  TextPainter _buildLabel(GraphNode n, {required bool isAiSource}) {
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
      col = yMuted.withValues(alpha: 0.9);
    } else if (filled) {
      col = yCream;
    } else {
      col = yInk;
    }
    final size = switch (n.kind) {
      GraphNodeKind.space => 9.6,
      GraphNodeKind.folder => isAiSource ? 8.6 : 8.4,
      GraphNodeKind.card => 8.4,
      GraphNodeKind.note => isAiSource ? 7.0 : 6.8,
      GraphNodeKind.task => 6.5,
      GraphNodeKind.url => 8.5,
    };
    final weight = switch (n.kind) {
      GraphNodeKind.space || GraphNodeKind.folder || GraphNodeKind.card =>
        FontWeight.w700,
      GraphNodeKind.note => isAiSource ? FontWeight.w700 : FontWeight.w600,
      GraphNodeKind.task => FontWeight.w600,
      GraphNodeKind.url => FontWeight.w700,
    };
    final tracking = switch (n.kind) {
      GraphNodeKind.space => 0.15,
      GraphNodeKind.folder || GraphNodeKind.card => 0.1,
      _ => 0.0,
    };
    final lineHeight = switch (n.kind) {
      GraphNodeKind.space => 1.0,
      GraphNodeKind.folder || GraphNodeKind.card => 1.04,
      GraphNodeKind.note || GraphNodeKind.task => 1.08,
      GraphNodeKind.url => 1.0,
    };
    final maxWidth = graphNodeRadius(n.kind) *
        switch (n.kind) {
          GraphNodeKind.space => 1.38,
          GraphNodeKind.folder => isAiSource ? 1.7 : 1.62,
          GraphNodeKind.card => 1.62,
          GraphNodeKind.note => isAiSource ? 1.62 : 1.5,
          GraphNodeKind.task => 1.58,
          GraphNodeKind.url => 1.5,
        };
    return TextPainter(
      text: TextSpan(
          text: n.label,
          style: yMono(
                  size: size,
                  weight: weight,
                  tracking: tracking,
                  color: col)
              .copyWith(height: lineHeight)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
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
        _aiEdge(canvas, a, b);
    }
  }

  void _aiEdge(Canvas canvas, Offset a, Offset b) {
    final total = (b - a).distance;
    if (total < 0.5) return;
    final dir = (b - a) / total;
    final normal = Offset(-dir.dy, dir.dx);
    final lift = normal * 1.0;
    canvas.drawLine(
        a + lift,
        b + lift,
        Paint()
          ..color = yFlight.withValues(alpha: 0.14)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    _dashedLine(
        canvas,
        a + lift,
        b + lift,
        Paint()
          ..color = yFlight.withValues(alpha: 0.88)
          ..strokeWidth = 1.35
          ..strokeCap = StrokeCap.round,
        dash: 2.2,
        gap: 5.4);
    final steps = math.max(1, (total / 26).floor());
    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      final p = Offset(
        a.dx + (b.dx - a.dx) * t,
        a.dy + (b.dy - a.dy) * t,
      );
      canvas.drawCircle(
          p - lift * 0.35,
          1.0,
          Paint()..color = yFlight.withValues(alpha: 0.45));
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

  void _node(Canvas canvas, GraphNode n, Offset p) {
    final r = _r(n.kind);
    switch (n.kind) {
      case GraphNodeKind.space:
        _sun(canvas, p, r, n.color);
      case GraphNodeKind.folder:
        _folder(canvas, n, p, r, isAiSource: _isAiSourceNode(n.id));
      case GraphNodeKind.card:
        _slab(canvas, p, r, n.color);
        canvas.drawRect(
            Rect.fromLTWH(p.dx - r * 0.6, p.dy - r * 0.6, r * 1.2, r * 0.24),
            Paint()
              ..color = n.cardPriority == null
                  ? yCream.withValues(alpha: 0.9)
                  : labPriorityColor(n.cardPriority!));
      case GraphNodeKind.note:
        _note(canvas, n, p, r, isAiSource: _isAiSourceNode(n.id));
      case GraphNodeKind.task:
        _task(canvas, n, p, r);
      case GraphNodeKind.url:
        break; // URLs are not drawn
    }
    if (selectedNodeId == n.id) {
      _selectedNodeOutline(canvas, p, r);
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
          ..color = border ?? yBorderSoft);
  }

  void _sun(Canvas canvas, Offset p, double r, Color accent) {
    final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = accent.withValues(alpha: 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    _slab(canvas, p, r, accent, border: accent, bw: 3.5);
  }

  void _folder(Canvas canvas, GraphNode n, Offset p, double r,
      {required bool isAiSource}) {
    if (isAiSource) {
      final outer = Rect.fromCenter(
          center: p, width: r * 2 + 10, height: r * 2 + 10);
      canvas.drawRect(
          outer,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = n.color.withValues(alpha: 0.82));
    }
    _slab(canvas, p, r, n.color);
  }

  void _note(Canvas canvas, GraphNode n, Offset p, double r,
      {required bool isAiSource}) {
    if (isAiSource) {
      final outer = Rect.fromCenter(
          center: p, width: r * 2 + 8, height: r * 2 + 8);
      canvas.drawRect(
          outer,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = n.color.withValues(alpha: 0.8));
    }
    _slab(canvas, p, r, yCream, border: n.color, bw: 3);
    final glyph = switch (n.noteVariant) {
      NoteVariant.block || null => 'Tt',
      NoteVariant.notebook => '\u25A4',
      NoteVariant.whiteboard => '\u270E',
    };
    final glyphPainter = TextPainter(
      text: TextSpan(
          text: glyph,
          style: ySans(
            size: n.noteVariant == NoteVariant.block ? 7.5 : 8.5,
            weight: FontWeight.w700,
            color: n.color.withValues(alpha: 0.9),
            height: 1.0,
          )),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    glyphPainter.paint(
        canvas, Offset(p.dx - r * 0.68, p.dy - r * 0.82));
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
        final fill = yMuted.withValues(alpha: 0.16);
        final border = yMuted.withValues(alpha: 0.42);
        canvas.drawRect(rect, Paint()..color = fill);
        canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4
              ..color = border);
      case TaskGraphState.urgente:
        canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = _urgentStroke.withValues(alpha: 0.8)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        _slab(canvas, p, r, n.color, border: _urgentStroke, bw: 3.5);
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
      final cornerColor = switch (n.taskState) {
        TaskGraphState.ayer => yMuted.withValues(alpha: 0.62),
        _ => yFight,
      };
      canvas.drawPath(path, Paint()..color = cornerColor);
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

  void _selectedNodeOutline(Canvas canvas, Offset p, double r) {
    final outer = Rect.fromCenter(center: p, width: r * 2 + 12, height: r * 2 + 12);
    canvas.drawRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = accent.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawRect(
        outer,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = accent.withValues(alpha: 0.92));
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.selectedNodeId != selectedNodeId ||
      !identical(old.data, data);
}

class _AlertPainter extends CustomPainter {
  _AlertPainter({
    required this.data,
    required this.sim,
    required this.xf,
    required this.anim,
  }) : super(repaint: anim);

  final GraphData data;
  final GraphSimulation sim;
  final _ViewTransform xf;
  final Animation<double> anim;
  late final Set<String> _aiSourceNodeIds = data.aiSourceNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    // Pulses the sun, AI-source nodes and urgent tasks. Perpetual but cheap: a
    // handful of stroke rects, and the layer lives in its own RepaintBoundary so
    // these 60fps repaints DON'T re-rasterise the main graph. (Balance kept on
    // purpose — the user likes the pulse and it barely costs anything.)
    final phase = anim.value <= 0.5 ? anim.value * 2 : (1 - anim.value) * 2;
    final pulse = Curves.easeInOut.transform(phase);
    final aiRaw = (anim.value + 0.18) % 1.0;
    final aiPhase = aiRaw <= 0.5 ? aiRaw * 2 : (1 - aiRaw) * 2;
    final aiPulse = Curves.easeInOutCubic.transform(aiPhase);
    canvas.save();
    canvas.translate(size.width / 2 + xf.pan.dx, size.height / 2 + xf.pan.dy);
    canvas.scale(xf.scale);
    for (final n in data.nodes) {
      final isUrgent = n.taskState == TaskGraphState.urgente;
      final isSun = n.kind == GraphNodeKind.space;
      final isAiSource = _aiSourceNodeIds.contains(n.id);
      if (!isUrgent && !isSun && !isAiSource) continue;
      final p = sim.posOf(n.id);
      if (p == null) continue;
      final pulseValue = isAiSource ? aiPulse : pulse;
      final base = graphNodeRadius(n.kind) +
          switch (n.kind) {
            GraphNodeKind.space => 6.0,
            GraphNodeKind.folder => 8.0,
            GraphNodeKind.note => 7.0,
            _ => 6.0,
          };
      final scaleBoost = isAiSource
          ? (n.kind == GraphNodeKind.folder ? 0.055 : 0.07)
          : 0.10;
      final half = base * (1 + scaleBoost * pulseValue);
      canvas.drawRect(
          Rect.fromCenter(center: p, width: half * 2, height: half * 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isAiSource
                ? (n.kind == GraphNodeKind.folder ? 1.6 : 1.4)
                : 1.8
            ..color = (isSun || isAiSource ? n.color : _urgentStroke)
                .withValues(
                    alpha: isAiSource
                        ? (n.kind == GraphNodeKind.folder
                            ? 0.18 + 0.22 * pulseValue
                            : 0.22 + 0.28 * pulseValue)
                        : 0.35 + 0.55 * pulseValue));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AlertPainter old) => true;
}

// ─── Overlay chrome ──────────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final Widget? icon;

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
        child: icon ??
            Text(label,
                style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: active ? yCream : yInk)),
      ),
    );
  }
}

class _GraphFilterSelection {
  const _GraphFilterSelection({
    required this.nodeKinds,
    required this.edgeKinds,
  });

  final Set<GraphNodeKind> nodeKinds;
  final Set<GraphEdgeKind> edgeKinds;
}

class _GraphFilterSheet extends StatefulWidget {
  const _GraphFilterSheet({
    required this.initialNodes,
    required this.initialEdges,
    required this.accent,
  });

  final Set<GraphNodeKind> initialNodes;
  final Set<GraphEdgeKind> initialEdges;
  final Color accent;

  @override
  State<_GraphFilterSheet> createState() => _GraphFilterSheetState();
}

class _GraphFilterSheetState extends State<_GraphFilterSheet> {
  late final Set<GraphNodeKind> _nodes = {...widget.initialNodes};
  late final Set<GraphEdgeKind> _edges = {...widget.initialEdges};

  void _toggleNode(GraphNodeKind kind) {
    setState(() {
      if (_nodes.contains(kind)) {
        if (_nodes.length > 1) _nodes.remove(kind);
      } else {
        _nodes.add(kind);
      }
    });
  }

  void _toggleEdge(GraphEdgeKind kind) {
    setState(() {
      if (_edges.contains(kind)) {
        if (_edges.length > 1) _edges.remove(kind);
      } else {
        _edges.add(kind);
      }
    });
  }

  int get _hiddenCount =>
      (_kAllNodeKinds.length - _nodes.length) +
      (_kAllEdgeKinds.length - _edges.length);

  @override
  Widget build(BuildContext context) {
    final hidden = _hiddenCount;
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: accent tile + title + live hidden-count badge.
            Row(
              children: [
                Container(width: 16, height: 16, color: widget.accent),
                const SizedBox(width: 10),
                Text('> FILTRO',
                    style: yMono(
                        size: 12, weight: FontWeight.w700, tracking: 1.8)),
                const Spacer(),
                Text(
                  hidden == 0
                      ? 'TODO VISIBLE'
                      : '$hidden OCULTO${hidden == 1 ? '' : 'S'}',
                  style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: hidden == 0 ? yMuted : yFight),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('> NODOS'),
            const SizedBox(height: 8),
            _group([
              _nodeRow(GraphNodeKind.space, 'ESPACIO'),
              _nodeRow(GraphNodeKind.card, 'TARJETA'),
              _nodeRow(GraphNodeKind.folder, 'CARPETA'),
              _nodeRow(GraphNodeKind.note, 'NOTA'),
              _nodeRow(GraphNodeKind.task, 'TAREA', last: true),
            ]),
            const SizedBox(height: 16),
            _label('> CONEXIONES'),
            const SizedBox(height: 8),
            _group([
              _edgeRow(GraphEdgeKind.structure, 'ESTRUCTURA'),
              _edgeRow(GraphEdgeKind.bridge, 'PUENTE TAREA'),
              _edgeRow(GraphEdgeKind.ai, 'CONTEXTO IA', last: true),
            ]),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _FilterActionBtn(
                    label: 'TODO',
                    fill: false,
                    accent: widget.accent,
                    onTap: () => setState(() {
                      _nodes
                        ..clear()
                        ..addAll(_kAllNodeKinds);
                      _edges
                        ..clear()
                        ..addAll(_kAllEdgeKinds);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilterActionBtn(
                    label: 'APLICAR',
                    fill: true,
                    accent: widget.accent,
                    onTap: () => Navigator.of(context).pop(
                      _GraphFilterSelection(
                        nodeKinds: {..._nodes},
                        edgeKinds: {..._edges},
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: yMono(
          size: 10, weight: FontWeight.w700, tracking: 1.6, color: yMuted));

  Widget _group(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Column(children: rows),
      );

  Widget _nodeRow(GraphNodeKind kind, String label, {bool last = false}) =>
      _FilterToggleRow(
        swatch: _nodeSwatch(kind),
        label: label,
        active: _nodes.contains(kind),
        last: last,
        accent: widget.accent,
        onTap: () => _toggleNode(kind),
      );

  Widget _edgeRow(GraphEdgeKind kind, String label, {bool last = false}) =>
      _FilterToggleRow(
        swatch: _edgeSwatch(kind),
        label: label,
        active: _edges.contains(kind),
        last: last,
        accent: widget.accent,
        onTap: () => _toggleEdge(kind),
      );

  /// Mini node swatch mirroring how the painter draws each kind, so the row
  /// reads as the thing it toggles (not a generic colored pill).
  Widget _nodeSwatch(GraphNodeKind kind) {
    switch (kind) {
      case GraphNodeKind.space:
        return Container(width: 15, height: 15, color: widget.accent);
      case GraphNodeKind.card:
        return SizedBox(
          width: 15,
          height: 15,
          child: Stack(children: [
            Container(width: 15, height: 15, color: widget.accent),
            Positioned(
              left: 0,
              right: 0,
              top: 2,
              child:
                  Container(height: 3, color: yCream.withValues(alpha: 0.9)),
            ),
          ]),
        );
      case GraphNodeKind.folder:
        return Container(width: 15, height: 15, color: widget.accent);
      case GraphNodeKind.note:
        return Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: widget.accent, width: 2)),
        );
      case GraphNodeKind.task:
        return SizedBox(
          width: 15,
          height: 15,
          child: CustomPaint(
              painter: _SwatchPainter(_SwatchKind.task, widget.accent)),
        );
      case GraphNodeKind.url:
        return const SizedBox(width: 15, height: 15);
    }
  }

  Widget _edgeSwatch(GraphEdgeKind kind) {
    final (sw, color) = switch (kind) {
      GraphEdgeKind.structure => (_SwatchKind.solid, yInk),
      GraphEdgeKind.bridge => (_SwatchKind.dashed, yInk),
      GraphEdgeKind.ai => (_SwatchKind.dashed, yFlight),
    };
    return SizedBox(
      width: 18,
      height: 10,
      child: CustomPaint(painter: _SwatchPainter(sw, color)),
    );
  }
}

class _FilterToggleRow extends StatelessWidget {
  const _FilterToggleRow({
    required this.swatch,
    required this.label,
    required this.active,
    required this.onTap,
    required this.accent,
    this.last = false,
  });

  final Widget swatch;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color accent;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: yCream,
          border: last
              ? null
              : const Border(
                  bottom: BorderSide(color: yBorderSoft, width: yLineThin)),
        ),
        child: Row(
          children: [
            SizedBox(width: 18, child: Center(child: swatch)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: active ? yInk : yMuted,
                ),
              ),
            ),
            // Brutalist checkbox: filled accent + crema check when on, hollow off.
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? accent : yCream,
                border: Border.all(
                  color: active ? accent : yBorderStrong,
                  width: yLineThin,
                ),
              ),
              child: active
                  ? const Icon(YuLiIcons.check, size: 14, color: yCream)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterActionBtn extends StatelessWidget {
  const _FilterActionBtn({
    required this.label,
    required this.fill,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool fill;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ? accent : yCream,
          border: Border.all(color: fill ? accent : yInk, width: yLineMid),
          boxShadow: fill
              ? const [BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0)]
              : null,
        ),
        child: Text(
          label,
          style: yMono(
            size: 12,
            weight: FontWeight.w700,
            tracking: 1.4,
            color: fill ? yCream : yInk,
          ),
        ),
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
    final yesterdayFill = yMuted.withValues(alpha: 0.16);
    final yesterdayBorder = yMuted.withValues(alpha: 0.42);
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
        _row(_box(fill: accent, border: _urgentStroke, bw: 2), 'Tarea urgente'),
        _row(_box(fill: yesterdayFill, border: yesterdayBorder), 'Tarea de ayer'),
        _row(
            SizedBox(
                width: 13,
                height: 13,
                child: CustomPaint(painter: _SwatchPainter(_SwatchKind.ghost, accent))),
            'Tarea fantasma'),
        _row(
            SizedBox(
                width: 13,
                height: 13,
                child: CustomPaint(
                    painter: _SwatchPainter(_SwatchKind.contextNode, accent))),
            'Nodo de contexto IA'),
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
                  painter: _SwatchPainter(_SwatchKind.ai, yFlight)),
              'Conexión de contexto'),
      ]),
    );
  }
}

enum _SwatchKind { task, ghost, solid, dashed, ai, contextNode }

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
      case _SwatchKind.ai:
        final a = Offset(0, size.height / 2 - 0.5);
        final b = Offset(size.width, size.height / 2 - 0.5);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = color.withValues(alpha: 0.16)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
        _dash(canvas, a, b, dash: 2, gap: 4.8);
        for (final dx in [3.0, 8.0, 13.0]) {
          if (dx >= size.width) break;
          canvas.drawCircle(
              Offset(dx, size.height / 2 + 1.2),
              0.9,
              Paint()..color = color.withValues(alpha: 0.5));
        }
      case _SwatchKind.contextNode:
        final outer = Rect.fromLTWH(0, 0, size.width, size.height);
        final inner = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
        canvas.drawRect(
            outer,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = color.withValues(alpha: 0.82));
        canvas.drawRect(
            inner,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = color);
    }
  }

  void _dash(Canvas canvas, Offset a, Offset b,
      {double dash = 3, double gap = 5}) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final total = (b - a).distance;
    final dir = total == 0 ? Offset.zero : (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * (d + dash < total ? d + dash : total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.kind != kind || old.color != color;
}
