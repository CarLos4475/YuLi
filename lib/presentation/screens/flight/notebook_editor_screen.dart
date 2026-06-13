import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart' show SchedulerBinding, Ticker;
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
import '../../../domain/repositories/drawing_stroke_repository.dart';
import '../../../domain/repositories/note_block_repository.dart';
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

class _ViewportRasterTile {
  final String key;
  final Rect worldRect;
  final int bucket;
  final int version;
  final ui.Image image;

  const _ViewportRasterTile({
    required this.key,
    required this.worldRect,
    required this.bucket,
    required this.version,
    required this.image,
  });
}

/// Composites the high-zoom overview when the chunk ring is engaged: per-cell,
/// the base/focus image (+ post-bake delta strokes) fills only the holes where
/// no tile is ready (even-odd clip), then the full-res tiles draw on top. The
/// clip is what prevents the base and a tile drawing the same ink twice (the
/// "tint"/halo of the earlier single-rectangle attempt). All in world coords.
class _NotebookChunkOverlayPainter extends CustomPainter {
  final List<int> pageBlockIds;
  final Map<int, DrawingData> pageData;
  final Map<int, ui.Image> pageImage; // chosen base/focus per visible page
  final Map<int, int> pageBaked; // baked stroke count → delta = the rest
  final List<(Rect, ui.Image)> tiles; // current-version tiles (worldRect, image)
  final Rect visibleWorld;

  const _NotebookChunkOverlayPainter({
    required this.pageBlockIds,
    required this.pageData,
    required this.pageImage,
    required this.pageBaked,
    required this.tiles,
    required this.visibleWorld,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium;
    // 1. Base ink + delta, clipped to the holes (everything NOT covered by a tile).
    final hole = Path()..addRect(visibleWorld);
    for (final (r, _) in tiles) {
      hole.addRect(r);
    }
    hole.fillType = PathFillType.evenOdd;
    canvas.save();
    canvas.clipPath(hole);
    for (int i = 0; i < pageBlockIds.length; i++) {
      final bid = pageBlockIds[i];
      final top = i * (kNotebookPageHeight + kNotebookPageGap);
      final pageWorld = Rect.fromLTWH(
        0,
        top,
        kNotebookPageWidth,
        kNotebookPageHeight,
      );
      if (!pageWorld.overlaps(visibleWorld)) continue;
      final img = pageImage[bid];
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          pageWorld,
          paint,
        );
      }
      final data = pageData[bid];
      if (data != null) {
        final baked = (pageBaked[bid] ?? 0).clamp(0, data.strokes.length).toInt();
        if (baked < data.strokes.length) {
          canvas.save();
          canvas.translate(0, top);
          canvas.clipRect(
            const Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight),
          );
          for (int s = baked; s < data.strokes.length; s++) {
            drawStroke(canvas, data.strokes[s]);
          }
          canvas.restore();
        }
      }
    }
    canvas.restore();
    // 2. Full-res tiles on top (where they exist they own the cell).
    for (final (r, image) in tiles) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NotebookChunkOverlayPainter old) => true;
}

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
  final Map<int, DrawingBlock> _pageShells = {};
  // Temporarily kept empty: pages are decoded eagerly on open so pan/scroll does
  // not pay hydration cost mid-gesture.
  final Map<int, DrawingBlock> _pendingDecode = {};
  final Set<int> _hydratingPages = {};
  static const int _livePageMargin = 2;
  static const int _evictPageMargin = 4;

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
  final Set<int> _overviewDirtyPages = {}; // pages queued for a re-bake
  // Pages whose baked image is STALE because an in-place edit (lasso
  // move/resize/rotate = same count, erase = fewer) changed already-baked
  // strokes — the append-only delta can't fix it. Those pages fall to tiles
  // until the re-bake, else the edited ink ghosts at its old spot on release.
  final Set<int> _overviewStalePages = {};
  double _overviewThreshold = 0;
  Timer? _overviewTimer;
  // ─── Pyramid Level 0: per-page FOCUS overview ─────────────────────────────
  // The base overview above is one fixed-density image per page (crisp only when
  // zoomed out). When you settle zoomed IN and then PAN, that base looks blurry —
  // and because the zoom is fixed during a pan, the blur is constant and very
  // noticeable. The focus level fixes exactly that: a higher-res image baked at
  // the SETTLED zoom for the page(s) in view + one neighbour each side (the
  // "active neighbourhood" prefetch), so panning at that zoom stays crisp. Pages
  // are bounded rectangles, so one image per page = no tile seams; the only
  // "pan out of the tile → hole" moment is a page boundary, covered by the
  // pre-baked neighbour. Falls back to the base image while a focus bakes / on
  // fast pan, and is dropped entirely when zoomed back out. RAM only.
  final Map<int, ui.Image> _overviewFocusByPage = {};
  final Map<int, double> _overviewFocusScaleByPage = {};
  final Map<int, int> _overviewFocusBakedCountByPage = {};
  final Set<int> _overviewFocusBakingPages = {};
  // ── Chunk tile ring (pyramid L0, dynamic) ──────────────────────────────────
  // Above the per-page focus ceiling (~2.4x) the page image tops out and panning
  // softens. This is a Minecraft-style ring of WORLD-anchored raster tiles baked
  // at the EXACT current zoom (1:1 with the screen → zero blur), generated at the
  // leading edge and freed behind as you pan, with the pyramid base UNDER them as
  // fallback (never a white hole). Tiles are ink-only and bake with the very same
  // drawStroke path as base/focus, so tile↔base edges match chromatically. Purely
  // additive; _tilesEnabled=false reverts to exactly today's behaviour.
  final Map<String, _ViewportRasterTile> _chunkTiles = {};
  final Set<String> _chunkBaking = {};
  double _chunkGridScale = 0; // zoom the current grid is anchored to
  double _chunkTileWorld = 0; // cell side in world units (viewport fraction)
  int _chunkVersion = 0; // bumped on ink edit → stale tiles discarded
  bool _chunkPumpScheduled = false;
  final bool _tilesEnabled = true; // master switch (A/B revert: flip + rebuild)
  static const int _kChunkTilesAcross = 3; // tiles spanning the viewport long side
  static const double _kChunkRingFactor = 0.5; // overscan ring = half a viewport
  static const int _kChunkMaxTiles = 36;
  static const int _kChunkPerFrame = 1; // bakes/frame (budgeted, runs during pan)
  // Fires the focus bake only once the view has truly STOPPED — including the
  // InteractiveViewer's fling/inertia AFTER the finger lifts. Baking mid-fling
  // would land the (main-isolate) recording micro-stutter while things are still
  // moving, where it's visible; in full stillness it's imperceptible. We poll
  // the transform matrix every frame with a Ticker (NOT the controller's change
  // notifications — those proved unreliable through the fling) and only settle
  // once the matrix is byte-identical for several consecutive frames.
  Ticker? _settleTicker;
  Matrix4? _lastSettleMatrix;
  int _settleStillFrames = 0;
  // Generous: the fling's sub-pixel tail can repeat the matrix for a few frames
  // before fully stopping; requiring a longer identical streak guarantees the
  // bake lands in true stillness (cost is only a slightly later crisp swap).
  static const int _settleStillFramesNeeded = 12; // ~200ms at 60fps
  // Cap a focus image's longest side (px). 4096 ≈ crisp to ~2.4x at dpr 2, ~47MB
  // per page; only the visible neighbourhood is kept resident. This is also the
  // ceiling: a page at this density is 4092px tall, just under the 4096 GPU
  // texture limit — higher would be rejected on some Android GPUs.
  static const double _focusMaxDim = 4096.0;
  static const double _baseOverviewDensity = 2.0;
  // Pin the overview through a 2-finger zoom gesture; hand back to crisp tiles
  // only when it ends (avoids re-rastering tiles mid-pinch → jank).
  bool _viewGestureActive = false;
  // True once a view-transform gesture has actually translated/scaled the
  // canvas (vs a finger that just touched down). Distinguishes a real pan from
  // a tap so we don't swap to the overview raster on every touch.
  bool _viewMoved = false;
  bool _overviewStickyThisGesture = false;
  bool _overviewActive = false;
  // Keep the overview raster mounted from gesture-end through the WHOLE fling,
  // handing back to crisp vector only when the view truly stops (the settle
  // Ticker flips this off). A fixed timer was wrong: the fling outlasts it, so
  // the linger expired mid-fling → vector tiles re-rastered WHILE STILL MOVING =
  // the stutter "before it stops". Tied to settle, the swap lands in stillness.
  bool _overviewLinger = false;
  ui.Image? _zoomSnapshotImage;
  Size? _zoomSnapshotSize;
  Timer? _zoomSnapshotTimer;
  bool _zoomSnapshotBaking = false;
  bool _zoomSnapshotPending = false;
  bool _zoomGestureActive = false;
  bool _zoomGestureSeen = false;
  double _zoomGestureScale = 1;
  Offset _zoomGestureStartFocal = Offset.zero;
  Offset _zoomGestureCurrentFocal = Offset.zero;
  Color _zoomSnapshotBgColor = const Color(0xFFFFFDF8);
  final ValueNotifier<int> _zoomGestureTick = ValueNotifier(0);
  final Map<String, _ViewportRasterTile> _viewportRasterTiles = {};
  Timer? _viewportRasterTimer;
  bool _viewportRasterBaking = false;
  bool _viewportRasterPending = false;
  int _viewportRasterVersion = 0;
  DateTime _lastLayerDecisionLog = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLayerDecisionKey = '';

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
        _scheduleDeferredDecode(Duration.zero);
        // Retired non-overview rasters (see _persistPage). Page overviews are
        // baked from the decode sites, so the first pan already has images.
        // _scheduleZoomSnapshotBake();
        // _scheduleViewportRasterBake();
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
    _settleTicker?.dispose();
    for (final img in _overviewFocusByPage.values) {
      img.dispose();
    }
    _overviewFocusByPage.clear();
    for (final t in _chunkTiles.values) {
      t.image.dispose();
    }
    _chunkTiles.clear();
    _zoomSnapshotTimer?.cancel();
    _zoomSnapshotImage?.dispose();
    _viewportRasterTimer?.cancel();
    for (final tile in _viewportRasterTiles.values) {
      tile.image.dispose();
    }
    _viewportRasterTiles.clear();
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
    _zoomGestureTick.dispose();
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

    _pageBlockIds.clear();
    _pageShells.clear();
    _pendingDecode.clear();
    _hydratingPages.clear();
    _pageData.clear();
    _pageTiles.clear();
    _pageWorldStrokeCache.clear();
    _persistedStrokeIdsByBlock.clear();
    _dirtyStrokeIdsByBlock.clear();
    _nextStrokePosByBlock.clear();

    for (final b in drawingBlocks) {
      _pageBlockIds.add(b.id);
      _pageShells[b.id] = b;
      if (b.starred) _starredBlockIds.add(b.id);
    }

    _lastBg = PageBackground.fromString(drawingBlocks.last.background ?? '');
    _lastBgColor = drawingBlocks.last.bgColor;

    var totalStrokes = 0;
    var totalPoints = 0;
    for (final b in drawingBlocks) {
      if (!mounted) return;
      _hydratingPages.add(b.id);
      try {
        final decoded = await _decodeData(b);
        if (!mounted) return;
        _pageData[b.id] = decoded;
        _pageTileIndex(b.id).rebuild(decoded.strokes);
        _rebuildWorldStrokeCache(b.id);
        _scheduleOverviewBake(b.id);
        totalStrokes += decoded.strokes.length;
        totalPoints += _pointCount(decoded.strokes);
      } finally {
        _hydratingPages.remove(b.id);
      }
    }

    _paintVersion++;
    setState(() {});

    sw.stop();
    CrashLogger.instance.note(
      'PERF abrir-cuaderno: ${drawingBlocks.length} paginas, '
      '${_pageData.length} decoded, ${_pendingDecode.length} pending, '
      '$totalStrokes trazos, $totalPoints puntos, '
      '${sw.elapsedMilliseconds}ms',
    );
  }

  /// Decode a few deferred pages per frame so even a 50-page note opens without
  /// a single blocking decode. The visible page wins, then neighbors, then the
  /// background stops; far pages remain cold on disk.
  Future<void> _decodeMorePages() async {
    if (!mounted) return;
    if (_isDrawing) {
      _scheduleDeferredDecode();
      return;
    }
    final sw = Stopwatch()..start();
    const perBatch = 1;
    var n = 0;
    while (n < perBatch) {
      final blockId = _nextPendingDecodeBlockId();
      if (blockId == null) break;
      final b = _pendingDecode.remove(blockId);
      if (b != null) {
        _hydratingPages.add(blockId);
        try {
          final decoded = await _decodeData(b);
          if (!mounted) return;
          _pageData[blockId] = decoded;
          final rebuildSw = Stopwatch()..start();
          _pageTileIndex(blockId).rebuild(_pageData[blockId]!.strokes);
          _rebuildWorldStrokeCache(blockId);
          _scheduleOverviewBake(blockId);
          rebuildSw.stop();
          final data = _pageData[blockId]!;
          final pts = _pointCount(data.strokes);
          final pageIndex = _pageBlockIds.indexOf(blockId);
          CrashLogger.instance.note(
            'PERF tile-cuaderno: page $pageIndex, ${data.strokes.length} trazos, '
            '$pts puntos, ${rebuildSw.elapsedMilliseconds}ms',
          );
          n++;
        } catch (e, st) {
          _pendingDecode[blockId] = b;
          CrashLogger.instance.record(
            e,
            st,
            context: 'decodeMorePages cuaderno',
          );
        } finally {
          _hydratingPages.remove(blockId);
        }
      }
    }
    final evicted = _evictColdPages();
    if (n > 0 || evicted > 0) {
      // Bump so the painter (which compares paintVersion, not the mutated
      // pageData map) repaints any newly-decoded page that's already in view.
      _paintVersion++;
      setState(() {});
    }
    if (_hasPendingDecodeInLiveWindow()) {
      _scheduleDeferredDecode();
    }
    sw.stop();
    if (n > 0 || evicted > 0) {
      CrashLogger.instance.note(
        'PERF decode-batch-cuaderno: $n paginas, '
        '$evicted evicted, ${_pendingDecode.length} pending, '
        '${_pageData.length} live, ${sw.elapsedMilliseconds}ms',
      );
    }
  }

  int? _nextPendingDecodeBlockId() {
    if (_pageBlockIds.isEmpty || _pendingDecode.isEmpty) return null;
    final live = _livePageIndices();
    final order =
        live.toList()..sort((a, b) {
          final current = _currentVisiblePage;
          final da = (a - current).abs();
          final db = (b - current).abs();
          return da.compareTo(db);
        });
    for (final pageIndex in order) {
      final blockId = _pageBlockIds[pageIndex];
      if (_pendingDecode.containsKey(blockId) &&
          !_hydratingPages.contains(blockId)) {
        return blockId;
      }
    }
    return null;
  }

  Set<int> _livePageIndices({int margin = _livePageMargin}) {
    if (_pageBlockIds.isEmpty) return const {};
    if (_viewport == Size.zero) {
      final current = _currentVisiblePage;
      return {
        for (int i = current - margin; i <= current + margin; i++)
          if (i >= 0 && i < _pageBlockIds.length) i,
      };
    }
    final visible = _visibleRectFor(_viewport);
    final wanted = <int>{};
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final top = _pageOffsetY(i);
      final rect = Rect.fromLTWH(
        0,
        top,
        kNotebookPageWidth,
        kNotebookPageHeight,
      );
      if (!rect.overlaps(visible)) continue;
      for (int j = i - margin; j <= i + margin; j++) {
        if (j >= 0 && j < _pageBlockIds.length) wanted.add(j);
      }
    }
    if (wanted.isEmpty) {
      final current = _currentVisiblePage;
      for (int i = current - margin; i <= current + margin; i++) {
        if (i >= 0 && i < _pageBlockIds.length) wanted.add(i);
      }
    }
    return wanted;
  }

  bool _hasPendingDecodeInLiveWindow() {
    if (_pendingDecode.isEmpty) return false;
    for (final pageIndex in _livePageIndices()) {
      final blockId = _pageBlockIds[pageIndex];
      if (_pendingDecode.containsKey(blockId) &&
          !_hydratingPages.contains(blockId)) {
        return true;
      }
    }
    return false;
  }

  bool _hasEvictableColdPages() {
    return false;
  }

  int _evictColdPages() {
    return 0;
  }

  void _scheduleDeferredDecode([
    Duration delay = const Duration(milliseconds: 16),
  ]) {
    if (!mounted ||
        (!_hasPendingDecodeInLiveWindow() && !_hasEvictableColdPages())) {
      return;
    }
    _deferredDecodeTimer?.cancel();
    _deferredDecodeTimer = Timer(delay, () {
      if (!mounted) return;
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
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    const batchSize = 450;
    final rows = <DrawingStrokeRecord>[];
    var lastPosition = -1;
    var batches = 0;
    while (mounted) {
      final batch = await strokeRepo.getByBlockAfterPosition(
        b.id,
        afterPosition: lastPosition,
        limit: batchSize,
      );
      if (batch.isEmpty) break;
      rows.addAll(batch);
      lastPosition = batch.last.position;
      batches++;
      await SchedulerBinding.instance.endOfFrame;
    }
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
    sw.stop();
    CrashLogger.instance.note(
      'PERF decode-cuaderno: page $pageIndex, ${data.strokes.length} trazos, '
      '$pts puntos, json ${(b.strokesJson.length / 1024).round()}KB, '
      '$batches batches, ${sw.elapsedMilliseconds}ms',
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
      _pageShells[block.id] = block;
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

  Future<void> _persistPageNow(
    int pageIndex, {
    DrawingStrokeRepository? strokeRepo,
    NoteBlockRepository? blockRepo,
  }) async {
    if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) return;
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) {
      _dirtyPersistPages.remove(blockId);
      return;
    }
    final DrawingStrokeRepository strokes =
        strokeRepo ?? ref.read(drawingStrokeRepositoryProvider);
    final NoteBlockRepository blocks =
        blockRepo ?? ref.read(noteBlockRepositoryProvider);
    _dirtyPersistPages.remove(blockId);
    final fullPersist = _fullStrokePersistBlocks.remove(blockId);
    final Set<int> dirtyBeforeFull =
        fullPersist ? _dirtyStrokeIds(blockId).toSet() : <int>{};
    if (fullPersist) _dirtyStrokeIds(blockId).clear();
    final removedDirtyIds = <int>{};
    final strokesSnapshot = List<DrawingStroke>.of(data.strokes);
    final imagesPayload = data.images.map((im) => im.toJson()).toList();
    final taskBlocksPayload = data.taskBlocks.map((b) => b.toJson()).toList();
    final textBlocksPayload = data.textBlocks.map((b) => b.toJson()).toList();
    final background = data.background;
    final bgColorValue = data.bgColorValue;
    final starred = _starredBlockIds.contains(blockId);
    final sw = Stopwatch()..start();
    int inserted = 0, updated = 0, deleted = 0;
    try {
      if (fullPersist) {
        final ids = await strokes.replaceBlock(blockId, [
          for (int i = 0; i < strokesSnapshot.length; i++)
            strokeWrite(i, strokesSnapshot[i]),
        ]);
        for (int i = 0; i < strokesSnapshot.length && i < ids.length; i++) {
          strokesSnapshot[i].dbId = ids[i];
          final liveIndex = data.strokes.indexOf(strokesSnapshot[i]);
          if (liveIndex >= 0 && liveIndex < data.strokes.length) {
            data.strokes[liveIndex].dbId = ids[i];
          }
          final cache = _pageWorldStrokeCache[blockId];
          if (cache != null && liveIndex >= 0 && liveIndex < cache.length) {
            cache[liveIndex].dbId = ids[i];
          }
        }
        _rebuildWorldStrokeCache(blockId);
        _persistedStrokeIds(blockId)
          ..clear()
          ..addAll(ids);
        _nextStrokePosByBlock[blockId] = strokesSnapshot.length;
        inserted = ids.length;
      } else {
        final persisted = _persistedStrokeIds(blockId);
        var nextPos = _nextStrokePos(blockId);
        final insertStrokes = <DrawingStroke>[];
        final insertWrites = <DrawingStrokeWrite>[];
        for (final stroke in strokesSnapshot) {
          if (stroke.dbId != null && persisted.contains(stroke.dbId)) {
            continue;
          }
          stroke.dbId = null;
          insertStrokes.add(stroke);
          insertWrites.add(strokeWrite(nextPos++, stroke));
        }
        final ids = await strokes.insertMany(blockId, insertWrites);
        for (int i = 0; i < ids.length && i < insertStrokes.length; i++) {
          final stroke = insertStrokes[i];
          final id = ids[i];
          stroke.dbId = id;
          final cacheIndex = data.strokes.indexOf(stroke);
          final cache = _pageWorldStrokeCache[blockId];
          if (cache != null && cacheIndex >= 0 && cacheIndex < cache.length) {
            cache[cacheIndex].dbId = id;
          }
          persisted.add(id);
        }
        inserted = ids.length;
        _nextStrokePosByBlock[blockId] = nextPos;

        final byId = <int, DrawingStroke>{
          for (final s in strokesSnapshot)
            if (s.dbId != null && persisted.contains(s.dbId)) s.dbId!: s,
        };
        final dirty = _dirtyStrokeIds(blockId);
        if (dirty.isNotEmpty) {
          final dirtyIds = dirty.toSet();
          final updates = <int, DrawingStrokeWrite>{};
          for (final id in dirtyIds) {
            final stroke = byId[id];
            if (stroke == null) continue;
            updates[id] = strokeWrite(0, stroke);
          }
          removedDirtyIds.addAll(updates.keys);
          dirty.removeAll(removedDirtyIds);
          await strokes.updateMany(updates);
          updated = updates.length;
        }

        final currentIds = byId.keys.toSet();
        final toDelete = persisted.difference(currentIds);
        if (toDelete.isNotEmpty) {
          await strokes.deleteByIds(toDelete.toList());
          persisted.removeAll(toDelete);
          deleted = toDelete.length;
        }
      }
      final strokeMs = sw.elapsedMilliseconds;
      await blocks.updatePayload(blockId, {
        'h': kNotebookPageHeight,
        's': const [],
        'i': imagesPayload,
        't': taskBlocksPayload,
        'tx': textBlocksPayload,
        'bg': background.toDbString(),
        if (bgColorValue != null) 'bgc': bgColorValue,
        'starred': starred,
      });
      final dbStats = await strokes.debugStatsByBlock(blockId);
      final memPoints = _pointCount(strokesSnapshot);
      final livePoints = _pointCount(data.strokes);
      final shell = _pageShells[blockId];
      if (shell != null) {
        _pageShells[blockId] = shell.copyWith(
          strokesJson: '[]',
          imagesJson: jsonEncode(imagesPayload),
          taskBlocksJson: jsonEncode(taskBlocksPayload),
          textBlocksJson: jsonEncode(textBlocksPayload),
          background: background.toDbString(),
          bgColor: bgColorValue,
          starred: starred,
        );
      }
      sw.stop();
      CrashLogger.instance.note(
        'PERF guardar-cuaderno: page $pageIndex, ${strokesSnapshot.length} trazos, '
        '$memPoints puntos, live ${data.strokes.length}/$livePoints, '
        '+$inserted ~$updated -$deleted, '
        'db ${dbStats.count} trazos/${dbStats.points} puntos/maxPos ${dbStats.maxPosition ?? -1}, '
        'strokesDB ${strokeMs}ms, '
        'total(+DB) ${sw.elapsedMilliseconds}ms',
      );
      if (dbStats.count != strokesSnapshot.length ||
          dbStats.points != memPoints) {
        CrashLogger.instance.note(
          'WARN persist-cuaderno-mismatch: page $pageIndex block $blockId, '
          'mem ${strokesSnapshot.length}/$memPoints vs '
          'db ${dbStats.count}/${dbStats.points}, '
          'live ${data.strokes.length}/$livePoints, '
          '+$inserted ~$updated -$deleted',
        );
      }
    } catch (_) {
      _dirtyPersistPages.add(blockId);
      if (fullPersist) {
        _fullStrokePersistBlocks.add(blockId);
        _dirtyStrokeIds(blockId).addAll(dirtyBeforeFull);
      }
      _dirtyStrokeIds(blockId).addAll(removedDirtyIds);
      rethrow;
    }
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
    final bid = _pageBlockIds[pageIndex];
    _scheduleOverviewBake(bid);
    // In-place edit (move/resize/rotate = same count, erase = fewer) changed
    // already-baked strokes → the append-only delta can't fix it. Mark the page
    // stale so it shows tiles until the re-bake, else the edited ink ghosts at
    // its old spot on release. Appends (count grows) stay on overview+delta.
    final data = _pageData[bid];
    if (data != null &&
        data.strokes.length <= (_overviewBakedCountByPage[bid] ?? 0)) {
      _overviewStalePages.add(bid);
    }
    // Drop the high-res focus too: it has the OLD strokes baked in, so an erase
    // or lasso-move would leave a ghost. Falls back to base+delta; the focus
    // re-bakes on the next settle. (At rest zoomed-in you're on vector anyway.)
    _disposeFocus(bid);
    // Same for the chunk ring: bump the version so the now-stale tiles stop being
    // shown (curTiles filters by version → the overlay yields to base+delta) and
    // re-bake at the new state on the next pump.
    _chunkVersion++;
    _scheduleChunkPump();
    // Retired (Phase A is overview-based): the viewport-raster / zoom-snapshot
    // bakes ran on every edit but their layers are now inert, so they were pure
    // waste. Kept callable for a possible Phase B LOD pyramid.
    // _scheduleZoomSnapshotBake();
    // _invalidateViewportRasterTiles();
    // _scheduleViewportRasterBake();
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
      final staleAtStart = _overviewStalePages.contains(blockId);
      // Page bounds are fixed, so any new stroke fits → appends are incremental.
      final incremental = !staleAtStart && oldImage != null && count > oldBaked;

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
      _overviewStalePages.remove(blockId); // fresh image matches _data again
      _overviewThreshold = (imgScale / dpr).clamp(0.0, 0.65);
      final pageIndex = _pageBlockIds.indexOf(blockId);
      CrashLogger.instance.note(
        'PERF bake-overview-cuaderno: page $pageIndex, '
        '${incremental ? 'incremental' : 'full'}, '
        'staleAtStart ${staleAtStart ? 'SI' : 'no'}, count $count, '
        'old $oldBaked, img ${w}x$h',
      );
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakePageOverview cuaderno');
    } finally {
      _overviewBakingPages.remove(blockId);
    }
  }

  /// The zoom below which the BASE per-page image is already crisp → no focus
  /// level needed. Derived from the base density and the device pixel ratio.
  double get _baseCrispCeiling {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return _baseOverviewDensity / dpr;
  }

  /// Start watching for the view to come to a full stop (finger lifted + fling
  /// finished). A Ticker samples the transform each frame; once it's been
  /// identical for [_settleStillFramesNeeded] frames we fire the focus bake — in
  /// guaranteed stillness, so its recording micro-stutter is invisible.
  void _beginSettleWatch() {
    _settleStillFrames = 0;
    _lastSettleMatrix = null;
    _settleTicker ??= createTicker(_onSettleTick);
    if (!_settleTicker!.isActive) _settleTicker!.start();
  }

  void _stopSettleWatch() {
    if (_settleTicker?.isActive ?? false) _settleTicker!.stop();
    _settleStillFrames = 0;
    _lastSettleMatrix = null;
  }

  void _onSettleTick(Duration _) {
    if (!mounted) {
      _stopSettleWatch();
      return;
    }
    // A finger is down or we're drawing → not settled; keep watching, reset.
    if (_viewGestureActive || _activePointers.isNotEmpty || _isDrawing) {
      _settleStillFrames = 0;
      _lastSettleMatrix = null;
      return;
    }
    final m = _viewCtrl.value;
    if (_lastSettleMatrix != null && m == _lastSettleMatrix) {
      _settleStillFrames++;
    } else {
      _settleStillFrames = 0;
      _lastSettleMatrix = m.clone();
    }
    if (_settleStillFrames >= _settleStillFramesNeeded) {
      _stopSettleWatch();
      // The view has truly stopped → NOW hand the overview back to crisp vector
      // (the swap + tile re-raster lands in stillness, invisible) and bake the
      // high-res focus for the next pan.
      if (_overviewLinger && mounted) {
        setState(() => _overviewLinger = false);
      }
      unawaited(_runFocusBakePass());
    }
  }

  Future<void> _runFocusBakePass() async {
    if (!mounted || _viewport == Size.zero || _pageBlockIds.isEmpty) return;
    // Recording strokes into a picture runs on the MAIN isolate (Flutter can't
    // rasterise ink on a worker), so never bake mid-gesture/draw — it would jank
    // the very pan we're trying to keep smooth. Defer until the view is idle.
    if (_viewGestureActive || _activePointers.isNotEmpty || _isDrawing) {
      _beginSettleWatch();
      return;
    }
    // Zoomed out enough that the base image is crisp → drop focus, reclaim RAM.
    if (_viewScale <= _baseCrispCeiling * 0.97) {
      _disposeAllFocus();
      return;
    }
    final visible = _visibleRectFor(_viewport);
    final wantedIdx = <int>{};
    for (int i = 0; i < _pageBlockIds.length; i++) {
      final top = _pageOffsetY(i);
      final pageRect = Rect.fromLTWH(
        0,
        top,
        kNotebookPageWidth,
        kNotebookPageHeight,
      );
      if (pageRect.overlaps(visible)) {
        wantedIdx.add(i);
        if (i > 0) wantedIdx.add(i - 1);
        if (i + 1 < _pageBlockIds.length) wantedIdx.add(i + 1);
      }
    }
    final wantedBids = wantedIdx.map((i) => _pageBlockIds[i]).toSet();
    for (final bid in _overviewFocusByPage.keys.toList()) {
      if (!wantedBids.contains(bid)) _disposeFocus(bid);
    }
    // Bake the closest page first so the swap-to-crisp feels immediate.
    final order =
        wantedIdx.toList()..sort((a, b) {
          final ca =
              (_pageOffsetY(a) + kNotebookPageHeight / 2 - visible.center.dy)
                  .abs();
          final cb =
              (_pageOffsetY(b) + kNotebookPageHeight / 2 - visible.center.dy)
                  .abs();
          return ca.compareTo(cb);
        });
    for (final i in order) {
      if (!mounted) break;
      // Re-check between pages: a focus bake awaits (toImage), and during that
      // yield the user may start ANOTHER fling. The next page's recording would
      // then run mid-motion and stutter visibly. An armed settle timer means the
      // view started moving again → bail and let the next settle finish the rest.
      if (_viewGestureActive ||
          _activePointers.isNotEmpty ||
          _isDrawing ||
          (_settleTicker?.isActive ?? false)) {
        _beginSettleWatch();
        break;
      }
      await _bakePageFocus(_pageBlockIds[i], _viewScale);
    }
    // Pre-load / refresh the chunk ring for the settled zoom (or free it if we
    // dropped below the engage threshold). Budgeted; runs in stillness here.
    if (mounted) _scheduleChunkPump();
  }

  /// Render one page's strokes at a density matched to [targetScale] (capped by
  /// [_focusMaxDim]). Full re-bake; skipped when the resident focus already
  /// matches this zoom and stroke count closely enough.
  Future<void> _bakePageFocus(int blockId, double targetScale) async {
    if (_overviewFocusBakingPages.contains(blockId) || !mounted) return;
    final data = _pageData[blockId];
    if (data == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final imgScale = (targetScale * dpr).clamp(
      _baseOverviewDensity,
      _focusMaxDim / kNotebookPageHeight,
    );
    final count = data.strokes.length;
    final haveScale = _overviewFocusScaleByPage[blockId];
    final haveCount = _overviewFocusBakedCountByPage[blockId];
    if (_overviewFocusByPage[blockId] != null &&
        haveScale != null &&
        (haveScale - imgScale).abs() / imgScale < 0.12 &&
        haveCount == count) {
      final pageIndex = _pageBlockIds.indexOf(blockId);
      CrashLogger.instance.note(
        'PERF bake-focus-cuaderno: page $pageIndex reuse, count $count, '
        'scale ${imgScale.toStringAsFixed(2)}, have ${haveScale.toStringAsFixed(2)}',
      );
      return; // resident focus is already good enough for this zoom
    }
    _overviewFocusBakingPages.add(blockId);
    try {
      final w = (kNotebookPageWidth * imgScale).ceil();
      final h = (kNotebookPageHeight * imgScale).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(imgScale); // strokes are page-local — no translate
      for (int i = 0; i < count; i++) {
        drawStroke(canvas, data.strokes[i]);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _overviewFocusByPage[blockId];
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _overviewFocusByPage[blockId] = image;
      _overviewFocusScaleByPage[blockId] = imgScale;
      _overviewFocusBakedCountByPage[blockId] = count;
      final pageIndex = _pageBlockIds.indexOf(blockId);
      CrashLogger.instance.note(
        'PERF bake-focus-cuaderno: page $pageIndex done, count $count, '
        'img ${w}x$h, scale ${imgScale.toStringAsFixed(2)}, '
        'stale ${_overviewStalePages.contains(blockId) ? 'SI' : 'no'}',
      );
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakePageFocus cuaderno');
    } finally {
      _overviewFocusBakingPages.remove(blockId);
    }
  }

  void _disposeFocus(int blockId) {
    final img = _overviewFocusByPage.remove(blockId);
    if (img != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
    }
    _overviewFocusScaleByPage.remove(blockId);
    _overviewFocusBakedCountByPage.remove(blockId);
  }

  void _disposeAllFocus() {
    if (_overviewFocusByPage.isEmpty) return;
    for (final img in _overviewFocusByPage.values) {
      final captured = img;
      WidgetsBinding.instance.addPostFrameCallback((_) => captured.dispose());
    }
    _overviewFocusByPage.clear();
    _overviewFocusScaleByPage.clear();
    _overviewFocusBakedCountByPage.clear();
    if (mounted) setState(() {});
  }

  // ── Chunk tile ring ────────────────────────────────────────────────────────

  /// Engaged only past the per-page focus ceiling (~2.4x), where the page image
  /// can no longer reach full device res and panning softens. Below it the
  /// existing pyramid is already crisp → chunks stay dormant.
  bool get _chunkEngaged {
    if (!_tilesEnabled) return false;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final ceiling = (_focusMaxDim / kNotebookPageHeight) / dpr;
    return _viewScale > ceiling * 0.97;
  }

  String _chunkKey(int gx, int gy) => '$gx:$gy';

  /// Cells whose world rect overlaps viewport + ring, nearest-first, capped.
  List<(int, int, Rect)> _wantedChunks(double tileWorld) {
    final visible = _visibleRectFor(_viewport);
    final ring = visible.inflate(visible.longestSide * _kChunkRingFactor);
    final gx0 = (ring.left / tileWorld).floor();
    final gy0 = (ring.top / tileWorld).floor();
    final gx1 = (ring.right / tileWorld).ceil();
    final gy1 = (ring.bottom / tileWorld).ceil();
    final center = visible.center;
    final out = <(int, int, Rect)>[];
    for (int gy = gy0; gy < gy1; gy++) {
      for (int gx = gx0; gx < gx1; gx++) {
        final rect = Rect.fromLTWH(
          gx * tileWorld,
          gy * tileWorld,
          tileWorld,
          tileWorld,
        );
        if (rect.overlaps(ring)) out.add((gx, gy, rect));
      }
    }
    out.sort(
      (a, b) => (a.$3.center - center).distanceSquared.compareTo(
        (b.$3.center - center).distanceSquared,
      ),
    );
    if (out.length > _kChunkMaxTiles) out.removeRange(_kChunkMaxTiles, out.length);
    return out;
  }

  void _disposeAllChunks() {
    if (_chunkTiles.isEmpty) return;
    for (final t in _chunkTiles.values) {
      final img = t.image;
      WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
    }
    _chunkTiles.clear();
    _chunkTileWorld = 0;
  }

  void _scheduleChunkPump() {
    if (_chunkPumpScheduled || !mounted) return;
    _chunkPumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chunkPumpScheduled = false;
      unawaited(_chunkPump());
    });
  }

  /// Budgeted baker: keeps the ring filled around the viewport, baking a few
  /// tiles per frame nearest-first (runs DURING pan, not only at rest). Drawing
  /// / lasso own the main isolate → it backs off for them. Re-anchors the grid
  /// to a new zoom only when settled (mid zoom-gesture the pyramid covers it).
  Future<void> _chunkPump() async {
    if (!mounted) return;
    if (_isDrawing ||
        _lassoCtrl.phase == LassoPhase.moving ||
        _lassoCtrl.phase == LassoPhase.resizing ||
        _lassoCtrl.phase == LassoPhase.rotating) {
      return;
    }
    if (!_chunkEngaged || _viewport == Size.zero || _pageBlockIds.isEmpty) {
      _disposeAllChunks();
      return;
    }
    final visible = _visibleRectFor(_viewport);
    final scaleChanged =
        _chunkTileWorld <= 0 ||
        (_viewScale - _chunkGridScale).abs() / _viewScale > 0.02;
    if (scaleChanged) {
      // During an active zoom gesture the scale changes every frame; re-anchoring
      // per frame would thrash. Defer to settle — the pyramid covers the gap.
      if (_viewGestureActive) return;
      _chunkGridScale = _viewScale;
      _chunkTileWorld = visible.longestSide / _kChunkTilesAcross;
      _chunkVersion++;
    }
    final tileWorld = _chunkTileWorld;
    final wanted = _wantedChunks(tileWorld);
    final wantedKeys = wanted.map((c) => _chunkKey(c.$1, c.$2)).toSet();
    for (final key in _chunkTiles.keys.toList()) {
      if (!wantedKeys.contains(key)) {
        final img = _chunkTiles.remove(key)!.image;
        WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
      }
    }
    var baked = 0;
    for (final (gx, gy, rect) in wanted) {
      if (baked >= _kChunkPerFrame) break;
      final key = _chunkKey(gx, gy);
      final existing = _chunkTiles[key];
      if (existing != null && existing.version == _chunkVersion) continue;
      if (_chunkBaking.contains(key)) continue;
      baked++;
      await _bakeChunk(gx, gy, rect, tileWorld);
      if (_isDrawing) break; // a draw started during the await → yield
    }
    final hasPending = wanted.any((c) {
      final t = _chunkTiles[_chunkKey(c.$1, c.$2)];
      return t == null || t.version != _chunkVersion;
    });
    if (hasPending && _chunkEngaged) _scheduleChunkPump();
  }

  /// Bake one cell at the EXACT anchored zoom (1:1 with the screen → zero blur),
  /// ink-only, world-anchored. Same `drawStroke` path as base/focus so tile↔base
  /// edges match chromatically.
  Future<void> _bakeChunk(int gx, int gy, Rect cell, double tileWorld) async {
    final key = _chunkKey(gx, gy);
    if (_chunkBaking.contains(key) || !mounted) return;
    final version = _chunkVersion;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final imgScale = _chunkGridScale * dpr;
    final px = (tileWorld * imgScale).round();
    if (px <= 0 || px > 4096) return; // texture-limit guard (shouldn't hit by design)
    _chunkBaking.add(key);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(imgScale);
      canvas.translate(-cell.left, -cell.top); // world → cell-local
      canvas.clipRect(cell);
      for (int i = 0; i < _pageBlockIds.length; i++) {
        final top = _pageOffsetY(i);
        final pageRect = Rect.fromLTWH(
          0,
          top,
          kNotebookPageWidth,
          kNotebookPageHeight,
        );
        if (!pageRect.overlaps(cell)) continue;
        final data = _pageData[_pageBlockIds[i]];
        if (data == null || data.strokes.isEmpty) continue;
        canvas.save();
        canvas.translate(0, top); // page-local → world
        canvas.clipRect(
          const Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight),
        );
        for (final s in data.strokes) {
          drawStroke(canvas, s);
        }
        canvas.restore();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(px, px);
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _chunkTiles[key];
      if (old != null) {
        final oldImg = old.image;
        WidgetsBinding.instance.addPostFrameCallback((_) => oldImg.dispose());
      }
      _chunkTiles[key] = _ViewportRasterTile(
        key: key,
        worldRect: cell,
        bucket: 0,
        version: version,
        image: image,
      );
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeChunk cuaderno');
    } finally {
      _chunkBaking.remove(key);
    }
  }

  void _scheduleZoomSnapshotBake({
    Duration delay = const Duration(milliseconds: 180),
  }) {
    _zoomSnapshotPending = true;
    _zoomSnapshotTimer?.cancel();
    _zoomSnapshotTimer = Timer(delay, () {
      if (mounted) unawaited(_bakeZoomSnapshot());
    });
  }

  Future<void> _bakeZoomSnapshot() async {
    if (!mounted || _viewGestureActive || _viewport == Size.zero) return;
    if (_zoomSnapshotBaking) {
      _zoomSnapshotPending = true;
      return;
    }
    final boundary =
        _canvasBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) {
      _scheduleZoomSnapshotBake(delay: const Duration(milliseconds: 80));
      return;
    }
    _zoomSnapshotPending = false;
    _zoomSnapshotBaking = true;
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: dpr);
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _zoomSnapshotImage;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _zoomSnapshotImage = image;
      _zoomSnapshotSize = _viewport;
      _zoomSnapshotBgColor = _currentBgColor;
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeZoomSnapshot cuaderno');
    } finally {
      _zoomSnapshotBaking = false;
      if (_zoomSnapshotPending && mounted) {
        _scheduleZoomSnapshotBake(delay: const Duration(milliseconds: 80));
      }
    }
  }

  static const double _viewportRasterTileScreen = 384;
  static const int _viewportRasterMaxTiles = 32;

  // Phase A is overview-based: during any view-transform gesture the cached
  // per-page overview images are shown (the InteractiveViewer transforms them
  // for free — no per-frame widget rebuild, no re-raster) instead of the live
  // vector tiles. The older screen-space viewport-raster path is retired: it
  // still rebuilt its widget tree every frame and only engaged on 2 fingers, so
  // 1-finger pans (the common stylus-mode navigation) re-rastered vectors and
  // lagged. Kept inert (not deleted) in case Phase B revives a true LOD pyramid.
  bool get _viewportRasterActive => false;

  // A view-transform gesture (pan or zoom) is actively moving the canvas, and
  // it is NOT a draw or a lasso transform → show overview rasters, not vectors.
  // Engages on 2 fingers immediately, or on 1 finger once it has actually moved.
  bool get _viewTransformActive =>
      _viewGestureActive &&
      !_isDrawing &&
      _lassoCtrl.phase != LassoPhase.moving &&
      _lassoCtrl.phase != LassoPhase.resizing &&
      _lassoCtrl.phase != LassoPhase.rotating &&
      (_activePointers.length >= 2 || _viewMoved);

  int _viewportRasterBucket(double scale) {
    if (scale < 0.45) return 0;
    if (scale < 0.7) return 1;
    if (scale < 1.05) return 2;
    if (scale < 1.55) return 3;
    if (scale < 2.3) return 4;
    return 5;
  }

  double _viewportRasterBucketScale(int bucket) {
    switch (bucket) {
      case 0:
        return 0.35;
      case 1:
        return 0.55;
      case 2:
        return 0.85;
      case 3:
        return 1.25;
      case 4:
        return 1.8;
      default:
        return 2.6;
    }
  }

  // ignore: unused_element  // retired with the viewport-raster path; kept for Phase B
  void _invalidateViewportRasterTiles() {
    _viewportRasterVersion++;
    for (final tile in _viewportRasterTiles.values) {
      tile.image.dispose();
    }
    _viewportRasterTiles.clear();
  }

  void _scheduleViewportRasterBake({
    Duration delay = const Duration(milliseconds: 220),
  }) {
    _viewportRasterPending = true;
    _viewportRasterTimer?.cancel();
    _viewportRasterTimer = Timer(delay, () {
      if (mounted) unawaited(_bakeViewportRasterTiles());
    });
  }

  Future<void> _bakeViewportRasterTiles() async {
    if (!mounted || _viewport == Size.zero) return;
    if (_viewGestureActive || _activePointers.isNotEmpty || _isDrawing) {
      _scheduleViewportRasterBake(delay: const Duration(milliseconds: 160));
      return;
    }
    if (_viewportRasterBaking) {
      _viewportRasterPending = true;
      return;
    }
    _viewportRasterPending = false;
    _viewportRasterBaking = true;
    try {
      final version = _viewportRasterVersion;
      final bucket = _viewportRasterBucket(_viewScale);
      final bucketScale = _viewportRasterBucketScale(bucket);
      final visible = _visibleRectFor(_viewport);
      final overscan = math.max(visible.width, visible.height) * 0.55;
      final wanted = visible.inflate(overscan);
      final tileWorld = _viewportRasterTileScreen / bucketScale;
      final minTx = (wanted.left / tileWorld).floor();
      final maxTx = (wanted.right / tileWorld).floor();
      final minTy = (wanted.top / tileWorld).floor();
      final maxTy = (wanted.bottom / tileWorld).floor();
      final candidates = <({String key, Rect rect, double dist})>[];
      final center = visible.center;
      for (int ty = minTy; ty <= maxTy; ty++) {
        for (int tx = minTx; tx <= maxTx; tx++) {
          final rect = Rect.fromLTWH(
            tx * tileWorld,
            ty * tileWorld,
            tileWorld,
            tileWorld,
          );
          final key = '$version:$bucket:$tx:$ty';
          final d = (rect.center - center).distanceSquared;
          candidates.add((key: key, rect: rect, dist: d));
        }
      }
      candidates.sort((a, b) => a.dist.compareTo(b.dist));
      final keep = candidates.take(_viewportRasterMaxTiles).toList();
      final keepKeys = keep.map((c) => c.key).toSet();
      final stale =
          _viewportRasterTiles.entries
              .where((e) => !keepKeys.contains(e.key))
              .map((e) => e.key)
              .toList();
      for (final key in stale) {
        _viewportRasterTiles.remove(key)?.image.dispose();
      }
      for (final c in keep) {
        if (!mounted || version != _viewportRasterVersion) break;
        if (_viewportRasterTiles.containsKey(c.key)) continue;
        final tile = await _renderViewportRasterTile(
          key: c.key,
          worldRect: c.rect,
          bucket: bucket,
          bucketScale: bucketScale,
          version: version,
        );
        if (tile == null) continue;
        if (!mounted || version != _viewportRasterVersion) {
          tile.image.dispose();
          break;
        }
        final old = _viewportRasterTiles[tile.key];
        old?.image.dispose();
        _viewportRasterTiles[tile.key] = tile;
        if (mounted) setState(() {});
      }
    } catch (e, st) {
      CrashLogger.instance.record(
        e,
        st,
        context: 'bakeViewportRaster cuaderno',
      );
    } finally {
      _viewportRasterBaking = false;
      if (_viewportRasterPending && mounted) {
        _scheduleViewportRasterBake(delay: const Duration(milliseconds: 120));
      }
    }
  }

  Future<_ViewportRasterTile?> _renderViewportRasterTile({
    required String key,
    required Rect worldRect,
    required int bucket,
    required double bucketScale,
    required int version,
  }) async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final imageScale = (bucketScale * dpr).clamp(0.45, 2.0);
    final w = math.max(1, (worldRect.width * imageScale).ceil());
    final h = math.max(1, (worldRect.height * imageScale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(imageScale);
    canvas.translate(-worldRect.left, -worldRect.top);
    _NotebookCanvasPainter(
      pageBlockIds: _pageBlockIds,
      pageData: _pageData,
      visibleRect: worldRect,
      paintVersion: _paintVersion + _inkTick.value,
      accentColor: _accent,
      imageCache: _imgCache,
      lod: lodForScale(bucketScale),
    ).paint(canvas, Size(kNotebookPageWidth, _totalCanvasHeight));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(w, h);
      return _ViewportRasterTile(
        key: key,
        worldRect: worldRect,
        bucket: bucket,
        version: version,
        image: image,
      );
    } finally {
      picture.dispose();
    }
  }

  Future<void> _flushPendingPersists() async {
    if (_dirtyPersistPages.isEmpty) return;
    if (_persisting) return;
    _persisting = true;
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    final blockRepo = ref.read(noteBlockRepositoryProvider);
    final sw = Stopwatch()..start();
    var pages = 0;
    try {
      while (_dirtyPersistPages.isNotEmpty) {
        final blockIds = _dirtyPersistPages.toList();
        for (final blockId in blockIds) {
          final pageIndex = _pageBlockIds.indexOf(blockId);
          if (pageIndex >= 0) {
            await _persistPageNow(
              pageIndex,
              strokeRepo: strokeRepo,
              blockRepo: blockRepo,
            );
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
    _scheduleDeferredDecode(Duration.zero);
    _togglePageDrawer();
  }

  Future<void> _toggleStarred(int blockId) async {
    final idx = _pageBlockIds.indexOf(blockId);
    if (idx < 0) return;
    final starred = !_starredBlockIds.contains(blockId);
    setState(() {
      if (starred) {
        _starredBlockIds.add(blockId);
      } else {
        _starredBlockIds.remove(blockId);
      }
    });
    if (_pageData.containsKey(blockId)) {
      await _persistPageNow(idx);
    } else {
      final shell = _pageShells[blockId];
      if (shell != null) {
        final updated = shell.copyWith(starred: starred);
        _pageShells[blockId] = updated;
        _pendingDecode[blockId] = updated;
        await ref.read(noteBlockRepositoryProvider).updatePayload(blockId, {
          'h': kNotebookPageHeight,
          's': const [],
          'i': jsonDecode(updated.imagesJson),
          't': jsonDecode(updated.taskBlocksJson),
          'tx': jsonDecode(updated.textBlocksJson),
          if (updated.background != null) 'bg': updated.background,
          if (updated.bgColor != null) 'bgc': updated.bgColor,
          'starred': starred,
        });
      }
    }
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
      _pageShells.remove(blockId);
      _pendingDecode.remove(blockId);
      _hydratingPages.remove(blockId);
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
      CrashLogger.instance.note(
        'PERF lasso-transform-cuaderno: affected ${affected.toList()..sort()}, '
        'selected ${_lassoCtrl.selectedIndices.length}, world ${strokes.length}, '
        'decoded ${_pageData.length}/${_pageBlockIds.length}, pending ${_pendingDecode.length}',
      );
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

  void _refreshLassoPageVisuals(
    int pageIndex,
    Rect? region, {
    required int touched,
    required bool structural,
    required String reason,
  }) {
    final blockId = _pageBlockIds[pageIndex];
    final data = _pageData[blockId];
    if (data == null) return;
    final index = _pageTileIndex(blockId);
    final forceRebuild = structural || region == null || touched > 128;
    _overviewStalePages.add(blockId);
    _disposeFocus(blockId);
    if (forceRebuild) {
      index.rebuild(data.strokes);
    } else {
      index.invalidateRegion(region, data.strokes);
    }
    CrashLogger.instance.note(
      'PERF lasso-tiles-cuaderno: $reason page $pageIndex, '
      '${forceRebuild ? 'rebuild' : 'region'}, touched $touched, '
      'strokes ${data.strokes.length}, tiles ${index.debugTileCount}/${index.debugEntryCount}, '
      'stale ${_overviewStalePages.contains(blockId)}, '
      'baked ${_overviewBakedCountByPage[blockId] ?? 0}, '
      'focus ${_overviewFocusBakedCountByPage[blockId] ?? 0}',
    );
  }

  (int, int) _syncLengthStableLassoStrokes(
    List<DrawingStroke> worldStrokes,
    Set<int> affected,
  ) {
    final dirtyByPage = <int, Rect>{};
    final removalsByPage = <int, List<int>>{};
    final appendsByPage = <int, List<DrawingStroke>>{};
    final structuralPages = <int>{};
    // Each selected stroke's final (page, object) so we can re-derive the flat
    // selection indices AFTER all list mutations settle. A cross-page move
    // removes from the source + appends to the target → every later flat index
    // shifts; without re-deriving, selectedIndices point at the wrong strokes
    // (the selection "grows" and grabs different ink on the next interaction).
    final placed = <(int, DrawingStroke)>[];
    var touched = 0;
    var points = 0;
    var skippedSourceCold = 0;
    var skippedTargetCold = 0;
    var selectedSeen = 0;

    for (final worldIndex in _lassoCtrl.selectedIndices) {
      if (worldIndex < 0 || worldIndex >= worldStrokes.length) continue;
      selectedSeen++;
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
        if (sourceData == null) skippedSourceCold++;
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
      final targetBlockId = _pageBlockIds[targetPage];
      final targetData = _pageData[targetBlockId];
      if (targetData == null) skippedTargetCold++;
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
        placed.add((sourcePage, newLocal));
      } else {
        (removalsByPage[sourcePage] ??= []).add(sourceLocal);
        (appendsByPage[targetPage] ??= []).add(newLocal);
        structuralPages.add(sourcePage);
        structuralPages.add(targetPage);
        placed.add((targetPage, newLocal));
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
      if (_pageData[blockId] == null) continue;
      _refreshLassoPageVisuals(
        pageIndex,
        entry.value,
        touched: touched,
        structural: structuralPages.contains(pageIndex),
        reason: 'length',
      );
      _persistPage(pageIndex);
    }

    if (skippedSourceCold > 0 ||
        skippedTargetCold > 0 ||
        touched != selectedSeen) {
      CrashLogger.instance.note(
        'WARN lasso-length-cuaderno: selected ${_lassoCtrl.selectedIndices.length}, '
        'seen $selectedSeen, touched $touched, '
        'sourceCold $skippedSourceCold, targetCold $skippedTargetCold, '
        'affected ${affected.toList()..sort()}, '
        'decoded ${_pageData.length}/${_pageBlockIds.length}, '
        'pending ${_pendingDecode.length}',
      );
    }

    // Re-derive the flat selection from where each stroke actually ended up (by
    // identity, after removals/appends shifted local indices). No-op for a
    // same-page move (indices unchanged); fixes the cross-page desync.
    if (placed.isNotEmpty) {
      final newSel = <int>{};
      for (final (page, stroke) in placed) {
        if (page < 0 || page >= _pageBlockIds.length) continue;
        final data = _pageData[_pageBlockIds[page]];
        if (data == null) continue;
        final local = data.strokes.indexWhere((s) => identical(s, stroke));
        if (local < 0) continue;
        newSel.add(_worldStrokeIndexFromPageLocal(page, local));
      }
      _lassoCtrl.selectedIndices = newSel;
    }

    return (touched, points);
  }

  (int, int) _syncDeletedLassoStrokes(Set<int> selectedBefore) {
    final dirtyByPage = <int, Rect>{};
    final removalsByPage = <int, List<int>>{};
    var touched = 0;
    var points = 0;
    var skippedCold = 0;

    for (final worldIndex in selectedBefore) {
      final source = _worldStrokePageLocalIndex(worldIndex);
      if (source == null) continue;
      final pageIndex = source.$1;
      final localIndex = source.$2;
      if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) continue;
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null || localIndex < 0 || localIndex >= data.strokes.length) {
        if (data == null) skippedCold++;
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
      if (_pageData[blockId] == null) continue;
      _refreshLassoPageVisuals(
        pageIndex,
        entry.value,
        touched: touched,
        structural: true,
        reason: 'delete',
      );
      _persistPage(pageIndex);
    }

    if (skippedCold > 0 || touched != selectedBefore.length) {
      CrashLogger.instance.note(
        'WARN lasso-delete-cuaderno: selected ${selectedBefore.length}, '
        'touched $touched, cold $skippedCold, '
        'dirtyPages ${dirtyByPage.keys.toList()..sort()}, '
        'decoded ${_pageData.length}/${_pageBlockIds.length}, '
        'pending ${_pendingDecode.length}',
      );
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
    var candidates = 0;
    var skippedCold = 0;
    var skippedInvalid = 0;

    for (final worldIndex in (_lassoCtrl.selectedIndices.toList()..sort())) {
      if (worldIndex < minNewIndex || worldIndex >= worldStrokes.length) {
        continue;
      }
      candidates++;
      final worldStroke = worldStrokes[worldIndex];
      if (worldStroke.points.isEmpty) {
        skippedInvalid++;
        continue;
      }
      var sumY = 0.0;
      for (final pt in worldStroke.points) {
        sumY += pt[1];
      }
      final pageIndex = _nearestPageIndex(sumY / worldStroke.points.length);
      if (pageIndex < 0 || pageIndex >= _pageBlockIds.length) {
        skippedInvalid++;
        continue;
      }
      final blockId = _pageBlockIds[pageIndex];
      final data = _pageData[blockId];
      if (data == null) {
        skippedCold++;
        continue;
      }
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
      if (_pageData[blockId] == null) continue;
      _refreshLassoPageVisuals(
        pageIndex,
        entry.value,
        touched: touched,
        structural: true,
        reason: 'append',
      );
      _persistPage(pageIndex);
    }

    if (skippedCold > 0 || skippedInvalid > 0 || touched != candidates) {
      CrashLogger.instance.note(
        'WARN lasso-append-cuaderno: candidates $candidates, '
        'touched $touched, cold $skippedCold, invalid $skippedInvalid, '
        'dirtyPages ${dirtyByPage.keys.toList()..sort()}, '
        'selected ${_lassoCtrl.selectedIndices.length}, minNew $minNewIndex, '
        'world ${worldStrokes.length}, decoded ${_pageData.length}/${_pageBlockIds.length}, '
        'pending ${_pendingDecode.length}',
      );
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
//PERF-LOG CrashLogger.instance.note('PERF lasso-sync-cuaderno: 0 paginas, 0ms');
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
      _overviewStalePages.add(bid);
      _disposeFocus(bid);
      final index = _pageTileIndex(bid);
      CrashLogger.instance.note(
        'PERF lasso-tiles-cuaderno: full page $i, rebuild, '
        'strokes ${_pageData[bid]!.strokes.length}, '
        'tiles ${index.debugTileCount}/${index.debugEntryCount}, '
        'stale ${_overviewStalePages.contains(bid)}, '
        'baked ${_overviewBakedCountByPage[bid] ?? 0}, '
        'focus ${_overviewFocusBakedCountByPage[bid] ?? 0}',
      );
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
    final affectedList = affected.toList()..sort();
    final pendingAffected = [
      for (final page in affectedList)
        if (page >= 0 &&
            page < _pageBlockIds.length &&
            _pendingDecode.containsKey(_pageBlockIds[page]))
          page,
    ];
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
      'PERF lasso-mut-cuaderno: mode $syncMode, '
      'selected ${selectedBefore.length}->${_lassoCtrl.selectedIndices.length}, '
      'strokes $strokeCountBefore->${strokes.length}, '
      'affected $affectedList, pendingAffected $pendingAffected, '
      'decoded ${_pageData.length}/${_pageBlockIds.length}, pending ${_pendingDecode.length}, '
      'snapshot ${snapMs}ms, flattenStrokes ${strokesMs}ms, '
      'total ${sw.elapsedMilliseconds}ms',
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

  void _invalidateUndoRedoPageVisuals(int blockId, String reason) {
    final data = _pageData[blockId];
    _pageTileIndex(blockId).rebuild(data?.strokes ?? const []);
    _overviewStalePages.add(blockId);
    _disposeFocus(blockId);
    _scheduleOverviewBake(blockId);
    _rebuildWorldStrokeCache(blockId);
    CrashLogger.instance.note(
      'PERF undo-redo-cuaderno: $reason block $blockId page ${_pageBlockIds.indexOf(blockId)}, '
      'strokes ${data?.strokes.length ?? 0}, '
      'tiles ${_pageTileIndex(blockId).debugTileCount}/${_pageTileIndex(blockId).debugEntryCount}, '
      'stale ${_overviewStalePages.contains(blockId)}, '
      'baked ${_overviewBakedCountByPage[blockId] ?? 0}, '
      'focus ${_overviewFocusBakedCountByPage[blockId] ?? 0}',
    );
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
        _fullStrokePersistBlocks.add(entry.key);
      }
      _invalidateUndoRedoPageVisuals(entry.key, 'restore');
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
          _overviewStalePages.add(entry.blockId);
          _disposeFocus(entry.blockId);
          _scheduleOverviewBake(entry.blockId);
          _rebuildWorldStrokeCache(entry.blockId);
          CrashLogger.instance.note(
            'PERF undo-redo-cuaderno: stroke-add undo block ${entry.blockId} '
            'page ${_pageBlockIds.indexOf(entry.blockId)}, '
            'strokes ${data.strokes.length}, stale ${_overviewStalePages.contains(entry.blockId)}, '
            'baked ${_overviewBakedCountByPage[entry.blockId] ?? 0}',
          );
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
          _overviewStalePages.add(entry.blockId);
          _disposeFocus(entry.blockId);
          _scheduleOverviewBake(entry.blockId);
          CrashLogger.instance.note(
            'PERF undo-redo-cuaderno: stroke-add redo block ${entry.blockId} '
            'page ${_pageBlockIds.indexOf(entry.blockId)}, '
            'strokes ${data.strokes.length}, stale ${_overviewStalePages.contains(entry.blockId)}, '
            'baked ${_overviewBakedCountByPage[entry.blockId] ?? 0}',
          );
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
        if (_viewportRasterActive ||
            (_zoomGestureActive && _zoomSnapshotImage != null)) {
          return const SizedBox.shrink();
        }
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

  void _logNotebookLayerDecision(
    String source, {
    required Rect visible,
    required int visiblePages,
    required int coldPages,
    required int emptyPages,
    required int tilePages,
    required int basePages,
    required int focusPages,
    required int stalePages,
    required int deltaStrokes,
    required int liveStrokes,
    required int bakedStrokes,
    required int widgetCount,
    required int lod,
    required String details,
  }) {
    final now = DateTime.now();
    final moving =
        _viewGestureActive ||
        _viewTransformActive ||
        _overviewLinger ||
        _activePointers.isNotEmpty;
    final key =
        '$source|${_viewScale.toStringAsFixed(2)}|$_overviewActive|'
        '$visiblePages|$coldPages|$emptyPages|$tilePages|$basePages|'
        '$focusPages|$stalePages|$deltaStrokes|$liveStrokes|$bakedStrokes|'
        '$widgetCount|$lod|$details|${_pendingDecode.length}|${_pageData.length}';
    final minGap = moving ? 700 : 2000;
    if (key == _lastLayerDecisionKey &&
        now.difference(_lastLayerDecisionLog).inMilliseconds < minGap) {
      return;
    }
    _lastLayerDecisionKey = key;
    _lastLayerDecisionLog = now;
    CrashLogger.instance.note(
      'PERF layer-cuaderno: $source, '
      'zoom ${_viewScale.toStringAsFixed(2)}, '
      'threshold ${_overviewThreshold.toStringAsFixed(2)}, '
      'overview ${_overviewActive ? 'SI' : 'no'}, '
      'gesture ${_viewGestureActive ? 'SI' : 'no'}, '
      'transform ${_viewTransformActive ? 'SI' : 'no'}, '
      'linger ${_overviewLinger ? 'SI' : 'no'}, '
      'pages visible $visiblePages cold $coldPages empty $emptyPages '
      'tiles $tilePages base $basePages focus $focusPages stale $stalePages, '
      'strokes live $liveStrokes baked $bakedStrokes delta $deltaStrokes, '
      'decoded ${_pageData.length}/${_pageBlockIds.length}, '
      'pending ${_pendingDecode.length}, widgets $widgetCount, lod $lod, '
      'rect ${visible.left.toStringAsFixed(1)},${visible.top.toStringAsFixed(1)},'
      '${visible.width.toStringAsFixed(1)}x${visible.height.toStringAsFixed(1)}, '
      'detail $details',
    );
  }

  Widget _buildNotebookStrokeLayer(Size viewport, Size canvasSize) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          // Pan/zoom, lasso phase, and any page-ink change (_inkTick).
          animation: Listenable.merge([_viewCtrl, _lassoPhaseTick, _inkTick]),
          builder: (_, _) {
            if (_viewportRasterActive ||
                (_zoomGestureActive && _zoomSnapshotImage != null)) {
              _overviewActive = false;
              final visible = _visibleRectFor(
                viewport,
              ).inflate(kStrokeTileSize);
              _logNotebookLayerDecision(
                _viewportRasterActive ? 'viewport-raster' : 'zoom-snapshot',
                visible: visible,
                visiblePages: 0,
                coldPages: 0,
                emptyPages: 0,
                tilePages: 0,
                basePages: 0,
                focusPages: 0,
                stalePages: 0,
                deltaStrokes: 0,
                liveStrokes: 0,
                bakedStrokes: 0,
                widgetCount: 0,
                lod: lodForScale(_viewScale),
                details:
                    'viewportRaster $_viewportRasterVersion zoomSnap ${_zoomSnapshotImage != null ? 'Y' : 'N'}',
              );
              return const SizedBox.shrink();
            }
            final visible = _visibleRectFor(viewport).inflate(kStrokeTileSize);
            final hiddenByPage = _hiddenStrokes();
            // Decimate stroke detail when zoomed out (dense tiles cheap to raster).
            final lod = lodForScale(_viewScale);
            // Show the cached per-page overview images instead of tiles when
            // zoomed out (or pinned through a zoom gesture); never during a lasso
            // gesture (the image can't hide the live selection).
            final inLasso =
                _lassoCtrl.phase == LassoPhase.moving ||
                _lassoCtrl.phase == LassoPhase.resizing ||
                _lassoCtrl.phase == LassoPhase.rotating;
            _overviewActive =
                !inLasso &&
                _overviewByPage.isNotEmpty &&
                (_viewScale < _overviewThreshold ||
                    _viewTransformActive ||
                    _overviewLinger ||
                    (_viewGestureActive && _overviewStickyThisGesture));

            // High-zoom chunk ring (pyramid L0): full-res world tiles composited
            // OVER the base, per-cell — base/focus + delta only in the holes (no
            // ready tile), tiles on top. The even-odd clip prevents doubling. On
            // any ink edit _chunkVersion bumps → curTiles empties → this branch
            // yields to the path below until the ring re-bakes. Stale pages also
            // fall through (the path below handles them). Dormant ≤ ~2.4x.
            if (_chunkEngaged) {
              _scheduleChunkPump(); // fill/follow the ring (also pre-loads at rest)
              if (_overviewActive) {
                var anyStale = false;
                final pageImage = <int, ui.Image>{};
                final pageBaked = <int, int>{};
                for (int i = 0; i < _pageBlockIds.length; i++) {
                  final bid = _pageBlockIds[i];
                  final top = _pageOffsetY(i);
                  final pageWorld = Rect.fromLTWH(
                    0,
                    top,
                    kNotebookPageWidth,
                    kNotebookPageHeight,
                  );
                  if (!pageWorld.overlaps(visible)) continue;
                  if (_overviewStalePages.contains(bid)) {
                    anyStale = true;
                    break;
                  }
                  final focusImg = _overviewFocusByPage[bid];
                  final img = focusImg ?? _overviewByPage[bid];
                  if (img != null) {
                    pageImage[bid] = img;
                    pageBaked[bid] =
                        focusImg != null
                            ? (_overviewFocusBakedCountByPage[bid] ?? 0)
                            : (_overviewBakedCountByPage[bid] ?? 0);
                  }
                }
                if (!anyStale) {
                  final curTiles = <(Rect, ui.Image)>[];
                  for (final t in _chunkTiles.values) {
                    if (t.version == _chunkVersion &&
                        t.worldRect.overlaps(visible)) {
                      curTiles.add((t.worldRect, t.image));
                    }
                  }
                  if (curTiles.isNotEmpty) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        painter: _NotebookChunkOverlayPainter(
                          pageBlockIds: _pageBlockIds,
                          pageData: _pageData,
                          pageImage: pageImage,
                          pageBaked: pageBaked,
                          tiles: curTiles,
                          visibleWorld: visible,
                        ),
                        size: canvasSize,
                      ),
                    );
                  }
                }
              }
            } else if (_chunkTiles.isNotEmpty) {
              _scheduleChunkPump(); // dropped below threshold → pump frees the ring
            }

            final tiles = <Widget>[];
            final pageDetails = <String>[];
            var visiblePages = 0;
            var coldPages = 0;
            var emptyPages = 0;
            var tilePages = 0;
            var basePages = 0;
            var focusPages = 0;
            var stalePages = 0;
            var deltaStrokes = 0;
            var liveStrokes = 0;
            var bakedStrokes = 0;
            for (int i = 0; i < _pageBlockIds.length; i++) {
              final bid = _pageBlockIds[i];
              final pageTop = _pageOffsetY(i);
              final pageWorld = Rect.fromLTWH(
                0,
                pageTop,
                kNotebookPageWidth,
                kNotebookPageHeight,
              );
              if (!pageWorld.overlaps(visible)) continue;
              visiblePages++;
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
              final data = _pageData[bid];
              final index = _pageTiles[bid];
              if (data == null) {
                coldPages++;
                if (pageDetails.length < 8) pageDetails.add('$i:cold');
                continue;
              }
              liveStrokes += data.strokes.length;
              if (index == null || index.isEmpty) {
                emptyPages++;
                if (pageDetails.length < 8) {
                  pageDetails.add('$i:empty live${data.strokes.length}');
                }
                continue;
              }

              Set<DrawingStroke>? hidden;
              final hi = hiddenByPage[i];
              if (hi != null && hi.isNotEmpty) {
                hidden = Set<DrawingStroke>.identity();
                for (final j in hi) {
                  if (j < data.strokes.length) hidden.add(data.strokes[j]);
                }
              }

              // Prefer the high-res focus image (crisp at the settled zoom);
              // fall back to the base image while a focus bakes / on fast pan.
              // A stale page (in-place edit pending re-bake) shows tiles instead,
              // so the edited ink never ghosts at its old spot.
              final pageOverviewOk =
                  _overviewActive && !_overviewStalePages.contains(bid);
              final focusImg =
                  pageOverviewOk ? _overviewFocusByPage[bid] : null;
              final pageImg =
                  focusImg ?? (pageOverviewOk ? _overviewByPage[bid] : null);
              final pageStale = _overviewStalePages.contains(bid);
              if (pageStale) stalePages++;
              if (pageImg != null) {
                if (focusImg != null) {
                  focusPages++;
                } else {
                  basePages++;
                }
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
                // Strokes drawn since the chosen image was baked → live on top,
                // full detail (the delta count must match the image shown).
                final bakedCount =
                    focusImg != null
                        ? (_overviewFocusBakedCountByPage[bid] ?? 0)
                        : (_overviewBakedCountByPage[bid] ?? 0);
                final baked = bakedCount.clamp(0, data.strokes.length).toInt();
                bakedStrokes += baked;
                final delta = data.strokes.length - baked;
                deltaStrokes += delta;
                if (pageDetails.length < 8) {
                  pageDetails.add(
                    '$i:${focusImg != null ? 'focus' : 'base'} '
                    'live${data.strokes.length}/b$baked/d$delta '
                    'stale${pageStale ? 'Y' : 'N'}',
                  );
                }
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
                tilePages++;
                if (pageDetails.length < 8) {
                  pageDetails.add(
                    '$i:tiles live${data.strokes.length} '
                    'stale${pageStale ? 'Y' : 'N'}',
                  );
                }
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
              _logNotebookLayerDecision(
                'fallback-painter',
                visible: visible,
                visiblePages: visiblePages,
                coldPages: coldPages,
                emptyPages: emptyPages,
                tilePages: tilePages,
                basePages: basePages,
                focusPages: focusPages,
                stalePages: stalePages,
                deltaStrokes: deltaStrokes,
                liveStrokes: liveStrokes,
                bakedStrokes: bakedStrokes,
                widgetCount: tiles.length,
                lod: lod,
                details: pageDetails.join(';'),
              );
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

            _logNotebookLayerDecision(
              _overviewActive ? 'mixed-overview' : 'tiles',
              visible: visible,
              visiblePages: visiblePages,
              coldPages: coldPages,
              emptyPages: emptyPages,
              tilePages: tilePages,
              basePages: basePages,
              focusPages: focusPages,
              stalePages: stalePages,
              deltaStrokes: deltaStrokes,
              liveStrokes: liveStrokes,
              bakedStrokes: bakedStrokes,
              widgetCount: tiles.length,
              lod: lod,
              details: pageDetails.join(';'),
            );
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
    if (_viewportRasterActive ||
        (_zoomGestureActive && _zoomSnapshotImage != null)) {
      return const SizedBox.shrink();
    }
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

  Widget _buildZoomSnapshotLayer(Size viewport) {
    final image = _zoomSnapshotImage;
    final snapshotSize = _zoomSnapshotSize;
    if (!_zoomGestureActive || image == null || snapshotSize == null) {
      return const SizedBox.shrink();
    }
    final scale = _zoomGestureScale;
    final dx = _zoomGestureCurrentFocal.dx - _zoomGestureStartFocal.dx * scale;
    final dy = _zoomGestureCurrentFocal.dy - _zoomGestureStartFocal.dy * scale;
    final transform =
        Matrix4.identity()
          ..setEntry(0, 0, scale)
          ..setEntry(1, 1, scale)
          ..setEntry(0, 3, dx)
          ..setEntry(1, 3, dy);
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: _zoomSnapshotBgColor,
          child: ClipRect(
            child: Transform(
              transform: transform,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: snapshotSize.width,
                  height: snapshotSize.height,
                  child: RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewportRasterLayer() {
    if (!_viewportRasterActive) return const SizedBox.shrink();
    final tiles =
        _viewportRasterTiles.values.toList()..sort((a, b) {
          final by = a.worldRect.top.compareTo(b.worldRect.top);
          return by != 0 ? by : a.worldRect.left.compareTo(b.worldRect.left);
        });
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final tile in tiles)
              Positioned.fromRect(
                rect: tile.worldRect,
                child: RawImage(
                  image: tile.image,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
          ],
        ),
      ),
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
                                final showingZoomSnapshot =
                                    _zoomGestureActive &&
                                    _zoomSnapshotImage != null;
                                final textBlockOverlays =
                                    showingZoomSnapshot
                                        ? const <Widget>[]
                                        : _buildTextBlockOverlays();
                                final taskBlockOverlays =
                                    showingZoomSnapshot
                                        ? const <Widget>[]
                                        : _buildTaskBlockOverlays();
                                final lassoActive =
                                    !showingZoomSnapshot &&
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
                                              onInteractionStart: (details) {
                                                // Pin the overview for the whole
                                                // gesture if it's showing, so
                                                // zooming in doesn't swap to tiles
                                                // mid-pinch.
                                                _zoomSnapshotTimer?.cancel();
                                                // A new gesture interrupts the prior
                                                // fling's settle watch (re-armed on this
                                                // gesture's end). The overview stays up
                                                // (_overviewLinger untouched) across the
                                                // chain so flick-pans never flash vector.
                                                _stopSettleWatch();
                                                _viewGestureActive = true;
                                                _viewMoved = false;
                                                _zoomGestureActive = false;
                                                _zoomGestureSeen = false;
                                                _zoomGestureScale = 1;
                                                _zoomGestureStartFocal =
                                                    details.localFocalPoint;
                                                _zoomGestureCurrentFocal =
                                                    details.localFocalPoint;
                                                _overviewStickyThisGesture =
                                                    _overviewActive;
                                                if (_activePointers.length >=
                                                        2 &&
                                                    _viewportRasterTiles
                                                        .isNotEmpty) {
                                                  if (mounted) setState(() {});
                                                } else if (_activePointers
                                                            .length >=
                                                        2 &&
                                                    _zoomSnapshotImage !=
                                                        null &&
                                                    _overviewByPage.isEmpty) {
                                                  _zoomGestureActive = true;
                                                  _zoomGestureSeen = true;
                                                  _zoomGestureTick.value++;
                                                  if (mounted) setState(() {});
                                                }
                                              },
                                              onInteractionUpdate: (details) {
                                                final zooming =
                                                    (details.scale - 1.0)
                                                        .abs() >
                                                    0.01;
                                                if (!_viewMoved &&
                                                    (zooming ||
                                                        details
                                                                .focalPointDelta
                                                                .distance >
                                                            0.5)) {
                                                  // First real pan/zoom frame:
                                                  // swap vectors for the overview
                                                  // raster (not a mere tap).
                                                  _viewMoved = true;
                                                  if (mounted) setState(() {});
                                                }
                                                final useSnapshot =
                                                    _zoomSnapshotImage !=
                                                        null &&
                                                    _viewportRasterTiles
                                                        .isEmpty &&
                                                    _overviewByPage.isEmpty &&
                                                    (_activePointers.length >=
                                                            2 ||
                                                        zooming);
                                                _zoomGestureScale =
                                                    details.scale;
                                                _zoomGestureCurrentFocal =
                                                    details.localFocalPoint;
                                                if (useSnapshot &&
                                                    !_zoomGestureSeen) {
                                                  _zoomGestureSeen = true;
                                                  _zoomGestureActive = true;
                                                  _zoomGestureTick.value++;
                                                  if (mounted) setState(() {});
                                                } else if (_zoomGestureActive) {
                                                  _zoomGestureTick.value++;
                                                }
                                              },
                                              onInteractionEnd: (_) {
                                                _viewGestureActive = false;
                                                _viewMoved = false;
                                                _zoomGestureActive = false;
                                                _zoomGestureSeen = false;
                                                _zoomGestureScale = 1;
                                                // Keep the overview up through the
                                                // ENTIRE fling — the settle Ticker drops
                                                // it back to crisp vector only when the
                                                // view truly stops (so the tile re-raster
                                                // never lands mid-motion) and bakes the
                                                // focus then too. Pyramid L0.
                                                _overviewLinger = true;
                                                _beginSettleWatch();
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
                                                    if (!showingZoomSnapshot)
                                                      ...textBlockOverlays,
                                                    _buildNotebookStrokeLayer(
                                                      viewport,
                                                      Size(
                                                        kNotebookPageWidth,
                                                        _totalCanvasHeight,
                                                      ),
                                                    ),
                                                    _buildViewportRasterLayer(),
                                                    if (!showingZoomSnapshot)
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
                                                    if (!showingZoomSnapshot)
                                                      ...taskBlockOverlays,
                                                    if (!showingZoomSnapshot)
                                                      _buildNotebookLassoLayer(
                                                        viewport,
                                                        Size(
                                                          kNotebookPageWidth,
                                                          _totalCanvasHeight,
                                                        ),
                                                        lassoStrokes,
                                                        lassoImages,
                                                      ),
                                                    if (!showingZoomSnapshot)
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
                                    AnimatedBuilder(
                                      animation: _zoomGestureTick,
                                      builder:
                                          (_, _) =>
                                              _buildZoomSnapshotLayer(viewport),
                                    ),
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
