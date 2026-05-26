import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import 'note_cell_model.dart';
import 'shape_recognizer.dart';

// World canvas size — large but finite to keep memory bounded. The user
// pans inside this via InteractiveViewer. ~10kx10k logical pixels.
const double _kCanvasW = 10000;
const double _kCanvasH = 10000;

// Palette: design tokens + folder accent.
const _baseColors = <Color>[
  yInk,
  yFight,
  yFlight,
  yLab,
  yAmber,
  yAmber2,
];
const _widths = [3.0, 6.0, 10.0];

class WhiteboardEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final Folder folder;

  const WhiteboardEditorScreen({
    super.key,
    required this.note,
    required this.folder,
  });

  @override
  ConsumerState<WhiteboardEditorScreen> createState() =>
      _WhiteboardEditorScreenState();
}

class _WhiteboardEditorScreenState
    extends ConsumerState<WhiteboardEditorScreen> {
  int? _blockId;
  DrawingData _data = DrawingData();
  final TransformationController _viewCtrl = TransformationController();
  Color _color = yInk;
  double _strokeW = 3.0;
  bool _erasing = false;
  bool _locked = false;
  bool _palmRejection = true;
  bool _shapeSnap = true;
  final List<DrawingStroke> _undoStack = [];
  DrawingStroke? _active;
  bool _pointerDown = false;
  Timer? _holdTimer;
  bool _snappedThisStroke = false;
  late final List<Color> _palette;

  @override
  void initState() {
    super.initState();
    _palette = [..._baseColors.sublist(0, 5), widget.folder.color];
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanvasBlock());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _viewCtrl.dispose();
    super.dispose();
  }

  void _scheduleHoldTimer() {
    _holdTimer?.cancel();
    if (!_shapeSnap) return;
    _holdTimer = Timer(const Duration(milliseconds: 800), _tryShapeSnap);
  }

  void _tryShapeSnap() {
    if (!_pointerDown) return;
    if (_active == null) return;
    if (_snappedThisStroke) return;
    final cleaned = ShapeRecognizer.detect(_active!.points);
    if (cleaned == null) return;
    final clean = shapeToStroke(cleaned, _color.toARGB32(), _strokeW);
    setState(() {
      _data.strokes.add(clean);
      _active = null;
      _undoStack.clear();
      _snappedThisStroke = true;
    });
    _persist();
    HapticFeedback.lightImpact();
  }

  Future<void> _ensureCanvasBlock() async {
    final repo = ref.read(noteBlockRepositoryProvider);
    final blocks = await repo.getByNote(widget.note.id);
    DrawingBlock? canvas = blocks
        .whereType<DrawingBlock>()
        .firstOrNull;
    canvas ??= await repo.insertAtEnd(
      widget.note.id,
      NoteBlockType.drawing,
      payload: {'h': _kCanvasH, 's': [], 'whiteboard': true},
    ) as DrawingBlock;
    if (!mounted) return;
    setState(() {
      _blockId = canvas!.id;
      _data = _decodeData(canvas);
    });
  }

  DrawingData _decodeData(DrawingBlock b) {
    List<dynamic> strokes = const [];
    try {
      final decoded = jsonDecode(b.strokesJson);
      if (decoded is List) strokes = decoded;
    } catch (_) {}
    return DrawingData.fromJson({'h': _kCanvasH, 's': strokes});
  }

  Future<void> _persist() async {
    if (_blockId == null) return;
    await ref.read(noteBlockRepositoryProvider).updatePayload(_blockId!, {
      'h': _kCanvasH,
      's': _data.strokes.map((s) => s.toJson()).toList(),
      'whiteboard': true,
    });
  }

  Offset _screenToWorld(Offset screen) {
    final inv = Matrix4.copy(_viewCtrl.value)..invert();
    final m = inv.storage;
    final w = m[3] * screen.dx + m[7] * screen.dy + m[15];
    final x = (m[0] * screen.dx + m[4] * screen.dy + m[12]) / w;
    final y = (m[1] * screen.dx + m[5] * screen.dy + m[13]) / w;
    return Offset(x, y);
  }

  bool _accept(PointerDeviceKind kind) {
    if (!_palmRejection) return true;
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  void _onDown(PointerDownEvent e) {
    if (!_locked) return;
    if (!_accept(e.kind)) return;
    _pointerDown = true;
    _snappedThisStroke = false;
    final p = _screenToWorld(e.localPosition);
    if (_erasing) {
      _eraseNear(p);
      return;
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        points: [
          [p.dx, p.dy]
        ],
      );
    });
    _scheduleHoldTimer();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_locked) return;
    if (!_accept(e.kind)) return;
    final p = _screenToWorld(e.localPosition);
    if (_erasing) {
      _eraseNear(p);
      return;
    }
    if (_active == null) return;
    setState(() => _active!.points.add([p.dx, p.dy]));
    _scheduleHoldTimer();
  }

  void _onUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    _pointerDown = false;
    if (!_locked) return;
    if (!_accept(e.kind)) return;
    _finishStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _pointerDown = false;
    if (!_locked) return;
    _finishStroke();
  }

  void _finishStroke() {
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      return;
    }
    setState(() {
      _data.strokes.add(_active!);
      _active = null;
      _undoStack.clear();
    });
    _persist();
  }

  void _eraseNear(Offset pos) {
    const r2 = 24.0 * 24.0;
    final before = _data.strokes.length;
    _data.strokes.removeWhere((s) {
      for (final p in s.points) {
        final dx = p[0] - pos.dx;
        final dy = p[1] - pos.dy;
        if (dx * dx + dy * dy < r2) return true;
      }
      return false;
    });
    if (_data.strokes.length != before) {
      setState(() {});
      _persist();
    }
  }

  void _undo() {
    if (_data.strokes.isEmpty) return;
    setState(() => _undoStack.add(_data.strokes.removeLast()));
    _persist();
  }

  void _redo() {
    if (_undoStack.isEmpty) return;
    setState(() => _data.strokes.add(_undoStack.removeLast()));
    _persist();
  }

  Future<void> _confirmClear() async {
    if (_data.strokes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Borrar pizarra',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text('¿Borrar todos los trazos?', style: yBody(size: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _undoStack.addAll(_data.strokes);
        _data.strokes.clear();
      });
      _persist();
    }
  }

  void _resetView() {
    setState(() => _viewCtrl.value = Matrix4.identity());
  }

  Future<void> _linkToLab(List<LabSpace> spaces) async {
    if (spaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay spaces activos'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final picked = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => _SpacePickerDialog(spaces: spaces),
    );
    if (picked == null || !mounted) return;
    final kanbanRepo = ref.read(kanbanCardRepositoryProvider);
    final existing = await kanbanRepo.watchBySourceNoteId(widget.note.id).first;
    if (existing.any((c) => c.labSpaceId == picked.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ya vinculada a ${picked.name}'),
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }
    final labRepo = ref.read(labSpaceRepositoryProvider);
    final columns = await labRepo.getColumns(picked.id);
    if (columns.isEmpty) return;
    final backlog = columns.firstWhere(
      (c) => c.name == 'Backlog' || c.name.toLowerCase() == 'backlog',
      orElse: () => columns.first,
    );
    final title = (widget.note.title?.trim().isNotEmpty == true)
        ? widget.note.title!
        : 'Pizarra ${widget.folder.name}';
    await kanbanRepo.create(
      labSpaceId: picked.id,
      columnId: backlog.id,
      title: title,
      sourceNoteId: widget.note.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Pizarra vinculada a ${picked.name}'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
    final linkedCards =
        ref.watch(kanbanCardsByNoteProvider(widget.note.id)).valueOrNull ?? [];
    final linkedSpaceIds = linkedCards.map((c) => c.labSpaceId).toSet();
    final linkedSpaces =
        spaces.where((s) => linkedSpaceIds.contains(s.id)).toList();

    return Scaffold(
      backgroundColor: yCream,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            child: Column(
              children: [
                ModeHeader(
                  mode: 'PIZARRA',
                  subtitle: 'INFINITA · CANVAS · PAN + ZOOM',
                  color: yFlight,
                  onBack: () => Navigator.pop(context),
                  headerRight: [
                    YBadge(
                      label: '@${widget.folder.name}',
                      bg: widget.folder.color,
                      fg: yCream,
                    ),
                    _BrutalBtn(
                      icon: Icons.center_focus_strong,
                      onTap: _resetView,
                    ),
                    _BrutalBtn(
                      icon: Icons.all_inclusive,
                      color: yLab,
                      onTap: () => _linkToLab(spaces),
                    ),
                  ],
                ),
                if (linkedSpaces.isNotEmpty) _LinkedSpacesBar(spaces: linkedSpaces),
              ],
            ),
          ),
          _toolbar(),
            Expanded(
              child: ClipRect(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onDown,
                  onPointerMove: _onMove,
                  onPointerUp: _onUp,
                  onPointerCancel: _onCancel,
                  child: InteractiveViewer(
                    transformationController: _viewCtrl,
                    minScale: 0.3,
                    maxScale: 4.0,
                    boundaryMargin:
                        const EdgeInsets.all(_kCanvasW * 0.5),
                    panEnabled: !_locked,
                    scaleEnabled: !_locked,
                    constrained: false,
                    child: SizedBox(
                      width: _kCanvasW,
                      height: _kCanvasH,
                      child: CustomPaint(
                        painter: _CanvasPainter(
                          strokes: _data.strokes,
                          active: _active,
                          locked: _locked,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _toolbar() {
    final paddingH = MediaQuery.of(context).size.width * 0.08;
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: paddingH.clamp(16.0, 120.0), vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          children: [
            _toolBtn(
              icon: _locked ? Icons.lock : Icons.lock_open,
              active: _locked,
              label: _locked ? 'DIBUJO' : 'NAV',
              onTap: () => setState(() => _locked = !_locked),
            ),
            const SizedBox(width: 16),
            _toolBtn(
              icon: Icons.edit_outlined,
              active: !_erasing,
              onTap: () => setState(() => _erasing = false),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.auto_fix_high,
              active: _erasing,
              onTap: () => setState(() => _erasing = true),
            ),
            _divider(),
            for (final c in _palette) ...[
              _colorBtn(c),
              const SizedBox(width: 10),
            ],
            _divider(),
            for (final w in _widths) ...[
              _widthBtn(w),
              const SizedBox(width: 10),
            ],
            _divider(),
            _toolBtn(
              icon: Icons.undo,
              active: false,
              enabled: _data.strokes.isNotEmpty,
              onTap: _undo,
            ),
            const SizedBox(width: 10),
            _toolBtn(
              icon: Icons.redo,
              active: false,
              enabled: _undoStack.isNotEmpty,
              onTap: _redo,
            ),
            _divider(),
            _toolBtn(
              icon: Icons.back_hand_outlined,
              active: _palmRejection,
              label: 'PALMA',
              onTap: () => setState(() => _palmRejection = !_palmRejection),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.auto_awesome,
              active: _shapeSnap,
              label: 'SNAP',
              onTap: () => setState(() => _shapeSnap = !_shapeSnap),
            ),
            const SizedBox(width: 16),
            _toolBtn(
              icon: Icons.delete_outline,
              active: false,
              onTap: _confirmClear,
            ),
          ],
        ),
      ),
    ));
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: yInk.withValues(alpha: 0.2),
      );

  Widget _toolBtn({
    required IconData icon,
    required bool active,
    bool enabled = true,
    String? label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: label != null ? 10 : 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? yFlight : yCream,
          border: Border.all(
            color: enabled ? yInk : yMuted.withValues(alpha: 0.4),
            width: yLineThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active
                  ? yCream
                  : enabled
                      ? yInk
                      : yMuted.withValues(alpha: 0.4),
            ),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label,
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: active ? yCream : yInk,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _colorBtn(Color c) {
    final sel = _color.toARGB32() == c.toARGB32() && !_erasing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _color = c;
        _erasing = false;
      }),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c,
          border: Border.all(color: yInk, width: sel ? 3 : yLineThin),
        ),
      ),
    );
  }

  Widget _widthBtn(double w) {
    final sel = _strokeW == w;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _strokeW = w),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(
            color: sel ? yInk : yMuted.withValues(alpha: 0.4),
            width: sel ? 2.5 : yLineThin,
          ),
        ),
        child: Container(
          width: w.clamp(3.0, 14.0),
          height: w.clamp(3.0, 14.0),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: yInk,
          ),
        ),
      ),
    );
  }
}

// ─── Canvas painter ───────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? active;
  final bool locked;

  _CanvasPainter({
    required this.strokes,
    required this.active,
    required this.locked,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid background — gentle dotted texture so users have a frame.
    final bg = Paint()..color = yCream;
    canvas.drawRect(Offset.zero & size, bg);

    final dot = Paint()..color = yMuted.withValues(alpha: 0.16);
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }

    for (final s in strokes) {
      _draw(canvas, s);
    }
    if (active != null) _draw(canvas, active!);

    if (!locked) {
      // Hint banner — centered, small.
      const center = Offset(_kCanvasW / 2, _kCanvasH / 2 - 8);
      final tp = TextPainter(
        text: TextSpan(
          text: 'BLOQUEAR PARA DIBUJAR · PINCH PARA ZOOM',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: yMuted.withValues(alpha: 0.45),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}

void _draw(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;
  final paint = Paint()
    ..color = Color(stroke.colorValue)
    ..strokeWidth = stroke.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (stroke.points.length == 1) {
    canvas.drawCircle(
      Offset(stroke.points[0][0], stroke.points[0][1]),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path();
  path.moveTo(stroke.points[0][0], stroke.points[0][1]);
  for (int i = 1; i < stroke.points.length - 1; i++) {
    final x0 = stroke.points[i][0];
    final y0 = stroke.points[i][1];
    final x1 = stroke.points[i + 1][0];
    final y1 = stroke.points[i + 1][1];
    path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
  }
  final last = stroke.points.last;
  path.lineTo(last[0], last[1]);
  canvas.drawPath(path, paint);
}

// ─── Linked-spaces bar (under header) ─────────────────────────────────────

class _LinkedSpacesBar extends StatelessWidget {
  final List<LabSpace> spaces;
  const _LinkedSpacesBar({required this.spaces});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Text('VINCULADA A',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in spaces) ...[
                    Container(
                      padding:
                          const EdgeInsets.fromLTRB(8, 3, 8, 4),
                      decoration: BoxDecoration(
                        color: s.accentColor,
                        border: Border.all(color: yInk, width: 1.5),
                      ),
                      child: Text('→ ${s.name.toUpperCase()}',
                          style: yMono(
                            size: 9,
                            weight: FontWeight.w700,
                            tracking: 1.2,
                            color: yCream,
                          )),
                    ),
                const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpacePickerDialog extends StatelessWidget {
  final List<LabSpace> spaces;
  const _SpacePickerDialog({required this.spaces});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vincular pizarra a LAB',
                style: ySans(
                  size: 20,
                  weight: FontWeight.w700,
                  color: yInk,
                )),
            const SizedBox(height: 4),
            Text('Aparecerá como tarjeta en el kanban del space.',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w500,
                  tracking: 1.2,
                  color: yMuted,
                )),
            const SizedBox(height: 14),
            for (final s in spaces)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, color: s.accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.name,
                            style: ySans(size: 16, color: yInk)),
                      ),
                    ],
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrutalBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BrutalBtn({required this.icon, this.color = yCream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: yInk, width: yLineMid),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: color == yCream ? yInk : yCream),
      ),
    );
  }
}
