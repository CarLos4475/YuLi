import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import '../../providers/ai_providers.dart';
import '../../providers/note_providers.dart';
import '../../widgets/ai_link_badge.dart';
import '../../widgets/status_bar_flood.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../utils/canvas_block_raster.dart';
import '../../utils/canvas_export.dart';
import 'ai_chat_sheet.dart';
import 'background_paint.dart';
import 'background_popup.dart';
import 'canvas_export_sheet.dart';
import 'canvas_image_cache.dart';
import 'canvas_task_block.dart';
import 'canvas_text_block.dart';
import 'color_loupe.dart';
import 'color_picker.dart';
import 'drawing_engine.dart';
import 'drawing_prefs.dart';
import 'eraser_mode_popup.dart';
import 'floating_palettes.dart';
import 'fountain_pen_engine.dart';
import 'popup_reveal.dart';
import 'image_crop_screen.dart';
import 'image_insert_panel.dart';
import 'lasso_controller.dart';
import 'lasso_mini_toolbar.dart';
import 'ocr_flow.dart';
import '../lab/lab_space_detail_screen.dart';
import 'lasso_painter.dart';
import 'note_cell_model.dart';
import 'notebook_constants.dart';
import 'notebook_page_drawer.dart';
import 'shape_recognizer.dart';
import 'shape_picker_popup.dart';
import 'stroke_bounds.dart';
import 'stroke_stabilizer.dart';
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
  int _paintVersion = 0;
  Rect? _renderRect;
  Color _color = yInk;
  double _strokeW = 3.0;
  DrawTool _tool = DrawTool.pen;
  bool _palmRejection = true;
  DrawingStroke? _active;
  int? _activePageIndex;
  // Ticked on every live point added to [_active]. Repaints only the active
  // stroke layer (its own RepaintBoundary) without a full-canvas setState, so
  // the wet stroke keeps up with the stylus instead of trailing it.
  final ValueNotifier<int> _activeTick = ValueNotifier(0);
  StabilizerLevel _stabilizer = StabilizerLevel.off;
  LiveStabilizer? _stab;
  bool _fillShapes = false;
  final Map<DrawTool, Color> _toolColors = {...DrawingPrefs.defaultColors};
  final Map<DrawTool, double> _toolWidths = {...DrawingPrefs.defaultWidths};
  CanvasImageCache? _imgCache;
  String? _imageDirPath;
  bool _imagePanelOpen = false;
  bool _shapePopupOpen = false;
  bool _morePopupOpen = false;
  // Post-snap live adjust state.
  ShapeKind? _snapKind;
  List<List<double>>? _snapBasePoints;
  Offset? _snapCenter;
  Offset? _snapAnchor;
  double _snapRefDist = 1;
  final List<
    Map<
      int,
      (
        List<DrawingStroke>,
        List<CanvasImage>,
        List<CanvasTaskBlock>,
        List<CanvasTextBlock>,
      )
    >
  >
  _undoStack = [];
  final List<
    Map<
      int,
      (
        List<DrawingStroke>,
        List<CanvasImage>,
        List<CanvasTaskBlock>,
        List<CanvasTextBlock>,
      )
    >
  >
  _redoStack = [];
  Map<
    int,
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
  >?
  _gestureBefore;
  bool _gestureChanged = false;
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
  // Last-applied background, inherited by new pages.
  PageBackground _lastBg = PageBackground.blank;
  int? _lastBgColor;
  bool _bgPopupOpen = false;
  bool _bgColorPickerOpen = false;
  bool _bgAllPages = false;
  Matrix4? _transformBeforeStylus;

  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  @override
  void setState(VoidCallback fn) {
    _paintVersion++;
    super.setState(fn);
  }

  Timer? _pasteTimer;
  Offset? _pastePos;
  Offset? _showPasteAt;

  // Lasso action toolbar is summoned by tapping the selection, not shown on
  // select. Tap outside hides it (selection kept); tap outside again deselects.
  bool _toolbarVisible = false;
  // Down outside an active selection, deferred until tap (dismiss) vs drag
  // (fresh lasso) is known. Stylus-only (finger taps go via onTapUp).
  Offset? _pendingLassoStart;
  Size _viewport = Size.zero;

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
  FloatingPalettesController? _palettes;
  // Favorite selected (== current color) when the color picker opened, so
  // starring a refined color replaces it in place instead of evicting oldest.
  Color? _pickerFavoriteAnchor;
  List<Color> _bgSavedColors = const [];
  bool _eyedropperMode = false;
  // Eyedropper loupe: per-pixel sampling of a raster snapshot (anything on the
  // canvas), not stroke hit-testing. See whiteboard editor for details.
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  ui.Image? _eyedropImg;
  ByteData? _eyedropBytes;
  double _eyedropDpr = 1;
  Offset _loupePos = Offset.zero;
  Color _loupeColor = yInk;
  Matrix4? _eyedropCaptureMatrix;
  void Function(Color)? _eyedropOnPick;
  EraserMode _eraserMode = EraserMode.stroke;
  bool _eraserPopupOpen = false;
  Offset? _eraserCursor;

  @override
  void initState() {
    super.initState();
    _palette = buildPenPalette(widget.note.color ?? widget.folder.color);
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pullAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _drawerAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _drawerSlide = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _drawerAnimCtrl, curve: Curves.easeOutCubic),
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
    DrawingPrefs.load().then((prefs) {
      if (!mounted) return;
      setState(() {
        _stabilizer = prefs.stabilizer;
        _palmRejection = prefs.palmRejection;
        _fillShapes = prefs.fillShapes;
        _eraserMode = prefs.eraserMode;
        _toolColors.addAll(prefs.toolColors);
        _toolWidths.addAll(prefs.toolWidths);
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialScroll();
      });
    });
  }

  @override
  void dispose() {
    _eyedropImg?.dispose();
    _reconcileImageFiles();
    _holdTimer?.cancel();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _pullAnimCtrl.dispose();
    _drawerAnimCtrl.dispose();
    _imgCache?.dispose();
    _viewCtrl.dispose();
    _activeTick.dispose();
    super.dispose();
  }

  /// On leaving the notebook, delete image files no longer referenced by any
  /// page. Canvas images are tracked only in the page payloads.
  void _reconcileImageFiles() {
    final dirPath = _imageDirPath;
    if (dirPath == null) return;
    final referenced = <String>{};
    for (final data in _pageData.values) {
      for (final im in data.images) {
        referenced.add(im.filename);
      }
    }
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

  // ─── Page management ───────────────────────────────────────────────────

  Future<void> _loadPages() async {
    final repo = ref.read(noteBlockRepositoryProvider);
    final blocks = await repo.getByNote(widget.note.id);
    final drawingBlocks =
        blocks.whereType<DrawingBlock>().toList()
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
      // Inherit new-page background from the last page.
      final last = _pageData[_pageBlockIds.last];
      if (last != null) {
        _lastBg = last.background;
        _lastBgColor = last.bgColorValue;
      }
    }

    setState(() {});
  }

  void _applyInitialScroll() {
    if (_scrollApplied || _pageBlockIds.isEmpty) return;
    _scrollApplied = true;
    final lastPageTop =
        (_pageBlockIds.length - 1) * (kNotebookPageHeight + kNotebookPageGap);
    final vw = MediaQuery.of(context).size.width;
    final dx = (vw - kNotebookPageWidth) / 2;
    final dy = -lastPageTop + 40;
    _viewCtrl.value = Matrix4.translationValues(dx, dy, 0);
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
      'h': kNotebookPageHeight,
      's': strokes,
      'i': images,
      't': taskBlocks,
      if (payload['tx'] != null) 'tx': payload['tx'],
      'bg': payload['bg'],
      'bgc': payload['bgc'],
    });
  }

  Future<void> _ensurePageAt(int pageIndex) async {
    final repo = ref.read(noteBlockRepositoryProvider);
    while (_pageBlockIds.length <= pageIndex) {
      final block =
          await repo.insertAtEnd(
                widget.note.id,
                NoteBlockType.drawing,
                payload: {
                  'h': kNotebookPageHeight,
                  's': [],
                  'bg': _lastBg.toDbString(),
                  if (_lastBgColor != null) 'bgc': _lastBgColor,
                },
              )
              as DrawingBlock;
      _pageBlockIds.add(block.id);
      _pageData[block.id] = DrawingData(
        height: kNotebookPageHeight,
        background: _lastBg,
        bgColorValue: _lastBgColor,
      );
    }
    setState(() {});
  }

  void _addPageAtEnd() {
    if (_pendingPageAdd) return;
    _pendingPageAdd = true;
    _ensurePageAt(_pageBlockIds.length).then((_) => _pendingPageAdd = false);
  }

  Future<void> _persistPage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) return;
    await ref.read(noteBlockRepositoryProvider).updatePayload(blockId, {
      'h': kNotebookPageHeight,
      's': data.strokes.map((s) => s.toJson()).toList(),
      'i': data.images.map((im) => im.toJson()).toList(),
      't': data.taskBlocks.map((b) => b.toJson()).toList(),
      'tx': data.textBlocks.map((b) => b.toJson()).toList(),
      'bg': data.background.toDbString(),
      if (data.bgColorValue != null) 'bgc': data.bgColorValue,
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

  void _toggleImagePanel() {
    setState(() {
      _imagePanelOpen = !_imagePanelOpen;
      if (_imagePanelOpen) {
        _colorPickerOpen = false;
        _widthPickerOpen = false;
      }
    });
  }

  /// Copy a ready (compressed) file into the note's image folder and place it
  /// centred on the currently visible page, as an undoable step.
  Future<void> _insertImageFile(File f) async {
    final dirPath = _imageDirPath;
    if (dirPath == null || _pageBlockIds.isEmpty) return;
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

      final pageIdx = _currentVisiblePage;
      final data = _pageData[_pageBlockIds[pageIdx]];
      if (data == null) return;
      final local = _worldToPageLocal(
        _screenToWorld(Offset(screen.width / 2, screen.height / 2)),
        pageIdx,
      );
      final w = kNotebookPageWidth * 0.5;
      final h = w * ih / iw;
      final img = CanvasImage(
        filename: filename,
        x: local.dx - w / 2,
        y: local.dy - h / 2,
        w: w,
        h: h,
      );
      final before = _snapshot();
      setState(() => data.images.add(img));
      _commit(before);
      _persistPage(pageIdx);
      _imgCache?.get(filename);
      HapticFeedback.lightImpact();
    } catch (_) {}
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
    setState(() {
      _eyedropperMode = true;
      _eyedropOnPick = onPick;
      _colorPickerOpen = false;
      _widthPickerOpen = false;
      _tool = DrawTool.pen;
      _lassoCtrl.deselect();
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
      _eyedropImg = null;
      _eyedropBytes = null;
    });
  }

  List<Widget> _buildLoupeOverlay(Size viewport) {
    const loupeW = 132.0;
    const loupeH = 160.0;
    final left =
        (_loupePos.dx - loupeW / 2).clamp(8.0, viewport.width - loupeW - 8);
    final top =
        (_loupePos.dy - loupeH - 40).clamp(8.0, viewport.height - loupeH - 8);
    return [
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
      _undoStack.clear();
      _redoStack.clear();
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

    final adjusted =
        newUnstarredIdx > oldUnstarredIdx
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
      _undoStack.clear();
      _redoStack.clear();
    });

    await ref
        .read(noteBlockRepositoryProvider)
        .reorder(widget.note.id, newOrder);
    HapticFeedback.lightImpact();
  }

  double get _totalCanvasHeight {
    final pages = _pageBlockIds.length.clamp(1, 9999);
    return pages * kNotebookPageHeight + (pages - 1) * kNotebookPageGap + 300;
  }

  // ─── Coordinate transforms ────────────────────────────────────────────

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

  void _syncPullTicker(bool visible) {
    if (visible) {
      if (!_pullAnimCtrl.isAnimating) _pullAnimCtrl.repeat(reverse: true);
      return;
    }
    if (_pullAnimCtrl.isAnimating) _pullAnimCtrl.stop();
    if (_pullAnimCtrl.value != 0) _pullAnimCtrl.value = 0;
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

  /// Padded render rect with hysteresis. The stroke/background painters cull and
  /// cache against a rect inflated by ~half a viewport, and it only grows (→ a
  /// repaint) once the live visible rect leaves it. A short pan or a draw while
  /// slightly scrolled then reuses the [RepaintBoundary] raster instead of
  /// re-rasterizing the visible ink every frame (the main sustained-heat source
  /// during pan, since per-frame culling defeats the boundary's caching).
  Rect _renderRectFor(Size viewport) {
    final visible = _visibleRectFor(viewport);
    final current = _renderRect;
    if (current != null &&
        current.left <= visible.left &&
        current.top <= visible.top &&
        current.right >= visible.right &&
        current.bottom >= visible.bottom) {
      return current;
    }
    final padX = visible.width * 0.5;
    final padY = visible.height * 0.5;
    final next = Rect.fromLTRB(
      visible.left - padX,
      visible.top - padY,
      visible.right + padX,
      visible.bottom + padY,
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

  int _pageIndexFromWorldY(double worldY) {
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final pageTop = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageBottom = pageTop + kNotebookPageHeight;
      if (worldY >= pageTop && worldY < pageBottom) return i;
    }
    final lastBottom =
        _pageBlockIds.isNotEmpty
            ? (_pageBlockIds.length - 1) *
                    (kNotebookPageHeight + kNotebookPageGap) +
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
    if (_tool == DrawTool.text) return false; // text mode never draws
    if (_tool == DrawTool.task) return false; // task mode never draws
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
    // A scribble densely fills a box and would be mis-snapped to a rectangle —
    // leave it for the scribble-erase on pen-up.
    if (isScribble(_active!.points)) return false;
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

  /// Replace the freehand stroke with clean geometry and enter live-adjust
  /// (resize closed shapes around their centre / move the end of lines/arrows).
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
    final pageIdx = _activePageIndex;
    _clearSnap();
    if (shape == null || pageIdx == null) return;
    final data = _pageData[_pageBlockIds[pageIdx]];
    if (data == null) {
      setState(() => _active = null);
      return;
    }
    final before = _snapshot();
    setState(() {
      data.strokes.add(shape);
      _active = null;
    });
    _commit(before);
    _persistPage(pageIdx);
  }

  void _clearSnap() {
    _snapKind = null;
    _snapBasePoints = null;
    _snapCenter = null;
    _snapAnchor = null;
  }

  void _startHoldTimer(Offset worldPos) {
    _holdTimer?.cancel();
    _holdAnchor = worldPos;
    _holdTimer = Timer(const Duration(milliseconds: 800), _tryShapeSnap);
  }

  // ─── Pointer events ────────────────────────────────────────────────────

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

    final isFinger = !isStylus;

    // Paste via long-press
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

    // Lasso + palm rejection + finger
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
      _gestureBefore = _snapshot();
      _gestureChanged = false;
      setState(() => _eraserCursor = e.localPosition);
      _eraseNear(local, pageIdx);
      return;
    }

    _stab = _newStabilizer();
    final sp = _stabilize(local);

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
      _startHoldTimer(world);
    }
  }

  LiveStabilizer? _newStabilizer() =>
      _stabilizer.isOn ? LiveStabilizer(_stabilizer.alpha) : null;

  Offset _stabilize(Offset p) => _stab?.process(p.dx, p.dy) ?? p;

  /// Finger tap (touch only) in lasso mode selects the stroke/image under it.
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
    final blocks = _allVisibleTaskBlocks;
    _lassoCtrl.hitScale = _viewScale;
    if (_lassoCtrl.phase == LassoPhase.selected) {
      // Tap inside the selection toggles the toolbar — handled by the pointer
      // flow's no-op move (_finishTransformOrTap); skip it here.
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
    // Nothing selected. A tap on an interactive TASK block belongs to its UI;
    // text blocks lasso-select here (they only edit in text mode).
    final textBlocks = _allVisibleTextBlocks;
    for (int i = 0; i < blocks.length; i++) {
      if (_lassoCtrl.selectedBlockIndices.contains(i)) continue;
      final b = blocks[i];
      if (Rect.fromLTWH(b.x, b.y, b.w, b.h).contains(p)) return;
    }
    setState(() {
      if (_lassoCtrl.tapSelect(
        p,
        _allVisibleStrokes,
        _allVisibleImages,
        blocks,
        textBlocks,
      )) {
        _toolbarVisible = false;
      } else {
        _lassoCtrl.deselect();
      }
    });
  }

  static const _minDist2 = 9.0;

  void _onMove(PointerMoveEvent e) {
    if (_eyedropperMode) {
      if (_activePointers.length < 2) _moveLoupe(e.localPosition);
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

    final world = _screenToWorld(e.localPosition);

    if (_tool == DrawTool.lasso) {
      _handleLassoMove(world);
      return;
    }
    if (_activePageIndex == null) return;
    final local = _worldToPageLocal(world, _activePageIndex!);

    if (_snapKind != null) {
      _updateShapeAdjust(local);
      return;
    }
    if (_tool == DrawTool.eraser) {
      setState(() => _eraserCursor = e.localPosition);
      _eraseNear(local, _activePageIndex!);
      return;
    }
    if (_active == null) return;
    final sp = _stabilize(local);
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
      final dx = world.dx - _holdAnchor!.dx;
      final dy = world.dy - _holdAnchor!.dy;
      if (dx * dx + dy * dy > _holdTolerance2) {
        _startHoldTimer(world);
      }
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_eyedropperMode) {
      _activePointers.remove(e.pointer);
      setState(() {});
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
      _bakePredictedTip();
      _finishFountainStroke();
      _stab = null;
      return;
    }
    if (_active == null) return;
    _bakePredictedTip();
    _finishStroke();
    _stab = null;
  }

  void _onCancel(PointerCancelEvent e) {
    if (_eyedropperMode) {
      _activePointers.remove(e.pointer);
      setState(() {});
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

  /// On lift, append the same predicted tip the live preview was leading with,
  /// so the committed stroke ends where the preview ended (no backward retraction).
  void _bakePredictedTip() {
    final a = _active;
    if (a == null || a.isShape) return;
    final tip = predictedTipPoint(a.points);
    if (tip != null) a.points.add(tip);
  }

  void _finishStroke() {
    if (_snapKind != null) return;
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
      (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite,
    );
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
      final before = _snapshot();
      final lenBefore = data.strokes.length;
      data.strokes.removeWhere((s) {
        for (final p in s.points) {
          if (bounds.contains(Offset(p[0], p[1]))) return true;
        }
        return false;
      });
      setState(() => _active = null);
      if (data.strokes.length != lenBefore) {
        _commit(before);
        HapticFeedback.lightImpact();
        _persistPage(_activePageIndex!);
      }
      return;
    }

    final before = _snapshot();
    setState(() {
      data.strokes.add(_active!);
      _active = null;
    });
    _commit(before);
    _persistPage(_activePageIndex!);
  }

  void _finishFountainStroke() {
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
      (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite,
    );
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
    final before = _snapshot();
    setState(() {
      data.strokes.add(baked);
      _active = null;
    });
    _commit(before);
    _persistPage(_activePageIndex!);
  }

  static const _eraserScreenRadius = 7.0;

  void _eraseNear(Offset local, int pageIndex) {
    final radius = _eraserScreenRadius / _viewScale;
    final data = _pageData[_pageBlockIds[pageIndex]];
    if (data == null) return;
    bool changed = false;
    if (_eraserMode == EraserMode.partial) {
      final out = <DrawingStroke>[];
      for (final s in data.strokes) {
        final pieces = splitStrokeByEraser(s, local, radius);
        if (pieces.length == 1 && identical(pieces.first, s)) {
          out.add(s);
        } else {
          out.addAll(pieces);
          changed = true;
        }
      }
      if (changed) data.strokes = out;
    } else {
      final before = data.strokes.length;
      data.strokes.removeWhere((s) => strokeHitByEraser(s, local, radius));
      changed = data.strokes.length != before;
    }
    if (changed) {
      _gestureChanged = true;
      setState(() {});
      _persistPage(pageIndex);
    }
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

  // ─── Lasso ─────────────────────────────────────────────────────────────

  double _pageOffsetY(int i) => i * (kNotebookPageHeight + kNotebookPageGap);

  List<DrawingStroke> get _allVisibleStrokes {
    final all = <DrawingStroke>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final s in data.strokes) {
        final c = s.clone();
        for (final pt in c.points) {
          pt[1] += offset;
        }
        all.add(c);
      }
    }
    return all;
  }

  List<CanvasImage> get _allVisibleImages {
    final all = <CanvasImage>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final im in data.images) {
        all.add(im.clone()..y += offset);
      }
    }
    return all;
  }

  List<CanvasTaskBlock> get _allVisibleTaskBlocks {
    final all = <CanvasTaskBlock>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final b in data.taskBlocks) {
        all.add(b.clone()..y += offset);
      }
    }
    return all;
  }

  List<CanvasTextBlock> get _allVisibleTextBlocks {
    final all = <CanvasTextBlock>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final b in data.textBlocks) {
        all.add(b.clone()..y += offset);
      }
    }
    return all;
  }

  /// Page whose vertical band contains [worldY], else the nearest page. Shared
  /// by strokes/images/task blocks so a selection dragged into a gap or past
  /// the last page lands somewhere instead of being dropped.
  int _nearestPageIndex(double worldY) {
    var bestIdx = -1;
    double bestDist = double.infinity;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final top = _pageOffsetY(i);
      final bottom = top + kNotebookPageHeight;
      if (worldY >= top && worldY < bottom) return i;
      final d = worldY < top ? top - worldY : worldY - bottom;
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _handleLassoDown(Offset worldPos) {
    _pasteTimer?.cancel();
    _lassoCtrl.hitScale = _viewScale;
    if (_showPasteAt != null) {
      setState(() => _showPasteAt = null);
      return;
    }
    final strokes = _allVisibleStrokes;
    final images = _allVisibleImages;
    final blocks = _allVisibleTaskBlocks;
    if (_lassoCtrl.phase == LassoPhase.selected) {
      if (_lassoCtrl.hitTestRotationHandle(worldPos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startRotation(worldPos, strokes, images, blocks);
        return;
      }
      final corner = _lassoCtrl.hitTestCornerHandle(worldPos);
      if (corner != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startResize(corner, worldPos, strokes, images, blocks);
        return;
      }
      final side = _lassoCtrl.hitTestSideHandle(worldPos);
      if (side != null) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startSideResize(side, worldPos, strokes, images, blocks);
        return;
      }
      if (_lassoCtrl.isTapInsideBoundingBox(worldPos)) {
        _gestureBefore = _snapshot();
        _lassoCtrl.startMove(worldPos, strokes, images, blocks);
        return;
      }
      // Outside the selection: defer (tap dismisses on up, drag starts a fresh
      // lasso on move). Keep the current selection meanwhile.
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
    final strokes = _allVisibleStrokes;
    final images = _allVisibleImages;
    final blocks = _allVisibleTaskBlocks;
    final textBlocks = _allVisibleTextBlocks;
    if (_lassoCtrl.phase == LassoPhase.tracing) {
      _lassoCtrl.finishTracing(strokes, images, blocks, textBlocks);
      _toolbarVisible = false;
    } else if (_lassoCtrl.phase == LassoPhase.moving) {
      final moved = _lassoCtrl.dragOffset.distance * _viewScale > 6;
      _lassoCtrl.finishMove(strokes, images, blocks, 0, textBlocks);
      _finishTransformOrTap(moved, strokes, images, blocks, textBlocks);
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
          ? _lassoCtrl.finishSideResize(strokes, images, blocks, textBlocks)
          : _lassoCtrl.finishResize(strokes, images, blocks, textBlocks);
      for (final i in _lassoCtrl.selectedBlockIndices) {
        if (i >= blocks.length) continue;
        final b = blocks[i];
        if (!side) b.scale = (b.scale * cornerScale).clamp(0.2, 8.0);
        if (b.w < kCanvasTextBlockMinW) b.w = kCanvasTextBlockMinW;
      }
      for (final i in _lassoCtrl.selectedTextBlockIndices) {
        if (i >= textBlocks.length) continue;
        final b = textBlocks[i];
        // Corner = uniform scale (text grows with box). Horizontal side = width
        // reflow (controller already set w). Vertical resize is disabled for
        // text (hitTestSideHandle skips top/bottom for text-only selections).
        if (!side) b.scale = (b.scale * cornerScale).clamp(0.2, 8.0);
        if (b.w < kCanvasTextBlockMinW) b.w = kCanvasTextBlockMinW;
      }
      _finishTransformOrTap(moved, strokes, images, blocks, textBlocks);
    } else if (_lassoCtrl.phase == LassoPhase.rotating) {
      final moved = _lassoCtrl.rotationAngle.abs() > 0.01;
      _lassoCtrl.finishRotation(strokes, images, blocks, textBlocks);
      _finishTransformOrTap(moved, strokes, images, blocks, textBlocks);
    }
  }

  /// A transform that moved is synced to the pages and committed; one that
  /// didn't is a tap on the selection → toggle the action toolbar.
  void _finishTransformOrTap(
    bool moved,
    List<DrawingStroke> strokes,
    List<CanvasImage> images,
    List<CanvasTaskBlock> blocks,
    List<CanvasTextBlock> textBlocks,
  ) {
    if (moved) {
      _syncLassoToPages(strokes, images, blocks, textBlocks);
      _commitGesture();
    } else {
      _gestureBefore = null;
      setState(() => _toolbarVisible = !_toolbarVisible);
    }
  }

  void _syncLassoToPages(
    List<DrawingStroke> worldStrokes,
    List<CanvasImage> worldImages,
    List<CanvasTaskBlock> worldBlocks,
    List<CanvasTextBlock> worldTextBlocks,
  ) {
    final pages = <int, List<DrawingStroke>>{};
    final imagesByPage = <int, List<CanvasImage>>{};
    final blocksByPage = <int, List<CanvasTaskBlock>>{};
    final textBlocksByPage = <int, List<CanvasTextBlock>>{};
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final bid = _pageBlockIds[i];
      pages[bid] = [];
      imagesByPage[bid] = [];
      blocksByPage[bid] = [];
      textBlocksByPage[bid] = [];
    }
    for (final s in worldStrokes) {
      if (s.points.isEmpty) continue;
      double sumY = 0;
      for (final pt in s.points) {
        sumY += pt[1];
      }
      final idx = _nearestPageIndex(sumY / s.points.length);
      if (idx < 0) continue;
      final c = s.clone();
      final pageTop = _pageOffsetY(idx);
      for (final pt in c.points) {
        pt[1] -= pageTop;
      }
      pages[_pageBlockIds[idx]]!.add(c);
    }
    for (final im in worldImages) {
      final idx = _nearestPageIndex(im.y + im.h / 2);
      if (idx < 0) continue;
      imagesByPage[_pageBlockIds[idx]]!.add(im.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0) continue;
      blocksByPage[_pageBlockIds[idx]]!.add(b.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldTextBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0) continue;
      textBlocksByPage[_pageBlockIds[idx]]!.add(
        b.clone()..y -= _pageOffsetY(idx),
      );
    }
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final bid = _pageBlockIds[i];
      final prev = _pageData[bid];
      _pageData[bid] = DrawingData(
        height: kNotebookPageHeight,
        strokes: pages[bid]!,
        images: imagesByPage[bid]!,
        taskBlocks: blocksByPage[bid]!,
        textBlocks: textBlocksByPage[bid]!,
        background: prev?.background ?? PageBackground.blank,
        bgColorValue: prev?.bgColorValue,
      );
      _persistPage(i);
    }
    setState(() {});
  }

  /// Run a lasso mutation over the flattened world strokes + images + blocks,
  /// sync back to the pages, and record it as one undoable step.
  void _lassoMutate(
    void Function(
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
    op,
  ) {
    final before = _snapshot();
    final strokes = _allVisibleStrokes;
    final images = _allVisibleImages;
    final blocks = _allVisibleTaskBlocks;
    final textBlocks = _allVisibleTextBlocks;
    op(strokes, images, blocks, textBlocks);
    _syncLassoToPages(strokes, images, blocks, textBlocks);
    _commit(before);
  }

  void _lassoDelete() {
    _lassoMutate((s, im, b, tx) => _lassoCtrl.deleteSelected(s, im, b, tx));
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    _lassoMutate((s, im, b, tx) => _lassoCtrl.duplicateSelected(s, im));
    HapticFeedback.lightImpact();
  }

  /// Enter task-insert mode: subsequent finger taps place a new task block at
  /// the tap position (mirrors text mode). Used by the toolbar Tareas button.
  void _enterTaskMode() {
    setState(() => _tool = DrawTool.task);
    _lassoCtrl.deselect();
    HapticFeedback.lightImpact();
  }

  /// Place a task block at [worldPos] (tap-to-insert in task mode).
  void _insertTaskBlockAt(Offset worldPos) {
    if (_pageBlockIds.isEmpty) return;
    final pageIdx = _nearestPageIndex(
      worldPos.dy,
    ).clamp(0, _pageBlockIds.length - 1);
    final w = (kCanvasTaskBlockDefaultW / _viewScale).clamp(60.0, 600.0);
    final h = (w * 0.375).clamp(40.0, 400.0);
    final localY = worldPos.dy - _pageOffsetY(pageIdx) - h / 2;
    final block = CanvasTaskBlock(
      x: worldPos.dx - w / 2,
      y: localY,
      w: w,
      h: h,
    );
    final before = _snapshot();
    setState(() {
      _pageData[_pageBlockIds[pageIdx]]?.taskBlocks.add(block);
      _tool = DrawTool.task;
    });
    _commit(before);
    _persistPage(pageIdx);
    HapticFeedback.lightImpact();
  }

  /// Insert a new text block (empty, or seeded with [markdown]) on the page
  /// currently in view. Used by the insert button and the AI chat's "send to
  /// canvas".
  void _enterTextMode() {
    setState(() => _tool = DrawTool.text);
    _lassoCtrl.deselect();
    HapticFeedback.lightImpact();
  }

  /// Insert a text block at [worldPos] (tap-to-insert in text mode).
  void _insertTextBlockAt(Offset worldPos) {
    if (_pageBlockIds.isEmpty) return;
    final pageIdx = _nearestPageIndex(
      worldPos.dy,
    ).clamp(0, _pageBlockIds.length - 1);
    final w = (240.0 / _viewScale).clamp(60.0, 600.0);
    final h = w / 2;
    final localY = worldPos.dy - _pageOffsetY(pageIdx) - h / 2;
    final block = CanvasTextBlock(
      x: worldPos.dx - w / 2,
      y: localY,
      w: w,
      h: h,
    );
    final before = _snapshot();
    setState(() {
      _pageData[_pageBlockIds[pageIdx]]?.textBlocks.add(block);
      _tool = DrawTool.text;
    });
    _commit(before);
    _persistPage(pageIdx);
    HapticFeedback.lightImpact();
  }

  /// Insert at centre with [markdown] (called from AI chat "Enviar a lienzo").
  void _insertTextBlock([String markdown = '']) {
    if (_pageBlockIds.isEmpty) return;
    final screen = MediaQuery.of(context).size;
    final center = _screenToWorld(Offset(screen.width / 2, screen.height / 2));
    final pageIdx = _nearestPageIndex(
      center.dy,
    ).clamp(0, _pageBlockIds.length - 1);
    final screenW =
        markdown.isNotEmpty
            ? (200.0 + markdown.length * 0.35).clamp(120.0, 800.0)
            : 200.0;
    final w = (screenW / _viewScale).clamp(60.0, 600.0);
    final h = markdown.isNotEmpty ? w : w / 2;
    final localY = center.dy - _pageOffsetY(pageIdx) - h / 2;
    final block = CanvasTextBlock(
      x: center.dx - w / 2,
      y: localY,
      w: w,
      h: h,
      markdown: markdown,
    );
    final before = _snapshot();
    setState(() {
      _pageData[_pageBlockIds[pageIdx]]?.textBlocks.add(block);
      var worldIdx = 0;
      for (int i = 0; i < pageIdx; i++) {
        worldIdx += _pageData[_pageBlockIds[i]]?.textBlocks.length ?? 0;
      }
      worldIdx +=
          (_pageData[_pageBlockIds[pageIdx]]?.textBlocks.length ?? 1) - 1;
      _tool = DrawTool.lasso;
      _lassoCtrl.hitScale = _viewScale;
      _lassoCtrl.selectTextBlock(
        worldIdx,
        _allVisibleStrokes,
        _allVisibleImages,
        _allVisibleTaskBlocks,
        _allVisibleTextBlocks,
      );
      _toolbarVisible = false;
    });
    _commit(before);
    _persistPage(pageIdx);
    HapticFeedback.lightImpact();
  }

  void _toggleShapePopup() {
    setState(() {
      _shapePopupOpen = !_shapePopupOpen;
      if (_shapePopupOpen) {
        _imagePanelOpen = false;
        _morePopupOpen = false;
      }
    });
  }

  void _toggleMorePopup() {
    setState(() {
      _morePopupOpen = !_morePopupOpen;
      if (_morePopupOpen) {
        _imagePanelOpen = false;
        _shapePopupOpen = false;
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _bgPopupOpen = false;
      }
    });
  }

  /// Drop a clean shape at the viewport centre (into the page under it), already
  /// lasso-selected so it can be moved/resized immediately. Undoable + persisted.
  void _insertShape(ShapeKind kind) {
    if (_pageBlockIds.isEmpty) return;
    final screen = MediaQuery.of(context).size;
    final center = _screenToWorld(Offset(screen.width / 2, screen.height / 2));
    final pageIdx = _nearestPageIndex(
      center.dy,
    ).clamp(0, _pageBlockIds.length - 1);
    final data = _pageData[_pageBlockIds[pageIdx]];
    if (data == null) return;
    final local = _worldToPageLocal(center, pageIdx);
    final size = 160 / _viewScale;
    final closed = shapeKindIsClosed(kind);
    final stroke = DrawingStroke(
      colorValue: _color.toARGB32(),
      strokeWidth: _strokeW,
      isShape: true,
      filled: closed && _fillShapes,
      points: buildShape(kind, local.dx, local.dy, size, size),
    );
    final before = _snapshot();
    setState(() {
      data.strokes.add(stroke);
      _tool = DrawTool.lasso;
      _shapePopupOpen = false;
      _toolbarVisible = false;
    });
    // Flat index in world-space _allVisibleStrokes (new stroke is last in its
    // page; pages concatenate in order).
    int flat = 0;
    for (int i = 0; i < pageIdx; i++) {
      flat += _pageData[_pageBlockIds[i]]?.strokes.length ?? 0;
    }
    flat += data.strokes.length - 1;
    _lassoCtrl.hitScale = _viewScale;
    _lassoCtrl.selectRange(_allVisibleStrokes, flat, flat + 1);
    _commit(before);
    _persistPage(pageIdx);
    HapticFeedback.lightImpact();
  }

  /// Interactive task-block overlays, one per page block, positioned in world
  /// coords. Bound to the real per-page block so task edits persist; the flat
  /// index matches [_allVisibleTaskBlocks] so lasso selection lines up.
  List<Widget> _buildTaskBlockOverlays() {
    final gesture =
        _lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating;
    final out = <Widget>[];
    int flat = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      final pageIndex = i;
      for (final b in data.taskBlocks) {
        final idx = flat++;
        final selected = _lassoCtrl.selectedBlockIndices.contains(idx);
        // Own compositing layer so dragging the card is a cheap layer-offset
        // instead of repainting its content every frame.
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
            onPersist: () => _persistPage(pageIndex),
            onTasksChanged: () {
              if (mounted) setState(() {});
            },
            onHeightMeasured: (h) {
              if (!mounted) return;
              setState(() => b.h = h);
              _lassoCtrl.refreshBoundingBox(
                data.strokes,
                data.images,
                data.taskBlocks,
              );
              _persistPage(pageIndex);
            },
          ),
        );
        // Live transform for move/rotate/corner-resize. During side resize
        // (non-uniform scale) the widget stays at original size so text doesn't
        // distort, snapping to the new geometry on release.
        final isLiveTransform =
            _lassoCtrl.phase == LassoPhase.moving ||
            _lassoCtrl.phase == LassoPhase.rotating ||
            (_lassoCtrl.phase == LassoPhase.resizing &&
                !_lassoCtrl.isSideResize);
        if (isLiveTransform && selected) {
          final off = Offset(b.x, offset + b.y);
          final tm =
              Matrix4.translationValues(-off.dx, -off.dy, 0) *
              _lassoCtrl.liveGestureMatrix() *
              Matrix4.translationValues(off.dx, off.dy, 0);
          overlay = Transform(transform: tm, child: overlay);
        }
        out.add(Positioned(left: b.x, top: offset + b.y, child: overlay));
      }
    }
    return out;
  }

  /// Text block overlays. Flat index matches [_allVisibleTextBlocks] so lasso
  /// selection lines up.
  List<Widget> _buildTextBlockOverlays() {
    final gesture =
        _lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating;
    final out = <Widget>[];
    int flat = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      final pageIndex = i;
      for (final b in data.textBlocks) {
        final idx = flat++;
        final selected = _lassoCtrl.selectedTextBlockIndices.contains(idx);
        Widget overlay = RepaintBoundary(
          child: CanvasTextBlockOverlay(
            key: ValueKey(b.id),
            block: b,
            accent: _accent,
            // Text blocks are ONLY interactive (tap = edit, drag = move) in text
            // mode. Inert (IgnorePointer) in pen/lasso: the lasso transforms
            // them by geometry, pens never touch them. Avoids a multi-touch
            // crash (finger on block + 2-finger zoom).
            interactive: !selected && !gesture && _tool == DrawTool.text,
            movable: !selected && !gesture && _tool == DrawTool.text,
            onPersist: () => _persistPage(pageIndex),
            onChanged: () {
              if (mounted) setState(() {});
            },
            onHeightMeasured: (h) {
              if (!mounted) return;
              setState(() => b.h = h);
              _lassoCtrl.refreshBoundingBox(
                _allVisibleStrokes,
                _allVisibleImages,
                _allVisibleTaskBlocks,
                _allVisibleTextBlocks,
              );
              _persistPage(pageIndex);
            },
            onDragStart: () => _gestureBefore = _snapshot(),
            onDragEnd: () {
              _commitGesture();
              _persistPage(pageIndex);
            },
          ),
        );
        final isLiveTransform =
            _lassoCtrl.phase == LassoPhase.moving ||
            _lassoCtrl.phase == LassoPhase.rotating ||
            (_lassoCtrl.phase == LassoPhase.resizing &&
                !_lassoCtrl.isSideResize);
        if (isLiveTransform && selected) {
          final off = Offset(b.x, offset + b.y);
          final tm =
              Matrix4.translationValues(-off.dx, -off.dy, 0) *
              _lassoCtrl.liveGestureMatrix() *
              Matrix4.translationValues(off.dx, off.dy, 0);
          overlay = Transform(transform: tm, child: overlay);
        }
        out.add(Positioned(left: b.x, top: offset + b.y, child: overlay));
      }
    }
    return out;
  }

  bool get _singleImageSelected =>
      _lassoCtrl.selectedImageIndices.length == 1 &&
      _lassoCtrl.selectedIndices.isEmpty;

  /// True when the lasso selection contains handwriting (pen/fountain) — the
  /// only thing OCR can read. Shapes/highlighter/images don't count.
  bool get _selectionHasWriting {
    final all = _allVisibleStrokes;
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= all.length) continue;
      final s = all[i];
      if (!s.isHighlighter && !s.isShape) return true;
    }
    return false;
  }

  /// OCR the selected handwriting → editable result sheet (shared flow).
  /// Strokes are world-coords from [_allVisibleStrokes].
  List<List<Offset>> _selectedWritingStrokes() {
    final all = _allVisibleStrokes;
    final strokes = <List<Offset>>[];
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= all.length) continue;
      final s = all[i];
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

  /// Map a flattened selected-image index back to (pageIndex, localIndex).
  (int, int)? _flatImageToPage(int flatIdx) {
    int acc = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final cnt = _pageData[_pageBlockIds[i]]?.images.length ?? 0;
      if (flatIdx < acc + cnt) return (i, flatIdx - acc);
      acc += cnt;
    }
    return null;
  }

  Future<void> _cropSelectedImage() async {
    final dirPath = _imageDirPath;
    if (dirPath == null || !_singleImageSelected) return;
    final loc = _flatImageToPage(_lassoCtrl.selectedImageIndices.first);
    if (loc == null) return;
    final (pageIdx, localIdx) = loc;
    final data = _pageData[_pageBlockIds[pageIdx]];
    if (data == null || localIdx >= data.images.length) return;
    final img = data.images[localIdx];
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
      data.images[localIdx] = CanvasImage(
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
    _persistPage(pageIdx);
    _imgCache?.get(newName);
  }

  // ─── Undo / redo (snapshot history, all pages) ──────────────────────────

  Map<
    int,
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    )
  >
  _snapshot() {
    final m =
        <
          int,
          (
            List<DrawingStroke>,
            List<CanvasImage>,
            List<CanvasTaskBlock>,
            List<CanvasTextBlock>,
          )
        >{};
    for (final entry in _pageData.entries) {
      m[entry.key] = (
        entry.value.strokes.map((s) => s.clone()).toList(),
        entry.value.images.map((im) => im.clone()).toList(),
        entry.value.taskBlocks.map((b) => b.clone()).toList(),
        entry.value.textBlocks.map((b) => b.clone()).toList(),
      );
    }
    return m;
  }

  void _commit(
    Map<
      int,
      (
        List<DrawingStroke>,
        List<CanvasImage>,
        List<CanvasTaskBlock>,
        List<CanvasTextBlock>,
      )
    >
    before,
  ) {
    _undoStack.add(before);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
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

  void _restore(
    Map<
      int,
      (
        List<DrawingStroke>,
        List<CanvasImage>,
        List<CanvasTaskBlock>,
        List<CanvasTextBlock>,
      )
    >
    snap,
  ) {
    for (final entry in snap.entries) {
      final data = _pageData[entry.key];
      if (data != null) {
        data.strokes = entry.value.$1;
        data.images = entry.value.$2;
        data.taskBlocks = entry.value.$3;
        data.textBlocks = entry.value.$4;
      }
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    final snap = _undoStack.removeLast();
    setState(() {
      _restore(snap);
      _lassoCtrl.deselect();
      _active = null;
    });
    for (int i = 0; i < _pageBlockIds.length; i++) {
      _persistPage(i);
    }
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    final snap = _redoStack.removeLast();
    setState(() {
      _restore(snap);
      _lassoCtrl.deselect();
      _active = null;
    });
    for (int i = 0; i < _pageBlockIds.length; i++) {
      _persistPage(i);
    }
  }

  // ─── Current page ──────────────────────────────────────────────────────

  Color get _accent => widget.note.color ?? widget.folder.color;

  Widget _buildNotebookBackgroundLayer(Size viewport, Size canvasSize) {
    return AnimatedBuilder(
      animation: _viewCtrl,
      builder: (_, _) {
        final visibleRect = _renderRectFor(viewport);
        return RepaintBoundary(
          child: CustomPaint(
            painter: _NotebookCanvasPainter(
              pageBlockIds: _pageBlockIds,
              pageData: _pageData,
              visibleRect: visibleRect,
              paintVersion: _paintVersion,
              accentColor: _accent,
              hiddenImages: _hiddenImages(),
              imageCache: _imgCache,
              drawStrokes: false,
            ),
            size: canvasSize,
          ),
        );
      },
    );
  }

  Widget _buildNotebookStrokeLayer(Size viewport, Size canvasSize) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _viewCtrl,
        builder: (_, _) {
          final visibleRect = _renderRectFor(viewport);
          return RepaintBoundary(
            child: CustomPaint(
              painter: _NotebookCanvasPainter(
                pageBlockIds: _pageBlockIds,
                pageData: _pageData,
                visibleRect: visibleRect,
                paintVersion: _paintVersion,
                accentColor: _accent,
                hiddenStrokes: _hiddenStrokes(),
                imageCache: _imgCache,
                drawBackground: false,
              ),
              size: canvasSize,
            ),
          );
        },
      ),
    );
  }

  // Overscroll "NUEVA PÁGINA" pull affordance. Isolated AnimatedBuilder(_viewCtrl)
  // so the pull amount + its side effects (_reachedPullThreshold / pull ticker)
  // recompute on pan without rebuilding the canvas. `top` is build-time constant
  // (depends only on page count), so the Positioned stays static and only the
  // content fades/animates.
  Widget _buildPullIndicator(Size viewport, double lastPageBottom) {
    return Positioned(
      top: lastPageBottom + 20,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _viewCtrl,
          builder: (_, _) {
            final overscroll =
                _visibleRectFor(viewport).bottom - lastPageBottom;
            final pull = (overscroll / 150.0).clamp(0.0, 1.0);
            _reachedPullThreshold = pull >= 1.0;
            _syncPullTicker(pull > 0);
            if (pull <= 0) return const SizedBox.shrink();
            return Opacity(
              opacity: pull,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _accent,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
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
                      color: yInk.withValues(
                        alpha: 0.3 + 0.4 * _pullAnimCtrl.value,
                      ),
                      fontFamily: 'monospace',
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotebookLassoLayer(
    Size viewport,
    Size canvasSize,
    List<DrawingStroke> strokes,
    List<CanvasImage> images,
  ) {
    if (_lassoCtrl.phase == LassoPhase.idle) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_viewCtrl, _lassoAnimCtrl]),
      builder: (_, _) {
        final visibleRect = _visibleRectFor(viewport);
        return CustomPaint(
          painter: LassoPainter(
            ctrl: _lassoCtrl,
            animValue: _lassoAnimCtrl.value,
            strokes: strokes,
            images: images,
            imageCache: _imgCache,
            visibleRect: visibleRect,
          ),
          size: canvasSize,
        );
      },
    );
  }

  int get _currentVisiblePage {
    if (_pageBlockIds.isEmpty) return 0;
    final inv = Matrix4.inverted(_viewCtrl.value);
    final center = MatrixUtils.transformPoint(
      inv,
      Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      ),
    );
    final idx = _pageIndexFromWorldY(center.dy);
    return idx.clamp(0, _pageBlockIds.length - 1);
  }

  // ─── Background ────────────────────────────────────────────────────────

  static const Color _notebookPaper = Color(0xFFFFFDF8);

  DrawingData? get _currentPageData =>
      _pageBlockIds.isEmpty
          ? null
          : _pageData[_pageBlockIds[_currentVisiblePage]];

  PageBackground get _currentBg => _currentPageData?.background ?? _lastBg;

  Color get _currentBgColor =>
      bgPaper(_currentPageData?.bgColorValue, _notebookPaper);

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

  List<int> get _bgTargetPages =>
      _bgAllPages
          ? List.generate(_pageBlockIds.length, (i) => i)
          : [_currentVisiblePage];

  void _applyBgPattern(PageBackground pb) {
    final targets = _bgTargetPages;
    setState(() {
      _lastBg = pb;
      for (final i in targets) {
        _pageData[_pageBlockIds[i]]?.background = pb;
      }
    });
    for (final i in targets) {
      _persistPage(i);
    }
  }

  void _applyBgColor(Color c) {
    final v = c.toARGB32();
    final targets = _bgTargetPages;
    setState(() {
      _lastBgColor = v;
      for (final i in targets) {
        _pageData[_pageBlockIds[i]]?.bgColorValue = v;
      }
    });
    for (final i in targets) {
      _persistPage(i);
    }
  }

  Map<int, Set<int>> _hiddenStrokes() {
    // Canonical const empty map (stable identity) when nothing is hidden, so the
    // painter's shouldRepaint doesn't see a "changed" map every pan frame and
    // defeat the render-rect hysteresis.
    if (_lassoCtrl.phase != LassoPhase.moving &&
        _lassoCtrl.phase != LassoPhase.resizing &&
        _lassoCtrl.phase != LassoPhase.rotating) {
      return const {};
    }
    if (_lassoCtrl.selectedIndices.isEmpty) return const {};
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

  /// Per-page indices of images hidden while being moved/resized via the lasso
  /// (the live preview draws them transformed).
  Map<int, Set<int>> _hiddenImages() {
    if (_lassoCtrl.phase != LassoPhase.moving &&
        _lassoCtrl.phase != LassoPhase.resizing &&
        _lassoCtrl.phase != LassoPhase.rotating) {
      return const {};
    }
    if (_lassoCtrl.selectedImageIndices.isEmpty) return const {};
    final hidden = <int, Set<int>>{};
    int globalIdx = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      final count = data?.images.length ?? 0;
      for (int j = 0; j < count; j++) {
        if (_lassoCtrl.selectedImageIndices.contains(globalIdx + j)) {
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
    final screenTop = MatrixUtils.transformPoint(
      _viewCtrl.value,
      Offset(bb.center.dx, bb.top),
    );
    // Anchor the toolbar's bottom a fixed screen gap above the selection top
    // (clearing the rotation handle), growing upward — never overlaps the top
    // handles even when zoomed out.
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
              (s, im, b, _) => _lassoCtrl.changeColor(s, c.toARGB32()),
            ),
        onWidthChange:
            (w) => _lassoMutate((s, im, b, _) => _lassoCtrl.changeWidth(s, w)),
        onFlipH:
            () => _lassoMutate((s, im, b, _) => _lassoCtrl.flipHorizontal(s)),
        onFlipV:
            () => _lassoMutate((s, im, b, _) => _lassoCtrl.flipVertical(s)),
        onCopy: () {
          _lassoCtrl.copySelected(_allVisibleStrokes, _allVisibleImages);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('COPIADO'),
              duration: Duration(milliseconds: 800),
            ),
          );
        },
        onCut: () {
          _lassoMutate((s, im, b, _) => _lassoCtrl.cutSelected(s, im, b));
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
            (s, im, b, _) => _lassoCtrl.pasteAt(_showPasteAt!, s, im),
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

  @override
  Widget build(BuildContext context) {
    final hasAiKey = ref.watch(aiHasKeyProvider).valueOrNull ?? false;
    final aiLinked =
        (ref
            .watch(canvasContextSourcesProvider(widget.note.id))
            .valueOrNull
            ?.isNotEmpty) ??
        false;
    final spaces =
        ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
    final linkedCards =
        ref.watch(kanbanCardsByNoteProvider(widget.note.id)).valueOrNull ?? [];
    final linkedSpaceIds = linkedCards.map((c) => c.labSpaceId).toSet();
    final linkedSpaces =
        spaces.where((s) => linkedSpaceIds.contains(s.id)).toList();
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
                    _CollapsedNotebookHeader(
                      folder: widget.folder,
                      pageCount: _pageBlockIds.length,
                      background: _currentBg,
                      accent: _accent,
                      hasAiKey: hasAiKey,
                      aiLinked: aiLinked,
                      noteTitle: widget.note.title ?? '',
                      onExpand: () => setState(() => _headerCollapsed = false),
                      onOpenPages: _togglePageDrawer,
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
                    ModeHeader(
                      mode: 'CUADERNO',
                      subtitle: (widget.note.title?.trim().isNotEmpty == true)
                          ? 'A4 · ${_pageBlockIds.length} PÁGINAS · ${_currentBg.label} · ${widget.note.title!.trim()}'
                          : 'A4 · ${_pageBlockIds.length} PÁGINAS · ${_currentBg.label}',
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
                              border: Border.all(
                                color: yBorderStrong,
                                width: yLineMid,
                              ),
                            ),
                            child: const Icon(
                              YuLiIcons.bookOpen,
                              color: yInk,
                              size: 18,
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
                              width: 34,
                              height: 34,
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
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _linkToLab(spaces),
                          child: Container(
                            width: 34,
                            height: 34,
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
                              size: 18,
                            ),
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
                  Expanded(
                child:
                    _pageBlockIds.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                          builder: (ctx, c) {
                            final viewport = Size(c.maxWidth, c.maxHeight);
                            _viewport = viewport;
                            final textBlockOverlays = _buildTextBlockOverlays();
                            final taskBlockOverlays = _buildTaskBlockOverlays();
                            final lassoActive =
                                _lassoCtrl.phase != LassoPhase.idle;
                            final lassoStrokes =
                                lassoActive
                                    ? _allVisibleStrokes
                                    : const <DrawingStroke>[];
                            final lassoImages =
                                lassoActive
                                    ? _allVisibleImages
                                    : const <CanvasImage>[];
                            // The canvas subtree below is built ONCE per build()
                            // — NOT wrapped in an AnimatedBuilder(_viewCtrl), so
                            // panning no longer reconstructs the InteractiveViewer
                            // + every layer each frame. Pan-driven repaints happen
                            // inside each layer's own AnimatedBuilder (render-rect
                            // hysteresis) and the isolated pull indicator.
                            final lastPageBottom =
                                _pageBlockIds.isNotEmpty
                                    ? (_pageBlockIds.length - 1) *
                                            (kNotebookPageHeight +
                                                kNotebookPageGap) +
                                        kNotebookPageHeight
                                    : 0.0;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                RepaintBoundary(
                                  key: _canvasBoundaryKey,
                                  child: ClipRect(
                                  child: RawGestureDetector(
                                    // A stylus must NEVER pan the canvas: this
                                    // Eager recognizer (stylus-only) wins the
                                    // gesture arena the instant a pen touches, so
                                    // the InteractiveViewer's pan recognizer is
                                    // rejected and never fights the stroke. Fingers
                                    // are unaffected (it ignores touch).
                                    gestures: <Type, GestureRecognizerFactory>{
                                      TapGestureRecognizer:
                                          GestureRecognizerFactoryWithHandlers<
                                              TapGestureRecognizer>(
                                        () => TapGestureRecognizer(),
                                        (i) => i.onTapUp = _onLassoTap,
                                      ),
                                      EagerGestureRecognizer:
                                          GestureRecognizerFactoryWithHandlers<
                                              EagerGestureRecognizer>(
                                        () => EagerGestureRecognizer(
                                          supportedDevices: const {
                                            PointerDeviceKind.stylus,
                                            PointerDeviceKind.invertedStylus,
                                          },
                                        ),
                                        (i) {},
                                      ),
                                    },
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
                                          if (_eyedropperMode &&
                                              _eyedropCaptureMatrix != null &&
                                              _viewCtrl.value !=
                                                  _eyedropCaptureMatrix) {
                                            _captureEyedropSnapshot(
                                              resetPos: false,
                                            );
                                          }
                                        },
                                        boundaryMargin: EdgeInsets.symmetric(
                                          horizontal: c.maxWidth,
                                          vertical: _totalCanvasHeight * 0.3,
                                        ),
                                        // Text mode: 1-finger drag moves a box (its
                                        // GestureDetector), so disable pan; 2-finger
                                        // still navigates.
                                        panEnabled:
                                            _eyedropperMode
                                                ? _activePointers.length >= 2
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
                                                : _tool == DrawTool.text
                                                ? true
                                                : _tool == DrawTool.task
                                                ? true
                                                : _tool == DrawTool.lasso
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
                                              _buildNotebookBackgroundLayer(
                                                viewport,
                                                Size(
                                                  kNotebookPageWidth,
                                                  _totalCanvasHeight,
                                                ),
                                              ),
                                              // Text blocks BELOW the ink.
                                              ...textBlockOverlays,
                                              _buildNotebookStrokeLayer(
                                                viewport,
                                                Size(
                                                  kNotebookPageWidth,
                                                  _totalCanvasHeight,
                                                ),
                                              ),
                                              IgnorePointer(
                                                child: RepaintBoundary(
                                                  child: AnimatedBuilder(
                                                    animation: _activeTick,
                                                    builder:
                                                        (_, _) => CustomPaint(
                                                          painter: _ActiveStrokePainter(
                                                            active: _active,
                                                            tick:
                                                                _activeTick
                                                                    .value,
                                                            pageTop:
                                                                _activePageIndex !=
                                                                        null
                                                                    ? _activePageIndex! *
                                                                        (kNotebookPageHeight +
                                                                            kNotebookPageGap)
                                                                    : 0.0,
                                                          ),
                                                          size: Size(
                                                            kNotebookPageWidth,
                                                            _totalCanvasHeight,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              // Task blocks above the ink.
                                              ...taskBlockOverlays,
                                              _buildNotebookLassoLayer(
                                                viewport,
                                                Size(
                                                  kNotebookPageWidth,
                                                  _totalCanvasHeight,
                                                ),
                                                lassoStrokes,
                                                lassoImages,
                                              ),
                                              _buildPullIndicator(
                                                viewport,
                                                lastPageBottom,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  ),
                                ),
                                // Floating palettes — sibling of the canvas
                                // Listener (no pointer leak) and OUTSIDE the
                                // _viewCtrl AnimatedBuilder so they stay pinned
                                // to the screen. They slide off toward their edge
                                // during the eyedropper.
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
                                // Eyedropper loupe (viewport-space, pinned).
                                if (_eyedropImg != null)
                                  ..._buildLoupeOverlay(viewport),
                                // Screen-space overlays that track the view
                                // transform — their own tiny AnimatedBuilder
                                // so they still follow pan, without dragging
                                // the heavy canvas subtree into a rebuild.
                                Positioned.fill(
                                  child: AnimatedBuilder(
                                    animation: _viewCtrl,
                                    builder:
                                        (_, _) => Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            if (_lassoCtrl.phase ==
                                                    LassoPhase.selected &&
                                                _toolbarVisible)
                                              _buildLassoMiniToolbar(),
                                            if (_showPasteAt != null)
                                              _buildPasteButton(),
                                            if (_tool == DrawTool.eraser &&
                                                _eraserCursor != null)
                                              Positioned(
                                                left:
                                                    _eraserCursor!.dx -
                                                    _eraserScreenRadius,
                                                top:
                                                    _eraserCursor!.dy -
                                                    _eraserScreenRadius,
                                                child: const EraserCursor(
                                                  radius: _eraserScreenRadius,
                                                ),
                                              ),
                                          ],
                                        ),
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
                  accentColor: _accent,
                  imageCache: _imgCache,
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
                  onExport: (indices) {
                    _togglePageDrawer();
                    _exportPages(indices);
                  },
                ),
              ),
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
              pattern: _currentBg,
              color: _currentBgColor,
              showScope: true,
              allPages: _bgAllPages,
              accent: _accent,
              onPattern: _applyBgPattern,
              onColor: _applyBgColor,
              onMoreColors: () => setState(() {
                _bgColorPickerOpen = true;
                _bgPopupOpen = false;
              }),
              onScope: (all) => setState(() => _bgAllPages = all),
              onClose: _toggleBgPopup,
            ),
          ),
          RevealPopup(
            key: const ValueKey('rp-bgcolor'),
            open: _bgColorPickerOpen,
            onDismiss: () => setState(() => _bgColorPickerOpen = false),
            child: ColorPickerPopup(
              currentColor: _currentBgColor,
              recentColors: const [],
              savedColors: _bgSavedColors,
              quickColors: _bgSavedColors,
              quickLabel: 'FAVORITOS',
              onPreview: _applyBgColor,
              onCommit: _applyBgColor,
              onStar: _starBgColor,
              onEyedropper: () {},
              onClose: () => setState(() {
                _bgColorPickerOpen = false;
                _bgPopupOpen = true;
              }),
            ),
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
          RevealPopup(
            key: const ValueKey('rp-eraser'),
            open: _eraserPopupOpen,
            onDismiss: () => setState(() => _eraserPopupOpen = false),
            child: _eraserModePopup(),
          ),
           ],
         ),
       ),
     ),
   );
    }

  // ─── Toolbar ───────────────────────────────────────────────────────────

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
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
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
              const SizedBox(width: 10),
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

  /// Secondary / occasional controls behind the toolbar's "more" (⋯) button so
  /// the main row stays uncluttered and edge-to-edge.
  // ─── Export ────────────────────────────────────────────────────────────

  /// Off-screen raster specs for one page's blocks (page-local coords; rotation
  /// captured at 0 and re-applied at composite).
  List<BlockRasterSpec> _pageBlockSpecs(
    DrawingData data,
    int pageIndex,
    bool includeTasks,
  ) {
    final specs = <BlockRasterSpec>[];
    for (final b in data.textBlocks) {
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
      for (final b in data.taskBlocks) {
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

  /// Entry from the page drawer: [indices] are the pages the user checked.
  Future<void> _exportPages(List<int> indices) async {
    if (indices.isEmpty || !mounted) return;
    final hasTasks = indices.any((i) {
      if (i < 0 || i >= _pageBlockIds.length) return false;
      final d = _pageData[_pageBlockIds[i]];
      return d != null && d.taskBlocks.isNotEmpty;
    });
    final opts = await showNotebookExportSheet(
      context,
      accent: _accent,
      selectedCount: indices.length,
      hasTasks: hasTasks,
    );
    if (opts == null || !mounted) return;
    _runExport(indices, opts);
  }

  Future<void> _runExport(List<int> indices, CanvasExportOptions opts) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportProgressDialog(accent: _accent),
    );

    final region = Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight);
    final pr = exportPixelRatio(region);

    final pageImages = <ui.Image>[];
    final pageSizes = <Size>[];
    final blockImgs = <ExportBlockImage>[];
    final images = <String, ui.Image>{};
    ui.Image? combined;
    try {
      for (final i in indices) {
        if (i < 0 || i >= _pageBlockIds.length) continue;
        final data = _pageData[_pageBlockIds[i]];
        if (data == null) continue;
        images.addAll(await loadExportImages(_imageDirPath, data.images));
        if (!mounted) return;
        final specs = _pageBlockSpecs(data, i, opts.includeTasks);
        final blocks = await rasterizeCanvasBlocks(
          context: context,
          specs: specs,
          pixelRatio: pr,
        );
        blockImgs.addAll(blocks);
        final paper = bgPaper(data.bgColorValue, const Color(0xFFFFFDF8));
        final img = await renderCanvasRegion(
          data: data,
          region: region,
          pixelRatio: pr,
          paper: paper,
          images: images,
          blocks: blocks,
        );
        pageImages.add(img);
        pageSizes.add(region.size);
      }
      if (pageImages.isEmpty) return;

      final name = sanitizeFilename(
        widget.note.title?.isNotEmpty == true
            ? widget.note.title!
            : widget.folder.name,
      );

      if (opts.format == ExportFormat.png) {
        final single = pageImages.length == 1;
        final out = single
            ? pageImages.first
            : (combined = await stackImagesVertically(
                pageImages,
                gap: 18 * pr,
                background: yCream2,
              ));
        final png = await imageToPngBytes(out);
        await shareExportBytes(png, '$name.png', text: 'Cuaderno · YuLi');
      } else if (opts.onePagePerSheet && pageImages.length > 1) {
        final pdf = await buildCanvasPdf([
          for (int k = 0; k < pageImages.length; k++)
            ExportPage(image: pageImages[k], worldSize: pageSizes[k]),
        ]);
        await shareExportBytes(pdf, '$name.pdf', text: 'Cuaderno · YuLi');
      } else {
        final single = pageImages.length == 1;
        final out = single
            ? pageImages.first
            : (combined = await stackImagesVertically(
                pageImages,
                gap: 18 * pr,
                background: yCream2,
              ));
        final pdf = await buildCanvasPdf([
          ExportPage(
            image: out,
            worldSize: Size(out.width / pr, out.height / pr),
          ),
        ]);
        await shareExportBytes(pdf, '$name.pdf', text: 'Cuaderno · YuLi');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo exportar'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      combined?.dispose();
      for (final img in pageImages) {
        img.dispose();
      }
      for (final b in blockImgs) {
        b.image.dispose();
      }
      disposeExportImages(images);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

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
        ],
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
    final existing =
        await kanbanRepo.watchBySourceNoteId(widget.note.id).first;
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
            : 'Cuaderno ${widget.folder.name}';
    await kanbanRepo.create(
      labSpaceId: picked.id,
      columnId: backlog.id,
      title: title,
      sourceNoteId: widget.note.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Vinculada a ${picked.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

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
              'Vincular cuaderno a LAB',
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

class _CollapsedNotebookHeader extends StatelessWidget {
  final Folder folder;
  final int pageCount;
  final PageBackground background;
  final Color accent;
  final bool hasAiKey;
  final bool aiLinked;
  final String noteTitle;
  final VoidCallback onExpand;
  final VoidCallback onOpenPages;
  final VoidCallback onAi;

  const _CollapsedNotebookHeader({
    required this.folder,
    required this.pageCount,
    required this.background,
    required this.accent,
    required this.hasAiKey,
    required this.aiLinked,
    required this.noteTitle,
    required this.onExpand,
    required this.onOpenPages,
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
                  ? 'CUADERNO · @${folder.name} · $pageCount PÁG'
                  : 'CUADERNO · @${folder.name} · $pageCount PÁG · ${noteTitle.trim()}',
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
            onTap: onOpenPages,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.bookOpen, color: yInk, size: 16),
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

// ─── Canvas painter ──────────────────────────────────────────────────────

// Reused across painter instances/frames — constant page chrome (never
// mutated, drawn read-only) and laid-out page-number labels (text shaping is
// not cheap; the number + style for a given page never change).
final Paint _pageBgPaint = Paint()..color = const Color(0xFFF0EDE6);
final Paint _pageShadowPaint = Paint()..color = yInk.withValues(alpha: 0.12);
final Paint _pageBorderPaint =
    Paint()
      ..color = yInk.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

final Map<int, TextPainter> _pageNumberPainters = {};

TextPainter _pageNumberPainter(int page) {
  final cached = _pageNumberPainters[page];
  if (cached != null) return cached;
  final tp = TextPainter(
    text: TextSpan(
      text: '$page',
      style: TextStyle(
        fontSize: 10,
        color: yMuted.withValues(alpha: 0.4),
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  _pageNumberPainters[page] = tp;
  return tp;
}

class _NotebookCanvasPainter extends CustomPainter {
  final List<int> pageBlockIds;
  final Map<int, DrawingData> pageData;
  final Rect visibleRect;
  final int paintVersion;
  final Color accentColor;
  final Map<int, Set<int>> hiddenStrokes;
  final Map<int, Set<int>> hiddenImages;
  final CanvasImageCache? imageCache;

  /// Layer split so strokes render ABOVE the text-block overlays: the bottom
  /// layer paints page chrome + images ([drawStrokes] false), and a second
  /// layer above the text overlays paints only strokes ([drawBackground] false).
  final bool drawBackground;
  final bool drawStrokes;

  _NotebookCanvasPainter({
    required this.pageBlockIds,
    required this.pageData,
    required this.visibleRect,
    required this.paintVersion,
    required this.accentColor,
    this.hiddenStrokes = const {},
    this.hiddenImages = const {},
    this.imageCache,
    this.drawBackground = true,
    this.drawStrokes = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (drawBackground) {
      // Background behind pages
      canvas.drawRect(visibleRect, _pageBgPaint);
    }

    for (int i = 0; i < pageBlockIds.length; i++) {
      final pageTop = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageRect = Rect.fromLTWH(
        0,
        pageTop,
        kNotebookPageWidth,
        kNotebookPageHeight,
      );

      if (!pageRect.overlaps(visibleRect)) continue;

      final pageDataItem = pageData[pageBlockIds[i]];

      if (drawBackground) {
        // Page shadow
        canvas.drawRect(pageRect.shift(const Offset(4, 4)), _pageShadowPaint);

        // Paper + pattern (per page).
        final paper = bgPaper(
          pageDataItem?.bgColorValue,
          const Color(0xFFFFFDF8),
        );
        canvas.drawRect(pageRect, Paint()..color = paper);
        paintBgPattern(
          canvas,
          pageRect,
          pageDataItem?.background ?? PageBackground.blank,
          bgMark(paper),
        );

        // Page border
        canvas.drawRect(pageRect, _pageBorderPaint);

        // Page number
        final tp = _pageNumberPainter(i + 1);
        tp.paint(
          canvas,
          Offset(
            kNotebookPageWidth - tp.width - 16,
            pageTop + kNotebookPageHeight - tp.height - 12,
          ),
        );
      }

      // Strokes / images — clipped + translated into page-local space.
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
        // Images behind strokes.
        final skipImg = hiddenImages[i];
        if (drawBackground) {
          for (int ii = 0; ii < data.images.length; ii++) {
            if (skipImg != null && skipImg.contains(ii)) continue;
            final im = data.images[ii];
            if (!Rect.fromLTWH(im.x, im.y, im.w, im.h).overlaps(pageVisible)) {
              continue;
            }
            drawCanvasImage(canvas, imageCache?.get(im.filename), im);
          }
        }
        final skip = hiddenStrokes[i];
        if (drawStrokes) {
          for (int si = 0; si < data.strokes.length; si++) {
            if (skip != null && skip.contains(si)) continue;
            if (!strokeOverlapsRect(data.strokes[si], pageVisible)) continue;
            drawStroke(canvas, data.strokes[si]);
          }
        }
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_NotebookCanvasPainter old) =>
      old.paintVersion != paintVersion ||
      old.visibleRect != visibleRect ||
      old.accentColor != accentColor ||
      old.drawBackground != drawBackground ||
      old.drawStrokes != drawStrokes ||
      old.hiddenStrokes != hiddenStrokes ||
      old.hiddenImages != hiddenImages;
}

/// Paints only the in-progress stroke, in its own RepaintBoundary, so live
/// point additions don't repaint the whole notebook canvas. [pageTop] offsets
/// the page-local stroke coords into canvas space.
class _ActiveStrokePainter extends CustomPainter {
  final DrawingStroke? active;
  final int tick;
  final double pageTop;

  _ActiveStrokePainter({
    required this.active,
    required this.tick,
    required this.pageTop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (active == null) return;
    canvas.save();
    canvas.translate(0, pageTop);
    drawActiveStroke(canvas, active!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter old) =>
      old.active != active || old.tick != tick || old.pageTop != pageTop;
}
