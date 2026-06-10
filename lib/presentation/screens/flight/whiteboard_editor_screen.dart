import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/ai_providers.dart';
import '../../providers/note_providers.dart';
import '../../widgets/ai_link_badge.dart';
import '../../widgets/status_bar_flood.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import 'background_paint.dart';
import 'background_popup.dart';
import 'color_picker.dart';
import 'color_loupe.dart';
import 'drawing_engine.dart';
import 'drawing_prefs.dart';
import 'eraser_mode_popup.dart';
import 'floating_palettes.dart';
import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';
import 'popup_reveal.dart';
import 'shape_recognizer.dart';
import 'shape_picker_popup.dart';
import 'lasso_controller.dart';
import 'lasso_painter.dart';
import 'lasso_mini_toolbar.dart';
import 'ai_chat_sheet.dart';
import 'canvas_export_sheet.dart';
import '../../utils/canvas_block_raster.dart';
import '../../utils/canvas_export.dart';
import 'ocr_flow.dart';
import 'canvas_image_cache.dart';
import 'canvas_task_block.dart';
import 'canvas_text_block.dart';
import 'image_crop_screen.dart';
import 'image_insert_panel.dart';
import 'stroke_bounds.dart';
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

class _WhiteboardEditorScreenState extends ConsumerState<WhiteboardEditorScreen>
    with TickerProviderStateMixin {
  int? _blockId;
  DrawingData _data = DrawingData();
  final TransformationController _viewCtrl = TransformationController();
  int _paintVersion = 0;
  Rect? _renderRect;
  Offset? _lastVisibleCenter;
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
  bool _shapePopupOpen = false;
  bool _morePopupOpen = false;
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
  final List<
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
  >
  _undoStack = [];
  final List<
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
  >
  _redoStack = [];
  (
    List<DrawingStroke>,
    List<CanvasImage>,
    List<CanvasTaskBlock>,
    List<CanvasTextBlock>,
  )?
  _gestureBefore;
  bool _gestureChanged = false;
  DrawingStroke? _active;
  // Ticked on every live point added to [_active]. Repaints only the active
  // stroke layer (its own RepaintBoundary) without a full-canvas setState, so
  // the wet stroke keeps up with the stylus instead of trailing it.
  final ValueNotifier<int> _activeTick = ValueNotifier(0);
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

  // Export: when a marquee selection is requested, the chosen options are held
  // until the user confirms. The selection [_marqueeWorld] is a WORLD-space rect
  // (captured through the same pointer pipeline + `_screenToWorld` as drawing, so
  // it lines up exactly). One finger draws/adjusts; two fingers pan/zoom (the
  // rect stays anchored in world space). After drawing it shows lasso-style
  // handles to resize/move; lifting a finger never exports — confirm with the
  // button.
  bool _exportMarquee = false;
  Rect? _marqueeWorld;
  CanvasExportOptions? _pendingExport;
  final Set<int> _marqueePointers = {};
  _MarqueeHandle? _marqueeDrag;
  Offset? _marqueeDragAnchorWorld; // world pos where the current drag began
  Rect? _marqueeRectAtDragStart; // rect when the resize/move drag began
  Offset? _marqueeDrawStart; // world anchor of a fresh draw
  Rect? _marqueeRectBackup; // restored if a fresh draw ends up too small

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
  FloatingPalettesController? _palettes;
  // Favorite that was selected (== current color) when the color picker opened.
  // Lets starring a refined color replace that favorite in place instead of
  // evicting the oldest. Null when no favorite was selected.
  Color? _pickerFavoriteAnchor;
  List<Color> _bgSavedColors = const [];
  bool _eyedropperMode = false;
  bool _lockBeforeEyedropper = false;
  // Eyedropper loupe: a raster snapshot of the visible canvas is sampled per
  // pixel (anything: paper, strokes, images, text), not stroke hit-testing.
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  ui.Image? _eyedropImg;
  ByteData? _eyedropBytes;
  double _eyedropDpr = 1;
  Offset _loupePos = Offset.zero;
  Color _loupeColor = yInk;
  Matrix4? _eyedropCaptureMatrix;
  void Function(Color)? _eyedropOnPick;

  // Multi-finger tap tracking
  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  @override
  void setState(VoidCallback fn) {
    _paintVersion++;
    super.setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _palette = buildPenPalette(widget.note.color ?? widget.folder.color);
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _lassoCtrl.onChanged = () {
      _syncLassoTicker();
      setState(() {});
    };
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
    FloatingPalettesController.load().then((c) {
      if (!mounted) return;
      setState(() => _palettes = c);
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
      if (_colorPickerOpen) {
        _widthPickerOpen = false;
        final v = _color.toARGB32();
        _pickerFavoriteAnchor = _savedColors.cast<Color?>().firstWhere(
          (c) => c!.toARGB32() == v,
          orElse: () => null,
        );
      } else {
        _pickerFavoriteAnchor = null;
      }
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
    final v = value.toARGB32();
    final isStarred = _savedColors.any((c) => c.toARGB32() == v);
    setState(() {
      if (isStarred) {
        _savedColors = SavedColorsPrefs.remove(_savedColors, value);
      } else {
        final anchor = _pickerFavoriteAnchor;
        final anchorIdx =
            anchor == null
                ? -1
                : _savedColors.indexWhere(
                  (c) => c.toARGB32() == anchor.toARGB32(),
                );
        if (anchorIdx >= 0) {
          // A favorite was selected: replace it in place with the new shade.
          final list = List<Color>.from(_savedColors);
          list[anchorIdx] = value;
          _savedColors = list;
        } else {
          _savedColors = SavedColorsPrefs.push(_savedColors, value);
        }
      }
      _pickerFavoriteAnchor = isStarred ? _pickerFavoriteAnchor : null;
    });
    SavedColorsPrefs.save(_savedColors);
    HapticFeedback.selectionClick();
  }

  void _starBgColor(Color value) {
    final isStarred = _bgSavedColors.any(
      (c) => c.toARGB32() == value.toARGB32(),
    );
    setState(() {
      _bgSavedColors =
          isStarred
              ? SavedBgColorsPrefs.remove(_bgSavedColors, value)
              : SavedBgColorsPrefs.push(_bgSavedColors, value);
    });
    SavedBgColorsPrefs.save(_bgSavedColors);
    HapticFeedback.selectionClick();
  }

  void _enterEyedropper({void Function(Color)? onPick}) {
    _lockBeforeEyedropper = _locked;
    setState(() {
      _eyedropperMode = true;
      _eyedropOnPick = onPick;
      _colorPickerOpen = false;
      _widthPickerOpen = false;
      _tool = DrawTool.pen;
      _lassoCtrl.deselect();
      _locked = true;
    });
    HapticFeedback.lightImpact();
    _captureEyedropSnapshot();
  }

  Future<void> _captureEyedropSnapshot({bool resetPos = true}) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_eyedropperMode) return;
    final boundary =
        _canvasBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final img = await boundary.toImage(pixelRatio: dpr);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (!mounted || !_eyedropperMode || bytes == null) {
      img.dispose();
      return;
    }
    final pos = resetPos
        ? Offset(_viewport.width / 2, _viewport.height / 2)
        : _loupePos;
    setState(() {
      _eyedropImg?.dispose();
      _eyedropImg = img;
      _eyedropBytes = bytes;
      _eyedropDpr = dpr;
      _eyedropCaptureMatrix = _viewCtrl.value.clone();
      _loupePos = pos;
      _loupeColor =
          sampleSnapshotColor(bytes, img.width, img.height, dpr, pos) ??
          _loupeColor;
    });
  }

  void _moveLoupe(Offset local) {
    final b = _eyedropBytes, img = _eyedropImg;
    if (b == null || img == null) return;
    setState(() {
      _loupePos = local;
      _loupeColor =
          sampleSnapshotColor(b, img.width, img.height, _eyedropDpr, local) ??
          _loupeColor;
    });
  }

  void _confirmLoupe() {
    final c = _loupeColor;
    final cb = _eyedropOnPick;
    _exitEyedropper();
    if (cb != null) {
      cb(c);
    } else {
      _commitColor(c);
    }
    HapticFeedback.mediumImpact();
  }

  void _exitEyedropper() {
    _eyedropImg?.dispose();
    setState(() {
      _eyedropperMode = false;
      _eyedropOnPick = null;
      _locked = _lockBeforeEyedropper;
      _eyedropImg = null;
      _eyedropBytes = null;
    });
  }

  List<Widget> _buildLoupeOverlay(Size viewport) {
    const loupeW = 132.0;
    const loupeH = 160.0;
    final left = (_loupePos.dx - loupeW / 2).clamp(8.0, viewport.width - loupeW - 8);
    final top = (_loupePos.dy - loupeH - 40).clamp(8.0, viewport.height - loupeH - 8);
    return [
      // Exact sample point.
      Positioned(
        left: _loupePos.dx - 7,
        top: _loupePos.dy - 7,
        child: IgnorePointer(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _loupeColor,
              border: Border.all(color: yCream, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: ColorLoupe(
            image: _eyedropImg!,
            dpr: _eyedropDpr,
            sample: _loupePos,
            color: _loupeColor,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 16,
        child: Center(
          child: LoupeActionBar(
            accent: _accent,
            onCancel: _exitEyedropper,
            onConfirm: _confirmLoupe,
          ),
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _eyedropImg?.dispose();
    _reconcileImageFiles();
    _holdTimer?.cancel();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _imgCache?.dispose();
    _viewCtrl.dispose();
    _activeTick.dispose();
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
          if (entity is File && !referenced.contains(p.basename(entity.path))) {
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
    if (isScribble(_rawPen.isNotEmpty ? _rawPen : _active!.points)) {
      return false;
    }
    final shape = ShapeRecognizer.detect(_active!.points);
    if (shape == null) return false;
    // Highlighter only snaps to straight lines (a marker arrow/box reads odd).
    if (_tool == DrawTool.highlighter && shape.kind != ShapeKind.line) {
      return false;
    }
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
      _snapRefDist = (Offset(end[0], end[1]) - _snapCenter!).distance.clamp(
        1.0,
        1e9,
      );
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: src.colorValue,
        strokeWidth: src.strokeWidth,
        filled: _fillShapes && shapeKindIsClosed(shape.kind),
        isShape: true,
        isHighlighter: src.isHighlighter,
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
      final ratio = ((p - _snapCenter!).distance / _snapRefDist).clamp(
        0.05,
        20.0,
      );
      pts = scaleShape(
        _snapBasePoints!,
        _snapCenter!.dx,
        _snapCenter!.dy,
        ratio,
      );
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: _active!.colorValue,
        strokeWidth: _active!.strokeWidth,
        filled: _active!.filled,
        isShape: true,
        isHighlighter: _active!.isHighlighter,
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
    DrawingBlock? canvas = blocks.whereType<DrawingBlock>().firstOrNull;
    canvas ??=
        await repo.insertAtEnd(
              widget.note.id,
              NoteBlockType.drawing,
              payload: {'h': _kCanvasH, 's': [], 'whiteboard': true},
            )
            as DrawingBlock;
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
      if (payload['tx'] != null) 'tx': payload['tx'],
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
      'tx': _data.textBlocks.map((b) => b.toJson()).toList(),
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
      final center = _screenToWorld(
        Offset(screen.width / 2, screen.height / 2),
      );
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
  void _enterTaskMode() {
    setState(() => _tool = DrawTool.task);
    _lassoCtrl.deselect();
    HapticFeedback.lightImpact();
  }

  /// Place a task block at [worldPos] (tap-to-insert in task mode).
  void _insertTaskBlockAt(Offset worldPos) {
    final w = (kCanvasTaskBlockDefaultW / _viewScale).clamp(60.0, 600.0);
    final h = (w * 0.375).clamp(40.0, 400.0);
    final block = CanvasTaskBlock(
      x: worldPos.dx - w / 2,
      y: worldPos.dy - h / 2,
      w: w,
      h: h,
    );
    final before = _snapshot();
    setState(() {
      _data.taskBlocks.add(block);
      _tool = DrawTool.task;
    });
    _commit(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  /// Place a new text block (empty, or seeded with [markdown]) at the centre of
  /// the current viewport. Used by the insert button and by the AI chat's
  /// "send to canvas".
  void _enterTextMode() {
    setState(() => _tool = DrawTool.text);
    _lassoCtrl.deselect();
    HapticFeedback.lightImpact();
  }

  /// Insert a text block at [worldPos] (tap-to-insert in text mode).
  void _insertTextBlockAt(Offset worldPos) {
    final w = (240.0 / _viewScale).clamp(60.0, 600.0);
    final block = CanvasTextBlock(
      x: worldPos.dx - w / 2,
      y: worldPos.dy - w / 4,
      w: w,
      h: w / 2,
    );
    final before = _snapshot();
    setState(() {
      _data.textBlocks.add(block);
      _tool = DrawTool.text;
    });
    _commit(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  /// Insert at centre with [markdown] (called from AI chat "Enviar a lienzo").
  void _insertTextBlock([String markdown = '']) {
    final screen = MediaQuery.of(context).size;
    final center = _screenToWorld(Offset(screen.width / 2, screen.height / 2));
    final screenW =
        markdown.isNotEmpty
            ? (200.0 + markdown.length * 0.35).clamp(120.0, 800.0)
            : 200.0;
    final w = (screenW / _viewScale).clamp(60.0, 600.0);
    final h = markdown.isNotEmpty ? w : w / 2;
    final block = CanvasTextBlock(
      x: center.dx - w / 2,
      y: center.dy - h / 2,
      w: w,
      h: h,
      markdown: markdown,
    );
    final before = _snapshot();
    setState(() {
      _data.textBlocks.add(block);
      // From the AI chat: show it selected via the lasso so the user sees a
      // placed, movable/resizable object instead of a box with no affordance.
      _tool = DrawTool.lasso;
      _lassoCtrl.hitScale = _viewScale;
      _lassoCtrl.selectTextBlock(
        _data.textBlocks.length - 1,
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        _data.textBlocks,
      );
      _toolbarVisible = false;
    });
    _commit(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  void _toggleShapePopup() {
    setState(() {
      _shapePopupOpen = !_shapePopupOpen;
      if (_shapePopupOpen) {
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _imagePanelOpen = false;
        _bgPopupOpen = false;
        _eraserPopupOpen = false;
        _morePopupOpen = false;
      }
    });
  }

  void _toggleMorePopup() {
    setState(() {
      _morePopupOpen = !_morePopupOpen;
      if (_morePopupOpen) {
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _imagePanelOpen = false;
        _bgPopupOpen = false;
        _eraserPopupOpen = false;
        _shapePopupOpen = false;
      }
    });
  }

  /// Drop a clean shape at the viewport centre, already lasso-selected so it can
  /// be moved/resized immediately. Undoable (snapshot/commit) and persisted.
  void _insertShape(ShapeKind kind) {
    final screen = MediaQuery.of(context).size;
    final center = _screenToWorld(Offset(screen.width / 2, screen.height / 2));
    // ~constant footprint on screen regardless of zoom.
    final size = 160 / _viewScale;
    final closed = shapeKindIsClosed(kind);
    final stroke = DrawingStroke(
      colorValue: _color.toARGB32(),
      strokeWidth: _strokeW,
      isShape: true,
      filled: closed && _fillShapes,
      points: buildShape(kind, center.dx, center.dy, size, size),
    );
    final before = _snapshot();
    setState(() {
      _data.strokes.add(stroke);
      _tool = DrawTool.lasso;
      _shapePopupOpen = false;
      _toolbarVisible = false;
    });
    final idx = _data.strokes.length - 1;
    _lassoCtrl.hitScale = _viewScale;
    _lassoCtrl.selectRange(_data.strokes, idx, idx + 1);
    _commit(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  double get _viewScale => _viewCtrl.value.getMaxScaleOnAxis();

  void _syncLassoTicker() {
    final shouldRun = _lassoCtrl.phase != LassoPhase.idle;
    if (shouldRun) {
      if (!_lassoAnimCtrl.isAnimating) _lassoAnimCtrl.repeat();
      return;
    }
    if (_lassoAnimCtrl.isAnimating) _lassoAnimCtrl.stop();
    if (_lassoAnimCtrl.value != 0) _lassoAnimCtrl.value = 0;
  }

  Rect _visibleRectFor(Size viewport) {
    final inv = Matrix4.inverted(_viewCtrl.value);
    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
    final br = MatrixUtils.transformPoint(
      inv,
      Offset(viewport.width, viewport.height),
    );
    _lassoCtrl.hitScale = _viewScale;
    return Rect.fromPoints(tl, br);
  }

  /// Padded render rect with PREDICTIVE hysteresis. The stroke/background painters
  /// cull and cache against this rect, which only grows (→ a repaint) once the
  /// live visible rect leaves it — so a pan within the buffer reuses the
  /// [RepaintBoundary] raster instead of re-rasterizing the ink every frame (the
  /// main sustained-heat source, since per-frame culling defeats the boundary).
  ///
  /// The buffer is biased toward the pan direction (a big `lead` ahead of travel,
  /// a tiny `trail`/`cross` elsewhere) instead of symmetric padding. On a 10000²
  /// canvas a symmetric margin repainted a ~4× block per re-expansion (a visible
  /// hitch); painting only toward where the finger is going makes each repaint
  /// ≈ a viewport + lead — both cooler (far less total raster) and smoother
  /// (smaller per-frame spike). A sharp direction reversal costs one repaint.
  Rect _renderRectFor(Size viewport) {
    final visible = _visibleRectFor(viewport);
    final prevCenter = _lastVisibleCenter;
    final center = visible.center;
    _lastVisibleCenter = center;
    final current = _renderRect;
    if (current != null &&
        current.left <= visible.left &&
        current.top <= visible.top &&
        current.right >= visible.right &&
        current.bottom >= visible.bottom) {
      return current;
    }
    const lead = 0.6;
    const trail = 0.1;
    const cross = 0.1;
    final w = visible.width;
    final h = visible.height;
    final dx = prevCenter != null ? center.dx - prevCenter.dx : 0.0;
    final dy = prevCenter != null ? center.dy - prevCenter.dy : 0.0;
    final padLeft = dx < 0 ? w * lead : (dx > 0 ? w * trail : w * cross);
    final padRight = dx > 0 ? w * lead : (dx < 0 ? w * trail : w * cross);
    final padTop = dy < 0 ? h * lead : (dy > 0 ? h * trail : h * cross);
    final padBottom = dy > 0 ? h * lead : (dy < 0 ? h * trail : h * cross);
    final next = Rect.fromLTRB(
      visible.left - padLeft,
      visible.top - padTop,
      visible.right + padRight,
      visible.bottom + padBottom,
    );
    _renderRect = next;
    return next;
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
    if (_tool == DrawTool.text) return false; // text mode never draws
    if (_tool == DrawTool.task) return false; // task mode never draws
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
    final screenTop = MatrixUtils.transformPoint(
      _viewCtrl.value,
      Offset(bb.center.dx, bb.top),
    );
    return Rect.fromLTWH(screenTop.dx - 110, screenTop.dy - 148, 220, 100);
  }

  void _onDown(PointerDownEvent e) {
    if (_exportMarquee) {
      _marqueePointers.add(e.pointer);
      if (_marqueePointers.length >= 2) {
        // Second finger → hand the gesture to the InteractiveViewer (pan/zoom);
        // abandon any in-progress drag, keep the committed rect.
        _marqueeDrag = null;
        return;
      }
      final p = e.localPosition;
      final rect = _marqueeWorld;
      if (rect != null) {
        final sr = _worldRectToScreen(rect);
        final handle = _hitMarqueeHandle(p, sr);
        if (handle != null) {
          _marqueeDrag = handle;
          _marqueeRectAtDragStart = rect;
          _marqueeDragAnchorWorld = _screenToWorld(p);
          return;
        }
        if (sr.contains(p)) {
          _marqueeDrag = _MarqueeHandle.move;
          _marqueeRectAtDragStart = rect;
          _marqueeDragAnchorWorld = _screenToWorld(p);
          return;
        }
      }
      // Fresh draw, anchored exactly at the touch point.
      _marqueeDrag = _MarqueeHandle.draw;
      _marqueeRectBackup = rect;
      _marqueeDrawStart = _screenToWorld(p);
      setState(
        () => _marqueeWorld = Rect.fromPoints(
          _marqueeDrawStart!,
          _marqueeDrawStart!,
        ),
      );
      return;
    }
    if (_eyedropperMode) {
      _activePointers.add(e.pointer);
      // 1 pointer drags the loupe; 2+ hands the gesture to pan/zoom.
      if (_activePointers.length < 2) {
        _moveLoupe(e.localPosition);
      } else {
        setState(() {});
      }
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

    final isStylus =
        e.kind == PointerDeviceKind.stylus ||
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
              e.timeStamp.inMilliseconds.toDouble(),
            ],
          ],
        );
      });
      return;
    }
    _rawPen = [
      [p.dx, p.dy],
    ];
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        isHighlighter: _tool == DrawTool.highlighter,
        isPencil: _tool == DrawTool.pencil,
        points: [
          _tool == DrawTool.pencil
              ? [sp.dx, sp.dy, e.pressure.isFinite ? e.pressure : 0.5]
              : [sp.dx, sp.dy],
        ],
      );
    });
    if (_tool == DrawTool.pen || _tool == DrawTool.highlighter) {
      _startHoldTimer(sp);
    }
  }

  LiveStabilizer? _newStabilizer() =>
      _stabilizer.isOn ? LiveStabilizer(_stabilizer.alpha) : null;

  Offset _stabilize(Offset p) => _stab?.process(p.dx, p.dy) ?? p;

  /// Finger tap (touch only) in lasso mode selects the stroke/image under it.
  /// Handled by a dedicated tap recognizer so it resolves cleanly against the
  /// InteractiveViewer pan in the gesture arena.
  void _onLassoTap(TapUpDetails d) {
    if (d.kind != PointerDeviceKind.touch) return;
    if (_tool == DrawTool.text) {
      final p = _screenToWorld(d.localPosition);
      _insertTextBlockAt(p);
      return;
    }
    if (_tool == DrawTool.task) {
      final p = _screenToWorld(d.localPosition);
      _insertTaskBlockAt(p);
      return;
    }
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
        p,
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        _data.textBlocks,
      )) {
        _toolbarVisible = false;
      } else {
        _lassoCtrl.deselect();
      }
    });
  }

  /// True when [worldPos] is over a TASK block that is currently interactive
  /// (lasso tool active and the block isn't the lasso selection). Text blocks
  /// are excluded: in lasso mode a tap on them lasso-selects (they only edit in
  /// text mode).
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
    // The stylus must never pan. The InteractiveViewer's pan recognizer can win
    // the gesture arena on a fast stroke before `panEnabled` flips to false, so
    // pin the view back to its stylus-down transform on every move — any leaked
    // pan is undone before it can drift.
    if (_stylusActive &&
        _palmRejection &&
        _transformBeforeStylus != null &&
        !_eyedropperMode &&
        _viewCtrl.value != _transformBeforeStylus) {
      _viewCtrl.value = _transformBeforeStylus!;
    }
    if (_eyedropperMode) {
      if (_activePointers.length < 2) _moveLoupe(e.localPosition);
      return;
    }
    if (_exportMarquee) {
      // Only a single finger draws/adjusts; with 2+ the InteractiveViewer pans.
      if (_marqueePointers.length != 1 || _marqueeDrag == null) return;
      final w = _screenToWorld(e.localPosition);
      final drag = _marqueeDrag!;
      if (drag == _MarqueeHandle.draw) {
        setState(() => _marqueeWorld = Rect.fromPoints(_marqueeDrawStart!, w));
      } else if (drag == _MarqueeHandle.move) {
        final d = w - _marqueeDragAnchorWorld!;
        setState(() => _marqueeWorld = _marqueeRectAtDragStart!.shift(d));
      } else {
        setState(
          () => _marqueeWorld = _resizeMarquee(_marqueeRectAtDragStart!, drag, w),
        );
      }
      return;
    }
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
      _active!.points.add([
        sp.dx,
        sp.dy,
        pressure,
        e.timeStamp.inMilliseconds.toDouble(),
      ]);
      _activeTick.value++;
      return;
    }
    final pts = _active!.points;
    _rawPen.add([p.dx, p.dy]);
    if (pts.isNotEmpty && !_stabilizer.isOn) {
      final dx = sp.dx - pts.last[0];
      final dy = sp.dy - pts.last[1];
      if (dx * dx + dy * dy < _minDist2) return;
    }
    pts.add(_active!.isPencil
        ? [sp.dx, sp.dy, e.pressure.isFinite ? e.pressure : 0.5]
        : [sp.dx, sp.dy]);
    _activeTick.value++;
    if (_holdAnchor != null) {
      final dx = sp.dx - _holdAnchor!.dx;
      final dy = sp.dy - _holdAnchor!.dy;
      if (dx * dx + dy * dy > _holdTolerance2) {
        _startHoldTimer(sp);
      }
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_eyedropperMode) {
      _activePointers.remove(e.pointer);
      setState(() {});
      return;
    }
    if (_exportMarquee) {
      // Lifting a finger never exports — the rect stays (with handles) for
      // adjustment until the user taps confirm.
      _marqueePointers.remove(e.pointer);
      final wasDraw = _marqueeDrag == _MarqueeHandle.draw;
      _marqueeDrag = null;
      if (wasDraw) {
        _marqueeDrawStart = null;
        final r = _marqueeWorld;
        if (r == null || r.width < 8 || r.height < 8) {
          setState(() => _marqueeWorld = _marqueeRectBackup);
        }
        _marqueeRectBackup = null;
      } else {
        setState(() {}); // refresh handle positions after move/resize
      }
      return;
    }
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
      final elapsed =
          _multiFingerDownTime != null
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
    if (_eyedropperMode) {
      _activePointers.remove(e.pointer);
      setState(() {});
      return;
    }
    if (_exportMarquee) {
      _marqueePointers.remove(e.pointer);
      _marqueeDrag = null;
      _marqueeDrawStart = null;
      return;
    }
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
      (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite,
    );
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      return;
    }

    final scribblePts =
        _rawPen.length >= _active!.points.length ? _rawPen : _active!.points;
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
      (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite,
    );
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
          worldPos,
          _data.strokes,
          _data.images,
          _data.taskBlocks,
        );
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(worldPos);
      if (corner != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startResize(
          corner,
          worldPos,
          _data.strokes,
          _data.images,
          _data.taskBlocks,
        );
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(worldPos);
      if (side != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startSideResize(
          side,
          worldPos,
          _data.strokes,
          _data.images,
          _data.taskBlocks,
        );
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(worldPos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startMove(
          worldPos,
          _data.strokes,
          _data.images,
          _data.taskBlocks,
        );
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
      _lassoCtrl.finishTracing(
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        _data.textBlocks,
      );
      _toolbarVisible =
          false; // a fresh selection starts with the toolbar hidden
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      final moved = _lassoCtrl.dragOffset.distance * _viewScale > 6;
      _lassoCtrl.finishMove(
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        0,
        _data.textBlocks,
      );
      _finishTransformOrTap(moved);
    } else if (_lassoCtrl.phase == LassoPhase.resizing) {
      final side = _lassoCtrl.isSideResize;
      final cornerScale = _lassoCtrl.resizeScale;
      final sideScaleX = _lassoCtrl.resizeScaleX;
      final sideScaleY = _lassoCtrl.resizeScaleY;
      final moved =
          side
              ? (sideScaleX - 1).abs() > 0.02 || (sideScaleY - 1).abs() > 0.02
              : (cornerScale - 1).abs() > 0.02;
      side
          ? _lassoCtrl.finishSideResize(
            _data.strokes,
            _data.images,
            _data.taskBlocks,
            _data.textBlocks,
          )
          : _lassoCtrl.finishResize(
            _data.strokes,
            _data.images,
            _data.taskBlocks,
            _data.textBlocks,
          );
      for (final i in _lassoCtrl.selectedBlockIndices) {
        if (i >= _data.taskBlocks.length) continue;
        final b = _data.taskBlocks[i];
        if (!side) b.scale = (b.scale * cornerScale).clamp(0.2, 8.0);
        if (b.w < kCanvasTextBlockMinW) b.w = kCanvasTextBlockMinW;
      }
      for (final i in _lassoCtrl.selectedTextBlockIndices) {
        if (i >= _data.textBlocks.length) continue;
        final b = _data.textBlocks[i];
        // Corner = uniform scale (text grows with box). Horizontal side = width
        // reflow (controller already set w). Vertical resize is disabled for
        // text (hitTestSideHandle skips top/bottom for text-only selections).
        if (!side) b.scale = (b.scale * cornerScale).clamp(0.2, 8.0);
        if (b.w < kCanvasTextBlockMinW) b.w = kCanvasTextBlockMinW;
      }
      _finishTransformOrTap(moved);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      final moved = _lassoCtrl.rotationAngle.abs() > 0.01;
      _lassoCtrl.finishRotation(
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        _data.textBlocks,
      );
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
    _lassoMutate(
      () => _lassoCtrl.deleteSelected(
        _data.strokes,
        _data.images,
        _data.taskBlocks,
        _data.textBlocks,
      ),
    );
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    _lassoMutate(
      () => _lassoCtrl.duplicateSelected(_data.strokes, _data.images),
    );
    HapticFeedback.lightImpact();
  }

  bool get _singleImageSelected =>
      _lassoCtrl.selectedImageIndices.length == 1 &&
      _lassoCtrl.selectedIndices.isEmpty;

  /// True when the lasso selection contains handwriting (pen/fountain), the
  /// only thing OCR can read. Shapes/highlighter/images don't count.
  bool get _selectionHasWriting {
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= _data.strokes.length) continue;
      final s = _data.strokes[i];
      if (!s.isHighlighter && !s.isShape) return true;
    }
    return false;
  }

  /// OCR the selected handwriting → editable result sheet (shared flow).
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

  Future<void> _recognizeSelection() async {
    final strokes = _selectedWritingStrokes();
    runOcrFlow(
      context,
      ref,
      strokes,
      accent: _accent,
      folderId: widget.note.folderId,
      noteId: widget.note.id,
    );
  }

  Future<void> _sendSelectionToYuli() async {
    final strokes = _selectedWritingStrokes();
    runOcrToYuliFlow(
      context,
      ref,
      strokes,
      accent: _accent,
      noteId: widget.note.id,
    );
  }

  Future<void> _sendMathSelectionToYuli() async {
    final strokes = _selectedWritingStrokes();
    runMathToYuliFlow(
      context,
      ref,
      strokes,
      accent: _accent,
      noteId: widget.note.id,
    );
  }

  Future<void> _cropSelectedImage() async {
    final dirPath = _imageDirPath;
    if (dirPath == null || !_singleImageSelected) return;
    final idx = _lassoCtrl.selectedImageIndices.first;
    if (idx >= _data.images.length) return;
    final img = _data.images[idx];
    final result = await Navigator.of(context).push<CropResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder:
            (_) => ImageCropScreen(
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
    final gesture =
        _lassoCtrl.phase == LassoPhase.moving ||
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
          accent: _accent,
          interactive:
              !selected &&
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
              _data.strokes,
              _data.images,
              _data.taskBlocks,
            );
            _persist();
          },
        ),
      );
      // Selected + mid-gesture: follow the live lasso transform for move/rotate.
      // During corner resize (uniform scale) the transform is fine; during side
      // resize (non-uniform) the widget stays at original size so text doesn't
      // distort, snapping to the new geometry on release.
      final isLiveTransform =
          _lassoCtrl.phase == LassoPhase.moving ||
          _lassoCtrl.phase == LassoPhase.rotating ||
          (_lassoCtrl.phase == LassoPhase.resizing && !_lassoCtrl.isSideResize);
      if (isLiveTransform && selected) {
        final off = Offset(b.x, b.y);
        final tm =
            Matrix4.translationValues(-off.dx, -off.dy, 0) *
            _lassoCtrl.liveGestureMatrix() *
            Matrix4.translationValues(off.dx, off.dy, 0);
        overlay = Transform(transform: tm, child: overlay);
      }
      out.add(Positioned(left: b.x, top: b.y, child: overlay));
    }
    return out;
  }

  List<Widget> _buildTextBlockOverlays() {
    final gesture =
        _lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating;
    final out = <Widget>[];
    for (int i = 0; i < _data.textBlocks.length; i++) {
      final b = _data.textBlocks[i];
      final selected = _lassoCtrl.selectedTextBlockIndices.contains(i);
      Widget overlay = RepaintBoundary(
        child: CanvasTextBlockOverlay(
          key: ValueKey(b.id),
          block: b,
          accent: _accent,
          // Text blocks are ONLY interactive (tap = edit, drag = move) in text
          // mode. In pen/lasso modes they're inert (IgnorePointer): the lasso
          // selects/moves/resizes them by geometry, pens never touch them. This
          // also avoids a multi-touch crash (finger on block + 2-finger zoom).
          interactive: !selected && !gesture && _tool == DrawTool.text,
          movable: !selected && !gesture && _tool == DrawTool.text,
          onPersist: _persist,
          onChanged: () {
            if (mounted) setState(() {});
          },
          onHeightMeasured: (h) {
            if (!mounted) return;
            setState(() => b.h = h);
            _lassoCtrl.refreshBoundingBox(
              _data.strokes,
              _data.images,
              _data.taskBlocks,
              _data.textBlocks,
            );
            _persist();
          },
          onDragStart: () => _gestureBefore = _snapshot(),
          onDragEnd: () {
            _commitGesture();
            _persist();
          },
        ),
      );
      final isLiveTransform =
          _lassoCtrl.phase == LassoPhase.moving ||
          _lassoCtrl.phase == LassoPhase.rotating ||
          (_lassoCtrl.phase == LassoPhase.resizing && !_lassoCtrl.isSideResize);
      if (isLiveTransform && selected) {
        final off = Offset(b.x, b.y);
        final tm =
            Matrix4.translationValues(-off.dx, -off.dy, 0) *
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
    final screenTop = MatrixUtils.transformPoint(
      _viewCtrl.value,
      Offset(bb.center.dx, bb.top),
    );
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
        onRecognizeText: _selectionHasWriting ? _recognizeSelection : null,
        onSendToYuli: _selectionHasWriting ? _sendSelectionToYuli : null,
        // Mathpix math OCR is debug-only for now (too costly for current scope).
        onSendMathToYuli:
            (kDebugMode && _selectionHasWriting)
                ? _sendMathSelectionToYuli
                : null,
        palette: _palette,
        onColorChange:
            (c) => _lassoMutate(
              () => _lassoCtrl.changeColor(_data.strokes, c.toARGB32()),
            ),
        onWidthChange:
            (w) => _lassoMutate(() => _lassoCtrl.changeWidth(_data.strokes, w)),
        onFlipH:
            () => _lassoMutate(() => _lassoCtrl.flipHorizontal(_data.strokes)),
        onFlipV:
            () => _lassoMutate(() => _lassoCtrl.flipVertical(_data.strokes)),
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
          _lassoMutate(
            () => _lassoCtrl.cutSelected(
              _data.strokes,
              _data.images,
              _data.taskBlocks,
            ),
          );
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
    final screenPos = MatrixUtils.transformPoint(
      _viewCtrl.value,
      _showPasteAt!,
    );
    return Positioned(
      left: screenPos.dx - 40,
      top: screenPos.dy - 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_tool != DrawTool.lasso) {
            setState(() => _tool = DrawTool.lasso);
          }
          _lassoMutate(
            () => _lassoCtrl.pasteAt(
              _showPasteAt!,
              _data.strokes,
              _data.images,
              0,
            ),
          );
          HapticFeedback.mediumImpact();
          setState(() => _showPasteAt = null);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow: const [
              BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(YuLiIcons.clipboard, size: 12, color: yInk),
              const SizedBox(width: 6),
              Text(
                'PEGAR',
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Undo / redo (snapshot history) ─────────────────────────────────────

  (
    List<DrawingStroke>,
    List<CanvasImage>,
    List<CanvasTaskBlock>,
    List<CanvasTextBlock>,
  )
  _snapshot() => (
    _data.strokes.map((s) => s.clone()).toList(),
    _data.images.map((im) => im.clone()).toList(),
    _data.taskBlocks.map((b) => b.clone()).toList(),
    _data.textBlocks.map((b) => b.clone()).toList(),
  );

  void _commit(
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
    before,
  ) {
    _undoStack.add(before);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _restore(
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
    snap,
  ) {
    _data.strokes = snap.$1;
    _data.images = snap.$2;
    _data.taskBlocks = snap.$3;
    _data.textBlocks = snap.$4;
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
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Borrar pizarra',
              style: ySans(size: 18, weight: FontWeight.w700),
            ),
            content: Text('¿Borrar todos los trazos?', style: yBody(size: 13)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Borrar'),
              ),
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
        _viewport.width / 2 - cx,
        _viewport.height / 2 - cy,
        0,
      );
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
    for (final b in _data.textBlocks) {
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
        _viewport.width / 2 - cx,
        _viewport.height / 2 - cy,
        0,
      );
    });
  }

  void _zoomToFit() {
    final box =
        (_lassoCtrl.phase == LassoPhase.selected &&
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
      _viewCtrl.value =
          Matrix4.translationValues(vw / 2, vh / 2, 0)
            ..multiply(Matrix4.diagonal3Values(s, s, 1))
            ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
    });
  }

  Future<void> _linkToLab(List<LabSpace> spaces) async {
    if (spaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay spaces activos'),
          duration: Duration(seconds: 2),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ya vinculada a ${picked.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final labRepo = ref.read(labSpaceRepositoryProvider);
    final columns = await labRepo.getColumns(picked.id);
    if (columns.isEmpty) return;
    final backlog = columns.firstWhere(
      (c) => c.name == 'Backlog' || c.name.toLowerCase() == 'backlog',
      orElse:
          () => columns.firstWhere(
            (c) => !c.isTerminal && !c.isExpired,
            orElse: () => columns.first,
          ),
    );
    final title =
        (widget.note.title?.trim().isNotEmpty == true)
            ? widget.note.title!
            : 'Pizarra ${widget.folder.name}';
    await kanbanRepo.create(
      labSpaceId: picked.id,
      columnId: backlog.id,
      title: title,
      sourceNoteId: widget.note.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pizarra vinculada a ${picked.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color get _accent => widget.note.color ?? widget.folder.color;

  Widget _buildWhiteboardBackgroundLayer(Size viewport) {
    return AnimatedBuilder(
      animation: _viewCtrl,
      builder: (_, _) {
        final visibleRect = _renderRectFor(viewport);
        return RepaintBoundary(
          child: CustomPaint(
            painter: _CanvasPainter(
              strokes: _data.strokes,
              images: _data.images,
              imageCache: _imgCache,
              background: _data.background,
              paper: bgPaper(_data.bgColorValue, yCream),
              visibleRect: visibleRect,
              paintVersion: _paintVersion,
              hiddenImageIndices:
                  (_lassoCtrl.phase == LassoPhase.moving ||
                          _lassoCtrl.phase == LassoPhase.resizing ||
                          _lassoCtrl.phase == LassoPhase.rotating)
                      ? _lassoCtrl.selectedImageIndices
                      : null,
              drawStrokes: false,
            ),
            size: const Size(_kCanvasW, _kCanvasH),
          ),
        );
      },
    );
  }

  Widget _buildWhiteboardStrokeLayer(Size viewport) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _viewCtrl,
        builder: (_, _) {
          final visibleRect = _renderRectFor(viewport);
          return RepaintBoundary(
            child: CustomPaint(
              painter: _CanvasPainter(
                strokes: _data.strokes,
                images: _data.images,
                imageCache: _imgCache,
                background: _data.background,
                paper: bgPaper(_data.bgColorValue, yCream),
                visibleRect: visibleRect,
                paintVersion: _paintVersion,
                hiddenIndices:
                    (_lassoCtrl.phase == LassoPhase.moving ||
                            _lassoCtrl.phase == LassoPhase.resizing ||
                            _lassoCtrl.phase == LassoPhase.rotating)
                        ? _lassoCtrl.selectedIndices
                        : null,
                drawBackground: false,
              ),
              size: const Size(_kCanvasW, _kCanvasH),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWhiteboardLassoLayer(Size viewport) {
    if (_lassoCtrl.phase == LassoPhase.idle) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_viewCtrl, _lassoAnimCtrl]),
      builder: (_, _) {
        final visibleRect = _visibleRectFor(viewport);
        return CustomPaint(
          painter: LassoPainter(
            ctrl: _lassoCtrl,
            animValue: _lassoAnimCtrl.value,
            strokes: _data.strokes,
            images: _data.images,
            imageCache: _imgCache,
            visibleRect: visibleRect,
          ),
          size: const Size(_kCanvasW, _kCanvasH),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
    final linkedCards =
        ref.watch(kanbanCardsByNoteProvider(widget.note.id)).valueOrNull ?? [];
    final linkedSpaceIds = linkedCards.map((c) => c.labSpaceId).toSet();
    final linkedSpaces =
        spaces.where((s) => linkedSpaceIds.contains(s.id)).toList();
    final hasAiKey = ref.watch(aiHasKeyProvider).valueOrNull ?? false;
    final aiLinked =
        (ref
            .watch(canvasContextSourcesProvider(widget.note.id))
            .valueOrNull
            ?.isNotEmpty) ??
        false;

    return Scaffold(
      backgroundColor: yCream,
      body: StatusBarFlood(
        color: _headerCollapsed ? yCream2 : _accent,
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_headerCollapsed)
                    _CollapsedWhiteboardHeader(
                      folder: widget.folder,
                      spaces: spaces,
                      accent: _accent,
                      hasAiKey: hasAiKey,
                      aiLinked: aiLinked,
                      noteTitle: widget.note.title ?? '',
                      onExpand: () => setState(() => _headerCollapsed = false),
                      onReset: _resetView,
                      onLink: () => _linkToLab(spaces),
                      onAi:
                          () => showAiChat(
                            context,
                            ref,
                            noteId: widget.note.id,
                            accent: _accent,
                            onSendToCanvas: _insertTextBlock,
                          ),
                    )
                  else ...[
                    Column(
                      children: [
                        ModeHeader(
                          mode: 'PIZARRA',
                          subtitle: (widget.note.title?.trim().isNotEmpty == true)
                              ? 'INFINITA · CANVAS · PAN + ZOOM · ${widget.note.title!.trim()}'
                              : 'INFINITA · CANVAS · PAN + ZOOM',
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
                            onTap: _resetView,
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: yCream,
                                border: Border.all(
                                  color: yBorderStrong,
                                  width: yLineMid,
                                ),
                              ),
                              child: const Icon(
                                YuLiIcons.scan,
                                color: yInk,
                                size: 16,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _linkToLab(spaces),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: yLab,
                                border: Border.all(
                                  color: yBorderStrong,
                                  width: yLineMid,
                                ),
                              ),
                              child: const Icon(
                                YuLiIcons.infinity,
                                color: yCream,
                                size: 16,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap:
                                hasAiKey
                                    ? () => showAiChat(
                                      context,
                                      ref,
                                      noteId: widget.note.id,
                                      accent: _accent,
                                      onSendToCanvas: _insertTextBlock,
                                    )
                                    : null,
                            child: AiLinkBadge(
                              active: aiLinked,
                              color: _accent,
                              child: Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: hasAiKey ? _accent : yMuted,
                                  border: Border.all(
                                    color: yBorderStrong,
                                    width: yLineMid,
                                  ),
                                ),
                                child: Icon(
                                  YuLiIcons.sparkles,
                                  color: hasAiKey ? yCream : yCream2,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap:
                                () => setState(() => _headerCollapsed = true),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: yCream,
                                border: Border.all(
                                  color: yBorderStrong,
                                  width: yLineMid,
                                ),
                              ),
                              child: const Icon(
                                YuLiIcons.chevronUp,
                                color: yInk,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (linkedSpaces.isNotEmpty)
                        _LinkedSpacesBar(spaces: linkedSpaces),
                      ],
                    ),
                  ],
                Expanded(
                child: LayoutBuilder(
                  builder: (ctx, c) {
                    _viewport = Size(c.maxWidth, c.maxHeight);
                    _maybeInitView();
                    final viewport = Size(c.maxWidth, c.maxHeight);
                    final textBlockOverlays = _buildTextBlockOverlays();
                    final taskBlockOverlays = _buildTaskBlockOverlays();
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        RepaintBoundary(
                          key: _canvasBoundaryKey,
                          child: ClipRect(
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
                                onInteractionEnd: (_) {
                                  // After a 2-finger pan/zoom the snapshot is
                                  // stale → recapture so the loupe keeps sampling
                                  // the right pixels (keeps its position).
                                  if (_eyedropperMode &&
                                      _eyedropCaptureMatrix != null &&
                                      _viewCtrl.value != _eyedropCaptureMatrix) {
                                    _captureEyedropSnapshot(resetPos: false);
                                  }
                                },
                                boundaryMargin: const EdgeInsets.all(
                                  _kCanvasW * 0.5,
                                ),
                                // Text mode: 1-finger drag is reserved for moving
                                // a box (its GestureDetector), so disable pan;
                                // 2-finger still zooms/navigates.
                                panEnabled:
                                    _eyedropperMode
                                        ? _activePointers.length >= 2
                                        : _exportMarquee
                                        ? false
                                        : _tool == DrawTool.text
                                        ? false
                                        : _tool == DrawTool.task
                                        ? false
                                        : _tool == DrawTool.lasso
                                        ? (_lassoCtrl.phase ==
                                                LassoPhase.idle &&
                                            !_isDrawing)
                                        : _palmRejection
                                        ? !_stylusActive
                                        : !_isDrawing,
                                scaleEnabled:
                                    _eyedropperMode
                                        ? _activePointers.length >= 2
                                        : _exportMarquee
                                        ? true
                                        : _tool == DrawTool.text
                                        ? true
                                        : _tool == DrawTool.task
                                        ? true
                                        : _tool == DrawTool.lasso
                                        ? (_lassoCtrl.phase ==
                                                LassoPhase.idle &&
                                            !_isDrawing)
                                        : !_stylusActive && !_locked,
                                constrained: false,
                                child: SizedBox(
                                  width: _kCanvasW,
                                  height: _kCanvasH,
                                  child: Stack(
                                    children: [
                                      _buildWhiteboardBackgroundLayer(viewport),
                                      // Text blocks sit BELOW the ink so strokes
                                      // drawn over them stay visible.
                                      ...textBlockOverlays,
                                      _buildWhiteboardStrokeLayer(viewport),
                                      IgnorePointer(
                                        child: RepaintBoundary(
                                          child: AnimatedBuilder(
                                            animation: _activeTick,
                                            builder:
                                                (_, _) => CustomPaint(
                                                  painter: _ActiveStrokePainter(
                                                    active: _active,
                                                    tick: _activeTick.value,
                                                  ),
                                                  size: const Size(
                                                    _kCanvasW,
                                                    _kCanvasH,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      // Task blocks above the ink (interactive UI).
                                      ...taskBlockOverlays,
                                      _buildWhiteboardLassoLayer(viewport),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ),
                        ),
                        // Floating palettes — sibling of the canvas Listener so
                        // touching a palette never leaks a pointer into a stroke.
                        // They slide off toward their edge during the eyedropper.
                        if (_palettes != null)
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _palettes!,
                              builder: (_, _) => FloatingPalettesLayer(
                                controller: _palettes!,
                                accent: _accent,
                                activeColor: _color,
                                activeWidth: _strokeW,
                                hidden: _eyedropperMode,
                                onPickColor: _commitColor,
                                onPickWidth: _commitWidth,
                                onInsertShape: _insertShape,
                                onUndo: _undo,
                                onRedo: _redo,
                                canUndo: _undoStack.isNotEmpty,
                                canRedo: _redoStack.isNotEmpty,
                                onEyedropper: () => _enterEyedropper(
                                  onPick: (c) => _palettes?.addColor(c),
                                ),
                              ),
                            ),
                          ),
                        if (_lassoCtrl.phase == LassoPhase.selected &&
                            _toolbarVisible)
                          _buildLassoMiniToolbar(),
                        if (_showPasteAt != null) _buildPasteButton(),
                        if (_tool == DrawTool.eraser && _eraserCursor != null)
                          Positioned(
                            left: _eraserCursor!.dx - _eraserScreenRadius,
                            top: _eraserCursor!.dy - _eraserScreenRadius,
                            child: const EraserCursor(
                              radius: _eraserScreenRadius,
                            ),
                          ),
                        // Eyedropper loupe (viewport-space, like the palettes).
                        if (_eyedropImg != null) ..._buildLoupeOverlay(viewport),
                        // Lives INSIDE the canvas Stack so the painter shares the
                        // InteractiveViewer's viewport space — the same space as
                        // `e.localPosition` used for handle hit-testing. In the
                        // outer Stack it was offset by the header height, so the
                        // visible handles sat above their hit area and dragging
                        // them started a fresh marquee instead of resizing.
                        if (_exportMarquee)
                          Positioned.fill(
                            child: _ExportMarqueeOverlay(
                              accent: _accent,
                              viewCtrl: _viewCtrl,
                              worldRect: _marqueeWorld,
                              onConfirm: _confirmMarquee,
                              onCancel: _cancelMarquee,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              _toolbar(),
            ],
          ),
          RevealPopup(
            key: const ValueKey('rp-image'),
            open: _imagePanelOpen,
            onDismiss: _toggleImagePanel,
            child: ImageInsertPanel(
              accent: _accent,
              onPick: (file) {
                _toggleImagePanel();
                _insertImageFile(file);
              },
              onClose: _toggleImagePanel,
            ),
          ),
          RevealPopup(
            key: const ValueKey('rp-bg'),
            open: _bgPopupOpen,
            onDismiss: _toggleBgPopup,
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
          RevealPopup(
            key: const ValueKey('rp-bgcolor'),
            open: _bgColorPickerOpen,
            onDismiss: () => setState(() => _bgColorPickerOpen = false),
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
          RevealPopup(
            key: const ValueKey('rp-eraser'),
            open: _eraserPopupOpen,
            onDismiss: () => setState(() => _eraserPopupOpen = false),
            child: _eraserModePopup(),
          ),
          RevealPopup(
            key: const ValueKey('rp-shape'),
            open: _shapePopupOpen,
            onDismiss: () => setState(() => _shapePopupOpen = false),
            child: ShapePickerPopup(accent: _accent, onPick: _insertShape),
          ),
          RevealPopup(
            key: const ValueKey('rp-more'),
            open: _morePopupOpen,
            onDismiss: () => setState(() => _morePopupOpen = false),
            child: _buildMorePopup(),
          ),
          RevealPopup(
            key: const ValueKey('rp-width'),
            open: _widthPickerOpen,
            onDismiss: _toggleWidthPicker,
            child: StrokeWidthPopup(
              currentWidth: _strokeW,
              recentWidths: _recentWidths,
              accentColor: _accent,
              onPreview: (v) => setState(() => _strokeW = v),
              onCommit: _commitWidth,
              onClose: _toggleWidthPicker,
            ),
          ),
          RevealPopup(
            key: const ValueKey('rp-color'),
            open: _colorPickerOpen,
            onDismiss: _toggleColorPicker,
            child: ColorPickerPopup(
              currentColor: _color,
              recentColors: _recentColors,
              savedColors: _savedColors,
              onPreview: (c) => setState(() => _color = c),
              onCommit: _commitColor,
              onStar: _starColor,
              onEyedropper: () => _enterEyedropper(),
              onClose: _toggleColorPicker,
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Export ────────────────────────────────────────────────────────────

  /// World-space rects of the blocks that will be exported (text always; tasks
  /// only when [includeTasks]). Used to grow the "export everything" bounds.
  List<Rect> _exportBlockRects(bool includeTasks) {
    final rects = <Rect>[
      for (final b in _data.textBlocks) Rect.fromLTWH(b.x, b.y, b.w, b.h),
    ];
    if (includeTasks) {
      for (final b in _data.taskBlocks) {
        rects.add(Rect.fromLTWH(b.x, b.y, b.w, b.h));
      }
    }
    return rects;
  }

  /// Off-screen raster specs for the visible blocks (rotation-zeroed clones; the
  /// rotation is re-applied at composite time).
  List<BlockRasterSpec> _exportBlockSpecs(bool includeTasks) {
    final specs = <BlockRasterSpec>[];
    for (final b in _data.textBlocks) {
      final clone = b.clone()..rotation = 0;
      specs.add(
        BlockRasterSpec(
          worldPos: Offset(b.x, b.y),
          rotation: b.rotation,
          child: CanvasTextBlockOverlay(
            block: clone,
            accent: _accent,
            interactive: false,
            onPersist: () async {},
            onChanged: () {},
            onHeightMeasured: (_) {},
          ),
        ),
      );
    }
    if (includeTasks) {
      for (final b in _data.taskBlocks) {
        final clone = b.clone()..rotation = 0;
        specs.add(
          BlockRasterSpec(
            worldPos: Offset(b.x, b.y),
            rotation: b.rotation,
            child: CanvasTaskBlockOverlay(
              block: clone,
              noteId: widget.note.id,
              folderId: widget.note.folderId,
              folderName: widget.folder.name,
              accent: _accent,
              interactive: false,
              onPersist: () async {},
              onTasksChanged: () {},
              onHeightMeasured: (_) {},
            ),
          ),
        );
      }
    }
    return specs;
  }

  Future<void> _startExport() async {
    setState(() => _morePopupOpen = false);
    final hasTasks = _data.taskBlocks.isNotEmpty;
    final opts = await showWhiteboardExportSheet(
      context,
      accent: _accent,
      hasTasks: hasTasks,
    );
    if (opts == null || !mounted) return;
    if (opts.region == WhiteboardRegion.marquee) {
      setState(() {
        _pendingExport = opts;
        _exportMarquee = true;
        _marqueeWorld = null;
        _marqueePointers.clear();
        _marqueeDrag = null;
        _marqueeDrawStart = null;
        _marqueeRectBackup = null;
      });
      HapticFeedback.lightImpact();
      return;
    }
    final bounds = contentBounds(
      _data,
      blockRects: _exportBlockRects(opts.includeTasks),
    );
    if (bounds == null || bounds.isEmpty) {
      _showExportEmpty();
      return;
    }
    _runExport(opts, bounds.inflate(24));
  }

  void _cancelMarquee() {
    setState(() {
      _exportMarquee = false;
      _marqueeWorld = null;
      _pendingExport = null;
      _marqueePointers.clear();
      _marqueeDrag = null;
      _marqueeDrawStart = null;
      _marqueeRectBackup = null;
    });
  }

  void _confirmMarquee() {
    final opts = _pendingExport;
    final region = _marqueeWorld;
    if (opts == null || region == null) return;
    if (region.width < 8 || region.height < 8) {
      _showExportEmpty(message: 'Área demasiado pequeña');
      return;
    }
    setState(() {
      _exportMarquee = false;
      _marqueeWorld = null;
      _pendingExport = null;
      _marqueePointers.clear();
      _marqueeDrag = null;
      _marqueeDrawStart = null;
      _marqueeRectBackup = null;
    });
    _runExport(opts, region);
  }

  /// Selection rect (world) → screen, normalized (left<right, top<bottom).
  Rect _worldRectToScreen(Rect world) {
    final tl = MatrixUtils.transformPoint(_viewCtrl.value, world.topLeft);
    final br = MatrixUtils.transformPoint(_viewCtrl.value, world.bottomRight);
    return Rect.fromPoints(tl, br);
  }

  /// Which handle (if any) is under [p] for the on-screen selection [sr].
  /// Corners win over sides. ~24px touch tolerance.
  _MarqueeHandle? _hitMarqueeHandle(Offset p, Rect sr) {
    const tol = 24.0;
    bool near(Offset h) => (p - h).distance <= tol;
    if (near(sr.topLeft)) return _MarqueeHandle.tl;
    if (near(sr.topRight)) return _MarqueeHandle.tr;
    if (near(sr.bottomLeft)) return _MarqueeHandle.bl;
    if (near(sr.bottomRight)) return _MarqueeHandle.br;
    if (near(sr.topCenter)) return _MarqueeHandle.t;
    if (near(sr.bottomCenter)) return _MarqueeHandle.b;
    if (near(sr.centerLeft)) return _MarqueeHandle.l;
    if (near(sr.centerRight)) return _MarqueeHandle.r;
    return null;
  }

  /// Resize [base] (world) by moving the edge(s) of [handle] to world point [w].
  Rect _resizeMarquee(Rect base, _MarqueeHandle handle, Offset w) {
    var l = base.left, t = base.top, r = base.right, b = base.bottom;
    switch (handle) {
      case _MarqueeHandle.tl:
        l = w.dx;
        t = w.dy;
      case _MarqueeHandle.tr:
        r = w.dx;
        t = w.dy;
      case _MarqueeHandle.bl:
        l = w.dx;
        b = w.dy;
      case _MarqueeHandle.br:
        r = w.dx;
        b = w.dy;
      case _MarqueeHandle.t:
        t = w.dy;
      case _MarqueeHandle.b:
        b = w.dy;
      case _MarqueeHandle.l:
        l = w.dx;
      case _MarqueeHandle.r:
        r = w.dx;
      case _MarqueeHandle.move:
      case _MarqueeHandle.draw:
        break;
    }
    return Rect.fromLTRB(l < r ? l : r, t < b ? t : b, l < r ? r : l, t < b ? b : t);
  }

  Future<void> _runExport(CanvasExportOptions opts, Rect region) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportProgressDialog(accent: _accent),
    );
    final images = <String, ui.Image>{};
    final blocks = <ExportBlockImage>[];
    ui.Image? rendered;
    try {
      final pr = exportPixelRatio(region);
      final specs = _exportBlockSpecs(opts.includeTasks);
      blocks.addAll(
        await rasterizeCanvasBlocks(
          context: context,
          specs: specs,
          pixelRatio: pr,
        ),
      );
      images.addAll(await loadExportImages(_imageDirPath, _data.images));
      rendered = await renderCanvasRegion(
        data: _data,
        region: region,
        pixelRatio: pr,
        paper: bgPaper(_data.bgColorValue, yCream),
        images: images,
        blocks: blocks,
      );
      final name = sanitizeFilename(
        widget.note.title?.isNotEmpty == true
            ? widget.note.title!
            : widget.folder.name,
      );
      if (opts.format == ExportFormat.png) {
        final png = await imageToPngBytes(rendered);
        await shareExportBytes(png, '$name.png', text: 'Pizarra · YuLi');
      } else {
        final pdf = await buildCanvasPdf([
          ExportPage(image: rendered, worldSize: region.size),
        ]);
        await shareExportBytes(pdf, '$name.pdf', text: 'Pizarra · YuLi');
      }
    } catch (_) {
      if (mounted) _showExportEmpty(message: 'No se pudo exportar');
    } finally {
      rendered?.dispose();
      for (final b in blocks) {
        b.image.dispose();
      }
      disposeExportImages(images);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showExportEmpty({String message = 'Nada que exportar'}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _togglePalette(FloatingPaletteKind kind) {
    if (_palettes == null) return;
    HapticFeedback.selectionClick();
    setState(() => _palettes!.toggle(kind));
  }

  Widget _toolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolBtn(
                icon: YuLiIcons.pen,
                active: _tool == DrawTool.pen,
                tooltip: 'Lápiz',
                onTap: () => _selectTool(DrawTool.pen),
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.penTool,
                active: _tool == DrawTool.fountainPen,
                tooltip: 'Pluma fuente',
                onTap: () => _selectTool(DrawTool.fountainPen),
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.pencil,
                active: _tool == DrawTool.pencil,
                tooltip: 'Lápiz',
                onTap: () => _selectTool(DrawTool.pencil),
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.highlighter,
                active: _tool == DrawTool.highlighter,
                tooltip: 'Resaltador',
                onTap: () => _selectTool(DrawTool.highlighter),
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon:
                    _eraserMode == EraserMode.partial
                        ? YuLiIcons.eraser
                        : YuLiIcons.wandSparkles,
                active: _tool == DrawTool.eraser,
                tooltip: 'Borrador',
                onTap: () {
                  if (_tool == DrawTool.eraser) {
                    setState(() => _eraserPopupOpen = !_eraserPopupOpen);
                  } else {
                    _selectTool(DrawTool.eraser);
                  }
                },
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.lasso,
                active: _tool == DrawTool.lasso,
                tooltip: 'Lazo',
                onTap: () => _selectTool(DrawTool.lasso),
              ),
              _divider(),
              _toolBtn(
                icon: YuLiIcons.image,
                active: _imagePanelOpen,
                tooltip: 'Imagen',
                onTap: _toggleImagePanel,
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.listChecks,
                active: _tool == DrawTool.task,
                tooltip: 'Tareas',
                onTap: _enterTaskMode,
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.textInitial,
                active: _tool == DrawTool.text,
                tooltip: 'Texto',
                onTap: _enterTextMode,
              ),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _togglePalette(FloatingPaletteKind.shapes),
                child: _toolBtn(
                  icon: YuLiIcons.shapes,
                  active: _shapePopupOpen,
                  onTap: _toggleShapePopup,
                ),
              ),
              _divider(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _togglePalette(FloatingPaletteKind.colors),
                child: ColorButton(
                  currentColor: _color,
                  isOpen: _colorPickerOpen,
                  onTap: _toggleColorPicker,
                ),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _togglePalette(FloatingPaletteKind.widths),
                child: StrokeWidthButton(
                  currentWidth: _strokeW,
                  isOpen: _widthPickerOpen,
                  accentColor: _accent,
                  onTap: _toggleWidthPicker,
                ),
              ),
              _divider(),
              _toolBtn(
                icon: YuLiIcons.undo,
                active: false,
                enabled: _undoStack.isNotEmpty,
                tooltip: 'Deshacer',
                onTap: _undo,
              ),
              const SizedBox(width: 10),
              _toolBtn(
                icon: YuLiIcons.redo,
                active: false,
                enabled: _redoStack.isNotEmpty,
                tooltip: 'Rehacer',
                onTap: _redo,
              ),
              _divider(),
              _toolBtn(
                icon: YuLiIcons.moreHorizontal,
                active: _morePopupOpen,
                tooltip: 'Más',
                onTap: _toggleMorePopup,
              ),
            ],
          ),
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
    String? tooltip,
    required VoidCallback onTap,
  }) {
    Widget btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: label != null ? 10 : 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _accent : yCream,
          border: Border.all(
            color: enabled ? yBorderStrong : yMuted.withValues(alpha: 0.4),
            width: yLineThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color:
                  active
                      ? yCream
                      : enabled
                      ? yInk
                      : yMuted.withValues(alpha: 0.4),
            ),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: active ? yCream : yInk,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (tooltip != null && label == null) {
      btn = Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.longPress,
        child: btn,
      );
    }
    return btn;
  }

  /// Secondary / occasional controls, tucked behind the toolbar's "more" (⋯)
  /// button so the main row stays uncluttered and edge-to-edge.
  Widget _buildMorePopup() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _toolBtn(
            icon: _locked ? YuLiIcons.lock : YuLiIcons.lockOpen,
            active: _locked,
            label: _locked ? 'ZOOM OFF' : 'ZOOM ON',
            onTap: () => setState(() => _locked = !_locked),
          ),
          _toolBtn(
            icon: YuLiIcons.lineSquiggle,
            active: _stabilizer.isOn,
            label: 'ESTAB · ${_stabilizer.label}',
            onTap: () {
              setState(() => _stabilizer = _stabilizer.next);
              DrawingPrefs.saveStabilizer(_stabilizer);
            },
          ),
          _toolBtn(
            icon: YuLiIcons.paintBucket,
            active: _fillShapes,
            label: 'RELLENO',
            onTap: () {
              setState(() => _fillShapes = !_fillShapes);
              DrawingPrefs.saveFill(_fillShapes);
            },
          ),
          _toolBtn(
            icon: YuLiIcons.hand,
            active: _palmRejection,
            label: 'PALMA',
            onTap: () {
              setState(() => _palmRejection = !_palmRejection);
              DrawingPrefs.savePalm(_palmRejection);
            },
          ),
          _toolBtn(
            icon: YuLiIcons.palette,
            active: _palettes?.isOpen(FloatingPaletteKind.colors) ?? false,
            label: 'P · COLORES',
            onTap: () => _togglePalette(FloatingPaletteKind.colors),
          ),
          _toolBtn(
            icon: YuLiIcons.shapes,
            active: _palettes?.isOpen(FloatingPaletteKind.shapes) ?? false,
            label: 'P · FIGURAS',
            onTap: () => _togglePalette(FloatingPaletteKind.shapes),
          ),
          _toolBtn(
            icon: YuLiIcons.lineSquiggle,
            active: _palettes?.isOpen(FloatingPaletteKind.widths) ?? false,
            label: 'P · GROSOR',
            onTap: () => _togglePalette(FloatingPaletteKind.widths),
          ),
          _toolBtn(
            icon: YuLiIcons.undo,
            active: _palettes?.isOpen(FloatingPaletteKind.undoRedo) ?? false,
            label: 'P · DESHACER',
            onTap: () => _togglePalette(FloatingPaletteKind.undoRedo),
          ),
          _toolBtn(
            icon: YuLiIcons.layoutGrid,
            active: _bgPopupOpen,
            label: 'FONDO',
            onTap: () {
              setState(() => _morePopupOpen = false);
              _toggleBgPopup();
            },
          ),
          _toolBtn(
            icon: YuLiIcons.maximize,
            active: false,
            label: 'ENCUADRAR',
            onTap: () {
              setState(() => _morePopupOpen = false);
              _zoomToFit();
            },
          ),
          _toolBtn(
            icon: YuLiIcons.share,
            active: false,
            label: 'EXPORTAR',
            onTap: _startExport,
          ),
          _toolBtn(
            icon: YuLiIcons.trash,
            active: false,
            label: 'BORRAR',
            onTap: () {
              setState(() => _morePopupOpen = false);
              _confirmClear();
            },
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
  final bool hasAiKey;
  final bool aiLinked;
  final String noteTitle;
  final VoidCallback onExpand;
  final VoidCallback onReset;
  final VoidCallback onLink;
  final VoidCallback onAi;

  const _CollapsedWhiteboardHeader({
    required this.folder,
    required this.spaces,
    required this.accent,
    required this.hasAiKey,
    required this.aiLinked,
    required this.noteTitle,
    required this.onExpand,
    required this.onReset,
    required this.onLink,
    required this.onAi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
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
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.arrowLeft, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 4, height: 24, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              noteTitle.trim().isEmpty
                  ? 'PIZARRA · @${folder.name}'
                  : 'PIZARRA · @${folder.name} · ${noteTitle.trim()}',
              style: ySans(
                size: 15,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: accent,
                height: 1.0,
              ),
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
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(
                YuLiIcons.scan,
                color: yInk,
                size: 16,
              ),
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
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.infinity, color: yCream, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hasAiKey ? onAi : null,
            child: AiLinkBadge(
              active: aiLinked,
              color: accent,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasAiKey ? accent : yMuted,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: Icon(
                  YuLiIcons.sparkles,
                  color: hasAiKey ? yCream : yCream2,
                  size: 16,
                ),
              ),
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
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(
                YuLiIcons.chevronDown,
                color: yInk,
                size: 18,
              ),
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
  final Rect visibleRect;
  final int paintVersion;
  final Set<int>? hiddenIndices;
  final Set<int>? hiddenImageIndices;

  /// Layer split so strokes can render ABOVE the text-block overlays: the bottom
  /// layer paints paper+pattern+images ([drawStrokes] false), and a second
  /// layer above the text overlays paints only strokes ([drawBackground] false).
  final bool drawBackground;
  final bool drawStrokes;

  _CanvasPainter({
    required this.strokes,
    required this.images,
    required this.imageCache,
    required this.background,
    required this.paper,
    required this.visibleRect,
    required this.paintVersion,
    this.hiddenIndices,
    this.hiddenImageIndices,
    this.drawBackground = true,
    this.drawStrokes = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vr = visibleRect;
    if (drawBackground) {
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
    }
    if (drawStrokes) {
      // Strokes — skip those that don't intersect the visible rect.
      for (int i = 0; i < strokes.length; i++) {
        if (hiddenIndices != null && hiddenIndices!.contains(i)) continue;
        if (strokeOverlapsRect(strokes[i], vr)) _draw(canvas, strokes[i]);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.paintVersion != paintVersion ||
      old.visibleRect != visibleRect ||
      old.background != background ||
      old.paper != paper ||
      old.drawBackground != drawBackground ||
      old.drawStrokes != drawStrokes ||
      old.hiddenIndices != hiddenIndices ||
      old.hiddenImageIndices != hiddenImageIndices;
}

void _draw(Canvas canvas, DrawingStroke stroke) => drawStroke(canvas, stroke);

/// Paints only the in-progress stroke (world coords), in its own
/// RepaintBoundary, so live point additions don't repaint the whole canvas.
class _ActiveStrokePainter extends CustomPainter {
  final DrawingStroke? active;
  final int tick;

  _ActiveStrokePainter({required this.active, required this.tick});

  @override
  void paint(Canvas canvas, Size size) {
    if (active == null) return;
    drawActiveStroke(canvas, active!);
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter old) =>
      old.active != active || old.tick != tick;
}

// ─── Linked-spaces bar (under header) ─────────────────────────────────────

class _LinkedSpacesBar extends ConsumerWidget {
  final List<LabSpace> spaces;
  const _LinkedSpacesBar({required this.spaces});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineThin),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Text(
            'VINCULADA A',
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
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
                          MaterialPageRoute(
                            builder: (_) => LabSpaceDetailScreen(space: s),
                          ),
                          (route) => route.isFirst,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
                        decoration: BoxDecoration(
                          color: s.accentColor,
                          border: Border.all(color: yBorderStrong, width: 1.5),
                        ),
                        child: Text(
                          '→ ${s.name.toUpperCase()}',
                          style: yMono(
                            size: 9,
                            weight: FontWeight.w700,
                            tracking: 1.2,
                            color: yCream,
                          ),
                        ),
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
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vincular pizarra a LAB',
              style: ySans(size: 20, weight: FontWeight.w700, color: yInk),
            ),
            const SizedBox(height: 4),
            Text(
              'Aparecerá como tarjeta en el kanban del space.',
              style: yMono(
                size: 10,
                weight: FontWeight.w500,
                tracking: 1.2,
                color: yMuted,
              ),
            ),
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
                        child: Text(
                          s.name,
                          style: ySans(size: 16, color: yInk),
                        ),
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

/// Full-screen overlay shown while choosing a rectangular export region. The
/// drag is handled by the canvas pointer pipeline (1 finger draws/adjusts, 2
/// fingers pan/zoom — coords match the drawing space exactly); this only paints
/// the dimmed area + selection + lasso-style resize handles ([worldRect] mapped
/// through [viewCtrl], so it stays anchored while panning/zooming) and offers
/// cancel / confirm. Lifting a finger does not export.
class _ExportMarqueeOverlay extends StatelessWidget {
  final Color accent;
  final TransformationController viewCtrl;
  final Rect? worldRect;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ExportMarqueeOverlay({
    required this.accent,
    required this.viewCtrl,
    required this.worldRect,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final hasRect = worldRect != null;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: viewCtrl,
              builder: (_, _) {
                Rect? rect;
                if (hasRect) {
                  final a = MatrixUtils.transformPoint(
                      viewCtrl.value, worldRect!.topLeft);
                  final b = MatrixUtils.transformPoint(
                      viewCtrl.value, worldRect!.bottomRight);
                  rect = Rect.fromPoints(a, b);
                }
                return CustomPaint(
                  painter: _MarqueePainter(rect: rect, accent: accent),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: yInk,
                        border: Border.all(color: yBorderStrong, width: yLineMid),
                      ),
                      child: Text(
                        '1 dedo: dibuja y ajusta con las manijas · 2 dedos: mover / zoom',
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.0,
                          color: yCream,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCancel,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(color: yBorderStrong, width: yLineMid),
                      ),
                      child: const Icon(YuLiIcons.close, color: yInk, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (hasRect)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onConfirm,
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      border: Border.all(color: yBorderStrong, width: yLineHeavy),
                      boxShadow: const [
                        BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                      ],
                    ),
                    child: Text(
                      'EXPORTAR ESTA ÁREA',
                      style: yMono(
                        size: 12,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yCream,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Which part of the export marquee a drag is manipulating.
enum _MarqueeHandle { tl, tr, bl, br, t, b, l, r, move, draw }

class _MarqueePainter extends CustomPainter {
  final Rect? rect;
  final Color accent;
  _MarqueePainter({required this.rect, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dim = Paint()..color = yInk.withValues(alpha: 0.32);
    if (rect == null) {
      canvas.drawRect(full, dim);
      return;
    }
    final sel = rect!;
    // Dim everything outside the selection (4 bands around it).
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, sel.top), dim);
    canvas.drawRect(
        Rect.fromLTRB(0, sel.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, sel.top, sel.left, sel.bottom), dim);
    canvas.drawRect(
        Rect.fromLTRB(sel.right, sel.top, size.width, sel.bottom), dim);
    canvas.drawRect(
      sel,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Lasso-style square handles at corners + side midpoints.
    final handles = <Offset>[
      sel.topLeft,
      sel.topRight,
      sel.bottomLeft,
      sel.bottomRight,
      sel.topCenter,
      sel.bottomCenter,
      sel.centerLeft,
      sel.centerRight,
    ];
    final fill = Paint()..color = yCream;
    final border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const r = 6.0;
    for (final h in handles) {
      final box = Rect.fromCenter(center: h, width: r * 2, height: r * 2);
      canvas.drawRect(box, fill);
      canvas.drawRect(box, border);
    }
  }

  @override
  bool shouldRepaint(_MarqueePainter old) =>
      old.rect != rect || old.accent != accent;
}
