import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/yuli_design.dart';
import 'color_picker.dart';
import 'fountain_pen_engine.dart';
import 'drawing_engine.dart';
import 'drawing_prefs.dart';
import 'note_cell_model.dart';
import 'lasso_controller.dart';
import 'lasso_painter.dart';
import 'lasso_mini_toolbar.dart';
import 'stroke_stabilizer.dart';
import 'stroke_width_picker.dart';

class DrawingCell extends StatefulWidget {
  final DrawingData data;
  final ValueChanged<DrawingData> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDrawStart;
  final VoidCallback onDrawEnd;
  final ValueChanged<bool> onScrollLockChanged;
  final Color? accent;
  final Widget? header;

  /// Run OCR on the given handwriting strokes (cell-local coords). Supplied by
  /// the host (a Consumer) which has the recognizer + note folder. Null hides
  /// the lasso's "→ Texto" action.
  final Future<void> Function(List<List<Offset>> strokes)? onRecognizeText;
  final Future<void> Function(List<List<Offset>> strokes)? onSendToYuli;
  final Future<void> Function(List<List<Offset>> strokes)? onSendMathToYuli;

  const DrawingCell({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
    required this.onDrawStart,
    required this.onDrawEnd,
    required this.onScrollLockChanged,
    this.accent,
    this.header,
    this.onRecognizeText,
    this.onSendToYuli,
    this.onSendMathToYuli,
  });

  @override
  State<DrawingCell> createState() => _DrawingCellState();
}

class _DrawingCellState extends State<DrawingCell>
    with TickerProviderStateMixin {
  late DrawingData _data;
  late List<Color> _palette;
  Color _color = yInk;
  double _strokeW = 3.0;
  DrawTool _tool = DrawTool.pen;
  bool _locked = false;
  bool _palmRejection = true;
  StabilizerLevel _stabilizer = StabilizerLevel.off;
  LiveStabilizer? _stab;
  final Map<DrawTool, Color> _toolColors = {...DrawingPrefs.defaultColors};
  final Map<DrawTool, double> _toolWidths = {...DrawingPrefs.defaultWidths};
  final List<List<DrawingStroke>> _undoStack = [];
  final List<List<DrawingStroke>> _redoStack = [];
  List<DrawingStroke>? _gestureBefore;
  bool _gestureChanged = false;
  DrawingStroke? _active;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  Timer? _pasteTimer;
  Offset? _pastePos;
  Offset? _showPasteAt;

  bool _widthPickerOpen = false;
  List<double> _recentWidths = const [3.0, 6.0, 10.0];

  bool _colorPickerOpen = false;
  List<Color> _recentColors = const [];
  List<Color> _savedColors = const [];
  bool _eyedropperMode = false;

  // Multi-finger tap tracking
  final Set<int> _activePointers = {};
  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _palette = _buildPalette();
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _lassoCtrl.onChanged = () => setState(() {});
    StrokeWidthPrefs.load().then((widths) {
      if (!mounted) return;
      setState(() => _recentWidths = widths);
    });
    ColorPalettePrefs.load().then((colors) {
      if (!mounted) return;
      setState(() => _recentColors = colors);
    });
    SavedColorsPrefs.load().then((colors) {
      if (!mounted) return;
      setState(() => _savedColors = colors);
    });
    DrawingPrefs.load().then((p) {
      if (!mounted) return;
      setState(() {
        _stabilizer = p.stabilizer;
        _palmRejection = p.palmRejection;
        _toolColors.addAll(p.toolColors);
        _toolWidths.addAll(p.toolWidths);
        _color = _toolColors[_tool] ?? _color;
        _strokeW = _toolWidths[_tool] ?? _strokeW;
      });
    });
  }

  void _selectTool(DrawTool t) {
    setState(() {
      if (DrawingPrefs.isColoredTool(_tool)) {
        _toolColors[_tool] = _color;
        _toolWidths[_tool] = _strokeW;
      }
      _tool = t;
      if (DrawingPrefs.isColoredTool(t)) {
        _color = _toolColors[t] ?? _color;
        _strokeW = _toolWidths[t] ?? _strokeW;
      }
      _lassoCtrl.deselect();
    });
  }

  void _toggleWidthPicker() {
    setState(() {
      _widthPickerOpen = !_widthPickerOpen;
      if (_widthPickerOpen) _colorPickerOpen = false;
    });
  }

  void _toggleColorPicker() {
    setState(() {
      _colorPickerOpen = !_colorPickerOpen;
      if (_colorPickerOpen) _widthPickerOpen = false;
    });
  }

  void _commitWidth(double value) {
    setState(() {
      _strokeW = value;
      _recentWidths = StrokeWidthPrefs.push(_recentWidths, value);
      if (DrawingPrefs.isColoredTool(_tool)) _toolWidths[_tool] = value;
    });
    StrokeWidthPrefs.save(_recentWidths);
    if (DrawingPrefs.isColoredTool(_tool)) {
      DrawingPrefs.saveToolWidth(_tool, value);
    }
  }

  void _commitColor(Color value) {
    setState(() {
      _color = value;
      _recentColors = ColorPalettePrefs.push(_recentColors, value);
      if (DrawingPrefs.isColoredTool(_tool)) _toolColors[_tool] = value;
    });
    ColorPalettePrefs.save(_recentColors);
    if (DrawingPrefs.isColoredTool(_tool)) {
      DrawingPrefs.saveToolColor(_tool, value);
    }
  }

  void _starColor(Color value) {
    final isStarred =
        _savedColors.any((c) => c.toARGB32() == value.toARGB32());
    setState(() {
      _savedColors = isStarred
          ? SavedColorsPrefs.remove(_savedColors, value)
          : SavedColorsPrefs.push(_savedColors, value);
    });
    SavedColorsPrefs.save(_savedColors);
    HapticFeedback.selectionClick();
  }

  bool _lockBeforeEyedropper = false;

  void _enterEyedropper() {
    _lockBeforeEyedropper = _locked;
    setState(() {
      _eyedropperMode = true;
      _colorPickerOpen = false;
      _widthPickerOpen = false;
      _tool = DrawTool.pen;
      _lassoCtrl.deselect();
      _locked = true;
    });
    widget.onScrollLockChanged(true);
    HapticFeedback.lightImpact();
  }

  void _exitEyedropper() {
    setState(() {
      _eyedropperMode = false;
      _locked = _lockBeforeEyedropper;
    });
    widget.onScrollLockChanged(_lockBeforeEyedropper);
  }

  bool _sampleAt(Offset pos) {
    final c = sampleStrokeColorAt(_data.strokes, pos);
    if (c == null) {
      _exitEyedropper();
      HapticFeedback.lightImpact();
      return false;
    }
    _exitEyedropper();
    _commitColor(c);
    HapticFeedback.mediumImpact();
    return true;
  }

  @override
  void dispose() {
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DrawingCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accent != widget.accent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _palette = _buildPalette());
      });
    }
  }

  List<Color> _buildPalette() {
    return buildPenPalette(widget.accent);
  }

  bool _shouldAcceptPointer(PointerDeviceKind kind) {
    if (!_palmRejection) return true;
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  LiveStabilizer? _newStabilizer() =>
      _stabilizer.isOn ? LiveStabilizer(_stabilizer.alpha) : null;

  Offset _stabilize(Offset p) => _stab?.process(p.dx, p.dy) ?? p;

  void _start(Offset pos) {
    widget.onDrawStart();
    if (_tool == DrawTool.lasso) {
      _handleLassoDown(pos);
      return;
    }
    if (_tool == DrawTool.eraser) {
      _gestureBefore = _snapshot();
      _gestureChanged = false;
      _eraseNear(pos);
      return;
    }
    _stab = _newStabilizer();
    final p = _stabilize(pos);
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        isHighlighter: _tool == DrawTool.highlighter,
        points: [
          [p.dx, p.dy]
        ],
      );
    });
  }

  void _move(Offset pos) {
    if (_tool == DrawTool.lasso) {
      _handleLassoMove(pos);
      return;
    }
    if (_tool == DrawTool.eraser) {
      _eraseNear(pos);
      return;
    }
    if (_active == null) return;
    final p = _stabilize(pos);
    setState(() {
      _active!.points.add([p.dx, p.dy]);
    });
  }

  void _end() {
    widget.onDrawEnd();
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.isEmpty) {
      _active = null;
      return;
    }

    if (_tool == DrawTool.pen && isScribble(_active!.points)) {
      final bounds = scribbleBounds(_active!.points);
      final before = _snapshot();
      final lenBefore = _data.strokes.length;
      _data.strokes.removeWhere((s) {
        for (final p in s.points) {
          if (bounds.contains(Offset(p[0], p[1]))) return true;
        }
        return false;
      });
      setState(() => _active = null);
      if (_data.strokes.length != lenBefore) {
        _commit(before);
        widget.onChanged(_data);
      }
      return;
    }

    final before = _snapshot();
    setState(() {
      _data.strokes.add(_active!);
      _active = null;
    });
    _commit(before);
    widget.onChanged(_data);
  }

  void _finishFountainStroke() {
    widget.onDrawEnd();
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.length < 2) {
      _active = null;
      return;
    }

    final baked = FountainPenEngine.finishStroke(_active!);
    final before = _snapshot();
    setState(() {
      _data.strokes.add(baked);
      _active = null;
    });
    _commit(before);
    widget.onChanged(_data);
  }

  static const _eraserRadius = 7.0;

  void _eraseNear(Offset pos) {
    final before = _data.strokes.length;
    _data.strokes.removeWhere((s) => strokeHitByEraser(s, pos, _eraserRadius));
    if (_data.strokes.length != before) {
      _gestureChanged = true;
      setState(() {});
      widget.onChanged(_data);
    }
  }

  // ─── Lasso handlers ──────────────────────────────────────────────────

  void _handleLassoDown(Offset pos) {
    _pasteTimer?.cancel();
    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.selected) {
      if (_lassoCtrl.hitTestRotationHandle(pos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startRotation(pos, _data.strokes);
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(pos);
      if (corner != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startResize(corner, pos, _data.strokes);
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(pos);
      if (side != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startSideResize(side, pos, _data.strokes);
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(pos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startMove(pos, _data.strokes);
        return;
      }
      _lassoCtrl.deselect();
    }
    _lassoCtrl.startTracing(pos);
  }

  void _handleLassoMove(Offset pos) {
    if (_pastePos != null) {
      if ((pos - _pastePos!).distanceSquared > 400) {
        _pasteTimer?.cancel();
        _pastePos = null;
        _lassoCtrl.startTracing(pos);
      }
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.addTracePoint(pos);
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      _lassoCtrl.updateMove(pos);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      _lassoCtrl.isSideResize
          ? _lassoCtrl.updateSideResize(pos)
          : _lassoCtrl.updateResize(pos);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      _lassoCtrl.updateRotation(pos);
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
      _commitGesture();
      widget.onChanged(_data);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      _lassoCtrl.isSideResize
          ? _lassoCtrl.finishSideResize(_data.strokes)
          : _lassoCtrl.finishResize(_data.strokes);
      _commitGesture();
      widget.onChanged(_data);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      _lassoCtrl.finishRotation(_data.strokes);
      _commitGesture();
      widget.onChanged(_data);
    }
  }

  void _commitGesture() {
    if (_gestureBefore != null) {
      _commit(_gestureBefore!);
      _gestureBefore = null;
    }
  }

  void _commitEraseGesture() {
    if (_gestureBefore != null && _gestureChanged) {
      _commit(_gestureBefore!);
    }
    _gestureBefore = null;
    _gestureChanged = false;
  }

  void _lassoMutate(VoidCallback op) {
    final before = _snapshot();
    op();
    _commit(before);
    widget.onChanged(_data);
  }

  void _lassoDelete() => _lassoMutate(() => _lassoCtrl.deleteSelected(_data.strokes));

  /// True when the lasso selection contains handwriting (pen/fountain) — the
  /// only thing OCR can read.
  bool get _selectionHasWriting {
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= _data.strokes.length) continue;
      final s = _data.strokes[i];
      if (!s.isHighlighter && !s.isShape) return true;
    }
    return false;
  }

  List<List<Offset>> _selectedWritingStrokes() {
    final strokes = <List<Offset>>[];
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= _data.strokes.length) continue;
      final s = _data.strokes[i];
      if (s.isHighlighter || s.isShape) continue;
      strokes.add(s.points.map((p) => Offset(p[0], p[1])).toList());
    }
    return strokes;
  }

  /// Gather the selected handwriting and hand it to the host's OCR flow.
  Future<void> _recognizeSelection() async {
    final handler = widget.onRecognizeText;
    if (handler == null) return;
    final strokes = _selectedWritingStrokes();
    if (strokes.isEmpty) return;
    await handler(strokes);
  }

  Future<void> _sendSelectionToYuli() async {
    final handler = widget.onSendToYuli;
    if (handler == null) return;
    final strokes = _selectedWritingStrokes();
    if (strokes.isEmpty) return;
    await handler(strokes);
  }

  Future<void> _sendMathSelectionToYuli() async {
    final handler = widget.onSendMathToYuli;
    if (handler == null) return;
    final strokes = _selectedWritingStrokes();
    if (strokes.isEmpty) return;
    await handler(strokes);
  }

  void _lassoDuplicate() =>
      _lassoMutate(() => _lassoCtrl.duplicateSelected(_data.strokes));

  // ─── Undo / redo (snapshot history) ─────────────────────────────────────

  List<DrawingStroke> _snapshot() =>
      _data.strokes.map((s) => s.clone()).toList();

  void _commit(List<DrawingStroke> before) {
    _undoStack.add(before);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    setState(() {
      _data.strokes = _undoStack.removeLast();
      _lassoCtrl.deselect();
      _active = null;
    });
    widget.onChanged(_data);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    setState(() {
      _data.strokes = _redoStack.removeLast();
      _lassoCtrl.deselect();
      _active = null;
    });
    widget.onChanged(_data);
  }

  void _clearAll() {
    if (_data.strokes.isEmpty) return;
    final before = _snapshot();
    setState(() => _data.strokes = []);
    _commit(before);
    widget.onChanged(_data);
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    widget.onScrollLockChanged(_locked);
  }

  void _togglePalmRejection() {
    setState(() => _palmRejection = !_palmRejection);
    DrawingPrefs.savePalm(_palmRejection);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.header != null) widget.header!,
              _buildToolbar(),
              _buildCanvas(),
              _buildResizeStrip(),
            ],
          ),
          if (_eyedropperMode)
            Positioned(
              left: 0,
              right: 0,
              top: (widget.header != null ? 48 : 0) + 50,
              child: Center(
                child: _EyedropperHint(onCancel: _exitEyedropper),
              ),
            ),
          if (_widthPickerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleWidthPicker,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: (widget.header != null ? 48 : 0) + 50,
              child: Align(
                alignment: Alignment.topCenter,
                child: StrokeWidthPopup(
                  currentWidth: _strokeW,
                  recentWidths: _recentWidths,
                  accentColor: widget.accent ?? yAmber,
                  onPreview: (v) => setState(() => _strokeW = v),
                  onCommit: _commitWidth,
                  onClose: _toggleWidthPicker,
                ),
              ),
            ),
          ],
          if (_colorPickerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleColorPicker,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: (widget.header != null ? 48 : 0) + 50,
              child: Align(
                alignment: Alignment.topCenter,
                child: ColorPickerPopup(
                  currentColor: _color,
                  recentColors: _recentColors,
                  savedColors: _savedColors,
                  onPreview: (c) => setState(() => _color = c),
                  onCommit: _commitColor,
                  onStar: _starColor,
                  onEyedropper: _enterEyedropper,
                  onClose: _toggleColorPicker,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolBtn(
              icon: _locked ? Icons.lock : Icons.lock_open,
              active: _locked,
              onTap: _toggleLock,
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.edit_outlined,
              active: _tool == DrawTool.pen,
              onTap: () => _selectTool(DrawTool.pen),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.gesture,
              active: _tool == DrawTool.fountainPen,
              onTap: () => _selectTool(DrawTool.fountainPen),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.highlight,
              active: _tool == DrawTool.highlighter,
              onTap: () => _selectTool(DrawTool.highlighter),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.auto_fix_high,
              active: _tool == DrawTool.eraser,
              onTap: () => _selectTool(DrawTool.eraser),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.highlight_alt,
              active: _tool == DrawTool.lasso,
              label: 'LAZO',
              onTap: () => _selectTool(DrawTool.lasso),
            ),
            _divider(),
            ColorButton(
              currentColor: _color,
              isOpen: _colorPickerOpen,
              onTap: _toggleColorPicker,
            ),
            if (_savedColors.isNotEmpty) ...[
              const SizedBox(width: 4),
              SavedColorsStrip(
                savedColors: _savedColors,
                currentColor: _color,
                onPick: (c) {
                  setState(() => _color = c);
                  _commitColor(c);
                },
              ),
            ],
            const SizedBox(width: 4),
            _divider(),
            StrokeWidthButton(
              currentWidth: _strokeW,
              isOpen: _widthPickerOpen,
              accentColor: widget.accent ?? yAmber,
              onTap: _toggleWidthPicker,
            ),
            const SizedBox(width: 4),
            _divider(),
            _toolBtn(
              icon: Icons.undo,
              active: false,
              enabled: _undoStack.isNotEmpty,
              onTap: _undo,
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.redo,
              active: false,
              enabled: _redoStack.isNotEmpty,
              onTap: _redo,
            ),
            _divider(),
            _toolBtn(
              icon: Icons.auto_graph,
              active: _stabilizer.isOn,
              label: _stabilizer.label,
              onTap: () {
                setState(() => _stabilizer = _stabilizer.next);
                DrawingPrefs.saveStabilizer(_stabilizer);
              },
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.back_hand_outlined,
              active: _palmRejection,
              label: 'PALMA',
              onTap: _togglePalmRejection,
            ),
            const SizedBox(width: 8),
            _toolBtn(
              icon: Icons.delete_outline,
              active: false,
              onTap: _confirmClear,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    if (_data.strokes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Borrar dibujo',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text('¿Borrar todos los trazos del bloque?',
            style: yBody(size: 13)),
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
    if (ok == true) _clearAll();
  }

  Widget _buildCanvas() {
    final canvas = Container(
      height: _data.height,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: yCream,
      ),
      child: ClipRect(
        child: Stack(
          children: [
            CustomPaint(
              painter: _StrokePainter(
                strokes: _data.strokes,
                active: _active,
                hiddenIndices: (_lassoCtrl.phase == LassoPhase.moving ||
                        _lassoCtrl.phase == LassoPhase.resizing ||
                        _lassoCtrl.phase == LassoPhase.rotating)
                    ? _lassoCtrl.selectedIndices
                    : null,
              ),
              size: Size.infinite,
            ),
            if (_lassoCtrl.phase != LassoPhase.idle)
              AnimatedBuilder(
                animation: _lassoAnimCtrl,
                builder: (_, _) => CustomPaint(
                  painter: LassoPainter(
                    ctrl: _lassoCtrl,
                    animValue: _lassoAnimCtrl.value,
                    strokes: _data.strokes,
                  ),
                  size: Size.infinite,
                ),
              ),
            if (!_locked)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'BLOQUEAR SCROLL PARA DIBUJAR',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!_locked) return canvas;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_eyedropperMode) {
          _activePointers.add(e.pointer);
          _pointerDownPos[e.pointer] = e.localPosition;
          _sampleAt(e.localPosition);
          return;
        }
        _activePointers.add(e.pointer);
        _pointerDownPos[e.pointer] = e.localPosition;
        if (_activePointers.length > _maxSimultaneous) {
          _maxSimultaneous = _activePointers.length;
        }
        if (_activePointers.length == 2) {
          _multiFingerDownTime = DateTime.now();
          _multiFingerMoved = false;
          setState(() => _active = null);
          return;
        }
        if (_activePointers.length > 2) return;

        final isStylus = e.kind == PointerDeviceKind.stylus ||
            e.kind == PointerDeviceKind.invertedStylus;

        if (_showPasteAt != null) {
          setState(() => _showPasteAt = null);
          return;
        }

        final isFinger = !isStylus;
        if (_lassoCtrl.hasClipboard && _activePointers.length == 1 &&
            _lassoCtrl.phase == LassoPhase.idle) {
          final canPaste = (isFinger && _palmRejection) || _tool == DrawTool.lasso;
          if (canPaste) {
            _pastePos = e.localPosition;
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

        if (_tool == DrawTool.lasso && isFinger && _palmRejection) {
          if (_lassoCtrl.phase == LassoPhase.selected) {
            final pos = e.localPosition;
            if (_lassoCtrl.hitTestRotationHandle(pos) ||
                _lassoCtrl.hitTestCornerHandle(pos) != null ||
                _lassoCtrl.hitTestSideHandle(pos) != null ||
                _lassoCtrl.isTapInsideBoundingBox(pos)) {
              _start(pos);
              return;
            }
            _lassoCtrl.deselect();
          }
          return;
        }

        if (!_shouldAcceptPointer(e.kind)) return;

        if (_tool == DrawTool.fountainPen) {
          _stab = _newStabilizer();
          final p = _stabilize(e.localPosition);
          final pressure = e.pressure.isFinite ? e.pressure : 0.5;
          setState(() {
            _active = DrawingStroke(
              colorValue: _color.toARGB32(),
              strokeWidth: _strokeW,
              isFountainPen: true,
              points: [
                [
                  p.dx,
                  p.dy,
                  pressure,
                  DateTime.now().millisecondsSinceEpoch.toDouble(),
                ],
              ],
            );
          });
          widget.onDrawStart();
          return;
        }

        _start(e.localPosition);
      },
      onPointerMove: (e) {
        if (_activePointers.length >= 2 && !_multiFingerMoved) {
          final start = _pointerDownPos[e.pointer];
          if (start != null && (e.localPosition - start).distance > 15) {
            _multiFingerMoved = true;
          }
        }
        if (_pastePos != null) {
          if ((e.localPosition - _pastePos!).distanceSquared > 400) {
            _pasteTimer?.cancel();
            _pastePos = null;
          }
          return;
        }
        if (_activePointers.length >= 2) return;
        if (!_shouldAcceptPointer(e.kind)) return;
        if (_tool == DrawTool.fountainPen) {
          if (_active == null) return;
          final p = _stabilize(e.localPosition);
          final pressure = e.pressure.isFinite ? e.pressure : 0.5;
          setState(() => _active!.points.add([
            p.dx,
            p.dy,
            pressure,
            DateTime.now().millisecondsSinceEpoch.toDouble(),
          ]));
          return;
        }
        if (_active == null && _tool == DrawTool.pen) return;
        _move(e.localPosition);
      },
      onPointerUp: (e) {
        _activePointers.remove(e.pointer);
        _pointerDownPos.remove(e.pointer);
        if (_activePointers.isEmpty && _maxSimultaneous >= 2) {
          final elapsed = _multiFingerDownTime != null
              ? DateTime.now().difference(_multiFingerDownTime!).inMilliseconds
              : 999;
          if (!_multiFingerMoved && elapsed < 400) {
            if (_maxSimultaneous == 2) _undo();
            if (_maxSimultaneous >= 3) _redo();
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
        if (!_shouldAcceptPointer(e.kind)) return;
        if (_tool == DrawTool.lasso) {
          _handleLassoUp();
          widget.onDrawEnd();
          return;
        }
        if (_tool == DrawTool.eraser) {
          _commitEraseGesture();
          widget.onDrawEnd();
          return;
        }
        if (_tool == DrawTool.fountainPen) {
          _finishFountainStroke();
          _stab = null;
          return;
        }
        _end();
        _stab = null;
      },
      onPointerCancel: (e) {
        _activePointers.remove(e.pointer);
        _pointerDownPos.remove(e.pointer);
        if (_activePointers.isEmpty) _maxSimultaneous = 0;
        if (!_shouldAcceptPointer(e.kind)) return;
        if (_tool == DrawTool.eraser) {
          _commitEraseGesture();
          widget.onDrawEnd();
          return;
        }
        if (_tool == DrawTool.fountainPen) {
          widget.onDrawEnd();
          _active = null;
          _stab = null;
          return;
        }
        _end();
        _stab = null;
      },
        child: canvas,
        ),
        if (_lassoCtrl.phase == LassoPhase.selected &&
            _lassoCtrl.boundingBox != null)
          Positioned(
            left: _lassoCtrl.boundingBox!.center.dx - 80,
            top: _lassoCtrl.boundingBox!.top - 64,
            child: LassoMiniToolbar(
              onDelete: _lassoDelete,
              onDuplicate: _lassoDuplicate,
              onRecognizeText: (widget.onRecognizeText != null &&
                      _selectionHasWriting)
                  ? _recognizeSelection
                  : null,
              onSendToYuli: (widget.onSendToYuli != null &&
                      _selectionHasWriting)
                  ? _sendSelectionToYuli
                  : null,
              onSendMathToYuli: (widget.onSendMathToYuli != null &&
                      _selectionHasWriting)
                  ? _sendMathSelectionToYuli
                  : null,
              palette: _palette,
              onColorChange: (c) => _lassoMutate(
                  () => _lassoCtrl.changeColor(_data.strokes, c.toARGB32())),
              onWidthChange: (w) =>
                  _lassoMutate(() => _lassoCtrl.changeWidth(_data.strokes, w)),
              onFlipH: () =>
                  _lassoMutate(() => _lassoCtrl.flipHorizontal(_data.strokes)),
              onFlipV: () =>
                  _lassoMutate(() => _lassoCtrl.flipVertical(_data.strokes)),
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
                _lassoMutate(() => _lassoCtrl.cutSelected(_data.strokes));
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('CORTADO'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
              },
            ),
          ),
        if (_showPasteAt != null)
          Positioned(
            left: _showPasteAt!.dx - 40,
            top: _showPasteAt!.dy - 40,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _lassoMutate(() => _lassoCtrl.pasteAt(_showPasteAt!, _data.strokes));
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
          ),
      ],
    );
  }

  Widget _buildResizeStrip() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _resizeBtn(Icons.remove, () => _resize(-60)),
          const SizedBox(width: 6),
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                final prev = _data.height;
                _data.height =
                    (_data.height + d.delta.dy).clamp(120.0, 1200.0);
                if (_data.height < prev) _cropStrokes();
              });
              widget.onChanged(_data);
            },
            child: Container(
              width: 36,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineThin),
              ),
              child: const Icon(Icons.swap_vert, size: 14, color: yInk),
            ),
          ),
          const SizedBox(width: 6),
          _resizeBtn(Icons.add, () => _resize(60)),
        ],
      ),
    );
  }

  Widget _resizeBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Icon(icon, size: 14, color: yInk),
      ),
    );
  }

  void _resize(double delta) {
    setState(() {
      final prev = _data.height;
      _data.height = (_data.height + delta).clamp(120.0, 1200.0);
      if (_data.height < prev) _cropStrokes();
    });
    widget.onChanged(_data);
  }

  void _cropStrokes() {
    final h = _data.height;
    final toRemove = <DrawingStroke>[];
    for (final s in _data.strokes) {
      _cropPointsInPlace(s.points, h);
      if (s.points.isEmpty) toRemove.add(s);
    }
    for (final s in toRemove) {
      _data.strokes.remove(s);
    }
    if (_active != null) {
      _cropPointsInPlace(_active!.points, h);
      if (_active!.points.isEmpty) _active = null;
    }
  }

  void _cropPointsInPlace(List<List<double>> points, double h) {
    if (points.isEmpty) return;
    final result = <List<double>>[];
    bool prevInside = points[0][1] <= h;
    if (prevInside) result.add(points[0]);
    for (int i = 1; i < points.length; i++) {
      final currInside = points[i][1] <= h;
      if (prevInside && !currInside) {
        final prev = points[i - 1];
        final curr = points[i];
        final dy = curr[1] - prev[1];
        if (dy.abs() > 0.001) {
          final t = (h - prev[1]) / dy;
          result.add([prev[0] + t * (curr[0] - prev[0]), h]);
        }
      } else if (!prevInside && currInside) {
        final prev = points[i - 1];
        final curr = points[i];
        final dy = curr[1] - prev[1];
        if (dy.abs() > 0.001) {
          final t = (h - prev[1]) / dy;
          result.add([prev[0] + t * (curr[0] - prev[0]), h]);
        }
        result.add(points[i]);
      } else if (currInside) {
        result.add(points[i]);
      }
      prevInside = currInside;
    }
    points
      ..clear()
      ..addAll(result);
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: yInk.withValues(alpha: 0.2),
    );
  }

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
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: label != null ? 8 : 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? yInk : yCream,
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
              size: 14,
              color: active
                  ? yCream
                  : enabled
                      ? yInk
                      : yMuted.withValues(alpha: 0.4),
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
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

}

class _EyedropperHint extends StatelessWidget {
  final VoidCallback onCancel;
  const _EyedropperHint({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.colorize, size: 14, color: yInk),
          const SizedBox(width: 8),
          Text(
            'TOCA UN TRAZO PARA COPIAR EL COLOR',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yInk,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: yInk,
                border: Border.all(color: yInk, width: 1.5),
              ),
              child: Text(
                'CANCELAR',
                style: yMono(
                  size: 9,
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
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────

class _StrokePainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? active;
  final Set<int>? hiddenIndices;

  _StrokePainter({required this.strokes, this.active, this.hiddenIndices});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < strokes.length; i++) {
      if (hiddenIndices != null && hiddenIndices!.contains(i)) continue;
      _draw(canvas, strokes[i]);
    }
    if (active != null) _draw(canvas, active!);
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

class DrawingPreviewPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  const DrawingPreviewPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, s);
    }
  }

  @override
  bool shouldRepaint(DrawingPreviewPainter old) => true;
}

void _draw(Canvas canvas, DrawingStroke stroke) => drawStroke(canvas, stroke);
