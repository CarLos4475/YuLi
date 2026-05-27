import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

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
import 'lasso_controller.dart';
import 'lasso_painter.dart';
import 'lasso_mini_toolbar.dart';

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
    extends ConsumerState<WhiteboardEditorScreen>
    with TickerProviderStateMixin {
  int? _blockId;
  DrawingData _data = DrawingData();
  final TransformationController _viewCtrl = TransformationController();
  Color _color = yInk;
  double _strokeW = 3.0;
  DrawTool _tool = DrawTool.pen;
  bool _locked = false;
  bool _palmRejection = true;
  final Set<int> _activePointers = {};
  bool _isDrawing = false;
  bool _stylusActive = false;
  final List<DrawingStroke> _undoStack = [];
  DrawingStroke? _active;
  Timer? _holdTimer;
  Offset? _holdAnchor;
  static const _holdTolerance2 = 400.0; // 20px squared
  late final List<Color> _palette;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  Timer? _pasteTimer;
  Offset? _pastePos;
  Offset? _showPasteAt;

  // Multi-finger tap tracking
  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  @override
  void initState() {
    super.initState();
    _palette = [..._baseColors.sublist(0, 5), widget.folder.color];
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _lassoCtrl.onChanged = () => setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanvasBlock());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _viewCtrl.dispose();
    super.dispose();
  }

  bool _tryShapeSnap() {
    if (_active == null) return false;
    final cleaned = ShapeRecognizer.detect(_active!.points);
    if (cleaned == null) return false;
    final clean = shapeToStroke(cleaned, _active!.colorValue, _active!.strokeWidth);
    setState(() {
      _data.strokes.add(clean);
      _active = null;
      _undoStack.clear();
    });
    _persist();
    HapticFeedback.lightImpact();
    return true;
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

  bool _shouldDraw(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (!_palmRejection) return true;
    return false;
  }

  void _startHoldTimer(Offset worldPos) {
    _holdTimer?.cancel();
    _holdAnchor = worldPos;
    _holdTimer = Timer(const Duration(milliseconds: 800), _tryShapeSnap);
  }

  void _onDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    _pointerDownPos[e.pointer] = e.localPosition;
    if (_activePointers.length > _maxSimultaneous) {
      _maxSimultaneous = _activePointers.length;
    }
    if (_activePointers.length == 2) {
      _multiFingerDownTime = DateTime.now();
      _multiFingerMoved = false;
    }

    final isStylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    if (isStylus) _stylusActive = true;

    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }

    if (!_palmRejection && !isStylus && _activePointers.length >= 2) {
      setState(() {
        _active = null;
        _isDrawing = false;
      });
      _holdTimer?.cancel();
      _holdAnchor = null;
      return;
    }

    // Finger long-press paste: works in any mode when palm rejection is on,
    // or in lasso mode regardless of palm rejection.
    final isFinger = !isStylus;
    if (_lassoCtrl.hasClipboard && _activePointers.length == 1) {
      final canPaste = (isFinger && _palmRejection) || _tool == DrawTool.lasso;
      if (canPaste && _lassoCtrl.phase == LassoPhase.idle) {
        final p = _screenToWorld(e.localPosition);
        _pastePos = p;
        _pasteTimer?.cancel();
        _pasteTimer = Timer(const Duration(milliseconds: 500), () {
          if (_pastePos != null) {
            setState(() => _showPasteAt = _pastePos);
            HapticFeedback.lightImpact();
            _pastePos = null;
          }
        });
        if (isFinger && _palmRejection) return;
      }
    }

    // Lasso + palm rejection + finger: interact with selection or pan/zoom
    if (_tool == DrawTool.lasso && isFinger && _palmRejection) {
      if (_lassoCtrl.phase == LassoPhase.selected) {
        final p = _screenToWorld(e.localPosition);
        if (_lassoCtrl.hitTestRotationHandle(p) ||
            _lassoCtrl.hitTestCornerHandle(p) != null ||
            _lassoCtrl.hitTestSideHandle(p) != null ||
            _lassoCtrl.isTapInsideBoundingBox(p)) {
          setState(() => _isDrawing = true);
          _handleLassoDown(p);
          return;
        }
        _lassoCtrl.deselect();
      }
      return;
    }

    final willDraw = _shouldDraw(e.kind);
    setState(() => _isDrawing = willDraw);
    if (!willDraw) return;

    final p = _screenToWorld(e.localPosition);
    if (_tool == DrawTool.lasso) {
      _handleLassoDown(p);
      return;
    }
    if (_tool == DrawTool.eraser) {
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
    _startHoldTimer(p);
  }

  static const _minDist2 = 9.0; // 3px squared

  void _onMove(PointerMoveEvent e) {
    if (_activePointers.length >= 2 && !_multiFingerMoved) {
      final start = _pointerDownPos[e.pointer];
      if (start != null && (e.localPosition - start).distance > 15) {
        _multiFingerMoved = true;
      }
    }
    if (_pastePos != null) {
      final p = _screenToWorld(e.localPosition);
      if ((p - _pastePos!).distanceSquared > 400) {
        _pasteTimer?.cancel();
        _pastePos = null;
      }
      return;
    }
    if (!_isDrawing) return;
    final p = _screenToWorld(e.localPosition);
    if (_tool == DrawTool.lasso) {
      _handleLassoMove(p);
      return;
    }
    if (_tool == DrawTool.eraser) {
      _eraseNear(p);
      return;
    }
    if (_active == null) return;
    final pts = _active!.points;
    if (pts.isNotEmpty) {
      final dx = p.dx - pts.last[0];
      final dy = p.dy - pts.last[1];
      if (dx * dx + dy * dy < _minDist2) return;
    }
    setState(() => pts.add([p.dx, p.dy]));
    if (_holdAnchor != null) {
      final dx = p.dx - _holdAnchor!.dx;
      final dy = p.dy - _holdAnchor!.dy;
      if (dx * dx + dy * dy > _holdTolerance2) {
        _startHoldTimer(p);
      }
    }
  }

  void _onUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    _pointerDownPos.remove(e.pointer);
    _holdTimer?.cancel();
    _holdAnchor = null;
    _stylusActive = false;
    setState(() => _isDrawing = false);

    if (_activePointers.isEmpty && _maxSimultaneous >= 2) {
      final elapsed = _multiFingerDownTime != null
          ? DateTime.now().difference(_multiFingerDownTime!).inMilliseconds
          : 999;
      if (!_multiFingerMoved && elapsed < 400) {
        if (_maxSimultaneous == 2) {
          _undo();
          HapticFeedback.lightImpact();
        } else if (_maxSimultaneous >= 3) {
          _redo();
          HapticFeedback.lightImpact();
        }
      }
      _maxSimultaneous = 0;
      _multiFingerDownTime = null;
      return;
    }
    if (_activePointers.isEmpty) _maxSimultaneous = 0;

    if (_pastePos != null) {
      _pasteTimer?.cancel();
      _pastePos = null;
      return;
    }

    if (_tool == DrawTool.lasso) {
      _handleLassoUp();
      return;
    }
    if (_active == null) return;
    _finishStroke();
  }

  void _onCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _pointerDownPos.remove(e.pointer);
    _holdTimer?.cancel();
    _holdAnchor = null;
    setState(() => _isDrawing = false);
    if (_activePointers.isEmpty) _maxSimultaneous = 0;
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

    if (_tool == DrawTool.pen && isScribble(_active!.points)) {
      final bounds = scribbleBounds(_active!.points);
      final before = _data.strokes.length;
      _data.strokes.removeWhere((s) {
        for (final p in s.points) {
          if (bounds.contains(Offset(p[0], p[1]))) return true;
        }
        return false;
      });
      setState(() => _active = null);
      if (_data.strokes.length != before) {
        HapticFeedback.lightImpact();
        _persist();
      }
      return;
    }

    _active = DrawingStroke(
      colorValue: _active!.colorValue,
      strokeWidth: _active!.strokeWidth,
      points: _smooth(_active!.points),
    );
    setState(() {
      _data.strokes.add(_active!);
      _active = null;
      _undoStack.clear();
    });
    _persist();
  }

  static List<List<double>> _smooth(List<List<double>> pts) {
    if (pts.length < 3) return pts;
    final out = <List<double>>[pts.first];
    for (int i = 1; i < pts.length - 1; i++) {
      out.add([
        (pts[i - 1][0] + pts[i][0] * 2 + pts[i + 1][0]) / 4,
        (pts[i - 1][1] + pts[i][1] * 2 + pts[i + 1][1]) / 4,
      ]);
    }
    out.add(pts.last);
    return out;
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

  // ─── Lasso gesture handlers ─────────────────────────────────────────────

  void _handleLassoDown(Offset worldPos) {
    _pasteTimer?.cancel();
    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.selected) {
      if (_lassoCtrl.hitTestRotationHandle(worldPos)) {
        _lassoCtrl.startRotation(worldPos, _data.strokes);
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(worldPos);
      if (corner != null) {
        _lassoCtrl.startResize(corner, worldPos, _data.strokes);
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(worldPos);
      if (side != null) {
        _lassoCtrl.startSideResize(side, worldPos, _data.strokes);
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(worldPos)) {
        _lassoCtrl.startMove(worldPos, _data.strokes);
        return;
      }
      _lassoCtrl.deselect();
    }
    _lassoCtrl.startTracing(worldPos);
  }

  void _handleLassoMove(Offset worldPos) {
    if (_pastePos != null) {
      if ((worldPos - _pastePos!).distanceSquared > 400) {
        _pasteTimer?.cancel();
        _pastePos = null;
        _lassoCtrl.startTracing(worldPos);
      }
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.addTracePoint(worldPos);
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      _lassoCtrl.updateMove(worldPos);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      _lassoCtrl.isSideResize
          ? _lassoCtrl.updateSideResize(worldPos)
          : _lassoCtrl.updateResize(worldPos);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      _lassoCtrl.updateRotation(worldPos);
    }
  }

  void _handleLassoUp() {
    if (_pastePos != null) {
      _pasteTimer?.cancel();
      _pastePos = null;
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.finishTracing(_data.strokes);
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      _lassoCtrl.finishMove(_data.strokes);
      _persist();
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      _lassoCtrl.isSideResize
          ? _lassoCtrl.finishSideResize(_data.strokes)
          : _lassoCtrl.finishResize(_data.strokes);
      _persist();
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      _lassoCtrl.finishRotation(_data.strokes);
      _persist();
    }
  }

  void _lassoDelete() {
    _lassoCtrl.deleteSelected(_data.strokes);
    _persist();
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    _lassoCtrl.duplicateSelected(_data.strokes);
    _persist();
    HapticFeedback.lightImpact();
  }

  Widget _buildLassoMiniToolbar() {
    final bb = _lassoCtrl.boundingBox!;
    final topCenter = Offset(bb.center.dx, bb.top - 64);
    final screenPos = MatrixUtils.transformPoint(_viewCtrl.value, topCenter);
    return Positioned(
      left: screenPos.dx - 80,
      top: screenPos.dy,
      child: LassoMiniToolbar(
        onDelete: _lassoDelete,
        onDuplicate: _lassoDuplicate,
        palette: _palette,
        onColorChange: (c) {
          _lassoCtrl.changeColor(_data.strokes, c.toARGB32());
          _persist();
        },
        onWidthChange: (w) {
          _lassoCtrl.changeWidth(_data.strokes, w);
          _persist();
        },
        onFlipH: () {
          _lassoCtrl.flipHorizontal(_data.strokes);
          _persist();
        },
        onFlipV: () {
          _lassoCtrl.flipVertical(_data.strokes);
          _persist();
        },
        onCopy: () {
          _lassoCtrl.copySelected(_data.strokes);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('COPIADO'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onCut: () {
          _lassoCtrl.cutSelected(_data.strokes);
          _persist();
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CORTADO'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPasteButton() {
    final screenPos = MatrixUtils.transformPoint(_viewCtrl.value, _showPasteAt!);
    return Positioned(
      left: screenPos.dx - 40,
      top: screenPos.dy - 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _lassoCtrl.pasteAt(_showPasteAt!, _data.strokes);
          _persist();
          HapticFeedback.mediumImpact();
          setState(() => _showPasteAt = null);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yInk, width: yLineMid),
            boxShadow: const [BoxShadow(color: yInk, offset: Offset(2, 2))],
          ),
          child: Text(
            'PEGAR',
            style: yMono(size: 11, weight: FontWeight.w700, tracking: 1.4, color: yInk),
          ),
        ),
      ),
    );
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
              child: LayoutBuilder(builder: (ctx, c) {
                return AnimatedBuilder(
                  animation: _viewCtrl,
                  builder: (_, _) {
                    final inv = Matrix4.inverted(_viewCtrl.value);
                    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
                    final br = MatrixUtils.transformPoint(
                        inv, Offset(c.maxWidth, c.maxHeight));
                    final visibleRect = Rect.fromPoints(tl, br);
                    return ClipRect(
                      child: Stack(
                        children: [
                          Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _onDown,
                            onPointerMove: _onMove,
                            onPointerUp: _onUp,
                            onPointerCancel: _onCancel,
                            child: InteractiveViewer(
                              transformationController: _viewCtrl,
                              minScale: 0.3,
                              maxScale: 4.0,
                              boundaryMargin: const EdgeInsets.all(_kCanvasW * 0.5),
                              panEnabled: _tool == DrawTool.lasso
                                  ? (_lassoCtrl.phase == LassoPhase.idle && !_isDrawing)
                                  : _palmRejection
                                      ? !_stylusActive
                                      : !_isDrawing,
                              scaleEnabled: _tool == DrawTool.lasso
                                  ? (_lassoCtrl.phase == LassoPhase.idle && !_isDrawing)
                                  : !_stylusActive && !_locked,
                              constrained: false,
                              child: SizedBox(
                                width: _kCanvasW,
                                height: _kCanvasH,
                                child: Stack(
                                  children: [
                                    CustomPaint(
                                      painter: _CanvasPainter(
                                        strokes: _data.strokes,
                                        active: _active,
                                        locked: _locked,
                                        visibleRect: visibleRect,
                                        hiddenIndices: (_lassoCtrl.phase == LassoPhase.moving ||
                                                _lassoCtrl.phase == LassoPhase.resizing ||
                                                _lassoCtrl.phase == LassoPhase.rotating)
                                            ? _lassoCtrl.selectedIndices
                                            : null,
                                      ),
                                      size: const Size(_kCanvasW, _kCanvasH),
                                    ),
                                    if (_lassoCtrl.phase != LassoPhase.idle)
                                      AnimatedBuilder(
                                        animation: _lassoAnimCtrl,
                                        builder: (_, _) => CustomPaint(
                                          painter: LassoPainter(
                                            ctrl: _lassoCtrl,
                                            animValue: _lassoAnimCtrl.value,
                                            strokes: _data.strokes,
                                            visibleRect: visibleRect,
                                          ),
                                          size: const Size(_kCanvasW, _kCanvasH),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_lassoCtrl.phase == LassoPhase.selected)
                            _buildLassoMiniToolbar(),
                          if (_showPasteAt != null)
                            _buildPasteButton(),
                        ],
                      ),
                    );
                  },
                );
              }),
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
              label: _locked ? 'ZOOM OFF' : 'ZOOM ON',
              onTap: () => setState(() => _locked = !_locked),
            ),
            const SizedBox(width: 16),
            _toolBtn(
              icon: Icons.edit_outlined,
              active: _tool == DrawTool.pen,
              onTap: () => setState(() { _tool = DrawTool.pen; _lassoCtrl.deselect(); }),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.auto_fix_high,
              active: _tool == DrawTool.eraser,
              onTap: () => setState(() { _tool = DrawTool.eraser; _lassoCtrl.deselect(); }),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.highlight_alt,
              active: _tool == DrawTool.lasso,
              label: 'LAZO',
              onTap: () => setState(() => _tool = DrawTool.lasso),
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
    final sel = _color.toARGB32() == c.toARGB32() && _tool == DrawTool.pen;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _color = c;
        _tool = DrawTool.pen;
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
  final Rect visibleRect;
  final Set<int>? hiddenIndices;

  _CanvasPainter({
    required this.strokes,
    required this.active,
    required this.locked,
    required this.visibleRect,
    this.hiddenIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vr = visibleRect;
    // Background — only the visible portion.
    canvas.drawRect(vr, Paint()..color = yCream);
    // Grid dots — only within visible rect (with 48px margin on each side).
    final dot = Paint()..color = yMuted.withValues(alpha: 0.16);
    const step = 48.0;
    final startX = (vr.left / step).floor() * step;
    final startY = (vr.top / step).floor() * step;
    for (double x = startX; x < vr.right + step; x += step) {
      for (double y = startY; y < vr.bottom + step; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
    // Strokes — skip those that don't intersect the visible rect.
    for (int i = 0; i < strokes.length; i++) {
      if (hiddenIndices != null && hiddenIndices!.contains(i)) continue;
      if (_strokeInRect(strokes[i], vr)) _draw(canvas, strokes[i]);
    }
    if (active != null && _strokeInRect(active!, vr)) _draw(canvas, active!);
    // Hint.
    if (!locked) {
      const center = Offset(_kCanvasW / 2, _kCanvasH / 2 - 8);
      if (vr.contains(center)) {
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
  }

  bool _strokeInRect(DrawingStroke s, Rect r) {
    for (final p in s.points) {
      if (r.contains(Offset(p[0], p[1]))) return true;
    }
    return false;
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.visibleRect != visibleRect ||
      old.locked != locked ||
      old.strokes != strokes ||
      old.active != active;
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
