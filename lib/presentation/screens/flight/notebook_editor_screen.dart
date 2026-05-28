import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart';
import 'color_picker.dart';
import 'drawing_engine.dart';
import 'fountain_pen_engine.dart';
import 'lasso_controller.dart';
import 'lasso_mini_toolbar.dart';
import 'lasso_painter.dart';
import 'note_cell_model.dart';
import 'notebook_constants.dart';
import 'notebook_page_drawer.dart';
import 'shape_recognizer.dart';
import 'stroke_width_picker.dart';

class NotebookEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final Folder folder;

  const NotebookEditorScreen({
    super.key,
    required this.note,
    required this.folder,
  });

  @override
  ConsumerState<NotebookEditorScreen> createState() =>
      _NotebookEditorScreenState();
}

class _NotebookEditorScreenState extends ConsumerState<NotebookEditorScreen>
    with TickerProviderStateMixin {
  final Map<int, DrawingData> _pageData = {};
  final List<int> _pageBlockIds = [];

  final TransformationController _viewCtrl = TransformationController();
  Color _color = yInk;
  double _strokeW = 3.0;
  DrawTool _tool = DrawTool.pen;
  bool _palmRejection = true;
  DrawingStroke? _active;
  int? _activePageIndex;
  final List<DrawingStroke> _undoStack = [];
  int? _undoPageIndex;
  bool _isDrawing = false;
  bool _stylusActive = false;
  bool _headerCollapsed = true;
  final Set<int> _activePointers = {};
  Timer? _holdTimer;
  Offset? _holdAnchor;
  static const _holdTolerance2 = 400.0;
  late final List<Color> _palette;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  late final AnimationController _pullAnimCtrl;
  bool _pendingPageAdd = false;
  bool _scrollApplied = false;
  bool _reachedPullThreshold = false;
  PageBackground _pageBackground = PageBackground.blank;
  Matrix4? _transformBeforeStylus;

  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  Timer? _pasteTimer;
  Offset? _pastePos;
  Offset? _showPasteAt;

  bool _pageDrawerOpen = false;
  late final AnimationController _drawerAnimCtrl;
  late final Animation<Offset> _drawerSlide;
  final Set<int> _starredBlockIds = {};
  int _drawerSnapshotPage = 0;

  bool _widthPickerOpen = false;
  List<double> _recentWidths = const [3.0, 6.0, 10.0];

  bool _colorPickerOpen = false;
  List<Color> _recentColors = const [];
  List<Color> _savedColors = const [];
  bool _eyedropperMode = false;

  @override
  void initState() {
    super.initState();
    _palette = buildPenPalette(widget.folder.color);
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _pullAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _drawerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _drawerSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _drawerAnimCtrl,
      curve: Curves.easeOutCubic,
    ));
    _lassoCtrl.onChanged = () => setState(() {});
    StrokeWidthPrefs.load().then((widths) {
      if (!mounted) return;
      setState(() {
        _recentWidths = widths;
        if (widths.isNotEmpty) _strokeW = widths.first;
      });
    });
    ColorPalettePrefs.load().then((colors) {
      if (!mounted) return;
      setState(() {
        _recentColors = colors;
        if (colors.isNotEmpty) _color = colors.first;
      });
    });
    SavedColorsPrefs.load().then((colors) {
      if (!mounted) return;
      setState(() => _savedColors = colors);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialScroll();
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _pullAnimCtrl.dispose();
    _drawerAnimCtrl.dispose();
    _viewCtrl.dispose();
    super.dispose();
  }

  // ─── Page management ───────────────────────────────────────────────────

  Future<void> _loadPages() async {
    final repo = ref.read(noteBlockRepositoryProvider);
    final blocks = await repo.getByNote(widget.note.id);
    final drawingBlocks = blocks.whereType<DrawingBlock>().toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    if (drawingBlocks.isEmpty) {
      await _ensurePageAt(0);
    } else {
      for (final b in drawingBlocks) {
        _pageBlockIds.add(b.id);
        _pageData[b.id] = _decodeData(b);
        try {
          if (b.payloadJson()['starred'] == true) {
            _starredBlockIds.add(b.id);
          }
        } catch (_) {}
      }
      _readBackground(drawingBlocks.first);
    }

    // Read notebook-level background preference
    if (widget.note.rawMarkdown.isNotEmpty) {
      try {
        final meta = jsonDecode(widget.note.rawMarkdown);
        if (meta is Map && meta['pageBackground'] != null) {
          _pageBackground = PageBackground.fromString(meta['pageBackground']);
        }
      } catch (_) {}
    }

    setState(() {});
  }

  void _applyInitialScroll() {
    if (_scrollApplied || _pageBlockIds.isEmpty) return;
    _scrollApplied = true;
    final lastPageTop = (_pageBlockIds.length - 1) *
        (kNotebookPageHeight + kNotebookPageGap);
    final vw = MediaQuery.of(context).size.width;
    final dx = (vw - kNotebookPageWidth) / 2;
    final dy = -lastPageTop + 40;
    _viewCtrl.value = Matrix4.translationValues(dx, dy, 0);
  }

  void _readBackground(DrawingBlock b) {
    try {
      final payload = b.payloadJson();
      final bg = payload['bg'];
      if (bg is String) {
        _pageBackground = PageBackground.fromString(bg);
      }
    } catch (_) {}
  }

  DrawingData _decodeData(DrawingBlock b) {
    List<dynamic> strokes = const [];
    try {
      final decoded = jsonDecode(b.strokesJson);
      if (decoded is List) strokes = decoded;
    } catch (_) {}
    return DrawingData.fromJson({'h': kNotebookPageHeight, 's': strokes});
  }

  Future<void> _ensurePageAt(int pageIndex) async {
    final repo = ref.read(noteBlockRepositoryProvider);
    while (_pageBlockIds.length <= pageIndex) {
      final block = await repo.insertAtEnd(
        widget.note.id,
        NoteBlockType.drawing,
        payload: {
          'h': kNotebookPageHeight,
          's': [],
          'bg': _pageBackground.toDbString(),
        },
      ) as DrawingBlock;
      _pageBlockIds.add(block.id);
      _pageData[block.id] = DrawingData(height: kNotebookPageHeight);
    }
    setState(() {});
  }

  void _addPageAtEnd() {
    if (_pendingPageAdd) return;
    _pendingPageAdd = true;
    _ensurePageAt(_pageBlockIds.length)
        .then((_) => _pendingPageAdd = false);
  }

  Future<void> _persistPage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) return;
    await ref.read(noteBlockRepositoryProvider).updatePayload(blockId, {
      'h': kNotebookPageHeight,
      's': data.strokes.map((s) => s.toJson()).toList(),
      'bg': _pageBackground.toDbString(),
      'starred': _starredBlockIds.contains(blockId),
    });
  }

  // ─── Width picker ──────────────────────────────────────────────────────

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
    });
    StrokeWidthPrefs.save(_recentWidths);
  }

  void _commitColor(Color value) {
    setState(() {
      _color = value;
      _recentColors = ColorPalettePrefs.push(_recentColors, value);
    });
    ColorPalettePrefs.save(_recentColors);
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

  void _enterEyedropper() {
    setState(() {
      _eyedropperMode = true;
      _colorPickerOpen = false;
      _widthPickerOpen = false;
      _tool = DrawTool.pen;
      _lassoCtrl.deselect();
    });
    HapticFeedback.lightImpact();
  }

  void _exitEyedropper() {
    setState(() => _eyedropperMode = false);
  }

  bool _sampleAt(int pageIndex, Offset localOnPage) {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) {
      _exitEyedropper();
      return false;
    }
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) {
      _exitEyedropper();
      return false;
    }
    final c = sampleStrokeColorAt(data.strokes, localOnPage);
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

  // ─── Page drawer ───────────────────────────────────────────────────────

  void _togglePageDrawer() {
    if (_pageDrawerOpen) {
      _drawerAnimCtrl.reverse().then((_) {
        if (mounted) setState(() => _pageDrawerOpen = false);
      });
    } else {
      _drawerSnapshotPage = _currentVisiblePage;
      setState(() => _pageDrawerOpen = true);
      _drawerAnimCtrl.forward();
    }
  }

  void _navigateToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final pageTop = pageIndex * (kNotebookPageHeight + kNotebookPageGap);
    final vw = MediaQuery.of(context).size.width;
    final dx = (vw - kNotebookPageWidth) / 2;
    final dy = -pageTop + 40;
    _viewCtrl.value = Matrix4.translationValues(dx, dy, 0);
    _togglePageDrawer();
  }

  Future<void> _toggleStarred(int blockId) async {
    final idx = _pageBlockIds.indexOf(blockId);
    if (idx < 0) return;
    setState(() {
      if (_starredBlockIds.contains(blockId)) {
        _starredBlockIds.remove(blockId);
      } else {
        _starredBlockIds.add(blockId);
      }
    });
    await _persistPage(idx);
    HapticFeedback.lightImpact();
  }

  Future<void> _deletePage(int pageIndex) async {
    if (_pageBlockIds.length <= 1) return;
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    final repo = ref.read(noteBlockRepositoryProvider);

    setState(() {
      _pageBlockIds.removeAt(pageIndex);
      _pageData.remove(blockId);
      _starredBlockIds.remove(blockId);
      if (_activePageIndex == pageIndex) _activePageIndex = null;
      if (_undoPageIndex == pageIndex) {
        _undoPageIndex = null;
        _undoStack.clear();
      }
      if (_drawerSnapshotPage >= _pageBlockIds.length) {
        _drawerSnapshotPage = _pageBlockIds.length - 1;
      }
    });

    await repo.delete(blockId);
    await repo.reorder(widget.note.id, List<int>.from(_pageBlockIds));
    HapticFeedback.lightImpact();
  }

  Future<void> _reorderPages(int oldUnstarredIdx, int newUnstarredIdx) async {
    final unstarred = <int>[];
    for (final id in _pageBlockIds) {
      if (!_starredBlockIds.contains(id)) unstarred.add(id);
    }
    if (oldUnstarredIdx < 0 || oldUnstarredIdx >= unstarred.length) return;

    final adjusted = newUnstarredIdx > oldUnstarredIdx
        ? newUnstarredIdx - 1
        : newUnstarredIdx;
    final movedId = unstarred.removeAt(oldUnstarredIdx);
    unstarred.insert(adjusted.clamp(0, unstarred.length), movedId);

    final newOrder = <int>[];
    int unstarredCursor = 0;
    for (final id in _pageBlockIds) {
      if (_starredBlockIds.contains(id)) {
        newOrder.add(id);
      } else {
        newOrder.add(unstarred[unstarredCursor++]);
      }
    }

    setState(() {
      _pageBlockIds
        ..clear()
        ..addAll(newOrder);
      _activePageIndex = null;
      _undoPageIndex = null;
      _undoStack.clear();
    });

    await ref
        .read(noteBlockRepositoryProvider)
        .reorder(widget.note.id, newOrder);
    HapticFeedback.lightImpact();
  }

  Future<void> _saveBackgroundPreference() async {
    await ref.read(noteRepositoryProvider).update(
          widget.note.copyWith(
            rawMarkdown: jsonEncode({'pageBackground': _pageBackground.toDbString()}),
          ),
        );
    for (int i = 0; i < _pageBlockIds.length; i++) {
      await _persistPage(i);
    }
  }

  double get _totalCanvasHeight {
    final pages = _pageBlockIds.length.clamp(1, 9999);
    return pages * kNotebookPageHeight + (pages - 1) * kNotebookPageGap + 300;
  }

  // ─── Coordinate transforms ────────────────────────────────────────────

  Offset _screenToWorld(Offset screen) {
    final inv = Matrix4.copy(_viewCtrl.value)..invert();
    final m = inv.storage;
    final w = m[3] * screen.dx + m[7] * screen.dy + m[15];
    final x = (m[0] * screen.dx + m[4] * screen.dy + m[12]) / w;
    final y = (m[1] * screen.dx + m[5] * screen.dy + m[13]) / w;
    return Offset(x, y);
  }

  int _pageIndexFromWorldY(double worldY) {
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final pageTop = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageBottom = pageTop + kNotebookPageHeight;
      if (worldY >= pageTop && worldY < pageBottom) return i;
    }
    final lastBottom = _pageBlockIds.isNotEmpty
        ? (_pageBlockIds.length - 1) * (kNotebookPageHeight + kNotebookPageGap) +
            kNotebookPageHeight
        : 0.0;
    if (worldY >= lastBottom) return _pageBlockIds.length;
    return -1;
  }

  Offset _worldToPageLocal(Offset world, int pageIndex) {
    final pageTop = pageIndex * (kNotebookPageHeight + kNotebookPageGap);
    return Offset(world.dx, world.dy - pageTop);
  }

  // ─── Drawing helpers ───────────────────────────────────────────────────

  bool _shouldDraw(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      return true;
    }
    if (!_palmRejection) return true;
    return false;
  }

  DrawingData? _activePageData() {
    if (_activePageIndex == null || _activePageIndex! >= _pageBlockIds.length) {
      return null;
    }
    return _pageData[_pageBlockIds[_activePageIndex!]];
  }

  bool _tryShapeSnap() {
    if (_active == null || _activePageIndex == null) return false;
    final cleaned = ShapeRecognizer.detect(_active!.points);
    if (cleaned == null) return false;
    final clean =
        shapeToStroke(cleaned, _active!.colorValue, _active!.strokeWidth);
    final data = _activePageData();
    if (data == null) return false;
    setState(() {
      data.strokes.add(clean);
      _active = null;
      _undoStack.clear();
    });
    _persistPage(_activePageIndex!);
    HapticFeedback.lightImpact();
    return true;
  }

  void _startHoldTimer(Offset worldPos) {
    _holdTimer?.cancel();
    _holdAnchor = worldPos;
    _holdTimer = Timer(const Duration(milliseconds: 800), _tryShapeSnap);
  }

  // ─── Pointer events ────────────────────────────────────────────────────

  Rect? _lassoToolbarScreenRect() {
    if (_lassoCtrl.phase != LassoPhase.selected ||
        _lassoCtrl.boundingBox == null) return null;
    final bb = _lassoCtrl.boundingBox!;
    final topCenter = Offset(bb.center.dx, bb.top - 64);
    final screenPos = MatrixUtils.transformPoint(_viewCtrl.value, topCenter);
    return Rect.fromLTWH(screenPos.dx - 100, screenPos.dy - 10, 200, 80);
  }

  void _onDown(PointerDownEvent e) {
    if (_eyedropperMode) {
      final world = _screenToWorld(e.localPosition);
      final pageIdx = _pageIndexFromWorldY(world.dy);
      if (pageIdx < 0) {
        _exitEyedropper();
        return;
      }
      _sampleAt(pageIdx, _worldToPageLocal(world, pageIdx));
      return;
    }
    final tbRect = _lassoToolbarScreenRect();
    if (tbRect != null && tbRect.contains(e.localPosition)) return;
    if (_showPasteAt != null) {
      final sp = MatrixUtils.transformPoint(_viewCtrl.value, _showPasteAt!);
      if ((e.localPosition - sp).distance < 60) return;
    }

    _activePointers.add(e.pointer);
    _pointerDownPos[e.pointer] = e.localPosition;
    if (_activePointers.length > _maxSimultaneous) {
      _maxSimultaneous = _activePointers.length;
    }
    if (_activePointers.length == 2) {
      _multiFingerDownTime = DateTime.now();
      _multiFingerMoved = false;
    }

    final isStylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (isStylus) {
      _stylusActive = true;
      if (_palmRejection) {
        _transformBeforeStylus = Matrix4.copy(_viewCtrl.value);
      }
    }

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

    final isFinger = !isStylus;

    // Paste via long-press
    if (_lassoCtrl.hasClipboard && _activePointers.length == 1) {
      final canPaste =
          (isFinger && _palmRejection) || _tool == DrawTool.lasso;
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

    // Lasso + palm rejection + finger
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

    final world = _screenToWorld(e.localPosition);
    var pageIdx = _pageIndexFromWorldY(world.dy);

    if (pageIdx < 0) return;
    if (pageIdx >= _pageBlockIds.length) {
      _ensurePageAt(pageIdx);
      if (pageIdx >= _pageBlockIds.length) return;
    }

    _activePageIndex = pageIdx;
    final local = _worldToPageLocal(world, pageIdx);

    if (_tool == DrawTool.lasso) {
      _handleLassoDown(world);
      return;
    }
    if (_tool == DrawTool.eraser) {
      _eraseNear(local, pageIdx);
      return;
    }

    if (_undoPageIndex != pageIdx) {
      _undoStack.clear();
      _undoPageIndex = pageIdx;
    }

    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() {
        _active = DrawingStroke(
          colorValue: _color.toARGB32(),
          strokeWidth: _strokeW,
          isFountainPen: true,
          points: [
            [
              local.dx,
              local.dy,
              pressure,
              DateTime.now().millisecondsSinceEpoch.toDouble(),
            ],
          ],
        );
      });
      return;
    }

    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        points: [
          [local.dx, local.dy]
        ],
      );
    });
    _startHoldTimer(world);
  }

  static const _minDist2 = 9.0;

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

    final world = _screenToWorld(e.localPosition);

    if (_tool == DrawTool.lasso) {
      _handleLassoMove(world);
      return;
    }
    if (_activePageIndex == null) return;
    final local = _worldToPageLocal(world, _activePageIndex!);

    if (_tool == DrawTool.eraser) {
      _eraseNear(local, _activePageIndex!);
      return;
    }
    if (_active == null) return;
    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() => _active!.points.add([
        local.dx,
        local.dy,
        pressure,
        DateTime.now().millisecondsSinceEpoch.toDouble(),
      ]));
      return;
    }
    final pts = _active!.points;
    if (pts.isNotEmpty) {
      final dx = local.dx - pts.last[0];
      final dy = local.dy - pts.last[1];
      if (dx * dx + dy * dy < _minDist2) return;
    }
    setState(() => pts.add([local.dx, local.dy]));
    if (_holdAnchor != null) {
      final dx = world.dx - _holdAnchor!.dx;
      final dy = world.dy - _holdAnchor!.dy;
      if (dx * dx + dy * dy > _holdTolerance2) {
        _startHoldTimer(world);
      }
    }
  }

  void _onUp(PointerUpEvent e) {
    _activePointers.remove(e.pointer);
    _pointerDownPos.remove(e.pointer);
    _holdTimer?.cancel();
    _holdAnchor = null;
    if (_stylusActive && _transformBeforeStylus != null && _palmRejection) {
      _viewCtrl.value = _transformBeforeStylus!;
      _transformBeforeStylus = null;
    }
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

    if (_reachedPullThreshold && _activePointers.isEmpty) {
      _reachedPullThreshold = false;
      _addPageAtEnd();
      return;
    }

    if (_pastePos != null) {
      _pasteTimer?.cancel();
      _pastePos = null;
      return;
    }

    if (_tool == DrawTool.lasso) {
      _handleLassoUp();
      return;
    }
    if (_tool == DrawTool.fountainPen) {
      _finishFountainStroke();
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
    if (_tool == DrawTool.fountainPen) {
      _active = null;
      return;
    }
    _finishStroke();
  }

  void _finishStroke() {
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      return;
    }

    final data = _activePageData();
    if (data == null) {
      setState(() => _active = null);
      return;
    }

    if (_tool == DrawTool.pen && isScribble(_active!.points)) {
      final bounds = scribbleBounds(_active!.points);
      final before = data.strokes.length;
      data.strokes.removeWhere((s) {
        for (final p in s.points) {
          if (bounds.contains(Offset(p[0], p[1]))) return true;
        }
        return false;
      });
      setState(() => _active = null);
      if (data.strokes.length != before) {
        HapticFeedback.lightImpact();
        _persistPage(_activePageIndex!);
      }
      return;
    }

    _active = DrawingStroke(
      colorValue: _active!.colorValue,
      strokeWidth: _active!.strokeWidth,
      points: smoothPoints(_active!.points),
    );
    setState(() {
      data.strokes.add(_active!);
      _active = null;
      _undoStack.clear();
    });
    _persistPage(_activePageIndex!);
  }

  void _finishFountainStroke() {
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.length < 2) {
      setState(() => _active = null);
      return;
    }

    final data = _activePageData();
    if (data == null) {
      setState(() => _active = null);
      return;
    }

    final baked = FountainPenEngine.finishStroke(_active!);
    setState(() {
      data.strokes.add(baked);
      _active = null;
      _undoStack.clear();
    });
    _persistPage(_activePageIndex!);
  }

  void _eraseNear(Offset local, int pageIndex) {
    const r2 = 24.0 * 24.0;
    final data = _pageData[_pageBlockIds[pageIndex]];
    if (data == null) return;
    final before = data.strokes.length;
    data.strokes.removeWhere((s) {
      for (final p in s.points) {
        final dx = p[0] - local.dx;
        final dy = p[1] - local.dy;
        if (dx * dx + dy * dy < r2) return true;
      }
      return false;
    });
    if (data.strokes.length != before) {
      setState(() {});
      _persistPage(pageIndex);
    }
  }

  // ─── Lasso ─────────────────────────────────────────────────────────────

  List<DrawingStroke> get _allVisibleStrokes {
    final all = <DrawingStroke>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = i * (kNotebookPageHeight + kNotebookPageGap);
      for (final s in data.strokes) {
        all.add(DrawingStroke(
          colorValue: s.colorValue,
          strokeWidth: s.strokeWidth,
          points: s.points.map((p) => [p[0], p[1] + offset]).toList(),
        ));
      }
    }
    return all;
  }

  void _handleLassoDown(Offset worldPos) {
    _pasteTimer?.cancel();
    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }
    final strokes = _allVisibleStrokes;
    if (_lassoCtrl.phase == LassoPhase.selected) {
      if (_lassoCtrl.hitTestRotationHandle(worldPos)) {
        _lassoCtrl.startRotation(worldPos, strokes);
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(worldPos);
      if (corner != null) {
        _lassoCtrl.startResize(corner, worldPos, strokes);
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(worldPos);
      if (side != null) {
        _lassoCtrl.startSideResize(side, worldPos, strokes);
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(worldPos)) {
        _lassoCtrl.startMove(worldPos, strokes);
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
    final strokes = _allVisibleStrokes;
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.finishTracing(strokes);
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      _lassoCtrl.finishMove(strokes);
      _syncLassoStrokesToPages(strokes);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      _lassoCtrl.isSideResize
          ? _lassoCtrl.finishSideResize(strokes)
          : _lassoCtrl.finishResize(strokes);
      _syncLassoStrokesToPages(strokes);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      _lassoCtrl.finishRotation(strokes);
      _syncLassoStrokesToPages(strokes);
    }
  }

  void _syncLassoStrokesToPages(List<DrawingStroke> worldStrokes) {
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final pageTop = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageBottom = pageTop + kNotebookPageHeight;
      final pageStrokes = <DrawingStroke>[];
      for (final s in worldStrokes) {
        final inPage = s.points.any(
            (p) => p[1] >= pageTop && p[1] < pageBottom);
        if (inPage) {
          pageStrokes.add(DrawingStroke(
            colorValue: s.colorValue,
            strokeWidth: s.strokeWidth,
            points: s.points.map((p) => [p[0], p[1] - pageTop]).toList(),
          ));
        }
      }
      _pageData[_pageBlockIds[i]] =
          DrawingData(height: kNotebookPageHeight, strokes: pageStrokes);
      _persistPage(i);
    }
    setState(() {});
  }

  void _lassoDelete() {
    final strokes = _allVisibleStrokes;
    _lassoCtrl.deleteSelected(strokes);
    _syncLassoStrokesToPages(strokes);
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    final strokes = _allVisibleStrokes;
    _lassoCtrl.duplicateSelected(strokes);
    _syncLassoStrokesToPages(strokes);
    HapticFeedback.lightImpact();
  }

  // ─── Undo / redo ───────────────────────────────────────────────────────

  void _undo() {
    if (_undoPageIndex == null) return;
    final data = _pageData[_pageBlockIds[_undoPageIndex!]];
    if (data == null || data.strokes.isEmpty) return;
    setState(() => _undoStack.add(data.strokes.removeLast()));
    _persistPage(_undoPageIndex!);
  }

  void _redo() {
    if (_undoPageIndex == null || _undoStack.isEmpty) return;
    final data = _pageData[_pageBlockIds[_undoPageIndex!]];
    if (data == null) return;
    setState(() => data.strokes.add(_undoStack.removeLast()));
    _persistPage(_undoPageIndex!);
  }

  // ─── Current page ──────────────────────────────────────────────────────

  Color get _accent => widget.note.color ?? widget.folder.color;

  int get _currentVisiblePage {
    if (_pageBlockIds.isEmpty) return 0;
    final inv = Matrix4.inverted(_viewCtrl.value);
    final center = MatrixUtils.transformPoint(
        inv,
        Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        ));
    final idx = _pageIndexFromWorldY(center.dy);
    return idx.clamp(0, _pageBlockIds.length - 1);
  }

  Map<int, Set<int>> _hiddenStrokes() {
    if (_lassoCtrl.phase != LassoPhase.moving &&
        _lassoCtrl.phase != LassoPhase.resizing &&
        _lassoCtrl.phase != LassoPhase.rotating) {
      return {};
    }
    if (_lassoCtrl.selectedIndices.isEmpty) return {};
    final hidden = <int, Set<int>>{};
    int globalIdx = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      final count = data?.strokes.length ?? 0;
      for (int j = 0; j < count; j++) {
        if (_lassoCtrl.selectedIndices.contains(globalIdx + j)) {
          hidden.putIfAbsent(i, () => {}).add(j);
        }
      }
      globalIdx += count;
    }
    return hidden;
  }

  // ─── Build ─────────────────────────────────────────────────────────────

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
          final strokes = _allVisibleStrokes;
          _lassoCtrl.changeColor(strokes, c.toARGB32());
          _syncLassoStrokesToPages(strokes);
        },
        onWidthChange: (w) {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.changeWidth(strokes, w);
          _syncLassoStrokesToPages(strokes);
        },
        onFlipH: () {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.flipHorizontal(strokes);
          _syncLassoStrokesToPages(strokes);
        },
        onFlipV: () {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.flipVertical(strokes);
          _syncLassoStrokesToPages(strokes);
        },
        onCopy: () {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.copySelected(strokes);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('COPIADO'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onCut: () {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.cutSelected(strokes);
          _syncLassoStrokesToPages(strokes);
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
    final screenPos =
        MatrixUtils.transformPoint(_viewCtrl.value, _showPasteAt!);
    return Positioned(
      left: screenPos.dx - 40,
      top: screenPos.dy - 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final strokes = _allVisibleStrokes;
          _lassoCtrl.pasteAt(_showPasteAt!, strokes);
          _syncLassoStrokesToPages(strokes);
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
            style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yInk),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: yCream,
      body: Stack(
        children: [
          Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_headerCollapsed)
            SafeArea(
              child: _CollapsedNotebookHeader(
                folder: widget.folder,
                pageCount: _pageBlockIds.length,
                background: _pageBackground,
                accent: _accent,
                onExpand: () => setState(() => _headerCollapsed = false),
                onOpenPages: _togglePageDrawer,
              ),
            )
          else ...[
            SafeArea(
              child: ModeHeader(
                mode: 'CUADERNO',
                subtitle:
                    'A4 · ${_pageBlockIds.length} PÁGINAS · ${_pageBackground.name.toUpperCase()}',
                color: _accent,
                onBack: () => Navigator.pop(context),
                headerRight: [
                  YBadge(
                    label: '@${widget.folder.name}',
                    bg: widget.folder.color,
                    fg: yCream,
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _togglePageDrawer,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(color: yInk, width: yLineMid),
                      ),
                      child: const Icon(Icons.auto_stories, color: yInk, size: 18),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _headerCollapsed = true),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(color: yInk, width: yLineMid),
                      ),
                      child: const Icon(Icons.keyboard_arrow_up, color: yInk, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: _pageBlockIds.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (ctx, c) {
                    return AnimatedBuilder(
                      animation: _viewCtrl,
                      builder: (_, _) {
                        final inv = Matrix4.inverted(_viewCtrl.value);
                        final tl =
                            MatrixUtils.transformPoint(inv, Offset.zero);
                        final br = MatrixUtils.transformPoint(
                            inv, Offset(c.maxWidth, c.maxHeight));
                        final visibleRect = Rect.fromPoints(tl, br);

                        final lastPageBottom = _pageBlockIds.isNotEmpty
                            ? (_pageBlockIds.length - 1) *
                                    (kNotebookPageHeight +
                                        kNotebookPageGap) +
                                kNotebookPageHeight
                            : 0.0;
                        final overscroll = br.dy - lastPageBottom;
                        final pull =
                            (overscroll / 150.0).clamp(0.0, 1.0);
                        _reachedPullThreshold = pull >= 1.0;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRect(
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
                                  boundaryMargin: EdgeInsets.symmetric(
                                    horizontal: c.maxWidth,
                                    vertical: _totalCanvasHeight * 0.3,
                                  ),
                                  panEnabled: _tool == DrawTool.lasso
                                      ? (_lassoCtrl.phase ==
                                              LassoPhase.idle &&
                                          !_isDrawing)
                                      : _palmRejection
                                          ? !_stylusActive
                                          : !_isDrawing,
                                  scaleEnabled: _tool == DrawTool.lasso
                                      ? (_lassoCtrl.phase ==
                                              LassoPhase.idle &&
                                          !_isDrawing)
                                      : !_stylusActive,
                                  constrained: false,
                                  child: SizedBox(
                                    width: kNotebookPageWidth,
                                    height: _totalCanvasHeight,
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          painter: _NotebookCanvasPainter(
                                            pageBlockIds: _pageBlockIds,
                                            pageData: _pageData,
                                            active: _active,
                                            activePageIndex:
                                                _activePageIndex,
                                            visibleRect: visibleRect,
                                            background: _pageBackground,
                                            accentColor: _accent,
                                            hiddenStrokes:
                                                _hiddenStrokes(),
                                          ),
                                          size: Size(kNotebookPageWidth,
                                              _totalCanvasHeight),
                                        ),
                                        if (_lassoCtrl.phase !=
                                            LassoPhase.idle)
                                          AnimatedBuilder(
                                            animation: _lassoAnimCtrl,
                                            builder: (_, _) => CustomPaint(
                                              painter: LassoPainter(
                                                ctrl: _lassoCtrl,
                                                animValue:
                                                    _lassoAnimCtrl.value,
                                                strokes:
                                                    _allVisibleStrokes,
                                                visibleRect: visibleRect,
                                              ),
                                              size: Size(
                                                  kNotebookPageWidth,
                                                  _totalCanvasHeight),
                                            ),
                                          ),
                                          if (pull > 0)
                                            Positioned(
                                              top: lastPageBottom + 20,
                                              left: 0,
                                              right: 0,
                                              child: IgnorePointer(
                                                child: Opacity(
                                                  opacity: pull,
                                                  child: Column(
                                                    children: [
                                                      Container(
                                                        width: 40,
                                                        height: 30,
                                                        alignment: Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color: _accent,
                                                          border: Border.all(color: yInk, width: yLineMid),
                                                        ),
                                                        child: Text(
                                                          '+',
                                                          style: ySans(
                                                            size: 20,
                                                            weight: FontWeight.w700,
                                                            color: yCream,
                                                            height: 1.0,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'NUEVA PÁGINA',
                                                        style: TextStyle(
                                                          fontSize: 9 + 3 * _pullAnimCtrl.value,
                                                          fontWeight: FontWeight.w700,
                                                          color: yInk.withValues(alpha: 0.3 + 0.4 * _pullAnimCtrl.value),
                                                          fontFamily: 'monospace',
                                                          letterSpacing: 1.4,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_lassoCtrl.phase == LassoPhase.selected)
                              _buildLassoMiniToolbar(),
                            if (_showPasteAt != null) _buildPasteButton(),
                          ],
                        );
                      },
                    );
                  }),
            ),
            _toolbar(),
          ],
        ),
          if (_pageDrawerOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePageDrawer,
                child: FadeTransition(
                  opacity: _drawerAnimCtrl,
                  child: Container(color: yInk.withValues(alpha: 0.35)),
                ),
              ),
            ),
          if (_pageDrawerOpen)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: MediaQuery.of(context).size.width * 0.40,
              child: SlideTransition(
                position: _drawerSlide,
                child: NotebookPageDrawer(
                  pageBlockIds: _pageBlockIds,
                  pageData: _pageData,
                  starredBlockIds: _starredBlockIds,
                  background: _pageBackground,
                  accentColor: _accent,
                  currentPageIndex: _drawerSnapshotPage,
                  onNavigate: _navigateToPage,
                  onToggleStar: _toggleStarred,
                  onDelete: _deletePage,
                  onReorder: _reorderPages,
                  onClose: _togglePageDrawer,
                  onAddPage: () {
                    _addPageAtEnd();
                    HapticFeedback.lightImpact();
                  },
                ),
              ),
            ),
          if (_eyedropperMode)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
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
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: StrokeWidthPopup(
                  currentWidth: _strokeW,
                  recentWidths: _recentWidths,
                  accentColor: _accent,
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
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
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

  // ─── Toolbar ───────────────────────────────────────────────────────────

  Widget _toolbar() {
    final paddingH = MediaQuery.of(context).size.width * 0.04;
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: paddingH.clamp(8.0, 60.0), vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolBtn(
                icon: Icons.edit_outlined,
                active: _tool == DrawTool.pen,
                onTap: () => setState(() {
                  _tool = DrawTool.pen;
                  _lassoCtrl.deselect();
                }),
              ),
              const SizedBox(width: 12),
              _toolBtn(
                icon: Icons.gesture,
                active: _tool == DrawTool.fountainPen,
                onTap: () => setState(() {
                  _tool = DrawTool.fountainPen;
                  _lassoCtrl.deselect();
                }),
              ),
              const SizedBox(width: 12),
              _toolBtn(
                icon: Icons.auto_fix_high,
                active: _tool == DrawTool.eraser,
                onTap: () => setState(() {
                  _tool = DrawTool.eraser;
                  _lassoCtrl.deselect();
                }),
              ),
              const SizedBox(width: 12),
              _toolBtn(
                icon: Icons.highlight_alt,
                active: _tool == DrawTool.lasso,
                label: 'LAZO',
                onTap: () => setState(() => _tool = DrawTool.lasso),
              ),
              _divider(),
              ColorButton(
                currentColor: _color,
                isOpen: _colorPickerOpen,
                onTap: _toggleColorPicker,
              ),
              if (_savedColors.isNotEmpty) ...[
                const SizedBox(width: 8),
                SavedColorsStrip(
                  savedColors: _savedColors,
                  currentColor: _color,
                  onPick: (c) {
                    setState(() => _color = c);
                    _commitColor(c);
                  },
                ),
              ],
              const SizedBox(width: 10),
              _divider(),
              StrokeWidthButton(
                currentWidth: _strokeW,
                isOpen: _widthPickerOpen,
                accentColor: _accent,
                onTap: _toggleWidthPicker,
              ),
              const SizedBox(width: 10),
              _divider(),
              _toolBtn(
                icon: Icons.undo,
                active: false,
                enabled: _undoPageIndex != null &&
                    _undoPageIndex! < _pageBlockIds.length &&
                    (_pageData[_pageBlockIds[_undoPageIndex!]]
                                ?.strokes
                                .isNotEmpty ??
                            false),
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
                onTap: () =>
                    setState(() => _palmRejection = !_palmRejection),
              ),
              _divider(),
              _bgBtn(),
              _divider(),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent,
                  border: Border.all(color: yInk, width: yLineThin),
                ),
                child: Text(
                  'PG ${_currentVisiblePage + 1}/${_pageBlockIds.length}',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: yCream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bgBtn() {
    final label = switch (_pageBackground) {
      PageBackground.blank => 'BLANCO',
      PageBackground.lined => 'LÍNEAS',
      PageBackground.grid => 'CUADRÍCULA',
      PageBackground.dotted => 'PUNTOS',
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showBackgroundPicker,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_on, size: 14, color: yInk),
            const SizedBox(width: 5),
            Text(label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: yInk,
                )),
          ],
        ),
      ),
    );
  }

  void _showBackgroundPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('FONDO DE PÁGINA',
                  style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted)),
            ),
            for (final bg in PageBackground.values)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _pageBackground = bg);
                  _saveBackgroundPreference();
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(color: yInk, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pageBackground == bg
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: _pageBackground == bg ? _accent : yMuted,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        switch (bg) {
                          PageBackground.blank => 'Blanco',
                          PageBackground.lined => 'Líneas',
                          PageBackground.grid => 'Cuadrícula',
                          PageBackground.dotted => 'Puntos',
                        },
                        style: ySans(
                          size: 15,
                          weight: FontWeight.w600,
                          color: yInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
          color: active ? _accent : yCream,
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

class _CollapsedNotebookHeader extends StatelessWidget {
  final Folder folder;
  final int pageCount;
  final PageBackground background;
  final Color accent;
  final VoidCallback onExpand;
  final VoidCallback onOpenPages;

  const _CollapsedNotebookHeader({
    required this.folder,
    required this.pageCount,
    required this.background,
    required this.accent,
    required this.onExpand,
    required this.onOpenPages,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: const Icon(Icons.arrow_back, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 4, height: 24, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CUADERNO · @${folder.name} · $pageCount PÁG',
              style: ySans(size: 15, weight: FontWeight.w700, letterSpacing: -0.3, color: accent, height: 1.0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenPages,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: const Icon(Icons.auto_stories, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExpand,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: const Icon(Icons.keyboard_arrow_down, color: yInk, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Canvas painter ──────────────────────────────────────────────────────

class _NotebookCanvasPainter extends CustomPainter {
  final List<int> pageBlockIds;
  final Map<int, DrawingData> pageData;
  final DrawingStroke? active;
  final int? activePageIndex;
  final Rect visibleRect;
  final PageBackground background;
  final Color accentColor;
  final Map<int, Set<int>> hiddenStrokes;

  _NotebookCanvasPainter({
    required this.pageBlockIds,
    required this.pageData,
    required this.active,
    required this.activePageIndex,
    required this.visibleRect,
    required this.background,
    required this.accentColor,
    this.hiddenStrokes = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background behind pages
    canvas.drawRect(
      visibleRect,
      Paint()..color = const Color(0xFFF0EDE6),
    );

    for (int i = 0; i < pageBlockIds.length; i++) {
      final pageTop = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageRect = Rect.fromLTWH(
          0, pageTop, kNotebookPageWidth, kNotebookPageHeight);

      if (!pageRect.overlaps(visibleRect)) continue;

      // Page shadow
      canvas.drawRect(
        pageRect.shift(const Offset(4, 4)),
        Paint()..color = yInk.withValues(alpha: 0.12),
      );

      // White page
      canvas.drawRect(pageRect, Paint()..color = const Color(0xFFFFFDF8));

      // Page background pattern
      _drawBackground(canvas, pageRect, background);

      // Page border
      canvas.drawRect(
        pageRect,
        Paint()
          ..color = yInk.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // Page number
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 10,
            color: yMuted.withValues(alpha: 0.4),
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          kNotebookPageWidth - tp.width - 16,
          pageTop + kNotebookPageHeight - tp.height - 12,
        ),
      );

      // Strokes
      canvas.save();
      canvas.clipRect(pageRect);
      canvas.translate(0, pageTop);

      // visibleRect in page-local coordinates (after translate).
      final pageVisible = Rect.fromLTRB(
        visibleRect.left,
        visibleRect.top - pageTop,
        visibleRect.right,
        visibleRect.bottom - pageTop,
      );

      final data = pageData[pageBlockIds[i]];
      if (data != null) {
        final skip = hiddenStrokes[i];
        for (int si = 0; si < data.strokes.length; si++) {
          if (skip != null && skip.contains(si)) continue;
          if (!_strokeInRect(data.strokes[si], pageVisible)) continue;
          drawStroke(canvas, data.strokes[si]);
        }
      }

      if (active != null && activePageIndex == i) {
        drawStroke(canvas, active!);
      }

      canvas.restore();
    }
  }

  bool _strokeInRect(DrawingStroke s, Rect r) {
    for (final p in s.points) {
      if (r.contains(Offset(p[0], p[1]))) return true;
    }
    return false;
  }

  void _drawBackground(Canvas canvas, Rect page, PageBackground bg) {
    switch (bg) {
      case PageBackground.blank:
        break;
      case PageBackground.lined:
        _drawLines(canvas, page);
      case PageBackground.grid:
        _drawGrid(canvas, page);
      case PageBackground.dotted:
        _drawDots(canvas, page);
    }
  }

  void _drawLines(Canvas canvas, Rect page) {
    final paint = Paint()
      ..color = const Color(0xFFD6D1C8)
      ..strokeWidth = 0.5;
    const step = 28.0;
    final startY = page.top + 60;
    for (double y = startY; y < page.bottom - 20; y += step) {
      canvas.drawLine(
        Offset(page.left + 40, y),
        Offset(page.right - 20, y),
        paint,
      );
    }
    canvas.drawLine(
      Offset(page.left + 36, page.top + 40),
      Offset(page.left + 36, page.bottom - 20),
      Paint()
        ..color = accentColor.withValues(alpha: 0.45)
        ..strokeWidth = 0.8,
    );
  }

  void _drawGrid(Canvas canvas, Rect page) {
    final paint = Paint()
      ..color = const Color(0xFFDAD6CE)
      ..strokeWidth = 0.4;
    const step = 28.0;
    for (double y = page.top + step; y < page.bottom; y += step) {
      canvas.drawLine(
          Offset(page.left, y), Offset(page.right, y), paint);
    }
    for (double x = page.left + step; x < page.right; x += step) {
      canvas.drawLine(
          Offset(x, page.top), Offset(x, page.bottom), paint);
    }
  }

  void _drawDots(Canvas canvas, Rect page) {
    final dot = Paint()..color = yMuted.withValues(alpha: 0.2);
    const step = 28.0;
    for (double x = page.left + step; x < page.right; x += step) {
      for (double y = page.top + step; y < page.bottom; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_NotebookCanvasPainter old) =>
      old.visibleRect != visibleRect ||
      old.active != active ||
      old.pageBlockIds.length != pageBlockIds.length ||
      old.background != background ||
      old.hiddenStrokes != hiddenStrokes;
}
