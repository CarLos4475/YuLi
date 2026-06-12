import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/crash_logger.dart';
import '../../../domain/models/drawing_stroke_record.dart';
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
import 'drawing_stroke_persistence.dart';
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
import 'pinned_snapshots.dart';
import 'notebook_constants.dart';
import 'notebook_page_drawer.dart';
import 'shape_recognizer.dart';
import 'shape_picker_popup.dart';
import 'stroke_bounds.dart';
import 'stroke_tiles.dart';
import 'stroke_stabilizer.dart';
import 'stroke_width_picker.dart';

typedef _NotebookSnapshot =
    Map<
      int,
      (
        List<DrawingStroke>,
        List<CanvasImage>,
        List<CanvasTaskBlock>,
        List<CanvasTextBlock>,
      )
    >;

abstract class _NotebookHistoryEntry {
  const _NotebookHistoryEntry();
}

class _NotebookSnapshotEntry extends _NotebookHistoryEntry {
  final _NotebookSnapshot snapshot;

  const _NotebookSnapshotEntry(this.snapshot);
}

class _NotebookStrokeAddEntry extends _NotebookHistoryEntry {
  final int blockId;
  final DrawingStroke stroke;

  const _NotebookStrokeAddEntry(this.blockId, this.stroke);
}

enum _LassoSyncMode { full, lengthStable, deleteSelected, appendSelected }

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
  // Pages whose JSON hasn't been decoded yet. Decoding every page up front
  // blocks the first frame (the open jank); these stream in after it. A page
  // here is absent from _pageData → treated as empty (blank chrome) until ready.
  final Map<int, DrawingBlock> _pendingDecode = {};

  final TransformationController _viewCtrl = TransformationController();
  int _paintVersion = 0;
  Rect? _renderRect;
  Color _color = yInk;
  double _strokeW = 3.0;
  DrawTool _tool = DrawTool.pen;
  bool _palmRejection = true;
  DrawingStroke? _active;
  int? _activePageIndex;
  Stopwatch? _inkPerfSw;
  int _inkMoveSamples = 0;
  int _inkSlowMoves = 0;
  int _inkWorstMoveUs = 0;
  // Ticked on every live point added to [_active]. Repaints only the active
  // stroke layer (its own RepaintBoundary) without a full-canvas setState, so
  // the wet stroke keeps up with the stylus instead of trailing it.
  final ValueNotifier<int> _activeTick = ValueNotifier(0);
  // Per-page spatial tile index of strokes. Each page renders as a grid of
  // RepaintBoundary tiles so a stroke edit re-rasterizes only the touched tile,
  // not the whole page (the dense-page writing/lasso jank).
  final Map<int, StrokeTileIndex> _pageTiles = {};
  final Map<int, List<DrawingStroke>> _pageWorldStrokeCache = {};
  // Bumped on any page-ink change so the (single) tile layer rebuilds and
  // re-emits tile widgets with fresh versions; only changed tiles repaint.
  final ValueNotifier<int> _inkTick = ValueNotifier(0);
  // Repaints only the lasso overlay during a continuous gesture (move/resize/
  // rotate/trace) so it follows the pointer immediately without a tree setState.
  final ValueNotifier<int> _lassoGestureTick = ValueNotifier(0);
  // Bumped on a grab/release (selected ↔ gesture) so the ink layers + toolbar
  // refresh their phase-dependent bits WITHOUT a full-tree setState — the latter
  // rebuilds every page/overlay/provider and is the grab/drop jank (and crash
  // risk on big notebooks).
  final ValueNotifier<int> _lassoPhaseTick = ValueNotifier(0);
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
  bool _floatingToolbarsPopupOpen = false;
  // Post-snap live adjust state.
  ShapeKind? _snapKind;
  List<List<double>>? _snapBasePoints;
  Offset? _snapCenter;
  Offset? _snapAnchor;
  double _snapRefDist = 1;
  final List<_NotebookHistoryEntry> _undoStack = [];
  final List<_NotebookHistoryEntry> _redoStack = [];
  _NotebookSnapshot? _gestureBefore;
  // World-space selection box captured when a move/resize/rotate grab starts, so
  // the drop only re-buckets + persists the pages the edit actually spans
  // (vs. rewriting and DB-writing every page in the notebook).
  Rect? _gestureBoxBefore;
  bool _gestureChanged = false;
  bool _isDrawing = false;
  bool _stylusActive = false;
  bool _headerCollapsed = true;
  final Set<int> _activePointers = {};
  Timer? _holdTimer;
  Timer? _deferredDecodeTimer;
  Offset? _holdAnchor;
  static const _holdTolerance2 = 400.0;
  late final List<Color> _palette;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  LassoPhase _lastLassoPhase = LassoPhase.idle;
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
  bool _decodeInteractionActive = false;

  @override
  void setState(VoidCallback fn) {
    _paintVersion++;
    super.setState(fn);
  }

  Timer? _pasteTimer;
  Timer? _persistTimer;
  final Set<int> _dirtyPersistPages = {};
  final Set<int> _fullStrokePersistBlocks = {};
  final Map<int, Set<int>> _persistedStrokeIdsByBlock = {};
  final Map<int, Set<int>> _dirtyStrokeIdsByBlock = {};
  final Map<int, int> _nextStrokePosByBlock = {};
  bool _persisting = false;
  Offset? _pastePos;
  Offset? _showPasteAt;

  // ─── Zoomed-out overview (per page) ───────────────────────────────────────
  // Below [_overviewThreshold] each page shows ONE cached downsampled ink image
  // instead of its tiles, so deep zoom-out blits textures instead of redrawing
  // thousands of strokes per frame. Per-page (not one giant image) keeps each at
  // a high, crisp density. Strokes-only/transparent over the live page chrome;
  // RAM only (never persisted). See [[canvas-heat-zoomout]].
  final Map<int, ui.Image> _overviewByPage = {};
  final Map<int, int> _overviewBakedCountByPage = {};
  final Set<int> _overviewBakingPages = {};
  final Set<int> _overviewDirtyPages = {};
  double _overviewThreshold = 0;
  Timer? _overviewTimer;
  // Pin the overview through a 2-finger zoom gesture; hand back to crisp tiles
  // only when it ends (avoids re-rastering tiles mid-pinch → jank).
  bool _viewGestureActive = false;
  bool _overviewStickyThisGesture = false;
  bool _overviewActive = false;

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

  // Pinned snapshots (PiN): process-level store keyed by note so they survive
  // leaving and re-entering. See pinned_snapshots.dart.
  late final List<PinnedSnapshot> _pins = PinnedSnapshotStore.instance.forNote(
    widget.note.id,
  );

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
    _lassoCtrl.onChanged = _onLassoChanged;
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
            // Bump paintVersion: the background painter (which draws images)
            // keys off it, so a bare setState wouldn't show a decoded image.
            if (mounted) setState(() => _paintVersion++);
          },
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialScroll();
        _scheduleDeferredDecode(const Duration(milliseconds: 220));
      });
    });
  }

  @override
  void dispose() {
    _eyedropImg?.dispose();
    _reconcileImageFiles();
    _holdTimer?.cancel();
    _deferredDecodeTimer?.cancel();
    _persistTimer?.cancel();
    _overviewTimer?.cancel();
    for (final img in _overviewByPage.values) {
      img.dispose();
    }
    _overviewByPage.clear();
    if (_dirtyPersistPages.isNotEmpty) unawaited(_flushPendingPersists());
    for (final index in _pageTiles.values) {
      index.dispose();
    }
    _pageTiles.clear();
    _pageWorldStrokeCache.clear();
    _inkTick.dispose();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _pullAnimCtrl.dispose();
    _drawerAnimCtrl.dispose();
    _imgCache?.dispose();
    _viewCtrl.dispose();
    _activeTick.dispose();
    _lassoGestureTick.dispose();
    _lassoPhaseTick.dispose();
    super.dispose();
  }

  /// On leaving the notebook, delete image files no longer referenced by any
  /// page. Canvas images are tracked only in the page payloads.
  void _reconcileImageFiles() {
    final dirPath = _imageDirPath;
    if (dirPath == null) return;
    // Pages still pending decode aren't in _pageData; their images would look
    // unreferenced and get wrongly deleted. Skip cleanup until everything's
    // loaded — the startup GC (cleanupOrphanedImages) catches real orphans.
    if (_pendingDecode.isNotEmpty) return;
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
    final sw = Stopwatch()..start();
    final repo = ref.read(noteBlockRepositoryProvider);
    final blocks = await repo.getByNote(widget.note.id);
    final drawingBlocks =
        blocks.whereType<DrawingBlock>().toList()
          ..sort((a, b) => a.position.compareTo(b.position));

    if (drawingBlocks.isEmpty) {
      await _ensurePageAt(0);
      return;
    }

    // Register all pages (cheap — drives layout/scroll/height) but DEFER the
    // heavy stroke decode of off-screen pages off the open path. The initial
    // scroll lands on the bottom, so decode the last page (+ its neighbor) now;
    // the rest stream in after the first frame (see _decodeMorePages).
    for (final b in drawingBlocks) {
      _pageBlockIds.add(b.id);
      _pendingDecode[b.id] = b;
      if (b.starred) _starredBlockIds.add(b.id);
    }

    // Decode the pages the first frames touch: the last page (where the scroll
    // lands) and the first (shown for the frame before the scroll applies). The
    // rest stream in. Still O(1) work on the open path, not O(pages).
    for (final id in {drawingBlocks.first.id, drawingBlocks.last.id}) {
      final b = _pendingDecode.remove(id);
      if (b != null) {
        _pageData[id] = await _decodeData(b);
        _pageTileIndex(id).rebuild(_pageData[id]!.strokes);
        _rebuildWorldStrokeCache(id);
        _scheduleOverviewBake(id);
      }
    }

    // Inherit new-page background from the last page.
    final last = _pageData[_pageBlockIds.last];
    if (last != null) {
      _lastBg = last.background;
      _lastBgColor = last.bgColorValue;
    }

    setState(() {});

    sw.stop();
    CrashLogger.instance.note(
      'PERF abrir-cuaderno: ${drawingBlocks.length} paginas, '
      '${_pageData.length} decoded, ${_pendingDecode.length} pending, '
      '${sw.elapsedMilliseconds}ms',
    );

    if (_pendingDecode.isNotEmpty) _scheduleDeferredDecode();
  }

  /// Decode a few deferred pages per frame so even a 50-page note opens without
  /// a single blocking decode. Bottom-up: the user lands at the last page and
  /// scrolls up, so decode toward where they're heading first.
  Future<void> _decodeMorePages() async {
    if (!mounted || _pendingDecode.isEmpty) return;
    if (_decodeInteractionActive || _activePointers.isNotEmpty || _isDrawing) {
      _scheduleDeferredDecode();
      return;
    }
    final sw = Stopwatch()..start();
    const perBatch = 1;
    var n = 0;
    for (int i = _pageBlockIds.length - 1; i >= 0 && n < perBatch; i--) {
      final b = _pendingDecode.remove(_pageBlockIds[i]);
      if (b != null) {
        _pageData[_pageBlockIds[i]] = await _decodeData(b);
        final rebuildSw = Stopwatch()..start();
        _pageTileIndex(
          _pageBlockIds[i],
        ).rebuild(_pageData[_pageBlockIds[i]]!.strokes);
        _rebuildWorldStrokeCache(_pageBlockIds[i]);
        _scheduleOverviewBake(_pageBlockIds[i]);
        rebuildSw.stop();
        final data = _pageData[_pageBlockIds[i]]!;
        final pts = _pointCount(data.strokes);
        CrashLogger.instance.note(
          'PERF tile-cuaderno: page $i, ${data.strokes.length} trazos, '
          '$pts puntos, ${rebuildSw.elapsedMilliseconds}ms',
        );
        n++;
      }
    }
    if (n > 0) {
      // Bump so the painter (which compares paintVersion, not the mutated
      // pageData map) repaints any newly-decoded page that's already in view.
      _paintVersion++;
      setState(() {});
    }
    if (_pendingDecode.isNotEmpty) {
      _scheduleDeferredDecode();
    }
    sw.stop();
    if (n > 0) {
      CrashLogger.instance.note(
        'PERF decode-batch-cuaderno: $n paginas, '
        '${_pendingDecode.length} pending, ${sw.elapsedMilliseconds}ms',
      );
    }
  }

  void _pauseDeferredDecode() {
    _decodeInteractionActive = true;
    _deferredDecodeTimer?.cancel();
    _deferredDecodeTimer = null;
  }

  void _scheduleDeferredDecode([
    Duration delay = const Duration(milliseconds: 140),
  ]) {
    if (!mounted || _pendingDecode.isEmpty) return;
    _deferredDecodeTimer?.cancel();
    _deferredDecodeTimer = Timer(delay, () {
      if (!mounted) return;
      _decodeInteractionActive = false;
      unawaited(_decodeMorePages());
    });
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

  Future<DrawingData> _decodeData(DrawingBlock b) async {
    final sw = Stopwatch()..start();
    List<dynamic> strokes = const [];
    List<dynamic> images = const [];
    List<dynamic> taskBlocks = const [];
    List<dynamic> textBlocks = const [];
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
    try {
      final decoded = jsonDecode(b.textBlocksJson);
      if (decoded is List) textBlocks = decoded;
    } catch (_) {}
    final data = DrawingData.fromJson({
      'h': kNotebookPageHeight,
      's': strokes,
      'i': images,
      't': taskBlocks,
      'tx': textBlocks,
      'bg': b.background,
      'bgc': b.bgColor,
    });
    sw.stop();
    final rows = await ref
        .read(drawingStrokeRepositoryProvider)
        .getByBlock(b.id);
    final persisted = _persistedStrokeIdsByBlock.putIfAbsent(b.id, () => {});
    persisted.clear();
    _dirtyStrokeIdsByBlock.putIfAbsent(b.id, () => {}).clear();
    if (rows.isNotEmpty) {
      data.strokes = rows.map(strokeFromRecord).toList();
      var maxPos = -1;
      for (final r in rows) {
        persisted.add(r.id);
        if (r.position > maxPos) maxPos = r.position;
      }
      _nextStrokePosByBlock[b.id] = maxPos + 1;
    } else {
      _nextStrokePosByBlock[b.id] = 0;
    }
    final pts = _pointCount(data.strokes);
    final pageIndex = _pageBlockIds.indexOf(b.id);
    CrashLogger.instance.note(
      'PERF decode-cuaderno: page $pageIndex, ${data.strokes.length} trazos, '
      '$pts puntos, json ${(b.strokesJson.length / 1024).round()}KB, '
      '${sw.elapsedMilliseconds}ms',
    );
    return data;
  }

  int _pointCount(Iterable<DrawingStroke> strokes) =>
      strokes.fold<int>(0, (total, s) => total + s.points.length);

  Set<int> _persistedStrokeIds(int blockId) =>
      _persistedStrokeIdsByBlock.putIfAbsent(blockId, () => {});

  Set<int> _dirtyStrokeIds(int blockId) =>
      _dirtyStrokeIdsByBlock.putIfAbsent(blockId, () => {});

  int _nextStrokePos(int blockId) => _nextStrokePosByBlock[blockId] ?? 0;

  void _markWorldStrokeDirty(DrawingStroke stroke) {
    final id = stroke.dbId;
    if (id == null || stroke.points.isEmpty) return;
    var sumY = 0.0;
    for (final p in stroke.points) {
      sumY += p[1];
    }
    final pageIndex = _nearestPageIndex(sumY / stroke.points.length);
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    if (_persistedStrokeIds(blockId).contains(id)) {
      _dirtyStrokeIds(blockId).add(id);
    }
  }

  void _markSelectedWorldStrokesDirty(List<DrawingStroke> worldStrokes) {
    for (final i in _lassoCtrl.selectedIndices) {
      if (i < worldStrokes.length) {
        _markWorldStrokeDirty(worldStrokes[i]);
      }
    }
  }

  void _beginInkPerf() {
    _inkPerfSw = Stopwatch()..start();
    _inkMoveSamples = 0;
    _inkSlowMoves = 0;
    _inkWorstMoveUs = 0;
  }

  void _recordInkMove(int micros) {
    _inkMoveSamples++;
    if (micros > _inkWorstMoveUs) _inkWorstMoveUs = micros;
    if (micros >= 8000) _inkSlowMoves++;
  }

  void _resetInkPerf() {
    _inkPerfSw = null;
    _inkMoveSamples = 0;
    _inkSlowMoves = 0;
    _inkWorstMoveUs = 0;
  }

  void _logInkPerf(
    String kind,
    DrawingStroke stroke, {
    required int pageIndex,
    required int finishMs,
    int? appendMs,
    int? historyMs,
    int? persistMs,
    int? snapshotMs,
  }) {
    final data = _pageData[_pageBlockIds[pageIndex]];
    final countSw = Stopwatch()..start();
    final pagePoints = data == null ? -1 : _pointCount(data.strokes);
    countSw.stop();
    final totalMs = _inkPerfSw?.elapsedMilliseconds ?? finishMs;
    CrashLogger.instance.note(
      'PERF escribir-cuaderno: $kind, pagina $pageIndex, '
      'trazo ${stroke.points.length} puntos, '
      'pagina ${data?.strokes.length ?? -1} trazos/$pagePoints puntos, '
      'moves $_inkMoveSamples, slowMoves $_inkSlowMoves, '
      'worstMove ${(_inkWorstMoveUs / 1000).toStringAsFixed(1)}ms, '
      'total ${totalMs}ms, finish ${finishMs}ms, '
      'snapshot ${snapshotMs ?? -1}ms, append ${appendMs ?? -1}ms, '
      'history ${historyMs ?? -1}ms, persist-schedule ${persistMs ?? -1}ms, '
      'count ${countSw.elapsedMilliseconds}ms',
    );
    _resetInkPerf();
  }

  // ─── Per-page tile index ──────────────────────────────────────────────────

  StrokeTileIndex _pageTileIndex(int blockId) =>
      _pageTiles.putIfAbsent(blockId, StrokeTileIndex.new);

  /// Append one committed stroke to a page's tile index (O(1)) and repaint.
  void _appendToPage(int blockId, DrawingStroke stroke) {
    _pageTileIndex(blockId).append(stroke);
    _appendWorldStrokeCache(blockId, stroke);
    _inkTick.value++;
  }

  Set<DrawingStroke> _strokesNearPage(
    int blockId,
    Offset local,
    double radius,
  ) {
    final rect = Rect.fromCircle(center: local, radius: radius);
    final out = <DrawingStroke>{};
    final index = _pageTiles[blockId];
    if (index == null) return out;
    for (final key in index.tilesInRect(rect)) {
      final list = index.strokesAt(key);
      if (list != null) out.addAll(list);
    }
    return out;
  }

  DrawingStroke _worldStrokeForPage(int pageIndex, DrawingStroke stroke) {
    final c = stroke.clone();
    final offset = _pageOffsetY(pageIndex);
    for (final pt in c.points) {
      pt[1] += offset;
    }
    return c;
  }

  void _rebuildWorldStrokeCache(int blockId) {
    final pageIndex = _pageBlockIds.indexOf(blockId);
    final data = _pageData[blockId];
    if (pageIndex < 0 || data == null) {
      _pageWorldStrokeCache.remove(blockId);
      return;
    }
    _pageWorldStrokeCache[blockId] = [
      for (final stroke in data.strokes) _worldStrokeForPage(pageIndex, stroke),
    ];
  }

  void _appendWorldStrokeCache(int blockId, DrawingStroke stroke) {
    final pageIndex = _pageBlockIds.indexOf(blockId);
    if (pageIndex < 0) return;
    (_pageWorldStrokeCache[blockId] ??= []).add(
      _worldStrokeForPage(pageIndex, stroke),
    );
  }

  List<DrawingStroke> _worldStrokeCacheForPage(int pageIndex) {
    final blockId = _pageBlockIds[pageIndex];
    if (!_pageWorldStrokeCache.containsKey(blockId)) {
      _rebuildWorldStrokeCache(blockId);
    }
    return _pageWorldStrokeCache[blockId] ?? const [];
  }

  (int, int)? _worldStrokePageLocalIndex(int worldIndex) {
    if (worldIndex < 0) return null;
    var start = 0;
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final count = _worldStrokeCacheForPage(i).length;
      final end = start + count;
      if (worldIndex < end) return (i, worldIndex - start);
      start = end;
    }
    return null;
  }

  int _worldStrokeIndexFromPageLocal(int pageIndex, int localIndex) {
    var start = 0;
    for (int i = 0; i < pageIndex; i++) {
      start += _worldStrokeCacheForPage(i).length;
    }
    return start + localIndex;
  }

  DrawingStroke _localStrokeFromWorld(int pageIndex, DrawingStroke stroke) {
    final c = stroke.clone();
    final offset = _pageOffsetY(pageIndex);
    for (final pt in c.points) {
      pt[1] -= offset;
    }
    return c;
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
      _persistedStrokeIdsByBlock[block.id] = {};
      _dirtyStrokeIdsByBlock[block.id] = {};
      _nextStrokePosByBlock[block.id] = 0;
    }
    setState(() {});
  }

  void _addPageAtEnd() {
    if (_pendingPageAdd) return;
    _pendingPageAdd = true;
    _ensurePageAt(_pageBlockIds.length).then((_) => _pendingPageAdd = false);
  }

  Future<void> _persistPageNow(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) {
      _dirtyPersistPages.remove(blockId);
      return;
    }
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    final blockRepo = ref.read(noteBlockRepositoryProvider);
    final sw = Stopwatch()..start();
    int inserted = 0, updated = 0, deleted = 0;
    if (_fullStrokePersistBlocks.remove(blockId)) {
      final ids = await strokeRepo.replaceBlock(blockId, [
        for (int i = 0; i < data.strokes.length; i++)
          strokeWrite(i, data.strokes[i]),
      ]);
      for (int i = 0; i < data.strokes.length && i < ids.length; i++) {
        data.strokes[i].dbId = ids[i];
      }
      _rebuildWorldStrokeCache(blockId);
      _persistedStrokeIds(blockId)
        ..clear()
        ..addAll(ids);
      _dirtyStrokeIds(blockId).clear();
      _nextStrokePosByBlock[blockId] = data.strokes.length;
      inserted = ids.length;
    } else {
      final persisted = _persistedStrokeIds(blockId);
      var nextPos = _nextStrokePos(blockId);
      final strokesSnapshot = List<DrawingStroke>.of(data.strokes);
      for (final stroke in strokesSnapshot) {
        if (stroke.dbId != null && persisted.contains(stroke.dbId)) {
          continue;
        }
        stroke.dbId = null;
        final id = await strokeRepo.insert(
          blockId,
          strokeWrite(nextPos++, stroke),
        );
        stroke.dbId = id;
        final cacheIndex = data.strokes.indexOf(stroke);
        final cache = _pageWorldStrokeCache[blockId];
        if (cache != null && cacheIndex >= 0 && cacheIndex < cache.length) {
          cache[cacheIndex].dbId = id;
        }
        persisted.add(id);
        inserted++;
      }
      _nextStrokePosByBlock[blockId] = nextPos;

      final byId = <int, DrawingStroke>{
        for (final s in data.strokes)
          if (s.dbId != null && persisted.contains(s.dbId)) s.dbId!: s,
      };
      final dirty = _dirtyStrokeIds(blockId);
      if (dirty.isNotEmpty) {
        final updates = <int, DrawingStrokeWrite>{};
        for (final id in dirty.toList()) {
          final stroke = byId[id];
          if (stroke == null) continue;
          updates[id] = strokeWrite(0, stroke);
        }
        await strokeRepo.updateMany(updates);
        updated = updates.length;
        dirty.clear();
      }

      final currentIds = byId.keys.toSet();
      final toDelete = persisted.difference(currentIds);
      if (toDelete.isNotEmpty) {
        await strokeRepo.deleteByIds(toDelete.toList());
        persisted.removeAll(toDelete);
        deleted = toDelete.length;
      }
    }
    final strokeMs = sw.elapsedMilliseconds;
    await blockRepo.updatePayload(blockId, {
      'h': kNotebookPageHeight,
      's': const [],
      'i': data.images.map((im) => im.toJson()).toList(),
      't': data.taskBlocks.map((b) => b.toJson()).toList(),
      'tx': data.textBlocks.map((b) => b.toJson()).toList(),
      'bg': data.background.toDbString(),
      if (data.bgColorValue != null) 'bgc': data.bgColorValue,
      'starred': _starredBlockIds.contains(blockId),
    });
    sw.stop();
    CrashLogger.instance.note(
      'PERF guardar-cuaderno: page $pageIndex, ${data.strokes.length} trazos, '
      '${_pointCount(data.strokes)} puntos, +$inserted ~$updated -$deleted, '
      'strokesDB ${strokeMs}ms, '
      'total(+DB) ${sw.elapsedMilliseconds}ms',
    );
    _dirtyPersistPages.remove(blockId);
  }

  void _persistPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    _dirtyPersistPages.add(_pageBlockIds[pageIndex]);
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_flushPendingPersists());
    });
    // Page ink changed → its zoomed-out overview image is stale.
    _scheduleOverviewBake(_pageBlockIds[pageIndex]);
  }

  /// Debounced re-bake of one page's zoomed-out overview after its ink settles.
  void _scheduleOverviewBake(int blockId) {
    _overviewDirtyPages.add(blockId);
    _overviewTimer?.cancel();
    _overviewTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final pages = _overviewDirtyPages.toList();
      _overviewDirtyPages.clear();
      for (final bid in pages) {
        unawaited(_bakePageOverview(bid));
      }
    });
  }

  /// Render one page's strokes into a downsampled, strokes-only [ui.Image] used
  /// in place of that page's tiles when zoomed out. Pages are a fixed size so
  /// the image is small and high-density; incremental when only appends happened.
  Future<void> _bakePageOverview(int blockId) async {
    if (_overviewBakingPages.contains(blockId) || !mounted) return;
    final data = _pageData[blockId];
    if (data == null) return;
    _overviewBakingPages.add(blockId);
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      const maxDim = 4096.0;
      final imgScale = (maxDim / kNotebookPageHeight).clamp(0.05, 2.0);
      final w = (kNotebookPageWidth * imgScale).ceil();
      final h = (kNotebookPageHeight * imgScale).ceil();
      final strokes = data.strokes;
      final count = strokes.length;
      final oldImage = _overviewByPage[blockId];
      final oldBaked = _overviewBakedCountByPage[blockId] ?? 0;
      // Page bounds are fixed, so any new stroke fits → appends are incremental.
      final incremental = oldImage != null && count > oldBaked;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(imgScale); // strokes are already page-local — no translate
      var from = 0;
      if (incremental) {
        canvas.drawImageRect(
          oldImage,
          Rect.fromLTWH(
            0,
            0,
            oldImage.width.toDouble(),
            oldImage.height.toDouble(),
          ),
          const Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight),
          Paint()..filterQuality = FilterQuality.medium,
        );
        from = oldBaked;
      }
      for (int i = from; i < count; i++) {
        drawStroke(canvas, strokes[i]);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _overviewByPage[blockId];
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _overviewByPage[blockId] = image;
      _overviewBakedCountByPage[blockId] = count;
      _overviewThreshold = (imgScale / dpr).clamp(0.0, 0.65);
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakePageOverview cuaderno');
    } finally {
      _overviewBakingPages.remove(blockId);
    }
  }

  Future<void> _flushPendingPersists() async {
    if (_dirtyPersistPages.isEmpty) return;
    if (_persisting) return;
    _persisting = true;
    final sw = Stopwatch()..start();
    var pages = 0;
    try {
      while (_dirtyPersistPages.isNotEmpty) {
        final blockIds = _dirtyPersistPages.toList();
        for (final blockId in blockIds) {
          final pageIndex = _pageBlockIds.indexOf(blockId);
          if (pageIndex >= 0) {
            await _persistPageNow(pageIndex);
            pages++;
          } else {
            _dirtyPersistPages.remove(blockId);
          }
        }
      }
    } catch (e, st) {
      CrashLogger.instance.record(
        e,
        st,
        context: 'flushPendingPersists cuaderno',
      );
    } finally {
      _persisting = false;
    }
    sw.stop();
    CrashLogger.instance.note(
      'PERF flush-cuaderno: $pages paginas, '
      '${sw.elapsedMilliseconds}ms',
    );
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
      // Bump paintVersion so the background painter repaints with the new image.
      setState(() {
        data.images.add(img);
        _paintVersion++;
      });
      _commitSnapshot(before);
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
    final pos =
        resetPos
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

  // ─── Pinned snapshots (PiN) ───────────────────────────────────────────────

  /// Capture the current lasso selection as a frozen raster cut-out and pin it
  /// over the canvas (paper, ink, images, blocks) — same boundary the eyedropper
  /// samples. The window floats fixed in viewport space across page changes.
  Future<void> _pinSelection() async {
    final bb = _lassoCtrl.boundingBox;
    if (bb == null) return;
    final vp = Rect.fromLTWH(0, 0, _viewport.width, _viewport.height);
    final screenRect = MatrixUtils.transformRect(
      _viewCtrl.value,
      bb,
    ).intersect(vp);
    if (screenRect.width < 8 || screenRect.height < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acerca la selección para fijarla'),
          duration: Duration(milliseconds: 1200),
        ),
      );
      return;
    }

    _lassoCtrl.deselect();
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final boundary =
        _canvasBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final full = await boundary.toImage(pixelRatio: dpr);

    final outW = (screenRect.width * dpr).round();
    final outH = (screenRect.height * dpr).round();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      full,
      Rect.fromLTWH(
        screenRect.left * dpr,
        screenRect.top * dpr,
        screenRect.width * dpr,
        screenRect.height * dpr,
      ),
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final cropped = await recorder.endRecording().toImage(outW, outH);
    full.dispose();
    if (!mounted) {
      cropped.dispose();
      return;
    }

    setState(() {
      _pins.add(
        PinnedSnapshot(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          image: cropped,
          pos: Offset(
            screenRect.left.clamp(8.0, _viewport.width - 60),
            screenRect.top.clamp(8.0, _viewport.height - 60),
          ),
          width: screenRect.width.clamp(120.0, _viewport.width * 0.6),
        ),
      );
    });
    HapticFeedback.mediumImpact();
  }

  void _movePin(String id, Offset delta) {
    final p = _pins.where((e) => e.id == id).firstOrNull;
    if (p == null) return;
    setState(() {
      p.pos = Offset(
        (p.pos.dx + delta.dx).clamp(48 - p.width, _viewport.width - 48),
        (p.pos.dy + delta.dy).clamp(8.0, _viewport.height - 48),
      );
    });
  }

  void _resizePin(String id, double dWidth) {
    final p = _pins.where((e) => e.id == id).firstOrNull;
    if (p == null) return;
    setState(
      () => p.width = (p.width + dWidth).clamp(100.0, _viewport.width * 0.95),
    );
  }

  void _closePin(String id) {
    final i = _pins.indexWhere((e) => e.id == id);
    if (i < 0) return;
    setState(() {
      _pins[i].dispose();
      _pins.removeAt(i);
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
    final left = (_loupePos.dx - loupeW / 2).clamp(
      8.0,
      viewport.width - loupeW - 8,
    );
    final top = (_loupePos.dy - loupeH - 40).clamp(
      8.0,
      viewport.height - loupeH - 8,
    );
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
    await _persistPageNow(idx);
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
    _pageTiles.remove(blockId)?.dispose();
    _pageWorldStrokeCache.remove(blockId);
    _persistedStrokeIdsByBlock.remove(blockId);
    _dirtyStrokeIdsByBlock.remove(blockId);
    _nextStrokePosByBlock.remove(blockId);
    _dirtyPersistPages.remove(blockId);
    _fullStrokePersistBlocks.remove(blockId);

    await ref.read(drawingStrokeRepositoryProvider).deleteByBlock(blockId);
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

  /// See whiteboard editor: the lasso overlay repaints every frame from
  /// _lassoAnimCtrl during a continuous gesture, so skip the full-tree setState
  /// per stylus point (~240Hz) — only rebuild on a phase change. This was the
  /// jank on dense multi-page notebooks.
  static const _kLassoGesturePhases = {
    LassoPhase.moving,
    LassoPhase.resizing,
    LassoPhase.rotating,
  };

  void _onLassoChanged() {
    _syncLassoTicker();
    final phase = _lassoCtrl.phase;
    final prev = _lastLassoPhase;
    _lastLassoPhase = phase;

    const continuous = {LassoPhase.tracing, ..._kLassoGesturePhases};
    // Same-phase continuous update (per stylus point): never rebuild the tree.
    // The lasso overlay and any selected block's Transform listen to
    // _lassoGestureTick and repaint in place.
    if (phase == prev && continuous.contains(phase)) {
      _lassoGestureTick.value++;
      return;
    }

    // Grab / release: selected ↔ a gesture phase. panEnabled is unchanged and
    // the lasso layer stays visible, so skip the full-tree setState (which
    // rebuilds every page/overlay/provider — the grab/drop jank). The ink layers
    // + toolbar refresh via _lassoPhaseTick. EXCEPTION: block selections, whose
    // overlays must (un)wrap their live-transform in build().
    final grabOrRelease =
        (prev == LassoPhase.selected && _kLassoGesturePhases.contains(phase)) ||
        (_kLassoGesturePhases.contains(prev) && phase == LassoPhase.selected);
    if (grabOrRelease && !_selectionHasBlocks) {
      _lassoPhaseTick.value++;
      _lassoGestureTick.value++;
      return;
    }

    if (mounted) setState(() {});
  }

  bool get _selectionHasBlocks =>
      _lassoCtrl.selectedBlockIndices.isNotEmpty ||
      _lassoCtrl.selectedTextBlockIndices.isNotEmpty;

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
    final snapPts = _active!.points;
    if (isScribble(snapPts, viewScale: _viewScale)) return false;
    final shape = ShapeRecognizer.detect(_active!.points);
    if (shape == null) return false;
    if (!_canSnapHeldShape(shape.kind, snapPts)) return false;
    // Highlighter only snaps to straight lines (a marker arrow/box reads odd).
    if (_tool == DrawTool.highlighter && shape.kind != ShapeKind.line) {
      return false;
    }
    _enterShapeAdjust(shape, _active!);
    HapticFeedback.lightImpact();
    return true;
  }

  bool _canSnapHeldShape(ShapeKind kind, List<List<double>> points) {
    if (kind == ShapeKind.line || kind == ShapeKind.arrow) return true;
    if (!shapeKindIsClosed(kind) && kind != ShapeKind.pentagram) return true;
    final bounds = scribbleBounds(points);
    final diag2 = bounds.width * bounds.width + bounds.height * bounds.height;
    if (diag2 <= 0) return false;
    final start = Offset(points.first[0], points.first[1]);
    final end = Offset(points.last[0], points.last[1]);
    final dist2 = (start - end).distanceSquared;
    return dist2 / diag2 <= 0.09;
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
    final sw = Stopwatch()..start();
    final shape = _active;
    final pageIdx = _activePageIndex;
    _clearSnap();
    if (shape == null || pageIdx == null) return;
    final data = _pageData[_pageBlockIds[pageIdx]];
    if (data == null) {
      setState(() => _active = null);
      return;
    }
    final snapSw = Stopwatch()..start();
    final before = _snapshot();
    snapSw.stop();
    setState(() {
      data.strokes.add(shape);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _appendToPage(_pageBlockIds[pageIdx], shape);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitSnapshot(before);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persistPage(pageIdx);
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'shape-snap',
      shape,
      pageIndex: pageIdx,
      finishMs: sw.elapsedMilliseconds,
      appendMs: appendSw.elapsedMilliseconds,
      historyMs: historySw.elapsedMilliseconds,
      persistMs: persistSw.elapsedMilliseconds,
      snapshotMs: snapSw.elapsedMilliseconds,
    );
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
    _pauseDeferredDecode();
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
          _isDrawing =
              true; // lasso: no rebuild needed (phase-gated panEnabled)
          _handleLassoDown(p);
          return;
        }
      }
      // A clean finger tap to (re)select is handled by the overlay
      // GestureDetector's onTapUp; a finger drag pans via InteractiveViewer.
      return;
    }

    final willDraw = _shouldDraw(e.kind);
    // Lasso never needs a rebuild just for _isDrawing (panEnabled is phase-gated)
    // → skip the setState to avoid a full-tree rebuild at grab. Phase-driven
    // rebuilds still fire via _onLassoChanged.
    if (_tool == DrawTool.lasso) {
      _isDrawing = willDraw;
    } else {
      setState(() => _isDrawing = willDraw);
    }
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
    _beginInkPerf();

    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() {
        _active = DrawingStroke(
          colorValue: _color.toARGB32(),
          strokeWidth: _strokeW,
          isFountainPen: true,
          points: [
            [sp.dx, sp.dy, pressure, e.timeStamp.inMilliseconds.toDouble()],
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
    final moveSw = _inkPerfSw == null ? null : (Stopwatch()..start());
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
      moveSw?.stop();
      if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
      return;
    }
    final pts = _active!.points;
    if (pts.isNotEmpty && !_stabilizer.isOn) {
      final dx = sp.dx - pts.last[0];
      final dy = sp.dy - pts.last[1];
      if (dx * dx + dy * dy < _minDist2) {
        moveSw?.stop();
        if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
        return;
      }
    }
    pts.add(
      _active!.isPencil
          ? [sp.dx, sp.dy, e.pressure.isFinite ? e.pressure : 0.5]
          : [sp.dx, sp.dy],
    );
    _activeTick.value++;
    moveSw?.stop();
    if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
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
    // Lasso: no rebuild for _isDrawing (phase-gated). Releasing a stroke
    // selection routes through _handleLassoUp → _onLassoChanged, which refreshes
    // via _lassoPhaseTick instead of a full-tree setState.
    if (_tool == DrawTool.lasso) {
      _isDrawing = false;
    } else {
      setState(() => _isDrawing = false);
    }

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
    if (_activePointers.isEmpty) _scheduleDeferredDecode();

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
    if (_activePointers.isEmpty) _scheduleDeferredDecode();
    if (_snapKind != null) {
      setState(() => _active = null);
      _clearSnap();
      _stab = null;
      _resetInkPerf();
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
      _resetInkPerf();
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
    final sw = Stopwatch()..start();
    if (_snapKind != null) return;
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
      (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite,
    );
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      _resetInkPerf();
      return;
    }

    final data = _activePageData();
    if (data == null) {
      setState(() => _active = null);
      _resetInkPerf();
      return;
    }

    if (_tool == DrawTool.pen &&
        isScribble(_active!.points, viewScale: _viewScale)) {
      final bounds = scribbleBounds(_active!.points);
      final snapSw = Stopwatch()..start();
      final before = _snapshot();
      snapSw.stop();
      final lenBefore = data.strokes.length;
      final activeStroke = _active!.clone();
      Rect? dirty;
      data.strokes.removeWhere((s) {
        for (final p in s.points) {
          if (bounds.contains(Offset(p[0], p[1]))) {
            final b = strokeBounds(s);
            dirty = dirty == null ? b : dirty!.expandToInclude(b);
            return true;
          }
        }
        return false;
      });
      setState(() => _active = null);
      if (data.strokes.length != lenBefore) {
        final index = _pageTileIndex(_pageBlockIds[_activePageIndex!]);
        if (dirty != null) {
          index.invalidateRegion(dirty!.inflate(4), data.strokes);
        } else {
          index.rebuild(data.strokes);
        }
        _rebuildWorldStrokeCache(_pageBlockIds[_activePageIndex!]);
        _inkTick.value++;
        _commitSnapshot(before);
        HapticFeedback.lightImpact();
        _persistPage(_activePageIndex!);
      }
      sw.stop();
      _logInkPerf(
        'scribble-erase',
        activeStroke,
        pageIndex: _activePageIndex!,
        finishMs: sw.elapsedMilliseconds,
        snapshotMs: snapSw.elapsedMilliseconds,
      );
      return;
    }

    final addedStroke = _active!.clone();
    setState(() {
      data.strokes.add(_active!);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _appendToPage(_pageBlockIds[_activePageIndex!], data.strokes.last);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitStrokeAdd(_pageBlockIds[_activePageIndex!], data.strokes.last);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persistPage(_activePageIndex!);
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'stroke',
      addedStroke,
      pageIndex: _activePageIndex!,
      finishMs: sw.elapsedMilliseconds,
      appendMs: appendSw.elapsedMilliseconds,
      historyMs: historySw.elapsedMilliseconds,
      persistMs: persistSw.elapsedMilliseconds,
    );
  }

  void _finishFountainStroke() {
    final sw = Stopwatch()..start();
    if (_active == null || _activePageIndex == null) return;
    _active!.points.removeWhere(
      (p) => p.length < 4 || !p[0].isFinite || !p[1].isFinite,
    );
    if (_active!.points.length < 2) {
      setState(() => _active = null);
      _resetInkPerf();
      return;
    }

    final data = _activePageData();
    if (data == null) {
      setState(() => _active = null);
      _resetInkPerf();
      return;
    }

    final bakeSw = Stopwatch()..start();
    final baked = FountainPenEngine.finishStroke(
      _active!,
      viewScale: _viewScale,
    );
    bakeSw.stop();
    setState(() {
      data.strokes.add(baked);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _appendToPage(_pageBlockIds[_activePageIndex!], baked);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitStrokeAdd(_pageBlockIds[_activePageIndex!], baked);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persistPage(_activePageIndex!);
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'fountain',
      baked,
      pageIndex: _activePageIndex!,
      finishMs: sw.elapsedMilliseconds,
      appendMs: appendSw.elapsedMilliseconds,
      historyMs: historySw.elapsedMilliseconds + bakeSw.elapsedMilliseconds,
      persistMs: persistSw.elapsedMilliseconds,
    );
  }

  static const _eraserScreenRadius = 7.0;

  void _eraseNear(Offset local, int pageIndex) {
    final radius = _eraserScreenRadius / _viewScale;
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) return;
    bool changed = false;
    // Bounds of every touched stroke → only those tiles rebuild.
    Rect? dirty;
    void markDirty(DrawingStroke s) {
      final b = strokeBounds(s);
      dirty = dirty == null ? b : dirty!.expandToInclude(b);
    }

    final candidates = _strokesNearPage(blockId, local, radius + 64);
    if (candidates.isEmpty) return;

    if (_eraserMode == EraserMode.partial) {
      final out = <DrawingStroke>[];
      for (final s in data.strokes) {
        if (!candidates.contains(s)) {
          out.add(s);
          continue;
        }
        final pieces = splitStrokeByEraser(s, local, radius);
        if (pieces.length == 1 && identical(pieces.first, s)) {
          out.add(s);
        } else {
          markDirty(s);
          out.addAll(pieces);
          changed = true;
        }
      }
      if (changed) data.strokes = out;
    } else {
      final hits = <DrawingStroke>{};
      for (final s in candidates) {
        if (strokeHitByEraser(s, local, radius)) {
          markDirty(s);
          hits.add(s);
        }
      }
      if (hits.isNotEmpty) {
        data.strokes.removeWhere(hits.contains);
        changed = true;
      }
    }
    if (changed) {
      _gestureChanged = true;
      final index = _pageTileIndex(blockId);
      if (dirty != null) {
        index.invalidateRegion(dirty!.inflate(4), data.strokes);
      } else {
        index.rebuild(data.strokes);
      }
      _rebuildWorldStrokeCache(blockId);
      _inkTick.value++;
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
    final sw = Stopwatch()..start();
    final all = <DrawingStroke>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      if (_pageData[_pageBlockIds[i]] == null) continue;
      all.addAll(_worldStrokeCacheForPage(i));
    }
    sw.stop();
    if (sw.elapsedMilliseconds > 3) {
      final pts = _pointCount(all);
      CrashLogger.instance.note(
        'PERF flatten-strokes-cuaderno: ${all.length} trazos, $pts puntos, '
        '${_pageData.length} paginas, ${sw.elapsedMilliseconds}ms',
      );
    }
    return all;
  }

  List<CanvasImage> get _allVisibleImages {
    final sw = Stopwatch()..start();
    final all = <CanvasImage>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final im in data.images) {
        all.add(im.clone()..y += offset);
      }
    }
    sw.stop();
    if (sw.elapsedMilliseconds > 3) {
      CrashLogger.instance.note(
        'PERF flatten-images-cuaderno: ${all.length} imagenes, '
        '${_pageData.length} paginas, ${sw.elapsedMilliseconds}ms',
      );
    }
    return all;
  }

  List<CanvasTaskBlock> get _allVisibleTaskBlocks {
    final sw = Stopwatch()..start();
    final all = <CanvasTaskBlock>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final b in data.taskBlocks) {
        all.add(b.clone()..y += offset);
      }
    }
    sw.stop();
    if (sw.elapsedMilliseconds > 3) {
      CrashLogger.instance.note(
        'PERF flatten-tasks-cuaderno: ${all.length} bloques, '
        '${_pageData.length} paginas, ${sw.elapsedMilliseconds}ms',
      );
    }
    return all;
  }

  List<CanvasTextBlock> get _allVisibleTextBlocks {
    final sw = Stopwatch()..start();
    final all = <CanvasTextBlock>[];
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final data = _pageData[_pageBlockIds[i]];
      if (data == null) continue;
      final offset = _pageOffsetY(i);
      for (final b in data.textBlocks) {
        all.add(b.clone()..y += offset);
      }
    }
    sw.stop();
    if (sw.elapsedMilliseconds > 3) {
      CrashLogger.instance.note(
        'PERF flatten-text-cuaderno: ${all.length} bloques, '
        '${_pageData.length} paginas, ${sw.elapsedMilliseconds}ms',
      );
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
      // Pre-gesture selection box → affected-page set on drop.
      _gestureBoxBefore = _lassoCtrl.boundingBox;
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
        _captureLassoSelection();
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
      final affected = _affectedPages(
        _gestureBoxBefore,
        _lassoCtrl.boundingBox,
      );
      _gestureBoxBefore = null;
      _markSelectedWorldStrokesDirty(strokes);
      _syncLassoToPages(
        strokes,
        images,
        blocks,
        textBlocks,
        affected,
        lengthStable: true,
      );
      _commitGesture();
    } else {
      _gestureBoxBefore = null;
      _gestureBefore = null;
      setState(() => _toolbarVisible = !_toolbarVisible);
    }
  }

  /// All currently-decoded page indices — the safe full set when an edit's extent
  /// isn't known.
  Set<int> _allDecodedPages() => {
    for (int i = 0; i < _pageBlockIds.length; i++)
      if (_pageData[_pageBlockIds[i]] != null) i,
  };

  /// Page indices a selection edit can touch: the decoded pages whose vertical
  /// band overlaps the selection box BEFORE the edit or AFTER it (plus the
  /// nearest page to each box edge, covering a box that sits in a page gap).
  /// Only these pages get re-bucketed, cache-invalidated and DB-persisted.
  Set<int> _affectedPages(Rect? before, Rect? after) {
    if (before == null && after == null) return _allDecodedPages();
    final out = <int>{};
    void addBox(Rect? r) {
      if (r == null) return;
      for (int i = 0; i < _pageBlockIds.length; i++) {
        if (_pageData[_pageBlockIds[i]] == null) continue;
        final top = _pageOffsetY(i);
        final bottom = top + kNotebookPageHeight;
        if (r.bottom >= top && r.top <= bottom) out.add(i);
      }
      for (final y in [r.top, r.center.dy, r.bottom]) {
        final idx = _nearestPageIndex(y);
        if (idx >= 0 && _pageData[_pageBlockIds[idx]] != null) out.add(idx);
      }
    }

    addBox(before);
    addBox(after);
    return out;
  }

  Rect _strokeDirtyRect(DrawingStroke stroke) =>
      strokeBounds(stroke).inflate(stroke.strokeWidth + 4);

  Rect _joinRect(Rect? a, Rect b) => a == null ? b : a.expandToInclude(b);

  (int, int) _syncLengthStableLassoStrokes(
    List<DrawingStroke> worldStrokes,
    Set<int> affected,
  ) {
    final dirtyByPage = <int, Rect>{};
    final removalsByPage = <int, List<int>>{};
    final appendsByPage = <int, List<DrawingStroke>>{};
    var touched = 0;
    var points = 0;

    for (final worldIndex in _lassoCtrl.selectedIndices) {
      if (worldIndex < 0 || worldIndex >= worldStrokes.length) continue;
      final source = _worldStrokePageLocalIndex(worldIndex);
      if (source == null) continue;
      final sourcePage = source.$1;
      final sourceLocal = source.$2;
      if (sourcePage < 0 || sourcePage >= _pageBlockIds.length) continue;
      final sourceBlockId = _pageBlockIds[sourcePage];
      final sourceData = _pageData[sourceBlockId];
      if (sourceData == null ||
          sourceLocal < 0 ||
          sourceLocal >= sourceData.strokes.length) {
        continue;
      }

      final worldStroke = worldStrokes[worldIndex];
      if (worldStroke.points.isEmpty) continue;
      var sumY = 0.0;
      for (final pt in worldStroke.points) {
        sumY += pt[1];
      }
      final targetPage = _nearestPageIndex(sumY / worldStroke.points.length);
      if (targetPage < 0 || targetPage >= _pageBlockIds.length) continue;
      if (!affected.contains(sourcePage) && !affected.contains(targetPage)) {
        continue;
      }

      final oldLocal = sourceData.strokes[sourceLocal];
      final newLocal = _localStrokeFromWorld(targetPage, worldStroke);
      dirtyByPage[sourcePage] = _joinRect(
        dirtyByPage[sourcePage],
        _strokeDirtyRect(oldLocal),
      );
      dirtyByPage[targetPage] = _joinRect(
        dirtyByPage[targetPage],
        _strokeDirtyRect(newLocal),
      );

      if (sourcePage == targetPage) {
        sourceData.strokes[sourceLocal] = newLocal;
        final cache = _pageWorldStrokeCache[sourceBlockId];
        if (cache != null && sourceLocal < cache.length) {
          cache[sourceLocal] = _worldStrokeForPage(sourcePage, newLocal);
        } else {
          _rebuildWorldStrokeCache(sourceBlockId);
        }
      } else {
        (removalsByPage[sourcePage] ??= []).add(sourceLocal);
        (appendsByPage[targetPage] ??= []).add(newLocal);
      }
      touched++;
      points += worldStroke.points.length;
    }

    for (final entry in removalsByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      final cache = _pageWorldStrokeCache[blockId];
      final locals = entry.value..sort((a, b) => b.compareTo(a));
      for (final local in locals) {
        if (local < 0 || local >= data.strokes.length) continue;
        data.strokes.removeAt(local);
        if (cache != null && local < cache.length) cache.removeAt(local);
      }
    }

    for (final entry in appendsByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      if (!_pageWorldStrokeCache.containsKey(blockId)) {
        _rebuildWorldStrokeCache(blockId);
      }
      final cache = _pageWorldStrokeCache[blockId] ??= [];
      for (final stroke in entry.value) {
        data.strokes.add(stroke);
        cache.add(_worldStrokeForPage(pageIndex, stroke));
      }
    }

    for (final entry in dirtyByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      _pageTileIndex(blockId).invalidateRegion(entry.value, data.strokes);
      _persistPage(pageIndex);
    }

    return (touched, points);
  }

  (int, int) _syncDeletedLassoStrokes(Set<int> selectedBefore) {
    final dirtyByPage = <int, Rect>{};
    final removalsByPage = <int, List<int>>{};
    var touched = 0;
    var points = 0;

    for (final worldIndex in selectedBefore) {
      final source = _worldStrokePageLocalIndex(worldIndex);
      if (source == null) continue;
      final pageIndex = source.$1;
      final localIndex = source.$2;
      if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) continue;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null || localIndex < 0 || localIndex >= data.strokes.length) {
        continue;
      }
      final stroke = data.strokes[localIndex];
      dirtyByPage[pageIndex] = _joinRect(
        dirtyByPage[pageIndex],
        _strokeDirtyRect(stroke),
      );
      (removalsByPage[pageIndex] ??= []).add(localIndex);
      touched++;
      points += stroke.points.length;
    }

    for (final entry in removalsByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      final cache = _pageWorldStrokeCache[blockId];
      final locals = entry.value..sort((a, b) => b.compareTo(a));
      for (final local in locals) {
        if (local < 0 || local >= data.strokes.length) continue;
        data.strokes.removeAt(local);
        if (cache != null && local < cache.length) cache.removeAt(local);
      }
    }

    for (final entry in dirtyByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      _pageTileIndex(blockId).invalidateRegion(entry.value, data.strokes);
      _persistPage(pageIndex);
    }

    return (touched, points);
  }

  (int, int) _syncAppendedLassoStrokes(
    List<DrawingStroke> worldStrokes,
    int minNewIndex,
  ) {
    final dirtyByPage = <int, Rect>{};
    final appendedLocals = <(int, int)>[];
    var touched = 0;
    var points = 0;

    for (final worldIndex in (_lassoCtrl.selectedIndices.toList()..sort())) {
      if (worldIndex < minNewIndex || worldIndex >= worldStrokes.length) {
        continue;
      }
      final worldStroke = worldStrokes[worldIndex];
      if (worldStroke.points.isEmpty) continue;
      var sumY = 0.0;
      for (final pt in worldStroke.points) {
        sumY += pt[1];
      }
      final pageIndex = _nearestPageIndex(sumY / worldStroke.points.length);
      if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) continue;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      if (!_pageWorldStrokeCache.containsKey(blockId)) {
        _rebuildWorldStrokeCache(blockId);
      }
      final localIndex = data.strokes.length;
      final localStroke = _localStrokeFromWorld(pageIndex, worldStroke);
      data.strokes.add(localStroke);
      (_pageWorldStrokeCache[blockId] ??= []).add(
        _worldStrokeForPage(pageIndex, localStroke),
      );
      appendedLocals.add((pageIndex, localIndex));
      dirtyByPage[pageIndex] = _joinRect(
        dirtyByPage[pageIndex],
        _strokeDirtyRect(localStroke),
      );
      touched++;
      points += worldStroke.points.length;
    }

    for (final entry in dirtyByPage.entries) {
      final pageIndex = entry.key;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) continue;
      _pageTileIndex(blockId).invalidateRegion(entry.value, data.strokes);
      _persistPage(pageIndex);
    }

    if (appendedLocals.isNotEmpty) {
      _lassoCtrl.selectedIndices = {
        for (final entry in appendedLocals)
          _worldStrokeIndexFromPageLocal(entry.$1, entry.$2),
      };
    }

    return (touched, points);
  }

  bool _syncLengthStableLassoObjects(
    List<CanvasImage> worldImages,
    List<CanvasTaskBlock> worldBlocks,
    List<CanvasTextBlock> worldTextBlocks,
    Set<int> affected, {
    bool force = false,
  }) {
    if (!force &&
        _lassoCtrl.selectedImageIndices.isEmpty &&
        _lassoCtrl.selectedBlockIndices.isEmpty &&
        _lassoCtrl.selectedTextBlockIndices.isEmpty) {
      return false;
    }

    final imagesByPage = <int, List<CanvasImage>>{};
    final blocksByPage = <int, List<CanvasTaskBlock>>{};
    final textBlocksByPage = <int, List<CanvasTextBlock>>{};
    for (final i in affected) {
      final bid = _pageBlockIds[i];
      imagesByPage[bid] = [];
      blocksByPage[bid] = [];
      textBlocksByPage[bid] = [];
    }
    for (final im in worldImages) {
      final idx = _nearestPageIndex(im.y + im.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      imagesByPage[_pageBlockIds[idx]]!.add(im.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      blocksByPage[_pageBlockIds[idx]]!.add(b.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldTextBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      textBlocksByPage[_pageBlockIds[idx]]!.add(
        b.clone()..y -= _pageOffsetY(idx),
      );
    }
    for (final i in affected) {
      final bid = _pageBlockIds[i];
      final data = _pageData[bid];
      if (data == null) continue;
      data.images = imagesByPage[bid]!;
      data.taskBlocks = blocksByPage[bid]!;
      data.textBlocks = textBlocksByPage[bid]!;
      _persistPage(i);
    }
    return true;
  }

  void _finishIncrementalLassoSync(
    Set<int> affected,
    int totalWorldStrokes,
    (int, int) strokeStats,
    bool objectsChanged,
    Stopwatch sw,
  ) {
    final changed = strokeStats.$1 > 0 || objectsChanged;
    if (changed) {
      _inkTick.value++;
      setState(() {});
    }
    sw.stop();
    CrashLogger.instance.note(
      'PERF lasso-sync-cuaderno: ${affected.length} paginas, '
      '${strokeStats.$1}/$totalWorldStrokes world trazos, '
      '${strokeStats.$2} puntos, ${sw.elapsedMilliseconds}ms',
    );
  }

  void _syncLassoToPages(
    List<DrawingStroke> worldStrokes,
    List<CanvasImage> worldImages,
    List<CanvasTaskBlock> worldBlocks,
    List<CanvasTextBlock> worldTextBlocks,
    Set<int> affected, {
    bool lengthStable = false,
  }) {
    final sw = Stopwatch()..start();
    if (affected.isEmpty) {
      setState(() {});
      CrashLogger.instance.note('PERF lasso-sync-cuaderno: 0 paginas, 0ms');
      return;
    }
    if (lengthStable) {
      final strokeStats = _syncLengthStableLassoStrokes(worldStrokes, affected);
      final objectsChanged = _syncLengthStableLassoObjects(
        worldImages,
        worldBlocks,
        worldTextBlocks,
        affected,
      );
      final changed = strokeStats.$1 > 0 || objectsChanged;
      if (changed) {
        _inkTick.value++;
        setState(() {});
      }
      sw.stop();
      CrashLogger.instance.note(
        'PERF lasso-sync-cuaderno: ${affected.length} paginas, '
        '${strokeStats.$1}/${worldStrokes.length} world trazos, '
        '${strokeStats.$2} puntos, ${sw.elapsedMilliseconds}ms',
      );
      return;
    }
    final pages = <int, List<DrawingStroke>>{};
    final imagesByPage = <int, List<CanvasImage>>{};
    final blocksByPage = <int, List<CanvasTaskBlock>>{};
    final textBlocksByPage = <int, List<CanvasTextBlock>>{};
    for (final i in affected) {
      final bid = _pageBlockIds[i];
      pages[bid] = [];
      imagesByPage[bid] = [];
      blocksByPage[bid] = [];
      textBlocksByPage[bid] = [];
    }
    final strokeSource = <DrawingStroke>[];
    strokeSource.addAll(worldStrokes);
    for (final s in strokeSource) {
      if (s.points.isEmpty) continue;
      double sumY = 0;
      for (final pt in s.points) {
        sumY += pt[1];
      }
      final idx = _nearestPageIndex(sumY / s.points.length);
      if (idx < 0 || !affected.contains(idx)) continue;
      final c = s.clone();
      final pageTop = _pageOffsetY(idx);
      for (final pt in c.points) {
        pt[1] -= pageTop;
      }
      pages[_pageBlockIds[idx]]!.add(c);
    }
    for (final im in worldImages) {
      final idx = _nearestPageIndex(im.y + im.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      imagesByPage[_pageBlockIds[idx]]!.add(im.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      blocksByPage[_pageBlockIds[idx]]!.add(b.clone()..y -= _pageOffsetY(idx));
    }
    for (final b in worldTextBlocks) {
      final idx = _nearestPageIndex(b.y + b.h / 2);
      if (idx < 0 || !affected.contains(idx)) continue;
      textBlocksByPage[_pageBlockIds[idx]]!.add(
        b.clone()..y -= _pageOffsetY(idx),
      );
    }
    for (final i in affected) {
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
      _pageTileIndex(bid).rebuild(_pageData[bid]!.strokes);
      _rebuildWorldStrokeCache(bid);
      _persistPage(i);
    }
    _inkTick.value++;
    setState(() {});
    sw.stop();
    CrashLogger.instance.note(
      'PERF lasso-sync-cuaderno: ${affected.length} paginas, '
      '${strokeSource.length}/${worldStrokes.length} world trazos, '
      '${_pointCount(strokeSource)} puntos, '
      '${sw.elapsedMilliseconds}ms',
    );
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
    op, {
    _LassoSyncMode syncMode = _LassoSyncMode.full,
  }) {
    final sw = Stopwatch()..start();
    final before = _snapshot();
    final snapMs = sw.elapsedMilliseconds;
    final strokes = _allVisibleStrokes;
    final strokesMs = sw.elapsedMilliseconds - snapMs;
    final images = _allVisibleImages;
    final blocks = _allVisibleTaskBlocks;
    final textBlocks = _allVisibleTextBlocks;
    final boxBefore = _lassoCtrl.boundingBox;
    final selectedBefore = Set<int>.from(_lassoCtrl.selectedIndices);
    final objectSelectionBefore =
        _lassoCtrl.selectedImageIndices.isNotEmpty ||
        _lassoCtrl.selectedBlockIndices.isNotEmpty ||
        _lassoCtrl.selectedTextBlockIndices.isNotEmpty;
    final strokeCountBefore = strokes.length;
    op(strokes, images, blocks, textBlocks);
    final affected = _affectedPages(boxBefore, _lassoCtrl.boundingBox);
    if (syncMode == _LassoSyncMode.lengthStable) {
      _markSelectedWorldStrokesDirty(strokes);
      _syncLassoToPages(
        strokes,
        images,
        blocks,
        textBlocks,
        affected,
        lengthStable: true,
      );
    } else if (syncMode == _LassoSyncMode.deleteSelected) {
      final syncSw = Stopwatch()..start();
      final strokeStats = _syncDeletedLassoStrokes(selectedBefore);
      final objectsChanged = _syncLengthStableLassoObjects(
        images,
        blocks,
        textBlocks,
        affected,
        force: objectSelectionBefore,
      );
      _finishIncrementalLassoSync(
        affected,
        strokes.length,
        strokeStats,
        objectsChanged,
        syncSw,
      );
    } else if (syncMode == _LassoSyncMode.appendSelected) {
      final syncSw = Stopwatch()..start();
      final strokeStats = _syncAppendedLassoStrokes(strokes, strokeCountBefore);
      final objectsChanged = _syncLengthStableLassoObjects(
        images,
        blocks,
        textBlocks,
        affected,
        force:
            objectSelectionBefore || _lassoCtrl.selectedImageIndices.isNotEmpty,
      );
      _finishIncrementalLassoSync(
        affected,
        strokes.length,
        strokeStats,
        objectsChanged,
        syncSw,
      );
    } else {
      _syncLassoToPages(strokes, images, blocks, textBlocks, affected);
    }
    _commitSnapshot(before);
    sw.stop();
    CrashLogger.instance.note(
      'PERF lasso-mut-cuaderno: snapshot ${snapMs}ms, '
      'flattenStrokes ${strokesMs}ms, total ${sw.elapsedMilliseconds}ms',
    );
  }

  void _lassoDelete() {
    _lassoMutate(
      (s, im, b, tx) => _lassoCtrl.deleteSelected(s, im, b, tx),
      syncMode: _LassoSyncMode.deleteSelected,
    );
    HapticFeedback.lightImpact();
  }

  void _lassoDuplicate() {
    _lassoMutate(
      (s, im, b, tx) => _lassoCtrl.duplicateSelected(s, im),
      syncMode: _LassoSyncMode.appendSelected,
    );
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
    _commitSnapshot(before);
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
    _commitSnapshot(before);
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
    _commitSnapshot(before);
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
        _floatingToolbarsPopupOpen = false;
        _imagePanelOpen = false;
        _shapePopupOpen = false;
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _bgPopupOpen = false;
      }
    });
  }

  void _toggleFloatingToolbarsPopup() {
    setState(() {
      _floatingToolbarsPopupOpen = !_floatingToolbarsPopupOpen;
      if (_floatingToolbarsPopupOpen) {
        _morePopupOpen = false;
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
    _appendWorldStrokeCache(_pageBlockIds[pageIdx], stroke);
    // Flat index in world-space _allVisibleStrokes (new stroke is last in its
    // page; pages concatenate in order).
    int flat = 0;
    for (int i = 0; i < pageIdx; i++) {
      flat += _pageData[_pageBlockIds[i]]?.strokes.length ?? 0;
    }
    flat += data.strokes.length - 1;
    _lassoCtrl.hitScale = _viewScale;
    _lassoCtrl.selectRange(_allVisibleStrokes, flat, flat + 1);
    _commitSnapshot(before);
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
            onPersist: () async {
              _persistPage(pageIndex);
            },
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
          overlay = _liveGestureTransform(overlay, b.x, offset + b.y);
        }
        out.add(Positioned(left: b.x, top: offset + b.y, child: overlay));
      }
    }
    return out;
  }

  /// Wraps a selected block overlay so it follows the live lasso gesture WITHOUT
  /// a full-tree rebuild: only this Transform reacts to _lassoGestureTick (the
  /// block content rides through as `child`, built once). Critical for many-page
  /// notebooks — the old per-frame setState rebuilt every page's overlays.
  Widget _liveGestureTransform(Widget child, double bx, double by) {
    final off = Offset(bx, by);
    return ValueListenableBuilder<int>(
      valueListenable: _lassoGestureTick,
      child: child,
      builder: (_, _, child) {
        final tm =
            Matrix4.translationValues(-off.dx, -off.dy, 0) *
            _lassoCtrl.liveGestureMatrix() *
            Matrix4.translationValues(off.dx, off.dy, 0);
        return Transform(transform: tm, child: child);
      },
    );
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
            onPersist: () async {
              _persistPage(pageIndex);
            },
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
          overlay = _liveGestureTransform(overlay, b.x, offset + b.y);
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
  ///
  /// [includeShapes]: las figuras imantadas (p.ej. la barra de fracción dibujada
  /// como línea recta con snap) deben entrar al MATH OCR — sin ellas el modelo
  /// ve los números flotando. El OCR de texto (ML Kit) sí las excluye.
  List<List<Offset>> _selectedWritingStrokes({bool includeShapes = false}) {
    final all = _allVisibleStrokes;
    final strokes = <List<Offset>>[];
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= all.length) continue;
      final s = all[i];
      if (s.isHighlighter) continue;
      if (s.isShape && !includeShapes) continue;
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
    final strokes = _selectedWritingStrokes(includeShapes: true);
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
    _commitSnapshot(before);
    _persistPage(pageIdx);
    _imgCache?.get(newName);
  }

  // ─── Undo / redo (snapshot history, all pages) ──────────────────────────

  _NotebookSnapshot _snapshot({Set<int>? blockIds}) {
    final sw = Stopwatch()..start();
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
    final entries =
        blockIds == null
            ? _pageData.entries
            : _pageData.entries.where((entry) => blockIds.contains(entry.key));
    for (final entry in entries) {
      m[entry.key] = (
        List<DrawingStroke>.of(entry.value.strokes),
        entry.value.images.map((im) => im.clone()).toList(),
        entry.value.taskBlocks.map((b) => b.clone()).toList(),
        entry.value.textBlocks.map((b) => b.clone()).toList(),
      );
    }
    sw.stop();
    if (sw.elapsedMilliseconds > 3) {
      final strokes = _pageData.values.fold<int>(
        0,
        (total, data) => total + data.strokes.length,
      );
      final pts = _pageData.values.fold<int>(
        0,
        (total, data) => total + _pointCount(data.strokes),
      );
      CrashLogger.instance.note(
        'PERF snapshot-cuaderno: ${_pageData.length} paginas, '
        '$strokes trazos, $pts puntos, ${sw.elapsedMilliseconds}ms',
      );
    }
    return m;
  }

  bool _sameStrokeRefs(List<DrawingStroke> a, List<DrawingStroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  bool _sameImages(List<CanvasImage> a, List<CanvasImage> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.filename != y.filename ||
          x.x != y.x ||
          x.y != y.y ||
          x.w != y.w ||
          x.h != y.h ||
          x.rotation != y.rotation) {
        return false;
      }
    }
    return true;
  }

  bool _sameTaskBlocks(List<CanvasTaskBlock> a, List<CanvasTaskBlock> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.x != y.x ||
          x.y != y.y ||
          x.w != y.w ||
          x.h != y.h ||
          x.rotation != y.rotation ||
          x.scale != y.scale ||
          x.taskIds.length != y.taskIds.length) {
        return false;
      }
      for (int j = 0; j < x.taskIds.length; j++) {
        if (x.taskIds[j] != y.taskIds[j]) return false;
      }
    }
    return true;
  }

  bool _sameTextBlocks(List<CanvasTextBlock> a, List<CanvasTextBlock> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.x != y.x ||
          x.y != y.y ||
          x.w != y.w ||
          x.h != y.h ||
          x.rotation != y.rotation ||
          x.scale != y.scale ||
          x.markdown != y.markdown ||
          x.isSquare != y.isSquare) {
        return false;
      }
    }
    return true;
  }

  Set<int> _changedSnapshotBlocks(_NotebookSnapshot snap) {
    final out = <int>{};
    for (final entry in snap.entries) {
      final data = _pageData[entry.key];
      if (data == null ||
          !_sameStrokeRefs(data.strokes, entry.value.$1) ||
          !_sameImages(data.images, entry.value.$2) ||
          !_sameTaskBlocks(data.taskBlocks, entry.value.$3) ||
          !_sameTextBlocks(data.textBlocks, entry.value.$4)) {
        out.add(entry.key);
      }
    }
    return out;
  }

  void _markRestoreStrokeDirty(int blockId, List<DrawingStroke> target) {
    final data = _pageData[blockId];
    if (data == null) return;
    final currentById = <int, DrawingStroke>{
      for (final s in data.strokes)
        if (s.dbId != null) s.dbId!: s,
    };
    final persisted = _persistedStrokeIds(blockId);
    final dirty = _dirtyStrokeIds(blockId);
    for (final stroke in target) {
      final id = stroke.dbId;
      if (id == null || !persisted.contains(id)) continue;
      final current = currentById[id];
      if (current != null && !identical(current, stroke)) dirty.add(id);
    }
  }

  void _pushHistory(_NotebookHistoryEntry entry) {
    _undoStack.add(entry);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _commitSnapshot(_NotebookSnapshot before) {
    _pushHistory(_NotebookSnapshotEntry(before));
  }

  void _commitStrokeAdd(int blockId, DrawingStroke stroke) {
    _pushHistory(_NotebookStrokeAddEntry(blockId, stroke.clone()));
  }

  void _commitGesture() {
    if (_gestureBefore != null) {
      _commitSnapshot(_gestureBefore!);
      _gestureBefore = null;
    }
  }

  void _commitEraseGesture() {
    if (_gestureBefore != null && _gestureChanged) {
      _commitSnapshot(_gestureBefore!);
    }
    _gestureBefore = null;
    _gestureChanged = false;
  }

  void _restore(_NotebookSnapshot snap, {Set<int>? blockIds}) {
    for (final entry in snap.entries) {
      if (blockIds != null && !blockIds.contains(entry.key)) continue;
      final data = _pageData[entry.key];
      if (data != null) {
        _markRestoreStrokeDirty(entry.key, entry.value.$1);
        data.strokes = entry.value.$1;
        data.images = entry.value.$2;
        data.taskBlocks = entry.value.$3;
        data.textBlocks = entry.value.$4;
      }
      _pageTileIndex(
        entry.key,
      ).rebuild(_pageData[entry.key]?.strokes ?? const []);
      _rebuildWorldStrokeCache(entry.key);
    }
    _inkTick.value++;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    final changed =
        entry is _NotebookSnapshotEntry
            ? _changedSnapshotBlocks(entry.snapshot)
            : <int>{};
    setState(() {
      if (entry is _NotebookSnapshotEntry) {
        if (changed.isNotEmpty) {
          _redoStack.add(_NotebookSnapshotEntry(_snapshot(blockIds: changed)));
          _restore(entry.snapshot, blockIds: changed);
        }
      } else if (entry is _NotebookStrokeAddEntry) {
        final data = _pageData[entry.blockId];
        if (data != null && data.strokes.isNotEmpty) {
          final removed = data.strokes.removeLast();
          _redoStack.add(
            _NotebookStrokeAddEntry(entry.blockId, removed.clone()),
          );
          _pageTileIndex(entry.blockId).invalidateRegion(
            strokeBounds(removed).inflate(removed.strokeWidth + 4),
            data.strokes,
          );
          _rebuildWorldStrokeCache(entry.blockId);
          _inkTick.value++;
        }
      }
      _lassoCtrl.deselect();
      _active = null;
    });
    if (entry is _NotebookSnapshotEntry) {
      for (final blockId in changed) {
        final pageIndex = _pageBlockIds.indexOf(blockId);
        if (pageIndex >= 0) _persistPage(pageIndex);
      }
    } else if (entry is _NotebookStrokeAddEntry) {
      final pageIndex = _pageBlockIds.indexOf(entry.blockId);
      if (pageIndex >= 0) _persistPage(pageIndex);
    }
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    final changed =
        entry is _NotebookSnapshotEntry
            ? _changedSnapshotBlocks(entry.snapshot)
            : <int>{};
    setState(() {
      if (entry is _NotebookSnapshotEntry) {
        if (changed.isNotEmpty) {
          _undoStack.add(_NotebookSnapshotEntry(_snapshot(blockIds: changed)));
          _restore(entry.snapshot, blockIds: changed);
        }
      } else if (entry is _NotebookStrokeAddEntry) {
        final data = _pageData[entry.blockId];
        if (data != null) {
          data.strokes.add(entry.stroke.clone());
          _undoStack.add(
            _NotebookStrokeAddEntry(entry.blockId, entry.stroke.clone()),
          );
          _appendToPage(entry.blockId, data.strokes.last);
        }
      }
      _lassoCtrl.deselect();
      _active = null;
    });
    if (entry is _NotebookSnapshotEntry) {
      for (final blockId in changed) {
        final pageIndex = _pageBlockIds.indexOf(blockId);
        if (pageIndex >= 0) _persistPage(pageIndex);
      }
    } else if (entry is _NotebookStrokeAddEntry) {
      final pageIndex = _pageBlockIds.indexOf(entry.blockId);
      if (pageIndex >= 0) _persistPage(pageIndex);
    }
  }

  // ─── Current page ──────────────────────────────────────────────────────

  Color get _accent => widget.note.color ?? widget.folder.color;

  Widget _buildNotebookBackgroundLayer(Size viewport, Size canvasSize) {
    return AnimatedBuilder(
      animation: Listenable.merge([_viewCtrl, _lassoPhaseTick]),
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

  // Zoomed-out: too many tiles to be worth per-tile boundaries → one painter.
  static const int _kMaxLiveTiles = 48;

  Widget _buildNotebookStrokeLayer(Size viewport, Size canvasSize) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          // Pan/zoom, lasso phase, and any page-ink change (_inkTick).
          animation: Listenable.merge([_viewCtrl, _lassoPhaseTick, _inkTick]),
          builder: (_, _) {
            final visible = _visibleRectFor(viewport).inflate(kStrokeTileSize);
            final hiddenByPage = _hiddenStrokes();
            // Decimate stroke detail when zoomed out (dense tiles cheap to raster).
            final lod = lodForScale(_viewScale);
            // Show the cached per-page overview images instead of tiles when
            // zoomed out (or pinned through a zoom gesture); never during a lasso
            // gesture (the image can't hide the live selection).
            final inLasso = _lassoCtrl.phase == LassoPhase.moving ||
                _lassoCtrl.phase == LassoPhase.resizing ||
                _lassoCtrl.phase == LassoPhase.rotating;
            _overviewActive = !inLasso &&
                _overviewByPage.isNotEmpty &&
                (_viewScale < _overviewThreshold ||
                    (_viewGestureActive && _overviewStickyThisGesture));

            final tiles = <Widget>[];
            for (int i = 0; i < _pageBlockIds.length; i++) {
              final bid = _pageBlockIds[i];
              final data = _pageData[bid];
              final index = _pageTiles[bid];
              if (data == null || index == null || index.isEmpty) continue;
              final pageTop = _pageOffsetY(i);
              final pageWorld = Rect.fromLTWH(
                0,
                pageTop,
                kNotebookPageWidth,
                kNotebookPageHeight,
              );
              if (!pageWorld.overlaps(visible)) continue;
              final localRect = Rect.fromLTRB(
                visible.left,
                visible.top - pageTop,
                visible.right,
                visible.bottom - pageTop,
              ).intersect(
                const Rect.fromLTWH(
                  0,
                  0,
                  kNotebookPageWidth,
                  kNotebookPageHeight,
                ),
              );
              if (localRect.isEmpty) continue;

              Set<DrawingStroke>? hidden;
              final hi = hiddenByPage[i];
              if (hi != null && hi.isNotEmpty) {
                hidden = Set<DrawingStroke>.identity();
                for (final j in hi) {
                  if (j < data.strokes.length) hidden.add(data.strokes[j]);
                }
              }

              final pageImg = _overviewActive ? _overviewByPage[bid] : null;
              if (pageImg != null) {
                // Cached ink image for this page (blit instead of re-drawing).
                tiles.add(
                  Positioned.fromRect(
                    key: ValueKey('ov:$bid'),
                    rect: pageWorld,
                    child: RawImage(
                      image: pageImg,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                );
                // Strokes drawn since the last bake → live on top, full detail.
                final baked = (_overviewBakedCountByPage[bid] ?? 0)
                    .clamp(0, data.strokes.length);
                if (baked < data.strokes.length) {
                  tiles.add(
                    Positioned.fromRect(
                      key: ValueKey('ovd:$bid'),
                      rect: pageWorld,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: StrokeTilePainter(
                            strokes: data.strokes.sublist(baked),
                            tileOrigin: Offset.zero,
                            version: data.strokes.length,
                            clipBounds: const Rect.fromLTWH(
                              0,
                              0,
                              kNotebookPageWidth,
                              kNotebookPageHeight,
                            ),
                          ),
                          size: const Size(
                            kNotebookPageWidth,
                            kNotebookPageHeight,
                          ),
                        ),
                      ),
                    ),
                  );
                }
              } else {
                tiles.addAll(
                  strokeTileWidgets(
                    index: index,
                    localRect: localRect,
                    worldOffset: Offset(0, pageTop),
                    hiddenStrokes: hidden,
                    keyPrefix: bid,
                    // Clip ink to the page so strokes can't bleed into the lateral
                    // margin or the inter-page gap (tiles span past page edges).
                    clipBounds: const Rect.fromLTWH(
                      0,
                      0,
                      kNotebookPageWidth,
                      kNotebookPageHeight,
                    ),
                    lod: lod,
                  ),
                );
              }
            }

            if (!_overviewActive && tiles.length > _kMaxLiveTiles) {
              // Zoomed-out fallback: one direct painter over all pages.
              return RepaintBoundary(
                child: CustomPaint(
                  painter: _NotebookCanvasPainter(
                    pageBlockIds: _pageBlockIds,
                    pageData: _pageData,
                    visibleRect: visible,
                    paintVersion: _paintVersion + _inkTick.value,
                    accentColor: _accent,
                    hiddenStrokes: hiddenByPage,
                    imageCache: _imgCache,
                    drawBackground: false,
                    lod: lod,
                  ),
                  size: canvasSize,
                ),
              );
            }

            return Stack(clipBehavior: Clip.none, children: tiles);
          },
        ),
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
      animation: Listenable.merge([
        _viewCtrl,
        _lassoAnimCtrl,
        _lassoGestureTick,
      ]),
      builder: (_, _) {
        final visibleRect = _visibleRectFor(viewport);
        // Own RepaintBoundary: the marching-ants + gesture ghost repaint every
        // frame; without isolation that re-composites every page each tick.
        return RepaintBoundary(
          child: CustomPaint(
            painter: LassoPainter(
              ctrl: _lassoCtrl,
              animValue: _lassoAnimCtrl.value,
              strokes: strokes,
              images: images,
              imageCache: _imgCache,
              visibleRect: visibleRect,
              liftedInk: _lassoCtrl.liftedInk,
            ),
            size: canvasSize,
          ),
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

  Future<void> _captureLassoSelection() async {
    final bb = _lassoCtrl.boundingBox;
    if (bb == null || bb == Rect.zero) return;

    final selectedIndices = Set<int>.from(_lassoCtrl.selectedIndices);
    final selectedImageIndices = Set<int>.from(_lassoCtrl.selectedImageIndices);

    if (selectedIndices.isEmpty && selectedImageIndices.isEmpty) return;

    final strokes = _allVisibleStrokes;
    final images = _allVisibleImages;
    final imageCache = _imgCache;
    final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final double captureScale = _viewScale * pixelRatio;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.scale(captureScale);
      canvas.translate(-bb.left, -bb.top);

      for (final i in selectedImageIndices) {
        if (i < images.length) {
          final im = images[i];
          final img = imageCache?.get(im.filename);
          drawCanvasImage(canvas, img, im);
        }
      }

      for (final i in selectedIndices) {
        if (i < strokes.length) {
          drawStroke(canvas, strokes[i]);
        }
      }

      final picture = recorder.endRecording();
      final width = (bb.width * captureScale).ceil();
      final height = (bb.height * captureScale).ceil();
      final img = await picture.toImage(
        width > 0 ? width : 1,
        height > 0 ? height : 1,
      );
      picture.dispose();

      if (mounted &&
          _lassoCtrl.phase == LassoPhase.moving &&
          _lassoCtrl.boundingBox == bb) {
        _lassoCtrl.liftedInk = img;
        _lassoCtrl.liftedRect = bb;
        _lassoGestureTick.value++;
      } else {
        img.dispose();
      }
    } catch (_) {}
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
        onPin: () {
          _pinSelection();
        },
        onCrop: _singleImageSelected ? _cropSelectedImage : null,
        onRecognizeText: _selectionHasWriting ? _recognizeSelection : null,
        onSendToYuli: _selectionHasWriting ? _sendSelectionToYuli : null,
        // OCR de matemáticas 100% local (ONNX): disponible siempre que haya trazos.
        onSendMathToYuli:
            _selectionHasWriting ? _sendMathSelectionToYuli : null,
        palette: _palette,
        onColorChange:
            (c) => _lassoMutate(
              (s, im, b, _) => _lassoCtrl.changeColor(s, c.toARGB32()),
              syncMode: _LassoSyncMode.lengthStable,
            ),
        onWidthChange:
            (w) => _lassoMutate(
              (s, im, b, _) => _lassoCtrl.changeWidth(s, w),
              syncMode: _LassoSyncMode.lengthStable,
            ),
        onFlipH:
            () => _lassoMutate(
              (s, im, b, _) => _lassoCtrl.flipHorizontal(s),
              syncMode: _LassoSyncMode.lengthStable,
            ),
        onFlipV:
            () => _lassoMutate(
              (s, im, b, _) => _lassoCtrl.flipVertical(s),
              syncMode: _LassoSyncMode.lengthStable,
            ),
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
          _lassoMutate(
            (s, im, b, _) => _lassoCtrl.cutSelected(s, im, b),
            syncMode: _LassoSyncMode.deleteSelected,
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
            (s, im, b, _) => _lassoCtrl.pasteAt(_showPasteAt!, s, im),
            syncMode: _LassoSyncMode.appendSelected,
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
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
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
                      subtitle:
                          (widget.note.title?.trim().isNotEmpty == true)
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
                                final textBlockOverlays =
                                    _buildTextBlockOverlays();
                                final taskBlockOverlays =
                                    _buildTaskBlockOverlays();
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
                                          gestures: <
                                            Type,
                                            GestureRecognizerFactory
                                          >{
                                            TapGestureRecognizer:
                                                GestureRecognizerFactoryWithHandlers<
                                                  TapGestureRecognizer
                                                >(
                                                  () => TapGestureRecognizer(),
                                                  (i) =>
                                                      i.onTapUp = _onLassoTap,
                                                ),
                                            EagerGestureRecognizer:
                                                GestureRecognizerFactoryWithHandlers<
                                                  EagerGestureRecognizer
                                                >(
                                                  () => EagerGestureRecognizer(
                                                    supportedDevices: const {
                                                      PointerDeviceKind.stylus,
                                                      PointerDeviceKind
                                                          .invertedStylus,
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
                                              transformationController:
                                                  _viewCtrl,
                                              minScale: 0.3,
                                              maxScale: 4.0,
                                              onInteractionStart: (_) {
                                                // Pin the overview for the whole
                                                // gesture if it's showing, so
                                                // zooming in doesn't swap to tiles
                                                // mid-pinch.
                                                _viewGestureActive = true;
                                                _overviewStickyThisGesture =
                                                    _overviewActive;
                                              },
                                              onInteractionEnd: (_) {
                                                _viewGestureActive = false;
                                                if (mounted) setState(() {});
                                                if (_eyedropperMode &&
                                                    _eyedropCaptureMatrix !=
                                                        null &&
                                                    _viewCtrl.value !=
                                                        _eyedropCaptureMatrix) {
                                                  _captureEyedropSnapshot(
                                                    resetPos: false,
                                                  );
                                                }
                                                _scheduleDeferredDecode();
                                              },
                                              boundaryMargin:
                                                  EdgeInsets.symmetric(
                                                    horizontal: c.maxWidth,
                                                    vertical:
                                                        _totalCanvasHeight *
                                                        0.3,
                                                  ),
                                              // Text mode: 1-finger drag moves a box (its
                                              // GestureDetector), so disable pan; 2-finger
                                              // still navigates.
                                              panEnabled:
                                                  _eyedropperMode
                                                      ? _activePointers
                                                              .length >=
                                                          2
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
                                                      ? _activePointers
                                                              .length >=
                                                          2
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
                                                          animation:
                                                              _activeTick,
                                                          builder:
                                                              (
                                                                _,
                                                                _,
                                                              ) => CustomPaint(
                                                                painter: _ActiveStrokePainter(
                                                                  active:
                                                                      _active,
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
                                                                  viewScale:
                                                                      _viewScale,
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
                                          builder:
                                              (_, _) => FloatingPalettesLayer(
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
                                                onEyedropper:
                                                    () => _enterEyedropper(
                                                      onPick:
                                                          (c) => _palettes
                                                              ?.addColor(c),
                                                    ),
                                              ),
                                        ),
                                      ),
                                    // Pinned snapshots (PiN) — viewport-pinned,
                                    // sibling of the canvas Listener so they don't
                                    // leak pointers and stay fixed across pages.
                                    if (_pins.isNotEmpty)
                                      Positioned.fill(
                                        child: PinnedSnapshotsLayer(
                                          pins: _pins,
                                          onMove: _movePin,
                                          onResize: _resizePin,
                                          onClose: _closePin,
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
                                        animation: Listenable.merge([
                                          _viewCtrl,
                                          _lassoPhaseTick,
                                        ]),
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
                                                      radius:
                                                          _eraserScreenRadius,
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
                key: const ValueKey('rp-floating-toolbars'),
                open: _floatingToolbarsPopupOpen,
                onDismiss:
                    () => setState(() => _floatingToolbarsPopupOpen = false),
                child: _buildFloatingToolbarsPopup(),
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
                  onMoreColors:
                      () => setState(() {
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
                  onClose:
                      () => setState(() {
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
                icon: YuLiIcons.squareDashedMousePointer,
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
        final out =
            single
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
        final out =
            single
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
            icon: YuLiIcons.lineSquiggle,
            active: _floatingToolbarsPopupOpen,
            label: 'TOOLBARS FLOTANTES',
            onTap: _toggleFloatingToolbarsPopup,
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

  Widget _buildFloatingToolbarsPopup() {
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
              child: const Icon(YuLiIcons.chevronDown, color: yInk, size: 18),
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
  /// Strokes are drawn directly + culled — used for the background layer and the
  /// zoomed-out fallback; the normal stroke layer is the tiled [strokeTileWidgets].
  final bool drawBackground;
  final bool drawStrokes;
  final int lod;

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
    this.lod = 0,
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
          canvas.save();
          canvas.clipRect(pageVisible);
          for (int si = 0; si < data.strokes.length; si++) {
            if (skip != null && skip.contains(si)) continue;
            if (!strokeOverlapsRect(data.strokes[si], pageVisible)) continue;
            drawStroke(canvas, data.strokes[si], lod: lod);
          }
          canvas.restore();
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
      old.lod != lod ||
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
  final double viewScale;

  _ActiveStrokePainter({
    required this.active,
    required this.tick,
    required this.pageTop,
    this.viewScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (active == null) return;
    canvas.save();
    canvas.translate(0, pageTop);
    drawActiveStroke(canvas, active!, viewScale: viewScale);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter old) =>
      old.active != active ||
      old.tick != tick ||
      old.pageTop != pageTop ||
      old.viewScale != viewScale;
}
