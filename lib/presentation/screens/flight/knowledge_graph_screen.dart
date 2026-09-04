import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/graph.dart';
import '../../../domain/models/note.dart';
import '../../providers/flight_workspace_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../lab/graph_simulation.dart';
import 'flight_workspace_route.dart';
import 'knowledge_graph_assembler.dart';

class KnowledgeGraphScreen extends ConsumerStatefulWidget {
  final int? folderId;
  final String scopeLabel;
  final Color accent;

  const KnowledgeGraphScreen({
    super.key,
    this.folderId,
    this.scopeLabel = 'Todo Flight',
    this.accent = yFlight,
  });

  @override
  ConsumerState<KnowledgeGraphScreen> createState() =>
      _KnowledgeGraphScreenState();
}

class _KnowledgeGraphScreenState extends ConsumerState<KnowledgeGraphScreen>
    with SingleTickerProviderStateMixin {
  final _transform = _KnowledgeViewTransform();
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  KnowledgeGraphSnapshot? _snapshot;
  GraphData _data = GraphData.empty;
  GraphSimulation? _simulation;
  Size _viewport = Size.zero;
  String? _selectedId;
  String? _dragId;
  bool _moved = false;
  bool _includeIslands = false;
  bool _needsFit = false;
  double _scaleStart = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _tick(Duration _) {
    final simulation = _simulation;
    if (simulation == null) return;
    final hot = simulation.step();
    if (!hot && _needsFit && _dragId == null) {
      _fitToView();
      _needsFit = false;
    }
    _repaint.value++;
    if (!hot && _dragId == null) _ticker.stop();
  }

  void _ensureTicking() {
    if (!_ticker.isTicking) _ticker.start();
  }

  void _applySnapshot(KnowledgeGraphSnapshot snapshot) {
    if (identical(snapshot, _snapshot)) return;
    _snapshot = snapshot;
    _rebuildSimulation(reframe: true);
  }

  void _rebuildSimulation({bool reframe = false}) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final previous = _simulation?.positions;
    _data = snapshot.graph(includeIslands: _includeIslands);
    if (_selectedId != null &&
        !_data.nodes.any((node) => node.id == _selectedId)) {
      _selectedId = null;
    }
    _simulation = GraphSimulation(
      _data,
      previous: previous,
      layout: GraphLayoutMode.knowledge,
    );
    _dragId = null;
    if (reframe || previous == null) _needsFit = true;
    _ticker.stop();
    if (_data.nodes.length > 1) {
      _ensureTicking();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitToView();
        _repaint.value++;
      });
    }
  }

  void _fitToView() {
    final simulation = _simulation;
    if (simulation == null || _viewport == Size.zero || _data.nodes.isEmpty) {
      return;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final node in _data.nodes) {
      final position = simulation.posOf(node.id);
      if (position == null) continue;
      const radius = 54.0;
      minX = math.min(minX, position.dx - radius);
      minY = math.min(minY, position.dy - radius);
      maxX = math.max(maxX, position.dx + radius);
      maxY = math.max(maxY, position.dy + radius);
    }
    if (minX > maxX) return;
    final graphWidth = math.max(maxX - minX, 1.0);
    final graphHeight = math.max(maxY - minY, 1.0);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final horizontalRoom = _selectedId == null ? 0.88 : 0.62;
    final scale = math
        .min(
          _viewport.width * horizontalRoom / graphWidth,
          _viewport.height * 0.82 / graphHeight,
        )
        .clamp(0.3, 1.65);
    _transform
      ..scale = scale
      ..pan = -center * scale;
  }

  Offset _screenToWorld(Offset point) => Offset(
    (point.dx - _viewport.width / 2 - _transform.pan.dx) / _transform.scale,
    (point.dy - _viewport.height / 2 - _transform.pan.dy) / _transform.scale,
  );

  String? _hitNode(Offset world) {
    final simulation = _simulation;
    if (simulation == null) return null;
    String? closest;
    var distance = double.infinity;
    for (final node in _data.nodes) {
      final position = simulation.posOf(node.id);
      if (position == null) continue;
      final candidate = (position - world).distance;
      if (candidate <= 30 && candidate < distance) {
        closest = node.id;
        distance = candidate;
      }
    }
    return closest;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _moved = false;
    _scaleStart = _transform.scale;
    final simulation = _simulation;
    if (simulation == null) return;
    final world = _screenToWorld(details.localFocalPoint);
    _dragId = _hitNode(world);
    if (_dragId == null) return;
    _needsFit = false;
    simulation
      ..dragActive = true
      ..pin(_dragId!, world)
      ..reheat(0.5);
    _ensureTicking();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale != 1 || details.focalPointDelta.distance > 0.5) {
      _moved = true;
    }
    if (_dragId != null && details.pointerCount == 1) {
      _simulation
        ?..movePinned(_dragId!, _screenToWorld(details.localFocalPoint))
        ..reheat(0.4);
      _ensureTicking();
      return;
    }
    _needsFit = false;
    _transform.pan += details.focalPointDelta;
    if (details.scale != 1) {
      final focal = details.localFocalPoint;
      final worldFocal = _screenToWorld(focal);
      _transform.scale = (_scaleStart * details.scale).clamp(0.3, 4.0);
      _transform.pan =
          focal -
          Offset(_viewport.width / 2, _viewport.height / 2) -
          worldFocal * _transform.scale;
    }
    _repaint.value++;
  }

  void _onScaleEnd(ScaleEndDetails _) {
    final dragged = _dragId;
    _dragId = null;
    if (dragged != null) {
      if (!_moved) setState(() => _selectedId = dragged);
      _simulation
        ?..dragActive = false
        ..unpin(dragged)
        ..reheat(0.3);
      _ensureTicking();
      return;
    }
    if (!_moved && _selectedId != null) {
      setState(() => _selectedId = null);
    }
  }

  void _centerNode(String nodeId) {
    final position = _simulation?.posOf(nodeId);
    if (position == null) return;
    setState(() => _selectedId = nodeId);
    _transform.pan = -position * _transform.scale;
    _repaint.value++;
  }

  Future<void> _search() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      builder:
          (_) =>
              _KnowledgeSearchSheet(nodes: _data.nodes, accent: widget.accent),
    );
    if (selected != null && mounted) _centerNode(selected);
  }

  Future<void> _openSelected() async {
    final snapshot = _snapshot;
    final node = _selectedNode;
    if (snapshot == null || node?.refId == null) return;
    final note = snapshot.notesById[node!.refId!];
    if (note == null) return;
    final folder = snapshot.foldersById[note.folderId];
    if (folder == null) return;
    await openFlightWorkspaceTarget(
      context,
      ref,
      FlightWorkspaceTarget(
        noteId: note.id,
        folderId: note.folderId,
        kind: note.kind,
        label: note.displayTitle,
        folderLabel: folder.name,
      ),
    );
  }

  GraphNode? get _selectedNode {
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    return _data.nodes.where((node) => node.id == selectedId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(knowledgeGraphProvider(widget.folderId));
    return Scaffold(
      backgroundColor: yCream,
      body: SafeArea(
        child: Column(
          children: [
            _KnowledgeHeader(
              accent: widget.accent,
              scopeLabel: widget.scopeLabel,
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: graph.when(
                loading:
                    () => Center(
                      child: CircularProgressIndicator(color: widget.accent),
                    ),
                error:
                    (_, _) => Center(
                      child: Text(
                        'NO SE PUDO ARMAR EL MAPA',
                        style: yMono(size: 12, color: yMuted),
                      ),
                    ),
                data: (snapshot) {
                  _applySnapshot(snapshot);
                  return _body(snapshot);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(KnowledgeGraphSnapshot snapshot) {
    final selected = _selectedNode;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (_, constraints) {
                _viewport = constraints.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: CustomPaint(
                    painter: _KnowledgeGraphPainter(
                      data: _data,
                      snapshot: snapshot,
                      simulation: _simulation!,
                      transform: _transform,
                      selectedId: _selectedId,
                      repaint: _repaint,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_data.isEmpty) _emptyState(),
          Positioned(
            top: 12,
            right: selected != null && wide ? 346 : 12,
            child: _controls(snapshot),
          ),
          Positioned(left: 12, bottom: 12, child: _legend(snapshot)),
          if (selected != null)
            _KnowledgeInspector(
              node: selected,
              snapshot: snapshot,
              accent: selected.color,
              onClose: () => setState(() => _selectedId = null),
              onOpen: _openSelected,
              onSelect:
                  (id) => _centerNode(
                    GraphNode.idFor(GraphNodeKind.note, refId: id),
                  ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(YuLiIcons.gitGraph, size: 38, color: widget.accent),
        const SizedBox(height: 14),
        Text(
          _includeIslands ? 'AÚN NO HAY DOCUMENTOS' : 'AÚN SIN CONEXIONES',
          style: yMono(
            size: 12,
            weight: FontWeight.w700,
            tracking: 1.5,
            color: yInk,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _includeIslands
              ? 'CREA UNA NOTA PARA EMPEZAR EL MAPA.'
              : 'ESCRIBE [[OTRA NOTA]] PARA TEJER EL MAPA.',
          style: yBody(size: 12, color: yMuted),
        ),
      ],
    ),
  );

  Widget _controls(KnowledgeGraphSnapshot snapshot) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _KnowledgeControl(
        icon: YuLiIcons.search,
        label: 'BUSCAR',
        accent: widget.accent,
        onTap: _search,
      ),
      const SizedBox(height: 6),
      _KnowledgeControl(
        icon: YuLiIcons.scan,
        label: 'CENTRAR',
        accent: widget.accent,
        onTap: () {
          _fitToView();
          _repaint.value++;
        },
      ),
      const SizedBox(height: 6),
      _KnowledgeControl(
        icon: YuLiIcons.eye,
        label: 'ISLAS',
        accent: widget.accent,
        active: _includeIslands,
        onTap: () {
          setState(() {
            _includeIslands = !_includeIslands;
            _rebuildSimulation(reframe: true);
          });
        },
      ),
      const SizedBox(height: 6),
      _KnowledgeControl(
        icon: YuLiIcons.refresh,
        label: 'ACTUALIZAR',
        accent: widget.accent,
        onTap: () => ref.invalidate(knowledgeGraphProvider(widget.folderId)),
      ),
    ],
  );

  Widget _legend(KnowledgeGraphSnapshot snapshot) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: yCream.withValues(alpha: 0.94),
      border: Border.all(color: yBorderStrong, width: yLineThin),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 2, color: yInk.withValues(alpha: 0.5)),
        const SizedBox(width: 7),
        Text(
          '${snapshot.mentions.fold<int>(0, (total, mention) => total + mention.count)} MENCIONES · ${_data.nodes.length} NODOS'
          '${snapshot.wasLimited ? ' · LÍMITE ${snapshot.scannedNotes}' : ''}',
          style: yMono(
            size: 9,
            weight: FontWeight.w700,
            tracking: 1,
            color: yInk,
          ),
        ),
      ],
    ),
  );
}

class _KnowledgeHeader extends StatelessWidget {
  final Color accent;
  final String scopeLabel;
  final VoidCallback onBack;

  const _KnowledgeHeader({
    required this.accent,
    required this.scopeLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: yCream2,
      border: const Border(
        bottom: BorderSide(color: yBorderStrong, width: yLineMid),
      ),
    ),
    child: Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child: const Icon(YuLiIcons.arrowLeft, size: 18, color: yInk),
          ),
        ),
        const SizedBox(width: 14),
        Container(width: 6, height: 40, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MAPA DE CONOCIMIENTO',
                style: ySans(size: 24, weight: FontWeight.w800, color: yInk),
              ),
              Text(
                'MENCIONES [[ ]] · ${scopeLabel.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yMono(size: 9, tracking: 1.3, color: yMuted),
              ),
            ],
          ),
        ),
        Icon(YuLiIcons.gitGraph, size: 28, color: accent),
      ],
    ),
  );
}

class _KnowledgeControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool active;
  final VoidCallback onTap;

  const _KnowledgeControl({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? accent : yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: active ? yCream : yInk),
          const SizedBox(width: 6),
          Text(
            label,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1,
              color: active ? yCream : yInk,
            ),
          ),
        ],
      ),
    ),
  );
}

class _KnowledgeInspector extends StatelessWidget {
  final GraphNode node;
  final KnowledgeGraphSnapshot snapshot;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final ValueChanged<int> onSelect;

  const _KnowledgeInspector({
    required this.node,
    required this.snapshot,
    required this.accent,
    required this.onClose,
    required this.onOpen,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final note = snapshot.notesById[node.refId];
    final folder = note == null ? null : snapshot.foldersById[note.folderId];
    final outgoing =
        note == null ? const <KnowledgeMention>[] : snapshot.outgoing(note.id);
    final incoming =
        note == null ? const <KnowledgeMention>[] : snapshot.incoming(note.id);
    final width = MediaQuery.sizeOf(context).width;
    final panel = Container(
      width: width >= 720 ? 334 : null,
      height: width >= 720 ? double.infinity : 280,
      decoration: BoxDecoration(
        color: yCream,
        border: Border(
          left:
              width >= 720
                  ? const BorderSide(color: yBorderStrong, width: yLineMid)
                  : BorderSide.none,
          top:
              width < 720
                  ? const BorderSide(color: yBorderStrong, width: yLineMid)
                  : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            color: accent,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    node.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                      size: 20,
                      weight: FontWeight.w800,
                      color: yCream,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yCream,
                      border: Border.all(
                        color: yBorderStrong,
                        width: yLineThin,
                      ),
                    ),
                    child: const Icon(YuLiIcons.close, size: 16, color: yInk),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '${_noteKindLabel(note?.kind)} · ${(folder?.name ?? 'SIN CARPETA').toUpperCase()}',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: yMuted,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                _connectionSection('MENCIONA', outgoing, source: false),
                const SizedBox(height: 14),
                _connectionSection('MENCIONADA POR', incoming, source: true),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
              ),
              child: Text(
                'ABRIR EN FLIGHT',
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: yCream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Positioned(
      right: 0,
      top: width >= 720 ? 0 : null,
      bottom: 0,
      child: panel,
    );
  }

  Widget _connectionSection(
    String title,
    List<KnowledgeMention> mentions, {
    required bool source,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$title · ${mentions.length}',
        style: yMono(
          size: 10,
          weight: FontWeight.w700,
          tracking: 1.2,
          color: yInk,
        ),
      ),
      const SizedBox(height: 6),
      if (mentions.isEmpty)
        Text('NINGUNA', style: yBody(size: 11, color: yMuted))
      else
        for (final mention in mentions)
          _ConnectionRow(
            note:
                snapshot.notesById[source
                    ? mention.sourceNoteId
                    : mention.targetNoteId]!,
            count: mention.count,
            onTap:
                () => onSelect(
                  source ? mention.sourceNoteId : mention.targetNoteId,
                ),
          ),
    ],
  );
}

class _ConnectionRow extends StatelessWidget {
  final Note note;
  final int count;
  final VoidCallback onTap;

  const _ConnectionRow({
    required this.note,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: yBorderSoft, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              note.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: yBody(size: 12, weight: FontWeight.w600, color: yInk),
            ),
          ),
          if (count > 1)
            Text(
              '×$count',
              style: yMono(size: 9, weight: FontWeight.w700, color: yMuted),
            ),
          const SizedBox(width: 6),
          const Icon(YuLiIcons.arrowRight, size: 13, color: yInk),
        ],
      ),
    ),
  );
}

class _KnowledgeSearchSheet extends StatefulWidget {
  final List<GraphNode> nodes;
  final Color accent;

  const _KnowledgeSearchSheet({required this.nodes, required this.accent});

  @override
  State<_KnowledgeSearchSheet> createState() => _KnowledgeSearchSheetState();
}

class _KnowledgeSearchSheetState extends State<_KnowledgeSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final matches =
        widget.nodes
            .where(
              (node) =>
                  query.isEmpty || node.label.toLowerCase().contains(query),
            )
            .take(12)
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          height: 390,
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
          ),
          child: Column(
            children: [
              Container(
                color: widget.accent,
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: yBody(size: 14, weight: FontWeight.w600, color: yInk),
                  decoration: InputDecoration(
                    hintText: 'BUSCAR DOCUMENTO',
                    hintStyle: yMono(size: 10, color: yMuted, tracking: 1.2),
                    filled: true,
                    fillColor: yCream,
                    prefixIcon: const Icon(
                      YuLiIcons.search,
                      size: 17,
                      color: yInk,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: yBorderStrong,
                        width: yLineMid,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: widget.accent,
                        width: yLineMid,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: matches.length,
                  separatorBuilder:
                      (_, _) => const Divider(height: 1, color: yBorderSoft),
                  itemBuilder: (_, index) {
                    final node = matches[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context, node.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(width: 8, height: 32, color: node.color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                node.label,
                                style: yBody(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: yInk,
                                ),
                              ),
                            ),
                            const Icon(
                              YuLiIcons.arrowRight,
                              size: 15,
                              color: yInk,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KnowledgeViewTransform {
  Offset pan = Offset.zero;
  double scale = 1;
}

class _KnowledgeGraphPainter extends CustomPainter {
  final GraphData data;
  final KnowledgeGraphSnapshot snapshot;
  final GraphSimulation simulation;
  final _KnowledgeViewTransform transform;
  final String? selectedId;

  _KnowledgeGraphPainter({
    required this.data,
    required this.snapshot,
    required this.simulation,
    required this.transform,
    required this.selectedId,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(
      size.width / 2 + transform.pan.dx,
      size.height / 2 + transform.pan.dy,
    );
    canvas.scale(transform.scale);
    _grid(canvas, size);
    final visibleIds = data.nodes.map((node) => node.id).toSet();
    for (final mention in snapshot.mentions) {
      final from = GraphNode.idFor(
        GraphNodeKind.note,
        refId: mention.sourceNoteId,
      );
      final to = GraphNode.idFor(
        GraphNodeKind.note,
        refId: mention.targetNoteId,
      );
      if (!visibleIds.contains(from) || !visibleIds.contains(to)) continue;
      final a = simulation.posOf(from);
      final b = simulation.posOf(to);
      if (a == null || b == null) continue;
      _mention(canvas, a, b, from, to, mention.count);
    }
    for (final node in data.nodes) {
      final position = simulation.posOf(node.id);
      if (position != null) _node(canvas, node, position);
    }
    canvas.restore();
  }

  void _grid(Canvas canvas, Size size) {
    const step = 36.0;
    if (step * transform.scale < 9) return;
    final topLeft = _screenToWorld(Offset.zero, size);
    final bottomRight = _screenToWorld(Offset(size.width, size.height), size);
    final paint = Paint()..color = yInk.withValues(alpha: 0.06);
    final startX = (topLeft.dx / step).floor() * step;
    final startY = (topLeft.dy / step).floor() * step;
    for (var x = startX; x < bottomRight.dx; x += step) {
      for (var y = startY; y < bottomRight.dy; y += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  Offset _screenToWorld(Offset point, Size size) => Offset(
    (point.dx - size.width / 2 - transform.pan.dx) / transform.scale,
    (point.dy - size.height / 2 - transform.pan.dy) / transform.scale,
  );

  void _mention(
    Canvas canvas,
    Offset from,
    Offset to,
    String fromId,
    String toId,
    int count,
  ) {
    final delta = to - from;
    final distance = delta.distance;
    if (distance < 1) return;
    final direction = delta / distance;
    final highlighted = selectedId == fromId || selectedId == toId;
    final source = data.nodes.where((node) => node.id == fromId).firstOrNull;
    final color = highlighted ? source?.color ?? yFlight : yInk;
    final paint =
        Paint()
          ..color = color.withValues(alpha: highlighted ? 0.78 : 0.2)
          ..strokeWidth = (1.2 + math.log(math.max(count, 1)) * 0.45).clamp(
            1.2,
            3.0,
          );
    final start = from + direction * 22;
    final end = to - direction * 24;
    canvas.drawLine(start, end, paint);
    final normal = Offset(-direction.dy, direction.dx);
    final arrow =
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            end.dx - direction.dx * 7 + normal.dx * 4,
            end.dy - direction.dy * 7 + normal.dy * 4,
          )
          ..lineTo(
            end.dx - direction.dx * 7 - normal.dx * 4,
            end.dy - direction.dy * 7 - normal.dy * 4,
          )
          ..close();
    canvas.drawPath(arrow, paint);
  }

  void _node(Canvas canvas, GraphNode node, Offset position) {
    final connected = selectedId == null || _connectedToSelection(node.id);
    final opacity = connected ? 1.0 : 0.24;
    canvas.save();
    const radius = 18.0;
    final rect = Rect.fromCenter(
      center: position,
      width: radius * 2,
      height: radius * 2,
    );
    canvas.drawRect(
      rect.shift(const Offset(3, 3)),
      Paint()..color = yInk.withValues(alpha: 0.72 * opacity),
    );
    canvas.drawRect(
      rect,
      Paint()..color = node.color.withValues(alpha: opacity),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = yBorderStrong.withValues(alpha: opacity),
    );
    switch (node.noteVariant) {
      case NoteVariant.block:
        final fold =
            Path()
              ..moveTo(rect.right - 9, rect.top)
              ..lineTo(rect.right, rect.top + 9)
              ..lineTo(rect.right - 9, rect.top + 9)
              ..close();
        canvas.drawPath(
          fold,
          Paint()..color = yCream.withValues(alpha: opacity),
        );
      case NoteVariant.whiteboard:
        final gridPaint =
            Paint()
              ..color = yCream.withValues(alpha: 0.62 * opacity)
              ..strokeWidth = 1;
        canvas.drawLine(
          Offset(rect.left + 12, rect.top + 4),
          Offset(rect.left + 12, rect.bottom - 4),
          gridPaint,
        );
        canvas.drawLine(
          Offset(rect.left + 4, rect.top + 12),
          Offset(rect.right - 4, rect.top + 12),
          gridPaint,
        );
        canvas.drawLine(
          Offset(rect.left + 4, rect.top + 24),
          Offset(rect.right - 4, rect.top + 24),
          gridPaint,
        );
      case NoteVariant.notebook:
        final ring = Paint()..color = yCream.withValues(alpha: opacity);
        for (var offset = -10.0; offset <= 10; offset += 10) {
          canvas.drawRect(
            Rect.fromLTWH(rect.left + 3, position.dy + offset - 1, 8, 2),
            ring,
          );
        }
      case null:
        break;
    }
    if (selectedId == node.id) {
      canvas.drawRect(
        rect.inflate(6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = node.color,
      );
    }
    final label = TextPainter(
      text: TextSpan(
        text: node.label,
        style: yMono(
          size: 8,
          weight: FontWeight.w700,
          color: yInk.withValues(alpha: opacity),
        ).copyWith(height: 1.05),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 92);
    label.paint(canvas, Offset(position.dx - label.width / 2, rect.bottom + 7));
    canvas.restore();
  }

  bool _connectedToSelection(String nodeId) {
    if (nodeId == selectedId) return true;
    return data.edges.any(
      (edge) =>
          (edge.from == selectedId && edge.to == nodeId) ||
          (edge.to == selectedId && edge.from == nodeId),
    );
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.snapshot != snapshot ||
      oldDelegate.selectedId != selectedId;
}

String _noteKindLabel(NoteKind? kind) => switch (kind) {
  NoteKind.block => 'NOTA',
  NoteKind.whiteboard => 'PIZARRA',
  NoteKind.notebook => 'CUADERNO',
  null => 'DOCUMENTO',
};
