import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import 'background_paint.dart';
import 'background_popup.dart';
import 'color_picker.dart';
import 'drawing_engine.dart';
import 'drawing_prefs.dart';
import 'eraser_mode_popup.dart';
import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';
import 'shape_recognizer.dart';
import 'lasso_controller.dart';
import 'lasso_painter.dart';
import 'lasso_mini_toolbar.dart';
import 'canvas_image_cache.dart';
import 'canvas_task_block.dart';
import 'image_crop_screen.dart';
import 'image_insert_panel.dart';
import 'stroke_stabilizer.dart';
import 'stroke_width_picker.dart';
import '../lab/lab_space_detail_screen.dart';

// World canvas size — large but finite to keep memory bounded. The user
// pans inside this via InteractiveViewer. ~10kx10k logical pixels.
const double _kCanvasW = 10000;
const double _kCanvasH = 10000;

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
  bool _headerCollapsed = true;
  StabilizerLevel _stabilizer = StabilizerLevel.off;
  LiveStabilizer? _stab;
  bool _fillShapes = false;
  final Map<DrawTool, Color> _toolColors = {...DrawingPrefs.defaultColors};
  final Map<DrawTool, double> _toolWidths = {...DrawingPrefs.defaultWidths};
  CanvasImageCache? _imgCache;
  String? _imageDirPath;
  bool _imagePanelOpen = false;
  bool _bgPopupOpen = false;
  bool _bgColorPickerOpen = false;
  EraserMode _eraserMode = EraserMode.stroke;
  bool _eraserPopupOpen = false;
  Offset? _eraserCursor; // screen pos for the eraser indicator
  // Raw (un-stabilized) pen points — used for scribble-erase detection so the
  // stabilizer's smoothing doesn't hide the zigzags.
  List<List<double>> _rawPen = [];
  // Post-snap live adjust state.
  ShapeKind? _snapKind;
  List<List<double>>? _snapBasePoints;
  Offset? _snapCenter;
  Offset? _snapAnchor;
  double _snapRefDist = 1;
  final List<(List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>)>
      _undoStack = [];
  final List<(List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>)>
      _redoStack = [];
  (List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>)?
      _gestureBefore;
  bool _gestureChanged = false;
  DrawingStroke? _active;
  Timer? _holdTimer;
  Offset? _holdAnchor;
  static const _holdTolerance2 = 400.0; // 20px squared
  late final List<Color> _palette;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  Matrix4? _transformBeforeStylus;
  Timer? _pasteTimer;
  Offset? _pastePos;
  Offset? _showPasteAt;

  // Lasso action toolbar is summoned by tapping the selection, not shown on
  // select. Tap outside hides it (selection kept); tap outside again deselects.
  bool _toolbarVisible = false;
  // Down outside an active selection: deferred until we know it's a tap
  // (dismiss) or a drag (fresh lasso). Stylus-only (finger taps go via onTapUp).
  Offset? _pendingLassoStart;

  bool _widthPickerOpen = false;
  List<double> _recentWidths = const [3.0, 6.0, 10.0];

  bool _colorPickerOpen = false;
  List<Color> _recentColors = const [];
  List<Color> _savedColors = const [];
  List<Color> _bgSavedColors = const [];
  bool _eyedropperMode = false;
  bool _lockBeforeEyedropper = false;

  // Multi-finger tap tracking
  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  @override
  void initState() {
    super.initState();
    _palette = buildPenPalette(widget.folder.color);
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
    SavedBgColorsPrefs.load().then((colors) {
      if (!mounted) return;
      setState(() => _bgSavedColors = colors);
    });
    DrawingPrefs.load().then((p) {
      if (!mounted) return;
      setState(() {
        _stabilizer = p.stabilizer;
        _palmRejection = p.palmRejection;
        _fillShapes = p.fillShapes;
        _eraserMode = p.eraserMode;
        _toolColors.addAll(p.toolColors);
        _toolWidths.addAll(p.toolWidths);
        _color = _toolColors[_tool] ?? _color;
        _strokeW = _toolWidths[_tool] ?? _strokeW;
      });
    });
    getApplicationDocumentsDirectory().then((dir) {
      if (!mounted) return;
      final path = p.join(dir.path, 'note_images', '${widget.note.id}');
      setState(() {
        _imageDirPath = path;
        _imgCache = CanvasImageCache(
          dirPath: path,
          onLoaded: () {
            if (mounted) setState(() {});
          },
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanvasBlock());
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

  void _starBgColor(Color value) {
    final isStarred =
        _bgSavedColors.any((c) => c.toARGB32() == value.toARGB32());
    setState(() {
      _bgSavedColors = isStarred
          ? SavedBgColorsPrefs.remove(_bgSavedColors, value)
          : SavedBgColorsPrefs.push(_bgSavedColors, value);
    });
    SavedBgColorsPrefs.save(_bgSavedColors);
    HapticFeedback.selectionClick();
  }

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
    HapticFeedback.lightImpact();
  }

  void _exitEyedropper() {
    setState(() {
      _eyedropperMode = false;
      _locked = _lockBeforeEyedropper;
    });
  }

  bool _sampleAt(Offset world) {
    final c = sampleStrokeColorAt(_data.strokes, world);
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
    _reconcileImageFiles();
    _holdTimer?.cancel();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _imgCache?.dispose();
    _viewCtrl.dispose();
    super.dispose();
  }

  /// On leaving the canvas, delete image files no longer referenced by the
  /// canvas data (orphans from inserts that were later removed). Canvas images
  /// are tracked only in the block payload, so that's the source of truth.
  /// Safe here because the undo history is discarded on exit.
  void _reconcileImageFiles() {
    final dirPath = _imageDirPath;
    if (dirPath == null) return;
    final referenced = _data.images.map((im) => im.filename).toSet();
    // Fire-and-forget; widget is disposing.
    () async {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) return;
        await for (final entity in dir.list()) {
          if (entity is File &&
              !referenced.contains(p.basename(entity.path))) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }();
  }

  bool _tryShapeSnap() {
    if (_active == null) return false;
    // A scribble densely fills a box and would be mis-snapped to a rectangle —
    // leave it for the scribble-erase on pen-up.
    if (isScribble(_rawPen.isNotEmpty ? _rawPen : _active!.points)) return false;
    final shape = ShapeRecognizer.detect(_active!.points);
    if (shape == null) return false;
    _enterShapeAdjust(shape, _active!);
    HapticFeedback.lightImpact();
    return true;
  }

  /// Replace the freehand stroke with clean geometry and enter live-adjust:
  /// the ongoing drag resizes closed shapes (around their centre) or moves the
  /// end point of lines/arrows, until the pen lifts.
  void _enterShapeAdjust(RecognizedShape shape, DrawingStroke src) {
    _holdTimer?.cancel();
    _holdAnchor = null;
    final pts = shape.points.map((p) => [p[0], p[1]]).toList();
    _snapKind = shape.kind;
    if (shape.isOpen) {
      _snapAnchor = Offset(pts.first[0], pts.first[1]);
      _snapBasePoints = null;
      _snapCenter = null;
    } else {
      final c = shapeCentroid(pts);
      _snapCenter = Offset(c[0], c[1]);
      _snapBasePoints = pts.map((p) => [p[0], p[1]]).toList();
      final end = src.points.last;
      _snapRefDist =
          (Offset(end[0], end[1]) - _snapCenter!).distance.clamp(1.0, 1e9);
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: src.colorValue,
        strokeWidth: src.strokeWidth,
        filled: _fillShapes && !shape.isOpen,
        isShape: true,
        points: pts,
      );
    });
  }

  void _updateShapeAdjust(Offset p) {
    if (_active == null || _snapKind == null) return;
    List<List<double>> pts;
    if (_snapKind == ShapeKind.line) {
      pts = buildLineShape(_snapAnchor!.dx, _snapAnchor!.dy, p.dx, p.dy);
    } else if (_snapKind == ShapeKind.arrow) {
      pts = buildArrowShape(_snapAnchor!.dx, _snapAnchor!.dy, p.dx, p.dy);
    } else {
      final ratio =
          ((p - _snapCenter!).distance / _snapRefDist).clamp(0.05, 20.0);
      pts = scaleShape(
          _snapBasePoints!, _snapCenter!.dx, _snapCenter!.dy, ratio);
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: _active!.colorValue,
        strokeWidth: _active!.strokeWidth,
        filled: _active!.filled,
        isShape: true,
        points: pts,
      );
    });
  }

  void _commitShapeAdjust() {
    final shape = _active;
    _clearSnap();
    if (shape == null) return;
    final before = _snapshot();
    setState(() {
      _data.strokes.add(shape);
      _active = null;
    });
    _commit(before);
    _persist();
  }

  void _clearSnap() {
    _snapKind = null;
    _snapBasePoints = null;
    _snapCenter = null;
    _snapAnchor = null;
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
    List<dynamic> images = const [];
    List<dynamic> taskBlocks = const [];
    final payload = b.payloadJson();
    try {
      final decoded = jsonDecode(b.strokesJson);
      if (decoded is List) strokes = decoded;
    } catch (_) {}
    try {
      final decoded = jsonDecode(b.imagesJson);
      if (decoded is List) images = decoded;
    } catch (_) {}
    try {
      final decoded = jsonDecode(b.taskBlocksJson);
      if (decoded is List) taskBlocks = decoded;
    } catch (_) {}
    return DrawingData.fromJson({
      'h': _kCanvasH,
      's': strokes,
      'i': images,
      't': taskBlocks,
      'bg': payload['bg'],
      'bgc': payload['bgc'],
    });
  }

  Future<void> _persist() async {
    if (_blockId == null) return;
    await ref.read(noteBlockRepositoryProvider).updatePayload(_blockId!, {
      'h': _kCanvasH,
      's': _data.strokes.map((s) => s.toJson()).toList(),
      'i': _data.images.map((im) => im.toJson()).toList(),
      't': _data.taskBlocks.map((b) => b.toJson()).toList(),
      'bg': _data.background.toDbString(),
      if (_data.bgColorValue != null) 'bgc': _data.bgColorValue,
      'whiteboard': true,
    });
  }

  void _toggleImagePanel() {
    setState(() {
      _imagePanelOpen = !_imagePanelOpen;
      if (_imagePanelOpen) {
        _colorPickerOpen = false;
        _widthPickerOpen = false;
      }
    });
  }

  void _toggleBgPopup() {
    setState(() {
      _bgPopupOpen = !_bgPopupOpen;
      _bgColorPickerOpen = false;
      if (_bgPopupOpen) {
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _imagePanelOpen = false;
      }
    });
  }

  void _setBgPattern(PageBackground pb) {
    setState(() => _data.background = pb);
    _persist();
  }

  void _setBgColor(Color c) {
    setState(() => _data.bgColorValue = c.toARGB32());
    _persist();
  }

  Widget _eraserModePopup() => EraserModePopup(
        mode: _eraserMode,
        accent: _accent,
        onPick: (m) {
          setState(() {
            _eraserMode = m;
            _eraserPopupOpen = false;
          });
          DrawingPrefs.saveEraserMode(m);
        },
      );

  /// Copy a ready (compressed) file into this note's image folder, place it at
  /// the centre of the current viewport, and record it as an undoable step.
  Future<void> _insertImageFile(File f) async {
    final dirPath = _imageDirPath;
    if (dirPath == null) return;
    final screen = MediaQuery.of(context).size;
    try {
      final bytes = await f.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final iw = frame.image.width.toDouble();
      final ih = frame.image.height.toDouble();
      frame.image.dispose();
      if (iw <= 0 || ih <= 0) return;

      final filename = '${const Uuid().v4()}.jpg';
      await Directory(dirPath).create(recursive: true);
      await f.copy(p.join(dirPath, filename));

      final worldW = (screen.width * 0.5) / _viewScale;
      final worldH = worldW * ih / iw;
      final center =
          _screenToWorld(Offset(screen.width / 2, screen.height / 2));
      final img = CanvasImage(
        filename: filename,
        x: center.dx - worldW / 2,
        y: center.dy - worldH / 2,
        w: worldW,
        h: worldH,
      );
      final before = _snapshot();
      setState(() => _data.images.add(img));
      _commit(before);
      _persist();
      _imgCache?.get(filename);
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Place a new empty task block at the centre of the current viewport.
  void _insertTaskBlock() {
    final screen = MediaQuery.of(context).size;
    final center = _screenToWorld(Offset(screen.width / 2, screen.height / 2));
    final w = kCanvasTaskBlockDefaultW;
    final block = CanvasTaskBlock(
      x: center.dx - w / 2,
      y: center.dy - 60,
      w: w,
      h: 120,
    );
    final before = _snapshot();
    setState(() {
      _data.taskBlocks.add(block);
      if (_tool != DrawTool.lasso) _tool = DrawTool.lasso;
    });
    _commit(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  double get _viewScale => _viewCtrl.value.getMaxScaleOnAxis();

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

  Rect? _lassoToolbarScreenRect() {
    // Only guard when the toolbar is actually on screen, and place the guard
    // ABOVE the selection (matching the toolbar) so it never covers the top
    // handles — a world-space offset shrank on screen when zoomed out and the
    // guard then swallowed the rotation / top-resize handles.
    if (!_toolbarVisible ||
        _lassoCtrl.phase != LassoPhase.selected ||
        _lassoCtrl.boundingBox == null) {
      return null;
    }
    final bb = _lassoCtrl.boundingBox!;
    final screenTop =
        MatrixUtils.transformPoint(_viewCtrl.value, Offset(bb.center.dx, bb.top));
    return Rect.fromLTWH(screenTop.dx - 110, screenTop.dy - 148, 220, 100);
  }

  void _onDown(PointerDownEvent e) {
    if (_eyedropperMode) {
      _sampleAt(_screenToWorld(e.localPosition));
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

    final isStylus = e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    if (isStylus) {
      _stylusActive = true;
      if (_palmRejection) _transformBeforeStylus = Matrix4.copy(_viewCtrl.value);
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
      final p = _screenToWorld(e.localPosition);
      _lassoCtrl.hitScale = _viewScale;
      if (_lassoCtrl.phase == LassoPhase.selected) {
        if (_lassoCtrl.hitTestRotationHandle(p) ||
            _lassoCtrl.hitTestCornerHandle(p) != null ||
            _lassoCtrl.hitTestSideHandle(p) != null ||
            _lassoCtrl.isTapInsideBoundingBox(p)) {
          setState(() => _isDrawing = true);
          _handleLassoDown(p);
          return;
        }
      }
      // A clean finger tap to (re)select is handled by the overlay
      // GestureDetector's onTapUp; a finger drag pans via InteractiveViewer.
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
      _gestureBefore = _snapshot();
      _gestureChanged = false;
      setState(() => _eraserCursor = e.localPosition);
      _eraseNear(p);
      return;
    }
    _stab = _newStabilizer();
    final sp = _stabilize(p);
    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() {
        _active = DrawingStroke(
          colorValue: _color.toARGB32(),
          strokeWidth: _strokeW,
          isFountainPen: true,
          points: [
            [
              sp.dx,
              sp.dy,
              pressure,
              DateTime.now().millisecondsSinceEpoch.toDouble(),
            ],
          ],
        );
      });
      return;
    }
    _rawPen = [
      [p.dx, p.dy]
    ];
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        isHighlighter: _tool == DrawTool.highlighter,
        points: [
          [sp.dx, sp.dy]
        ],
      );
    });
    if (_tool == DrawTool.pen) _startHoldTimer(sp);
  }

  LiveStabilizer? _newStabilizer() =>
      _stabilizer.isOn ? LiveStabilizer(_stabilizer.alpha) : null;

  Offset _stabilize(Offset p) => _stab?.process(p.dx, p.dy) ?? p;

  /// Finger tap (touch only) in lasso mode selects the stroke/image under it.
  /// Handled by a dedicated tap recognizer so it resolves cleanly against the
  /// InteractiveViewer pan in the gesture arena.
  void _onLassoTap(TapUpDetails d) {
    if (d.kind != PointerDeviceKind.touch) return;
    if (_tool != DrawTool.lasso || !_palmRejection) return;
    if (_lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating) {
      return;
    }
    final p = _screenToWorld(d.localPosition);
    _lassoCtrl.hitScale = _viewScale;
    if (_lassoCtrl.phase == LassoPhase.selected) {
      // A tap inside the selection (toggle the toolbar) is driven by the
      // pointer flow's no-op move (_finishTransformOrTap) — skip it here.
      if (_lassoCtrl.isTapInsideBoundingBox(p)) return;
      // Tap outside: hide the toolbar, or deselect if already hidden.
      setState(() {
        if (_toolbarVisible) {
          _toolbarVisible = false;
        } else {
          _lassoCtrl.deselect();
        }
      });
      return;
    }
    // Nothing selected. A tap on an interactive block belongs to its task UI.
    if (_interactiveBlockAt(p)) return;
    setState(() {
      if (_lassoCtrl.tapSelect(
          p, _data.strokes, _data.images, _data.taskBlocks)) {
        _toolbarVisible = false;
      } else {
        _lassoCtrl.deselect();
      }
    });
  }

  /// True when [worldPos] is over a task block that is currently interactive
  /// (lasso tool active and the block isn't the lasso selection).
  bool _interactiveBlockAt(Offset worldPos) {
    if (_tool != DrawTool.lasso) return false;
    for (int i = _data.taskBlocks.length - 1; i >= 0; i--) {
      if (_lassoCtrl.selectedBlockIndices.contains(i)) continue;
      final b = _data.taskBlocks[i];
      if (Rect.fromLTWH(b.x, b.y, b.w, b.h).contains(worldPos)) return true;
    }
    return false;
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
    if (_snapKind != null) {
      _updateShapeAdjust(p);
      return;
    }
    if (_tool == DrawTool.lasso) {
      _handleLassoMove(p);
      return;
    }
    if (_tool == DrawTool.eraser) {
      setState(() => _eraserCursor = e.localPosition);
      _eraseNear(p);
      return;
    }
    if (_active == null) return;
    final sp = _stabilize(p);
    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() => _active!.points.add([
        sp.dx,
        sp.dy,
        pressure,
        DateTime.now().millisecondsSinceEpoch.toDouble(),
      ]));
      return;
    }
    final pts = _active!.points;
    _rawPen.add([p.dx, p.dy]);
    if (pts.isNotEmpty && !_stabilizer.isOn) {
      final dx = sp.dx - pts.last[0];
      final dy = sp.dy - pts.last[1];
      if (dx * dx + dy * dy < _minDist2) return;
    }
    setState(() => pts.add([sp.dx, sp.dy]));
    if (_holdAnchor != null) {
      final dx = sp.dx - _holdAnchor!.dx;
      final dy = sp.dy - _holdAnchor!.dy;
      if (dx * dx + dy * dy > _holdTolerance2) {
        _startHoldTimer(sp);
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

    if (_pastePos != null) {
      _pasteTimer?.cancel();
      _pastePos = null;
      return;
    }

    // Scribble-erase has priority over any shape that the hold-timer may have
    // wrongly snapped (a dense scribble can match the rectangle detector).
    if (_tool == DrawTool.pen && _rawPen.isNotEmpty && isScribble(_rawPen)) {
      _doScribbleErase();
      _stab = null;
      return;
    }

    if (_snapKind != null) {
      _commitShapeAdjust();
      _stab = null;
      return;
    }
    if (_tool == DrawTool.lasso) {
      _handleLassoUp();
      return;
    }
    if (_tool == DrawTool.eraser) {
      _commitEraseGesture();
      setState(() => _eraserCursor = null);
      return;
    }
    if (_tool == DrawTool.fountainPen) {
      _finishFountainStroke();
      _stab = null;
      return;
    }
    if (_active == null) return;
    _finishStroke();
    _stab = null;
  }

  void _onCancel(PointerCancelEvent e) {
    _activePointers.remove(e.pointer);
    _pointerDownPos.remove(e.pointer);
    _holdTimer?.cancel();
    _holdAnchor = null;
    _pendingLassoStart = null;
    setState(() => _isDrawing = false);
    if (_activePointers.isEmpty) _maxSimultaneous = 0;
    if (_snapKind != null) {
      setState(() => _active = null);
      _clearSnap();
      _stab = null;
      return;
    }
    if (_tool == DrawTool.eraser) {
      _commitEraseGesture();
      setState(() => _eraserCursor = null);
      return;
    }
    if (_tool == DrawTool.fountainPen) {
      _active = null;
      _stab = null;
      return;
    }
    _finishStroke();
    _stab = null;
  }

  void _doScribbleErase() {
    final scribblePts = _rawPen;
    if (!isScribble(scribblePts)) return;
    final bounds = scribbleBounds(scribblePts);
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
      HapticFeedback.lightImpact();
      _persist();
    }
    _rawPen = [];
  }

  void _finishStroke() {
    if (_snapKind != null) return;
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      return;
    }

    final scribblePts = _rawPen.length >= _active!.points.length
        ? _rawPen
        : _active!.points;
    if (_tool == DrawTool.pen && isScribble(scribblePts)) {
      final bounds = scribbleBounds(scribblePts);
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
        HapticFeedback.lightImpact();
        _persist();
      }
      _rawPen = [];
      return;
    }

    final before = _snapshot();
    setState(() {
      _data.strokes.add(_active!);
      _active = null;
    });
    _commit(before);
    _persist();
  }

  void _finishFountainStroke() {
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.length < 2) {
      setState(() => _active = null);
      return;
    }

    final baked = FountainPenEngine.finishStroke(_active!);
    final before = _snapshot();
    setState(() {
      _data.strokes.add(baked);
      _active = null;
    });
    _commit(before);
    _persist();
  }

  static const _eraserScreenRadius = 7.0;

  void _eraseNear(Offset pos) {
    final radius = _eraserScreenRadius / _viewScale;
    bool changed = false;
    if (_eraserMode == EraserMode.partial) {
      final out = <DrawingStroke>[];
      for (final s in _data.strokes) {
        final pieces = splitStrokeByEraser(s, pos, radius);
        if (pieces.length == 1 && identical(pieces.first, s)) {
          out.add(s);
        } else {
          out.addAll(pieces);
          changed = true;
        }
      }
      if (changed) _data.strokes = out;
    } else {
      final before = _data.strokes.length;
      _data.strokes.removeWhere((s) => strokeHitByEraser(s, pos, radius));
      changed = _data.strokes.length != before;
    }
    if (changed) {
      _gestureChanged = true;
      setState(() {});
      _persist();
    }
  }

  // ─── Lasso gesture handlers ─────────────────────────────────────────────

  void _handleLassoDown(Offset worldPos) {
    _pasteTimer?.cancel();
    _lassoCtrl.hitScale = _viewScale;
    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.selected) {
      if (_lassoCtrl.hitTestRotationHandle(worldPos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startRotation(
            worldPos, _data.strokes, _data.images, _data.taskBlocks);
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(worldPos);
      if (corner != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startResize(
            corner, worldPos, _data.strokes, _data.images, _data.taskBlocks);
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(worldPos);
      if (side != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startSideResize(
            side, worldPos, _data.strokes, _data.images, _data.taskBlocks);
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(worldPos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startMove(
            worldPos, _data.strokes, _data.images, _data.taskBlocks);
        return;
      }
      // Outside the selection: defer. A tap (no drag) dismisses the toolbar /
      // selection on up; a drag starts a fresh lasso on move. Keep the current
      // selection meanwhile.
      _pendingLassoStart = worldPos;
      return;
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
    if (_pendingLassoStart != null) {
      if ((worldPos - _pendingLassoStart!).distance * _viewScale > 6) {
        _lassoCtrl.deselect();
        _toolbarVisible = false;
        _lassoCtrl.startTracing(_pendingLassoStart!);
        _lassoCtrl.addTracePoint(worldPos);
        _pendingLassoStart = null;
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
    // Tap outside the selection (no drag): hide the toolbar, or deselect if it
    // was already hidden.
    if (_pendingLassoStart != null) {
      _pendingLassoStart = null;
      setState(() {
        if (_toolbarVisible) {
          _toolbarVisible = false;
        } else {
          _lassoCtrl.deselect();
        }
      });
      return;
    }
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.finishTracing(_data.strokes, _data.images, _data.taskBlocks);
      _toolbarVisible = false; // a fresh selection starts with the toolbar hidden
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      final moved = _lassoCtrl.dragOffset.distance * _viewScale > 6;
      _lassoCtrl.finishMove(
          _data.strokes, _data.images, _data.taskBlocks, 0);
      _finishTransformOrTap(moved);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      final moved = _lassoCtrl.isSideResize
          ? (_lassoCtrl.resizeScaleX - 1).abs() > 0.02 ||
              (_lassoCtrl.resizeScaleY - 1).abs() > 0.02
          : (_lassoCtrl.resizeScale - 1).abs() > 0.02;
      _lassoCtrl.isSideResize
          ? _lassoCtrl.finishSideResize(
              _data.strokes, _data.images, _data.taskBlocks)
          : _lassoCtrl.finishResize(
              _data.strokes, _data.images, _data.taskBlocks);
      for (final i in _lassoCtrl.selectedBlockIndices) {
        if (i >= _data.taskBlocks.length) continue;
        final b = _data.taskBlocks[i];
        if (b.w < 220) b.w = 220;
        if (b.h < 90) b.h = 90;
      }
      _finishTransformOrTap(moved);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      final moved = _lassoCtrl.rotationAngle.abs() > 0.01;
      _lassoCtrl.finishRotation(_data.strokes, _data.images, _data.taskBlocks);
      _finishTransformOrTap(moved);
    }
  }

  /// A transform gesture that actually moved is committed; one that didn't is a
  /// tap on the selection → toggle the action toolbar (no undo step).
  void _finishTransformOrTap(bool moved) {
    if (moved) {
      _commitGesture();
      _persist();
    } else {
      _gestureBefore = null;
      setState(() => _toolbarVisible = !_toolbarVisible);
    }
  }

  void _lassoDelete() {
    _lassoMutate(() => _lassoCtrl.deleteSelected(
        _data.strokes, _data.images, _data.taskBlocks));
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    _lassoMutate(
        () => _lassoCtrl.duplicateSelected(_data.strokes, _data.images));
    HapticFeedback.lightImpact();
  }

  bool get _singleImageSelected =>
      _lassoCtrl.selectedImageIndices.length == 1 &&
      _lassoCtrl.selectedIndices.isEmpty;

  Future<void> _cropSelectedImage() async {
    final dirPath = _imageDirPath;
    if (dirPath == null || !_singleImageSelected) return;
    final idx = _lassoCtrl.selectedImageIndices.first;
    if (idx >= _data.images.length) return;
    final img = _data.images[idx];
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(
          sourcePath: p.join(dirPath, img.filename),
          accent: _accent,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final ext = p.extension(result.file.path);
    final newName = '${const Uuid().v4()}$ext';
    await result.file.copy(p.join(dirPath, newName));
    final before = _snapshot();
    setState(() {
      _data.images[idx] = CanvasImage(
        filename: newName,
        x: img.x + img.w * result.fracLeft,
        y: img.y + img.h * result.fracTop,
        w: img.w * result.fracW,
        h: img.h * result.fracH,
        rotation: img.rotation,
      );
      _lassoCtrl.deselect();
    });
    _commit(before);
    _persist();
    _imgCache?.get(newName);
  }

  List<Widget> _buildTaskBlockOverlays() {
    final gesture = _lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating;
    final out = <Widget>[];
    for (int i = 0; i < _data.taskBlocks.length; i++) {
      final b = _data.taskBlocks[i];
      final selected = _lassoCtrl.selectedBlockIndices.contains(i);
      // Own compositing layer so dragging the card (live Transform below) is a
      // cheap layer-offset instead of repainting its content every frame.
      Widget overlay = RepaintBoundary(
        child: CanvasTaskBlockOverlay(
          key: ValueKey(b.id),
          block: b,
          noteId: widget.note.id,
          folderId: widget.note.folderId,
          folderName: widget.folder.name,
          folderColor: widget.folder.color,
          accent: _accent,
          interactive: !selected &&
              !gesture &&
              (_tool == DrawTool.lasso || _palmRejection),
          onPersist: _persist,
          onTasksChanged: () {
            if (mounted) setState(() {});
          },
          onHeightMeasured: (h) {
            if (!mounted) return;
            setState(() => b.h = h);
            _lassoCtrl.refreshBoundingBox(
                _data.strokes, _data.images, _data.taskBlocks);
            _persist();
          },
        ),
      );
      // Selected + mid-gesture: follow the live lasso transform for move/rotate.
      // During corner resize (uniform scale) the transform is fine; during side
      // resize (non-uniform) the widget stays at original size so text doesn't
      // distort, snapping to the new geometry on release.
      final isLiveTransform = _lassoCtrl.phase == LassoPhase.moving ||
          _lassoCtrl.phase == LassoPhase.rotating ||
          (_lassoCtrl.phase == LassoPhase.resizing && !_lassoCtrl.isSideResize);
      if (isLiveTransform && selected) {
        final off = Offset(b.x, b.y);
        final tm = Matrix4.translationValues(-off.dx, -off.dy, 0) *
            _lassoCtrl.liveGestureMatrix() *
            Matrix4.translationValues(off.dx, off.dy, 0);
        overlay = Transform(transform: tm, child: overlay);
      }
      out.add(Positioned(left: b.x, top: b.y, child: overlay));
    }
    return out;
  }

  Widget _buildLassoMiniToolbar() {
    final bb = _lassoCtrl.boundingBox!;
    final screenTop =
        MatrixUtils.transformPoint(_viewCtrl.value, Offset(bb.center.dx, bb.top));
    // Anchor the toolbar's BOTTOM a fixed screen gap above the selection top
    // (clearing the rotation handle), growing upward. A world-space offset
    // shrank on screen when zoomed out and the toolbar then covered the top
    // handles / top of the object, making them dead.
    return Positioned(
      left: screenTop.dx - 80,
      bottom: _viewport.height - screenTop.dy + 48,
      child: LassoMiniToolbar(
        onDelete: _lassoDelete,
        onDuplicate: _lassoDuplicate,
        onCrop: _singleImageSelected ? _cropSelectedImage : null,
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
          _lassoCtrl.copySelected(_data.strokes, _data.images);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('COPIADO'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onCut: () {
          _lassoMutate(() => _lassoCtrl.cutSelected(
              _data.strokes, _data.images, _data.taskBlocks));
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
          _lassoMutate(() => _lassoCtrl.pasteAt(_showPasteAt!, _data.strokes,
              _data.images, 0));
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

  // ─── Undo / redo (snapshot history) ─────────────────────────────────────

  (List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>)
      _snapshot() => (
            _data.strokes.map((s) => s.clone()).toList(),
            _data.images.map((im) => im.clone()).toList(),
            _data.taskBlocks.map((b) => b.clone()).toList(),
          );

  void _commit(
      (List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>) before) {
    _undoStack.add(before);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restore(
      (List<DrawingStroke>, List<CanvasImage>, List<CanvasTaskBlock>) snap) {
    _data.strokes = snap.$1;
    _data.images = snap.$2;
    _data.taskBlocks = snap.$3;
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
    _persist();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    setState(() {
      _restore(_undoStack.removeLast());
      _lassoCtrl.deselect();
      _active = null;
    });
    _persist();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    setState(() {
      _restore(_redoStack.removeLast());
      _lassoCtrl.deselect();
      _active = null;
    });
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
      final before = _snapshot();
      setState(() => _data.strokes = []);
      _commit(before);
      _persist();
    }
  }

  void _resetView() {
    if (_viewport == Size.zero) {
      setState(() => _viewCtrl.value = Matrix4.identity());
      return;
    }
    final box = _contentBounds();
    final cx = box?.center.dx ?? _kCanvasW / 2;
    final cy = box?.center.dy ?? _kCanvasH / 2;
    setState(() {
      _viewCtrl.value = Matrix4.translationValues(
          _viewport.width / 2 - cx, _viewport.height / 2 - cy, 0);
    });
  }

  Size _viewport = Size.zero;

  Rect? _contentBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in _data.strokes) {
      for (final p in s.points) {
        if (p[0] < minX) minX = p[0];
        if (p[0] > maxX) maxX = p[0];
        if (p[1] < minY) minY = p[1];
        if (p[1] > maxY) maxY = p[1];
      }
    }
    for (final im in _data.images) {
      if (im.x < minX) minX = im.x;
      if (im.y < minY) minY = im.y;
      if (im.x + im.w > maxX) maxX = im.x + im.w;
      if (im.y + im.h > maxY) maxY = im.y + im.h;
    }
    for (final b in _data.taskBlocks) {
      if (b.x < minX) minX = b.x;
      if (b.y < minY) minY = b.y;
      if (b.x + b.w > maxX) maxX = b.x + b.w;
      if (b.y + b.h > maxY) maxY = b.y + b.h;
    }
    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _viewInitialized = false;

  /// Open centered: a new (empty) whiteboard lands on the canvas centre — far
  /// from the real 10k×10k edges — instead of the top-left corner, so the user
  /// never bumps into the boundary in normal use. An existing board centres on
  /// its content. Runs once, after the data and viewport are both ready.
  void _maybeInitView() {
    if (_viewInitialized || _blockId == null || _viewport == Size.zero) return;
    _viewInitialized = true;
    final box = _contentBounds();
    final cx = box?.center.dx ?? _kCanvasW / 2;
    final cy = box?.center.dy ?? _kCanvasH / 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewCtrl.value = Matrix4.translationValues(
          _viewport.width / 2 - cx, _viewport.height / 2 - cy, 0);
    });
  }

  void _zoomToFit() {
    final box = (_lassoCtrl.phase == LassoPhase.selected &&
            _lassoCtrl.boundingBox != null)
        ? _lassoCtrl.boundingBox!
        : _contentBounds();
    if (box == null || box.width < 1 || box.height < 1) return;
    final vw = _viewport.width, vh = _viewport.height;
    if (vw < 1 || vh < 1) return;
    const pad = 60.0;
    final sx = (vw - pad) / box.width;
    final sy = (vh - pad) / box.height;
    final scale = sx < sy ? sx : sy;
    final s = scale.clamp(0.3, 4.0);
    final c = box.center;
    setState(() {
      _viewCtrl.value = Matrix4.translationValues(vw / 2, vh / 2, 0)
        ..multiply(Matrix4.diagonal3Values(s, s, 1))
        ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
    });
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

  Color get _accent => widget.note.color ?? widget.folder.color;

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
      body: Stack(
        children: [
          Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_headerCollapsed)
            SafeArea(
              child: _CollapsedWhiteboardHeader(
                folder: widget.folder,
                spaces: spaces,
                accent: _accent,
                onExpand: () => setState(() => _headerCollapsed = false),
                onReset: _resetView,
                onLink: () => _linkToLab(spaces),
              ),
            )
          else ...[
            SafeArea(
              child: Column(
                children: [
                  ModeHeader(
                    mode: 'PIZARRA',
                    subtitle: 'INFINITA · CANVAS · PAN + ZOOM',
                    color: _accent,
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
                  if (linkedSpaces.isNotEmpty) _LinkedSpacesBar(spaces: linkedSpaces),
                ],
              ),
            ),
          ],
          Expanded(
              child: LayoutBuilder(builder: (ctx, c) {
                _viewport = Size(c.maxWidth, c.maxHeight);
                _maybeInitView();
                return AnimatedBuilder(
                  animation: _viewCtrl,
                  builder: (_, _) {
                    final inv = Matrix4.inverted(_viewCtrl.value);
                    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
                    final br = MatrixUtils.transformPoint(
                        inv, Offset(c.maxWidth, c.maxHeight));
                    final visibleRect = Rect.fromPoints(tl, br);
                    // Keep handle hit/draw sizes correct even if the user zooms
                    // while a selection is active.
                    _lassoCtrl.hitScale = _viewScale;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRect(
                          child: GestureDetector(
                            onTapUp: _onLassoTap,
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
                                        images: _data.images,
                                        imageCache: _imgCache,
                                        background: _data.background,
                                        paper: bgPaper(_data.bgColorValue, yCream),
                                        active: _active,
                                        locked: _locked,
                                        visibleRect: visibleRect,
                                        hiddenIndices: (_lassoCtrl.phase == LassoPhase.moving ||
                                                _lassoCtrl.phase == LassoPhase.resizing ||
                                                _lassoCtrl.phase == LassoPhase.rotating)
                                            ? _lassoCtrl.selectedIndices
                                            : null,
                                        hiddenImageIndices: (_lassoCtrl.phase == LassoPhase.moving ||
                                                _lassoCtrl.phase == LassoPhase.resizing ||
                                                _lassoCtrl.phase == LassoPhase.rotating)
                                            ? _lassoCtrl.selectedImageIndices
                                            : null,
                                      ),
                                      size: const Size(_kCanvasW, _kCanvasH),
                                    ),
                                    ..._buildTaskBlockOverlays(),
                                    if (_lassoCtrl.phase != LassoPhase.idle)
                                      AnimatedBuilder(
                                        animation: _lassoAnimCtrl,
                                        builder: (_, _) => CustomPaint(
                                          painter: LassoPainter(
                                            ctrl: _lassoCtrl,
                                            animValue: _lassoAnimCtrl.value,
                                            strokes: _data.strokes,
                                            images: _data.images,
                                            imageCache: _imgCache,
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
                          ),
                        ),
                        if (_lassoCtrl.phase == LassoPhase.selected &&
                            _toolbarVisible)
                          _buildLassoMiniToolbar(),
                        if (_showPasteAt != null)
                          _buildPasteButton(),
                        if (_tool == DrawTool.eraser && _eraserCursor != null)
                          Positioned(
                            left: _eraserCursor!.dx - _eraserScreenRadius,
                            top: _eraserCursor!.dy - _eraserScreenRadius,
                            child: const EraserCursor(radius: _eraserScreenRadius),
                          ),
                      ],
                    );
                  },
                );
              }),
            ),
            _toolbar(),
          ],
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
          if (_imagePanelOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleImagePanel,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ImageInsertPanel(
                  accent: _accent,
                  onPick: (file) {
                    _toggleImagePanel();
                    _insertImageFile(file);
                  },
                  onClose: _toggleImagePanel,
                ),
              ),
            ),
          ],
          if (_bgPopupOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleBgPopup,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BackgroundPopup(
                  pattern: _data.background,
                  color: bgPaper(_data.bgColorValue, yCream),
                  showScope: false,
                  allPages: false,
                  accent: _accent,
                  onPattern: _setBgPattern,
                  onColor: _setBgColor,
                  onMoreColors: () => setState(() {
                    _bgColorPickerOpen = true;
                    _bgPopupOpen = false;
                  }),
                  onScope: (_) {},
                  onClose: _toggleBgPopup,
                ),
              ),
            ),
          ],
          if (_bgColorPickerOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _bgColorPickerOpen = false),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ColorPickerPopup(
                  currentColor: bgPaper(_data.bgColorValue, yCream),
                  recentColors: const [],
                  savedColors: _bgSavedColors,
                  quickColors: _bgSavedColors,
                  quickLabel: 'FAVORITOS',
                  onPreview: (c) =>
                      setState(() => _data.bgColorValue = c.toARGB32()),
                  onCommit: _setBgColor,
                  onStar: _starBgColor,
                  onEyedropper: () {},
                  onClose: () => setState(() {
                    _bgColorPickerOpen = false;
                    _bgPopupOpen = true;
                  }),
                ),
              ),
            ),
          ],
          if (_eraserPopupOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _eraserPopupOpen = false),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 64,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _eraserModePopup(),
              ),
            ),
          ],
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

  Widget _toolbar() {
    final paddingH = MediaQuery.of(context).size.width * 0.08;
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
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
              onTap: () => _selectTool(DrawTool.pen),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.gesture,
              active: _tool == DrawTool.fountainPen,
              onTap: () => _selectTool(DrawTool.fountainPen),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.highlight,
              active: _tool == DrawTool.highlighter,
              onTap: () => _selectTool(DrawTool.highlighter),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: _eraserMode == EraserMode.partial
                  ? Icons.cleaning_services_outlined
                  : Icons.auto_fix_high,
              active: _tool == DrawTool.eraser,
              onTap: () {
                if (_tool == DrawTool.eraser) {
                  setState(() => _eraserPopupOpen = !_eraserPopupOpen);
                } else {
                  _selectTool(DrawTool.eraser);
                }
              },
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.highlight_alt,
              active: _tool == DrawTool.lasso,
              label: 'LAZO',
              onTap: () => _selectTool(DrawTool.lasso),
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.image_outlined,
              active: _imagePanelOpen,
              onTap: _toggleImagePanel,
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.checklist,
              active: false,
              label: 'TAREAS',
              onTap: _insertTaskBlock,
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
              enabled: _undoStack.isNotEmpty,
              onTap: _undo,
            ),
            const SizedBox(width: 10),
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
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.format_color_fill,
              active: _fillShapes,
              label: 'RELLENO',
              onTap: () {
                setState(() => _fillShapes = !_fillShapes);
                DrawingPrefs.saveFill(_fillShapes);
              },
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.grid_on,
              active: _bgPopupOpen,
              label: 'FONDO',
              onTap: _toggleBgPopup,
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.fit_screen,
              active: false,
              label: 'ENCUADRAR',
              onTap: _zoomToFit,
            ),
            const SizedBox(width: 12),
            _toolBtn(
              icon: Icons.back_hand_outlined,
              active: _palmRejection,
              label: 'PALMA',
              onTap: () {
                setState(() => _palmRejection = !_palmRejection);
                DrawingPrefs.savePalm(_palmRejection);
              },
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

class _CollapsedWhiteboardHeader extends StatelessWidget {
  final Folder folder;
  final List<LabSpace> spaces;
  final Color accent;
  final VoidCallback onExpand;
  final VoidCallback onReset;
  final VoidCallback onLink;

  const _CollapsedWhiteboardHeader({
    required this.folder,
    required this.spaces,
    required this.accent,
    required this.onExpand,
    required this.onReset,
    required this.onLink,
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
              'PIZARRA · @${folder.name}',
              style: ySans(size: 15, weight: FontWeight.w700, letterSpacing: -0.3, color: accent, height: 1.0),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onReset,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: const Icon(Icons.center_focus_strong, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onLink,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yLab,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: const Icon(Icons.all_inclusive, color: yCream, size: 16),
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

// ─── Canvas painter ───────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<CanvasImage> images;
  final CanvasImageCache? imageCache;
  final PageBackground background;
  final Color paper;
  final DrawingStroke? active;
  final bool locked;
  final Rect visibleRect;
  final Set<int>? hiddenIndices;
  final Set<int>? hiddenImageIndices;

  _CanvasPainter({
    required this.strokes,
    required this.images,
    required this.imageCache,
    required this.background,
    required this.paper,
    required this.active,
    required this.locked,
    required this.visibleRect,
    this.hiddenIndices,
    this.hiddenImageIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vr = visibleRect;
    // Paper + pattern — only the visible portion.
    canvas.drawRect(vr, Paint()..color = paper);
    paintBgPattern(canvas, vr, background, bgMark(paper));
    // Images — behind strokes; skip those outside the visible rect.
    for (int i = 0; i < images.length; i++) {
      if (hiddenImageIndices != null && hiddenImageIndices!.contains(i)) {
        continue;
      }
      final im = images[i];
      if (!Rect.fromLTWH(im.x, im.y, im.w, im.h).overlaps(vr)) continue;
      drawCanvasImage(canvas, imageCache?.get(im.filename), im);
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
      old.images != images ||
      old.background != background ||
      old.paper != paper ||
      old.active != active ||
      old.hiddenImageIndices != hiddenImageIndices;
}

void _draw(Canvas canvas, DrawingStroke stroke) => drawStroke(canvas, stroke);

// ─── Linked-spaces bar (under header) ─────────────────────────────────────

class _LinkedSpacesBar extends ConsumerWidget {
  final List<LabSpace> spaces;
  const _LinkedSpacesBar({required this.spaces});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => LabSpaceDetailScreen(space: s)),
                          (route) => route.isFirst,
                        );
                      },
                      child: Container(
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
