import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, instantiateImageCodec;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart'
    show SchedulerBinding, FrameTiming, Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/crash_logger.dart';
import '../../providers/ai_providers.dart';
import '../../providers/note_providers.dart';
import '../../widgets/ai_link_badge.dart';
import '../../widgets/status_bar_flood.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/models/drawing_stroke_record.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import '../../../domain/repositories/drawing_stroke_repository.dart';
import 'background_paint.dart';
import 'background_popup.dart';
import 'color_picker.dart';
import 'color_loupe.dart';
import 'drawing_engine.dart';
import 'drawing_prefs.dart';
import 'drawing_stroke_persistence.dart';
import 'eraser_mode_popup.dart';
import 'floating_palettes.dart';
import 'fountain_pen_engine.dart';
import 'note_cell_model.dart';
import 'pinned_snapshots.dart';
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
import 'stroke_tiles.dart';
import 'stroke_stabilizer.dart';
import 'stroke_width_picker.dart';
import '../lab/lab_space_detail_screen.dart';

// World canvas size — large but finite to keep memory bounded. The user
// pans inside this via InteractiveViewer. ~10kx10k logical pixels.
const double _kCanvasW = 10000;
const double _kCanvasH = 10000;

typedef _WhiteboardSnapshot =
    (
      List<DrawingStroke>,
      List<CanvasImage>,
      List<CanvasTaskBlock>,
      List<CanvasTextBlock>,
    );

abstract class _WhiteboardHistoryEntry {
  const _WhiteboardHistoryEntry();
}

class _WhiteboardSnapshotEntry extends _WhiteboardHistoryEntry {
  final _WhiteboardSnapshot snapshot;

  const _WhiteboardSnapshotEntry(this.snapshot);
}

class _WhiteboardStrokeAddEntry extends _WhiteboardHistoryEntry {
  final DrawingStroke stroke;

  const _WhiteboardStrokeAddEntry(this.stroke);
}

/// Decode a whiteboard block's stored JSON into [DrawingData]. Pure and
/// top-level so it can run in a background isolate via [compute] — the parse +
/// object construction of a dense board is the "tirón al abrir", and doing it
/// off the UI thread keeps the first frame responsive. All fields are plain data
/// (numbers/strings/lists/enum), so the result ships across the isolate port.
DrawingData _decodeWhiteboardData(Map<String, dynamic> args) {
  List<dynamic> dec(String? s) {
    if (s == null) return const [];
    try {
      final decoded = jsonDecode(s);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  return DrawingData.fromJson({
    'h': _kCanvasH,
    's': dec(args['s'] as String?),
    'i': dec(args['i'] as String?),
    't': dec(args['t'] as String?),
    if (args['tx'] != null) 'tx': args['tx'],
    'bg': args['bg'],
    'bgc': args['bgc'],
  });
}

/// One world-anchored chunk tile baked at the exact current zoom (1:1 with the
/// screen → zero blur). [version] is bumped on every ink edit so a stale tile
/// (baked before the edit) is recognised and stops being shown.
class _WbChunkTile {
  final Rect worldRect;
  final int version;
  final ui.Image image;
  const _WbChunkTile(this.worldRect, this.version, this.image);
}

/// Composites the high-zoom overview when the chunk ring is engaged: per-cell,
/// the base overview (+ focus tile + post-bake delta strokes) fills only the
/// holes where no tile is ready (even-odd clip), then the full-res tiles draw on
/// top. The clip is what prevents the base and a tile drawing the same ink twice
/// (the "tint"/halo of a naive overlay). All in world coords (size = canvas).
class _WhiteboardChunkOverlayPainter extends CustomPainter {
  final ui.Image baseImage;
  final Rect baseBounds;
  final ui.Image? focusImage;
  final Rect? focusBounds;
  final List<DrawingStroke>? delta;
  final List<(Rect, ui.Image)> tiles; // current-version tiles (worldRect, image)
  final Rect visibleWorld;

  const _WhiteboardChunkOverlayPainter({
    required this.baseImage,
    required this.baseBounds,
    required this.focusImage,
    required this.focusBounds,
    required this.delta,
    required this.tiles,
    required this.visibleWorld,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium;
    // 1. Base + focus + delta, clipped to the holes (everything NOT under a tile).
    final hole = Path()..addRect(visibleWorld);
    for (final (r, _) in tiles) {
      hole.addRect(r);
    }
    hole.fillType = PathFillType.evenOdd;
    canvas.save();
    canvas.clipPath(hole);
    canvas.drawImageRect(
      baseImage,
      Rect.fromLTWH(
        0,
        0,
        baseImage.width.toDouble(),
        baseImage.height.toDouble(),
      ),
      baseBounds,
      paint,
    );
    final fImg = focusImage;
    final fBounds = focusBounds;
    if (fImg != null && fBounds != null) {
      canvas.drawImageRect(
        fImg,
        Rect.fromLTWH(0, 0, fImg.width.toDouble(), fImg.height.toDouble()),
        fBounds,
        paint,
      );
    }
    final d = delta;
    if (d != null) {
      for (final s in d) {
        drawStroke(canvas, s);
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
  bool shouldRepaint(covariant _WhiteboardChunkOverlayPainter old) => true;
}

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
  final Map<int, int> _loadedStrokePositions = {};
  final TransformationController _viewCtrl = TransformationController();
  int _paintVersion = 0;

  // ─── Zoomed-out overview ──────────────────────────────────────────────────
  // At deep zoom-out the tiled layer re-rasterizes thousands of strokes every
  // pan frame (raster cache doesn't hold under the gesture). Below
  // [_overviewThreshold] we show ONE cached downsampled image of all the ink
  // instead — the GPU just blits a texture. The image is strokes-only
  // (transparent), composited over the live paper layer, so the swap is
  // invisible. Strokes drawn after the last bake render live on top (the delta)
  // so editing while zoomed out still shows instantly; a debounced re-bake folds
  // them in. Tiles are the fallback whenever the image isn't ready or a lasso
  // gesture needs per-stroke hiding.
  ui.Image? _overviewImage;
  Rect? _overviewBounds;
  double _overviewThreshold = 0; // show overview when _viewScale < this
  int _overviewBakedCount = 0; // strokes already in the image
  bool _overviewBaking = false;
  bool _overviewBakePending = false;
  // The baked image is valid only for an append-only history (the delta draws
  // the un-baked tail live). A move/resize/rotate (count unchanged) or
  // erase/delete (count shrank) mutates already-baked strokes → the image is
  // stale and the delta can't fix it → fall to tiles until the re-bake, else the
  // edited ink ghosts at its OLD spot for a frame on release. Set in _persist,
  // cleared when _bakeOverview produces a fresh image.
  bool _overviewDirty = false;
  Timer? _overviewTimer;
  ui.Image? _zoomSnapshotImage;
  Size? _zoomSnapshotSize;
  Timer? _zoomSnapshotTimer;
  bool _zoomSnapshotBaking = false;
  bool _zoomSnapshotPending = false;
  bool _zoomGestureActive = false;
  bool _zoomGestureSeen = false;
  double _zoomGestureScale = 1;
  final Offset _zoomGestureStartFocal = Offset.zero;
  Offset _zoomGestureCurrentFocal = Offset.zero;
  // True while a 2-finger pan/zoom is in flight. The overview stays up for the
  // WHOLE gesture (even past its crisp threshold) and only hands back to the
  // crisp tiles when the gesture ENDS — otherwise crossing the threshold while
  // zooming in re-rasterizes tiles mid-pinch and janks. Zooming OUT still flips
  // to the overview the instant it crosses the threshold (it's cheap).
  bool _viewGestureActive = false;
  // True once a view-transform gesture actually moved the canvas (vs a bare
  // touch) → distinguishes a real pan from a tap so the overview doesn't flash in
  // on every finger-down. Mirrors the notebook (the validated reference).
  bool _viewMoved = false;
  // The overview stays mounted from gesture-end through the WHOLE fling; the
  // settle Ticker drops it back to crisp tiles only when the view truly stops, so
  // the tile re-raster never lands mid-motion. A fixed timer was wrong (the fling
  // outlasts it → re-raster while still moving = visible stutter).
  bool _overviewLinger = false;
  // Per-frame matrix poll to detect the true stop (incl. the fling tail). The
  // controller's change notifications proved unreliable through the fling.
  Ticker? _settleTicker;
  Matrix4? _lastSettleMatrix;
  int _settleStillFrames = 0;
  static const int _settleStillFramesNeeded = 12; // ~200ms at 60fps
  // ─── Pyramid Level 0: viewport-region FOCUS tile ──────────────────────────
  // The base overview above is ONE whole-board image at low density (crisp only
  // zoomed out). Panning zoomed-in over it looks blurry — and since the zoom is
  // fixed during a pan, the blur is constant and obvious. The focus tile fixes
  // that: a high-res raster of just the visible region (+ overscan), culled to
  // the strokes there and baked at the settled zoom, layered over the base. The
  // infinite canvas has no pages, so it's a viewport tile (not per-page); panning
  // past it falls back to the blurry base until the next settle re-bakes. RAM
  // only; dropped when zoomed back out or on edit.
  ui.Image? _focusImage;
  Rect? _focusBounds;
  double _focusScale = 0;
  int _focusBakedCount = 0;
  bool _focusBaking = false;
  static const double _focusMaxDim = 4096.0;
  // ── Chunk tile ring (pyramid L0, dynamic) ──────────────────────────────────
  // The single focus tile above tops out: on a viewport wider than ~2048/dpr its
  // overscan region can't be baked at full screen density, so panning zoomed-in
  // softens. This is a Minecraft-style ring of WORLD-anchored raster tiles baked
  // at the EXACT current zoom (1:1 with the screen → zero blur), generated at the
  // leading edge and freed behind as you pan, with the base overview (+ focus) as
  // fallback (never a white hole). Tiles are ink-only and bake with the very same
  // drawStroke path as base/focus, so tile↔base edges match chromatically. Purely
  // additive; _tilesEnabled=false reverts to exactly today's behaviour. Mirrors
  // the validated notebook implementation; the page loop becomes a strokeBounds
  // cull (infinite canvas, no pages).
  final Map<String, _WbChunkTile> _chunkTiles = {};
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

  // ─── Heat / pan-zoom frame timing (temporary diagnostics) ─────────────────
  // True when the last stroke-layer build fell back to the single uncached
  // painter (zoomed out past the tile budget) — the suspected heat source.
  bool _strokeFallbackActive = false;
  bool _overviewActive = false;
  int _slowFrames = 0;
  double _worstFrameMs = 0, _worstBuildMs = 0, _worstRasterMs = 0;
  DateTime _lastFrameLog = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLayerDecisionLog = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLayerDecisionKey = '';

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000.0;
      final r = t.rasterDuration.inMicroseconds / 1000.0;
      final tot = b + r;
      if (tot <= 24) continue; // ignore frames that hit the budget
      _slowFrames++;
      if (tot > _worstFrameMs) {
        _worstFrameMs = tot;
        _worstBuildMs = b;
        _worstRasterMs = r;
      }
    }
    final now = DateTime.now();
    if (_slowFrames > 0 && now.difference(_lastFrameLog).inMilliseconds > 700) {
      _lastFrameLog = now;
      CrashLogger.instance.note(
        'PERF frames-pizarra: $_slowFrames lentos, peor ${_worstFrameMs.round()}ms '
        '(build ${_worstBuildMs.round()} + raster ${_worstRasterMs.round()}), '
        'zoom ${_viewScale.toStringAsFixed(2)}, '
        'fallback ${_strokeFallbackActive ? 'SI' : 'no'}, '
        'overview ${_overviewActive ? 'SI' : 'no'}, '
        'dirty ${_overviewDirty ? 'SI' : 'no'}, '
        'trazos ${_data.strokes.length}',
      );
      _slowFrames = 0;
      _worstFrameMs = 0;
      _worstBuildMs = 0;
      _worstRasterMs = 0;
    }
  }

  void _logWhiteboardLayerDecision(
    String source, {
    required Rect renderRect,
    required int tileCount,
    required bool inGesture,
    required bool hydrationActive,
    required bool canOverview,
    required int lod,
    int delta = 0,
  }) {
    final now = DateTime.now();
    final moving =
        _viewGestureActive ||
        _viewTransformActive ||
        _overviewLinger ||
        _activePointers.isNotEmpty;
    final focusReady = _focusImage != null && _focusBounds != null;
    final key =
        '$source|${_data.strokes.length}|$_overviewBakedCount|$_overviewDirty|'
        '$hydrationActive|$tileCount|${_viewScale.toStringAsFixed(2)}|'
        '$_strokeFallbackActive|$_overviewActive|$delta|$focusReady|'
        '$_focusBakedCount|$inGesture|$canOverview|$lod';
    final minGap = moving ? 700 : 2000;
    if (key == _lastLayerDecisionKey &&
        now.difference(_lastLayerDecisionLog).inMilliseconds < minGap) {
      return;
    }
    _lastLayerDecisionKey = key;
    _lastLayerDecisionLog = now;
    CrashLogger.instance.note(
      'PERF layer-pizarra: $source, '
      'live ${_data.strokes.length}, baked $_overviewBakedCount, '
      'delta $delta, dirty ${_overviewDirty ? 'SI' : 'no'}, '
      'hydrate ${hydrationActive ? 'SI' : 'no'}, '
      'canOverview ${canOverview ? 'SI' : 'no'}, '
      'overview ${_overviewActive ? 'SI' : 'no'}, '
      'fallback ${_strokeFallbackActive ? 'SI' : 'no'}, '
      'tiles $tileCount/${_strokeTiles.debugTileCount}/${_strokeTiles.debugEntryCount}, '
      'zoom ${_viewScale.toStringAsFixed(2)}, '
      'threshold ${_overviewThreshold.toStringAsFixed(2)}, '
      'focus ${focusReady ? 'SI' : 'no'}/$_focusBakedCount, '
      'lasso ${_lassoCtrl.phase.name}, lod $lod, '
      'rect ${renderRect.left.toStringAsFixed(1)},${renderRect.top.toStringAsFixed(1)},'
      '${renderRect.width.toStringAsFixed(1)}x${renderRect.height.toStringAsFixed(1)}',
    );
  }

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
  bool _floatingToolbarsPopupOpen = false;
  Offset? _eraserCursor; // screen pos for the eraser indicator
  // Raw (un-stabilized) pen points — used for scribble-erase detection so the
  // stabilizer's smoothing doesn't hide the zigzags.
  StrokePoints _rawPen = StrokePoints();
  // Post-snap live adjust state.
  ShapeKind? _snapKind;
  List<List<double>>? _snapBasePoints;
  Offset? _snapCenter;
  Offset? _snapAnchor;
  double _snapRefDist = 1;
  final List<_WhiteboardHistoryEntry> _undoStack = [];
  final List<_WhiteboardHistoryEntry> _redoStack = [];
  _WhiteboardSnapshot? _gestureBefore;
  // World-space bounding box of the selection at the moment a move/resize/rotate
  // grab started — unioned with the post-gesture box to invalidate only the
  // tiles the edit actually touched (vs. nuking the whole tile cache).
  Rect? _gestureRegionBefore;
  bool _gestureChanged = false;
  DrawingStroke? _active;
  Stopwatch? _inkPerfSw;
  int _inkMoveSamples = 0;
  int _inkSlowMoves = 0;
  int _inkWorstMoveUs = 0;
  // Ticked on every live point added to [_active]. Repaints only the active
  // stroke layer (its own RepaintBoundary) without a full-canvas setState, so
  // the wet stroke keeps up with the stylus instead of trailing it.
  final ValueNotifier<int> _activeTick = ValueNotifier(0);
  final StrokeTileIndex _strokeTiles = StrokeTileIndex();
  // Repaints only the lasso overlay during a continuous gesture (move/resize/
  // rotate/trace) so it follows the pointer immediately without a tree setState.
  final ValueNotifier<int> _lassoGestureTick = ValueNotifier(0);
  // Bumped on a grab/release (selected ↔ gesture) so the ink layers + toolbar
  // update their phase-dependent bits WITHOUT a full-tree setState — the latter
  // rebuilds every page/overlay/provider and is the jank (and crash risk on
  // big notes) felt at the moment you grab or drop a selection.
  final ValueNotifier<int> _lassoPhaseTick = ValueNotifier(0);
  Timer? _holdTimer;
  Timer? _persistTimer;
  bool _persistDirty = false;
  bool _persisting = false;
  bool _strokesNeedFullPersist = false;

  // ─── Incremental stroke persistence ───────────────────────────────────────
  // The stroke list is mirrored into the drawing_strokes table one row per
  // stroke, edited surgically: pen-up = 1 INSERT, geometry edit = UPDATE of the
  // touched rows, erase/lasso-delete = DELETE of the gone rows. This replaces
  // the old "rewrite the whole block" path (O(N) per edit) — see
  // [[ink-persistence-refactor]].
  //
  //  • _persistedStrokeIds: dbIds currently materialized in the table for this
  //    block. Diffed against the live strokes at persist time to find deletes.
  //  • _dirtyStrokeIds: dbIds whose geometry changed in place (move/resize/
  //    rotate/flip/color/width) and need an UPDATE.
  //  • _nextStrokePos: monotonic z-order position for freshly inserted rows
  //    (never reused after deletes, so order survives reload).
  final Set<int> _persistedStrokeIds = {};
  final Set<int> _dirtyStrokeIds = {};
  int _nextStrokePos = 0;
  Offset? _holdAnchor;
  static const _holdTolerance2 = 400.0; // 20px squared
  late final List<Color> _palette;
  final LassoController _lassoCtrl = LassoController();
  late final AnimationController _lassoAnimCtrl;
  LassoPhase _lastLassoPhase = LassoPhase.idle;
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

  // Pinned snapshots (PiN): frozen raster cut-outs that float over the canvas.
  // Held in a process-level store keyed by note, so they survive leaving and
  // re-entering the note; only an app kill (or closing a window) drops them.
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

  // Multi-finger tap tracking
  int _maxSimultaneous = 0;
  bool _multiFingerMoved = false;
  DateTime? _multiFingerDownTime;
  final Map<int, Offset> _pointerDownPos = {};

  void _markCanvasDirty() {
    _paintVersion++;
    _renderRect = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();
    _palette = buildPenPalette(widget.note.color ?? widget.folder.color);
    _lassoAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
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
            // Bump paintVersion: the background _CanvasPainter (which draws
            // images) only repaints when paintVersion/visibleRect change, so a
            // bare setState wouldn't show a freshly decoded image.
            if (mounted) setState(() => _paintVersion++);
          },
        );
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanvasBlock());
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
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
    final dpr = _dpr;
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
  /// over the canvas. Captures EVERYTHING under the selection (paper, ink,
  /// images, blocks) — same boundary the eyedropper samples.
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

    // Drop the lasso overlay so its box/handles aren't baked into the capture.
    _lassoCtrl.deselect();
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final boundary =
        _canvasBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final dpr = _dpr;
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
      _locked = _lockBeforeEyedropper;
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
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _overviewTimer?.cancel();
    _overviewImage?.dispose();
    _settleTicker?.dispose();
    _focusImage?.dispose();
    for (final t in _chunkTiles.values) {
      t.image.dispose();
    }
    _chunkTiles.clear();
    _zoomSnapshotTimer?.cancel();
    _zoomSnapshotImage?.dispose();
    _eyedropImg?.dispose();
    // Pins live in the process-level store — do NOT dispose them here, or they'd
    // vanish on navigation. They're freed on close (X) or app kill.
    _reconcileImageFiles();
    _holdTimer?.cancel();
    _persistTimer?.cancel();
    if (_persistDirty) unawaited(_persistNow());
    _strokeTiles.dispose();
    _pasteTimer?.cancel();
    _lassoAnimCtrl.dispose();
    _imgCache?.dispose();
    _viewCtrl.dispose();
    _activeTick.dispose();
    _lassoGestureTick.dispose();
    _lassoPhaseTick.dispose();
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
    final snapPts = _rawPen.isNotEmpty ? _rawPen : _active!.points;
    if (isScribble(snapPts, viewScale: _viewScale)) {
      return false;
    }
    final shape = ShapeRecognizer.detect(_active!.points.toNested());
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

  bool _canSnapHeldShape(ShapeKind kind, StrokePoints points) {
    if (kind == ShapeKind.line || kind == ShapeKind.arrow) return true;
    if (!shapeKindIsClosed(kind) && kind != ShapeKind.pentagram) return true;
    final bounds = scribbleBounds(points);
    final diag2 = bounds.width * bounds.width + bounds.height * bounds.height;
    if (diag2 <= 0) return false;
    final start = Offset(points.firstX, points.firstY);
    final end = Offset(points.lastX, points.lastY);
    final dist2 = (start - end).distanceSquared;
    return dist2 / diag2 <= 0.09;
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
      _snapRefDist =
          (Offset(src.points.lastX, src.points.lastY) - _snapCenter!).distance
              .clamp(1.0, 1e9);
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: src.colorValue,
        strokeWidth: src.strokeWidth,
        filled: _fillShapes && shapeKindIsClosed(shape.kind),
        isShape: true,
        isHighlighter: src.isHighlighter,
        points: StrokePoints.fromNested(pts),
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
        points: StrokePoints.fromNested(pts),
      );
    });
  }

  void _commitShapeAdjust() {
    final sw = Stopwatch()..start();
    final shape = _active;
    _clearSnap();
    if (shape == null) return;
    final snapSw = Stopwatch()..start();
    final before = _snapshot();
    snapSw.stop();
    setState(() {
      _data.strokes.add(shape);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _strokeTiles.append(shape);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitSnapshot(before);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persist();
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'shape-snap',
      shape,
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

  Future<void> _ensureCanvasBlock() async {
    try {
      final repo = ref.read(noteBlockRepositoryProvider);
      final blocks = await repo.getByNote(widget.note.id);
      final existing = blocks.whereType<DrawingBlock>().firstOrNull;
      final canvas =
          existing ??
          await repo.insertAtEnd(
                widget.note.id,
                NoteBlockType.drawing,
                payload: {'h': _kCanvasH, 's': [], 'whiteboard': true},
              )
              as DrawingBlock;
      if (!mounted) return;
      final id = canvas.id;
      CrashLogger.instance.note(
        'PERF abrir-pizarra: note ${widget.note.id}, block $id '
        '(${existing == null ? 'CREADO nuevo' : 'encontrado'}), '
        '${blocks.length} bloques en la nota',
      );
      final data = await _decodeData(canvas);
      if (!mounted) return;
      setState(() {
        _blockId = id;
        _data = data;
        _persistedStrokeIds.clear();
        _dirtyStrokeIds.clear();
        _loadedStrokePositions.clear();
      });
      _strokeTiles.rebuild(_data.strokes);
      _scheduleOverviewBake();
    } catch (e, st) {
      // A silent throw here leaves _blockId null → empty board, default bg,
      // corner view, and NO persistence. Surface it instead of losing data.
      CrashLogger.instance.record(e, st, context: 'ensureCanvasBlock pizarra');
    }
  }

  void _mergeLoadedStrokeRows(
    List<DrawingStrokeRecord> rows,
    Rect keepRegion, {
    bool evict = true,
  }) {
    final byId = <int, DrawingStroke>{
      for (final s in _data.strokes)
        if (s.dbId != null) s.dbId!: s,
    };
    for (final r in rows) {
      _loadedStrokePositions[r.id] = r.position;
      _persistedStrokeIds.add(r.id);
      if (_dirtyStrokeIds.contains(r.id)) continue;
      final existing = byId[r.id];
      if (existing != null) continue;
      final stroke = strokeFromRecord(r);
      _data.strokes.add(stroke);
      byId[r.id] = stroke;
    }
    final canEvict =
        _undoStack.isEmpty &&
        _redoStack.isEmpty &&
        _lassoCtrl.phase == LassoPhase.idle &&
        !_isDrawing &&
        !_persistDirty &&
        !_persisting;
    if (evict && canEvict) {
      _data.strokes.removeWhere((stroke) {
        final id = stroke.dbId;
        if (id == null || _dirtyStrokeIds.contains(id)) return false;
        if (strokeBounds(stroke).overlaps(keepRegion)) return false;
        _persistedStrokeIds.remove(id);
        _loadedStrokePositions.remove(id);
        return true;
      });
    }
    _data.strokes.sort((a, b) {
      final ap =
          a.dbId == null ? _nextStrokePos : _loadedStrokePositions[a.dbId] ?? 0;
      final bp =
          b.dbId == null ? _nextStrokePos : _loadedStrokePositions[b.dbId] ?? 0;
      return ap.compareTo(bp);
    });
  }

  Future<void> _ensureStrokesLoadedForRegion(Rect region) async {
    final blockId = _blockId;
    if (blockId == null) return;
    final sw = Stopwatch()..start();
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    final rows = await strokeRepo.getByBlockBounds(
      blockId,
      _boundsFromRect(region),
    );
    if (!mounted || _blockId != blockId) return;
    _mergeLoadedStrokeRows(rows, region, evict: false);
    if (rows.isNotEmpty) {
      _overviewDirty = true;
      _disposeFocus();
      _scheduleOverviewBake();
    }
    _strokeTiles.rebuild(_data.strokes);
    setState(() => _paintVersion++);
    sw.stop();
    CrashLogger.instance.note(
      'PERF hydrate-region-pizarra: ${rows.length} query, '
      '${_data.strokes.length} live, ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> _ensureAllStrokesLoadedForGlobalOp() async {
    final blockId = _blockId;
    if (blockId == null) return;
    final sw = Stopwatch()..start();
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    const batchSize = 600;
    var afterPosition = -1;
    var batches = 0;
    var rowsRead = 0;
    while (mounted && _blockId == blockId) {
      final rows = await strokeRepo.getByBlockAfterPosition(
        blockId,
        afterPosition: afterPosition,
        limit: batchSize,
      );
      if (rows.isEmpty) break;
      _mergeLoadedStrokeRows(
        rows,
        const Rect.fromLTRB(-1e12, -1e12, 1e12, 1e12),
        evict: false,
      );
      afterPosition = rows.last.position;
      rowsRead += rows.length;
      batches++;
      await SchedulerBinding.instance.endOfFrame;
    }
    if (!mounted || _blockId != blockId) return;
    if (rowsRead > 0) {
      _overviewDirty = true;
      _disposeFocus();
      _scheduleOverviewBake();
    }
    _strokeTiles.rebuild(_data.strokes);
    setState(() => _paintVersion++);
    sw.stop();
    CrashLogger.instance.note(
      'PERF hydrate-all-pizarra: $rowsRead query, '
      '${_data.strokes.length} live, $batches batches, '
      '${sw.elapsedMilliseconds}ms',
    );
  }

  // ignore: unused_element
  Future<DrawingData> _decodeData(
    DrawingBlock b, [
    DrawingStrokeRepository? strokeRepo,
  ]) async {
    final payload = b.payloadJson();
    final args = <String, dynamic>{
      's': b.strokesJson,
      'i': b.imagesJson,
      't': b.taskBlocksJson,
      if (payload['tx'] != null) 'tx': payload['tx'],
      'bg': payload['bg'],
      'bgc': payload['bgc'],
    };
    final sw = Stopwatch()..start();
    final jsonBytes = b.strokesJson.length;
    // Decode INLINE (no compute/isolate). The payload no longer carries strokes
    // — they live in the drawing_strokes table — so this is a trivial decode of
    // background/images/blocks. compute() was spawning an isolate that could
    // HANG on device, leaving _decodeData (and thus _blockId/_data) never set →
    // no persistence + corner view. See [[ink-persistence-refactor]].
    final data = _decodeWhiteboardData(args);
    final rows =
        strokeRepo == null
            ? await ref.read(drawingStrokeRepositoryProvider).getByBlock(b.id)
            : await strokeRepo.getByBlock(b.id);
    _persistedStrokeIds.clear();
    _dirtyStrokeIds.clear();
    if (rows.isNotEmpty) {
      data.strokes = rows.map(strokeFromRecord).toList();
      var maxPos = -1;
      for (final r in rows) {
        _persistedStrokeIds.add(r.id);
        if (r.position > maxPos) maxPos = r.position;
      }
      _nextStrokePos = maxPos + 1;
    } else {
      // Legacy payload strokes (not yet in the table) carry no dbId and get
      // inserted on the first persist; positions start fresh.
      _nextStrokePos = 0;
    }
    sw.stop();
    final pts = data.strokes.fold<int>(0, (a, s) => a + s.points.length);
    CrashLogger.instance.note(
      'PERF abrir-pizarra: ${data.strokes.length} trazos, $pts puntos, '
      'json ${(jsonBytes / 1024).round()}KB, decode ${sw.elapsedMilliseconds}ms',
    );
    return data;
  }

  Future<void> _persistNow() async {
    if (_blockId == null) return;
    // Guard against overlapping runs: a debounce can fire while a previous
    // persist is still awaiting. The straggler re-runs once this pass finishes.
    if (_persisting) {
      _persistDirty = true;
      return;
    }
    _persisting = true;
    _persistDirty = false;
    final blockId = _blockId!;
    // Capture repos BEFORE any await. _persistNow also runs from dispose() (the
    // exit flush): touching `ref` after an await on a disposed widget throws and
    // silently drops the save — which was wiping the board on close.
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    final blockRepo = ref.read(noteBlockRepositoryProvider);
    final sw = Stopwatch()..start();
    int inserted = 0, updated = 0, deleted = 0;
    final fullPersist = _strokesNeedFullPersist;
    if (fullPersist) _strokesNeedFullPersist = false;
    final Set<int> dirtyBeforeFull =
        fullPersist ? _dirtyStrokeIds.toSet() : <int>{};
    if (fullPersist) _dirtyStrokeIds.clear();
    final removedDirtyIds = <int>{};
    final strokesSnapshot = List<DrawingStroke>.of(_data.strokes);
    final imagesPayload = _data.images.map((im) => im.toJson()).toList();
    final taskBlocksPayload = _data.taskBlocks.map((b) => b.toJson()).toList();
    final textBlocksPayload = _data.textBlocks.map((b) => b.toJson()).toList();
    final background = _data.background;
    final bgColorValue = _data.bgColorValue;
    var failed = false;
    try {
      if (fullPersist) {
        // Order changed wholesale (undo/redo/clear) — cheapest to rewrite and
        // reseat ids/positions. Rare path.
        final ids = await strokeRepo.replaceBlock(blockId, [
          for (int i = 0; i < strokesSnapshot.length; i++)
            strokeWrite(i, strokesSnapshot[i]),
        ]);
        for (int i = 0; i < strokesSnapshot.length && i < ids.length; i++) {
          strokesSnapshot[i].dbId = ids[i];
          final liveIndex = _data.strokes.indexOf(strokesSnapshot[i]);
          if (liveIndex >= 0 && liveIndex < _data.strokes.length) {
            _data.strokes[liveIndex].dbId = ids[i];
          }
          _loadedStrokePositions[ids[i]] = i;
        }
        _persistedStrokeIds
          ..clear()
          ..addAll(ids);
        _nextStrokePos = strokesSnapshot.length;
      } else {
        // 1) Inserts: strokes with no dbId yet (pen-up, duplicate, paste, split).
        final insertStrokes = <DrawingStroke>[];
        final insertWrites = <DrawingStrokeWrite>[];
        final insertPositions = <int>[];
        for (final stroke in strokesSnapshot) {
          if (stroke.dbId != null &&
              _persistedStrokeIds.contains(stroke.dbId)) {
            continue;
          }
          stroke.dbId = null;
          final pos = _nextStrokePos++;
          insertStrokes.add(stroke);
          insertWrites.add(strokeWrite(pos, stroke));
          insertPositions.add(pos);
        }
        final ids = await strokeRepo.insertMany(blockId, insertWrites);
        for (int i = 0; i < ids.length && i < insertStrokes.length; i++) {
          final stroke = insertStrokes[i];
          final id = ids[i];
          stroke.dbId = id;
          _persistedStrokeIds.add(id);
          _loadedStrokePositions[id] = insertPositions[i];
        }
        inserted = ids.length;
        // 2) Updates: in-place geometry edits flagged dirty.
        if (_dirtyStrokeIds.isNotEmpty) {
          final byId = <int, DrawingStroke>{
            for (final s in strokesSnapshot)
              if (s.dbId != null) s.dbId!: s,
          };
          final dirtyIds = _dirtyStrokeIds.toSet();
          final updates = <int, DrawingStrokeWrite>{};
          for (final id in dirtyIds) {
            final s = byId[id];
            if (s == null) continue;
            updates[id] = strokeWrite(0, s);
          }
          removedDirtyIds.addAll(dirtyIds);
          _dirtyStrokeIds.removeAll(dirtyIds);
          await strokeRepo.updateMany(updates);
          updated = updates.length;
        }
        // 3) Deletes: rows whose stroke is gone (erase, lasso-delete).
        final currentIds = <int>{
          for (final s in strokesSnapshot)
            if (s.dbId != null) s.dbId!,
        };
        final toDelete = _persistedStrokeIds.difference(currentIds);
        if (toDelete.isNotEmpty) {
          await strokeRepo.deleteByIds(toDelete.toList());
          _persistedStrokeIds.removeAll(toDelete);
          for (final id in toDelete) {
            _loadedStrokePositions.remove(id);
          }
          deleted = toDelete.length;
        }
      }
      final strokeMs = sw.elapsedMilliseconds;
      await blockRepo.updatePayload(blockId, {
        'h': _kCanvasH,
        's': const [],
        'i': imagesPayload,
        't': taskBlocksPayload,
        'tx': textBlocksPayload,
        'bg': background.toDbString(),
        if (bgColorValue != null) 'bgc': bgColorValue,
        'whiteboard': true,
      });
      final dbStats = await strokeRepo.debugStatsByBlock(blockId);
      final memPoints = _pointCount(strokesSnapshot);
      final livePoints = _pointCount(_data.strokes);
      sw.stop();
      CrashLogger.instance.note(
        'PERF guardar-pizarra: ${strokesSnapshot.length} trazos, '
        '$memPoints puntos, live ${_data.strokes.length}/$livePoints, '
        '+$inserted ~$updated -$deleted, '
        'db ${dbStats.count} trazos/${dbStats.points} puntos/maxPos ${dbStats.maxPosition ?? -1}, '
        'strokesDB ${strokeMs}ms, total(+DB) ${sw.elapsedMilliseconds}ms',
      );
      if (dbStats.count != strokesSnapshot.length ||
          dbStats.points != memPoints) {
        CrashLogger.instance.note(
          'WARN persist-pizarra-mismatch: block $blockId, '
          'mem ${strokesSnapshot.length}/$memPoints vs '
          'db ${dbStats.count}/${dbStats.points}, '
          'live ${_data.strokes.length}/$livePoints, '
          '+$inserted ~$updated -$deleted',
        );
      }
    } catch (e, st) {
      failed = true;
      _persistDirty = true;
      if (fullPersist) {
        _strokesNeedFullPersist = true;
        _dirtyStrokeIds.addAll(dirtyBeforeFull);
      }
      _dirtyStrokeIds.addAll(removedDirtyIds);
      // unawaited() callers swallow errors → a failed save was invisible. Log it.
      CrashLogger.instance.record(e, st, context: 'persistNow pizarra');
    } finally {
      _persisting = false;
    }
    // Edits that arrived mid-persist (or a guarded straggler) → flush once more.
    if (_persistDirty && mounted && !failed) unawaited(_persistNow());
  }

  void _persist() {
    _persistDirty = true;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      unawaited(_persistNow());
    });
    // Ink changed → the zoomed-out overview image is stale; re-bake once settled.
    _scheduleOverviewBake();
    // In-place edit (move/resize/rotate = same count, erase/delete = fewer) →
    // the baked image's prefix changed and the append-only delta can't fix it.
    // Mark dirty so the overview steps aside for tiles until the re-bake lands.
    if (_data.strokes.length <= _overviewBakedCount) _overviewDirty = true;
    // The focus tile has the OLD strokes baked in → drop it (erase/lasso would
    // ghost). Falls back to base+delta; re-bakes on the next settle.
    _disposeFocus();
    // Same for the chunk ring: bump the version so the now-stale tiles stop being
    // shown (curTiles filters by version → the overlay yields to base+delta) and
    // re-bake at the new state on the next pump.
    _chunkVersion++;
    _scheduleChunkPump();
  }

  int _pointCount(Iterable<DrawingStroke> strokes) =>
      strokes.fold<int>(0, (total, s) => total + s.points.length);

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
    required int finishMs,
    int? appendMs,
    int? historyMs,
    int? persistMs,
    int? snapshotMs,
  }) {
    final countSw = Stopwatch()..start();
    final totalPoints = _pointCount(_data.strokes);
    countSw.stop();
    final totalMs = _inkPerfSw?.elapsedMilliseconds ?? finishMs;
    CrashLogger.instance.note(
      'PERF escribir-pizarra: $kind, trazo ${stroke.points.length} puntos, '
      'total ${_data.strokes.length} trazos/$totalPoints puntos, '
      'moves $_inkMoveSamples, slowMoves $_inkSlowMoves, '
      'worstMove ${(_inkWorstMoveUs / 1000).toStringAsFixed(1)}ms, '
      'total ${totalMs}ms, finish ${finishMs}ms, '
      'snapshot ${snapshotMs ?? -1}ms, append ${appendMs ?? -1}ms, '
      'history ${historyMs ?? -1}ms, persist-schedule ${persistMs ?? -1}ms, '
      'count ${countSw.elapsedMilliseconds}ms',
    );
    _resetInkPerf();
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
      // Bump paintVersion so the background painter repaints with the new image
      // (it keys off paintVersion, not the images list) — otherwise it shows up
      // only after a pan/lasso forces a repaint.
      setState(() {
        _data.images.add(img);
        _paintVersion++;
      });
      _commitSnapshot(before);
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
    _commitSnapshot(before);
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
    _commitSnapshot(before);
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
    _commitSnapshot(before);
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
        _floatingToolbarsPopupOpen = false;
        _colorPickerOpen = false;
        _widthPickerOpen = false;
        _imagePanelOpen = false;
        _bgPopupOpen = false;
        _eraserPopupOpen = false;
        _shapePopupOpen = false;
      }
    });
  }

  void _toggleFloatingToolbarsPopup() {
    setState(() {
      _floatingToolbarsPopupOpen = !_floatingToolbarsPopupOpen;
      if (_floatingToolbarsPopupOpen) {
        _morePopupOpen = false;
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
      points: StrokePoints.fromNested(
        buildShape(kind, center.dx, center.dy, size, size),
      ),
    );
    final before = _snapshot();
    setState(() {
      _data.strokes.add(stroke);
      _tool = DrawTool.lasso;
      _shapePopupOpen = false;
      _toolbarVisible = false;
    });
    // Index the shape (same instance) so the tiled layer paints it immediately;
    // without this it's invisible until a lasso edit invalidates the region.
    _strokeTiles.append(stroke);
    final idx = _data.strokes.length - 1;
    _lassoCtrl.hitScale = _viewScale;
    _lassoCtrl.selectRange(_data.strokes, idx, idx + 1);
    _commitSnapshot(before);
    _persist();
    HapticFeedback.lightImpact();
  }

  double get _viewScale => _viewCtrl.value.getMaxScaleOnAxis();

  void _syncLassoTicker() {
    final shouldRun =
        _lassoCtrl.phase == LassoPhase.tracing ||
        _kLassoGesturePhases.contains(_lassoCtrl.phase);
    if (shouldRun) {
      if (!_lassoAnimCtrl.isAnimating) _lassoAnimCtrl.repeat();
      return;
    }
    if (_lassoAnimCtrl.isAnimating) _lassoAnimCtrl.stop();
    if (_lassoAnimCtrl.value != 0) _lassoAnimCtrl.value = 0;
  }

  /// Lasso change callback. During a continuous gesture (tracing/moving/
  /// resizing/rotating) the lasso overlay already repaints every frame from
  /// _lassoAnimCtrl, so a full-tree setState per stylus point (~240Hz) is pure
  /// waste and janks the canvas on dense pages. Only rebuild on a phase change
  /// (toolbar visibility / pan-enable flip).
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
    // _lassoGestureTick and repaint in place. A full setState here janks dense /
    // many-page notes.
    if (phase == prev && continuous.contains(phase)) {
      _lassoGestureTick.value++;
      return;
    }

    // Grab / release: selected ↔ a gesture phase. panEnabled is unchanged and
    // the lasso layer stays visible, so skip the full-tree setState (which
    // rebuilds every page/overlay/provider — the grab/drop jank). The ink
    // layers + toolbar refresh via _lassoPhaseTick. EXCEPTION: block selections,
    // whose overlays must (un)wrap their live-transform in build().
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

  DrawingStrokeBounds _boundsFromRect(Rect r) => DrawingStrokeBounds(
    minX: r.left,
    minY: r.top,
    maxX: r.right,
    maxY: r.bottom,
  );

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
        () =>
            _marqueeWorld = Rect.fromPoints(
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
          _isDrawing =
              true; // lasso: no rebuild needed (see _onDown note below)
          _handleLassoDown(p);
          return;
        }
      }
      // A clean finger tap to (re)select is handled by the overlay
      // GestureDetector's onTapUp; a finger drag pans via InteractiveViewer.
      return;
    }

    final willDraw = _shouldDraw(e.kind);
    // Lasso never needs a rebuild just for _isDrawing — its panEnabled is gated
    // by phase, not _isDrawing — so skip the setState to avoid a full-tree
    // rebuild at grab. Phase-driven rebuilds still fire via _onLassoChanged.
    if (_tool == DrawTool.lasso) {
      _isDrawing = willDraw;
    } else {
      setState(() => _isDrawing = willDraw);
    }
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
    _beginInkPerf();
    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      setState(() {
        _active = DrawingStroke(
          colorValue: _color.toARGB32(),
          strokeWidth: _strokeW,
          isFountainPen: true,
          points: StrokePoints(comps: 4)
            ..add(sp.dx, sp.dy, pressure, e.timeStamp.inMilliseconds.toDouble()),
        );
      });
      return;
    }
    _rawPen = StrokePoints(comps: 2)..add(p.dx, p.dy);
    setState(() {
      final pencil = _tool == DrawTool.pencil;
      final pts = StrokePoints(comps: pencil ? 3 : 2);
      if (pencil) {
        pts.add(sp.dx, sp.dy, e.pressure.isFinite ? e.pressure : 0.5);
      } else {
        pts.add(sp.dx, sp.dy);
      }
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        isHighlighter: _tool == DrawTool.highlighter,
        isPencil: pencil,
        points: pts,
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
          () =>
              _marqueeWorld = _resizeMarquee(_marqueeRectAtDragStart!, drag, w),
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
    final moveSw = _inkPerfSw == null ? null : (Stopwatch()..start());
    final sp = _stabilize(p);
    if (_tool == DrawTool.fountainPen) {
      final pressure = e.pressure.isFinite ? e.pressure : 0.5;
      _active!.points.add(
        sp.dx,
        sp.dy,
        pressure,
        e.timeStamp.inMilliseconds.toDouble(),
      );
      _activeTick.value++;
      moveSw?.stop();
      if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
      return;
    }
    final pts = _active!.points;
    _rawPen.add(p.dx, p.dy);
    if (pts.isNotEmpty && !_stabilizer.isOn) {
      final dx = sp.dx - pts.lastX;
      final dy = sp.dy - pts.lastY;
      if (dx * dx + dy * dy < _minDist2) {
        moveSw?.stop();
        if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
        return;
      }
    }
    if (_active!.isPencil) {
      pts.add(sp.dx, sp.dy, e.pressure.isFinite ? e.pressure : 0.5);
    } else {
      pts.add(sp.dx, sp.dy);
    }
    _activeTick.value++;
    moveSw?.stop();
    if (moveSw != null) _recordInkMove(moveSw.elapsedMicroseconds);
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
    // Lasso: no rebuild for _isDrawing (phase-gated panEnabled). Releasing a
    // stroke selection then routes through _handleLassoUp → _onLassoChanged,
    // which refreshes via _lassoPhaseTick instead of a full-tree setState.
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

    if (_pastePos != null) {
      _pasteTimer?.cancel();
      _pastePos = null;
      return;
    }

    // Scribble-erase has priority over any shape that the hold-timer may have
    // wrongly snapped (a dense scribble can match the rectangle detector).
    if (_tool == DrawTool.pen &&
        _rawPen.isNotEmpty &&
        isScribble(_rawPen, viewScale: _viewScale)) {
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

  /// On lift, append the same predicted tip the live preview was leading with,
  /// so the committed stroke ends where the preview ended (no backward retraction).
  void _bakePredictedTip() {
    final a = _active;
    if (a == null || a.isShape) return;
    final tip = predictedTipPoint(a.points);
    if (tip != null) a.points.addLikeLast(tip.dx, tip.dy);
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

  void _doScribbleErase() {
    final sw = Stopwatch()..start();
    final scribblePts = _rawPen;
    if (!isScribble(scribblePts, viewScale: _viewScale)) return;
    final bounds = scribbleBounds(scribblePts);
    final snapSw = Stopwatch()..start();
    final before = _snapshot();
    snapSw.stop();
    final lenBefore = _data.strokes.length;
    final activeStroke = _active?.clone();
    Rect? dirty;
    _data.strokes.removeWhere((s) {
      final sp = s.points;
      for (int i = 0; i < sp.length; i++) {
        if (bounds.contains(sp.offset(i))) {
          final b = strokeBounds(s);
          dirty = dirty == null ? b : dirty!.expandToInclude(b);
          return true;
        }
      }
      return false;
    });
    setState(() => _active = null);
    if (_data.strokes.length != lenBefore) {
      if (dirty != null) {
        _strokeTiles.invalidateRegion(dirty!.inflate(4), _data.strokes);
      } else {
        _strokeTiles.rebuild(_data.strokes);
      }
      _commitSnapshot(before);
      HapticFeedback.lightImpact();
      // Removed strokes → handled by the delete-diff pass in _persistNow.
      _persist();
    }
    sw.stop();
    if (activeStroke != null) {
      _logInkPerf(
        'scribble-erase',
        activeStroke,
        finishMs: sw.elapsedMilliseconds,
        snapshotMs: snapSw.elapsedMilliseconds,
      );
    } else {
      _resetInkPerf();
    }
    _rawPen = StrokePoints(comps: 2);
  }

  void _finishStroke() {
    final sw = Stopwatch()..start();
    if (_snapKind != null) return;
    if (_active == null) return;
    final ap = _active!.points;
    ap.removeWhere((i) => !ap.x(i).isFinite || !ap.y(i).isFinite);
    if (_active!.points.isEmpty) {
      setState(() => _active = null);
      _resetInkPerf();
      return;
    }

    final scribblePts =
        _rawPen.length >= _active!.points.length ? _rawPen : _active!.points;
    if (_tool == DrawTool.pen &&
        isScribble(scribblePts, viewScale: _viewScale)) {
      final bounds = scribbleBounds(scribblePts);
      final snapSw = Stopwatch()..start();
      final before = _snapshot();
      snapSw.stop();
      final lenBefore = _data.strokes.length;
      final activeStroke = _active!.clone();
      Rect? dirty;
      _data.strokes.removeWhere((s) {
        final sp = s.points;
        for (int i = 0; i < sp.length; i++) {
          if (bounds.contains(sp.offset(i))) {
            final b = strokeBounds(s);
            dirty = dirty == null ? b : dirty!.expandToInclude(b);
            return true;
          }
        }
        return false;
      });
      setState(() => _active = null);
      if (_data.strokes.length != lenBefore) {
        if (dirty != null) {
          _strokeTiles.invalidateRegion(dirty!.inflate(4), _data.strokes);
        } else {
          _strokeTiles.rebuild(_data.strokes);
        }
        _commitSnapshot(before);
        HapticFeedback.lightImpact();
        // Removed strokes → handled by the delete-diff pass in _persistNow.
        _persist();
      }
      sw.stop();
      _logInkPerf(
        'scribble-erase',
        activeStroke,
        finishMs: sw.elapsedMilliseconds,
        snapshotMs: snapSw.elapsedMilliseconds,
      );
      _rawPen = StrokePoints(comps: 2);
      return;
    }

    // The committed stroke object must be the SAME instance in both _data.strokes
    // and the tile index — the lasso hides the live selection by IDENTITY, so a
    // clone in the tiles wouldn't match and would ghost at the old spot on move.
    final addedStroke = _active!.clone();
    setState(() {
      _data.strokes.add(addedStroke);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _strokeTiles.append(addedStroke);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitStrokeAdd(addedStroke);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persist();
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'stroke',
      addedStroke,
      finishMs: sw.elapsedMilliseconds,
      appendMs: appendSw.elapsedMilliseconds,
      historyMs: historySw.elapsedMilliseconds,
      persistMs: persistSw.elapsedMilliseconds,
    );
  }

  void _finishFountainStroke() {
    final sw = Stopwatch()..start();
    if (_active == null) return;
    final ap = _active!.points;
    ap.removeWhere((i) => !ap.x(i).isFinite || !ap.y(i).isFinite);
    if (_active!.points.length < 2) {
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
      _data.strokes.add(baked);
      _active = null;
    });
    final appendSw = Stopwatch()..start();
    _strokeTiles.append(baked);
    appendSw.stop();
    final historySw = Stopwatch()..start();
    _commitStrokeAdd(baked);
    historySw.stop();
    final persistSw = Stopwatch()..start();
    _persist();
    persistSw.stop();
    sw.stop();
    _logInkPerf(
      'fountain',
      baked,
      finishMs: sw.elapsedMilliseconds,
      appendMs: appendSw.elapsedMilliseconds,
      historyMs: historySw.elapsedMilliseconds + bakeSw.elapsedMilliseconds,
      persistMs: persistSw.elapsedMilliseconds,
    );
  }

  static const _eraserScreenRadius = 7.0;

  /// Strokes whose tiles overlap a [radius] box around [pos], pulled from the
  /// spatial index. Lets hit-testing (eraser, tap-select) stay local instead of
  /// scanning every stroke on the board.
  Set<DrawingStroke> _strokesNear(Offset pos, double radius) {
    final rect = Rect.fromCircle(center: pos, radius: radius);
    final out = <DrawingStroke>{};
    for (final key in _strokeTiles.tilesInRect(rect)) {
      final list = _strokeTiles.strokesAt(key);
      if (list != null) out.addAll(list);
    }
    return out;
  }

  void _eraseNear(Offset pos) {
    final radius = _eraserScreenRadius / _viewScale;
    bool changed = false;
    // Accumulate the bounds of every stroke the eraser touched so only those
    // tiles are rebuilt (a removed stroke can reach far past the eraser point).
    Rect? dirty;
    void markDirty(DrawingStroke s) {
      final b = strokeBounds(s);
      dirty = dirty == null ? b : dirty!.expandToInclude(b);
    }

    // Only strokes in the tiles around the eraser can be touched — gather them
    // from the spatial index instead of hit-testing all N strokes per move
    // (which was O(N·points) every pointer event → the eraser lag on dense
    // boards). Inflated generously to cover wide strokes whose centre line sits
    // just outside the eraser circle.
    final candidates = _strokesNear(pos, radius + 64);
    if (candidates.isEmpty) return;

    if (_eraserMode == EraserMode.partial) {
      final out = <DrawingStroke>[];
      for (final s in _data.strokes) {
        if (!candidates.contains(s)) {
          out.add(s);
          continue;
        }
        final pieces = splitStrokeByEraser(s, pos, radius);
        if (pieces.length == 1 && identical(pieces.first, s)) {
          out.add(s);
        } else {
          markDirty(s);
          out.addAll(pieces);
          changed = true;
        }
      }
      if (changed) _data.strokes = out;
    } else {
      final hits = <DrawingStroke>{};
      for (final s in candidates) {
        if (strokeHitByEraser(s, pos, radius)) {
          hits.add(s);
          markDirty(s);
        }
      }
      if (hits.isNotEmpty) {
        _data.strokes.removeWhere(hits.contains);
        changed = true;
      }
    }
    if (changed) {
      _gestureChanged = true;
      if (dirty != null) {
        _strokeTiles.invalidateRegion(dirty!.inflate(4), _data.strokes);
      } else {
        _strokeTiles.rebuild(_data.strokes);
      }
      setState(() {});
      // Removed strokes → handled by the delete-diff pass in _persistNow.
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
      // Capture the pre-gesture selection box for surgical tile invalidation on
      // drop (any of rotate/resize/move below).
      _gestureRegionBefore = _lassoCtrl.boundingBox;
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
        _captureLassoSelection();
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
      // Clone the selection right before finishMove mutates points in place, so
      // the start-of-gesture snapshot keeps the originals. ONLY on a real move:
      // a tap (which toggles the action toolbar) must not swap object identity,
      // or the tiles desync from _data.strokes and the ghost returns next move.
      if (moved) _cloneSelectedStrokesInPlace();
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
      if (moved) _cloneSelectedStrokesInPlace(); // only a real edit clones
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
      if (moved) _cloneSelectedStrokesInPlace(); // only a real edit clones
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
      // Geometry mutated in place → the tile cache for the touched region is now
      // stale. Without this the moved ink ghosts at its old spot and is invisible
      // at the new one until the board is re-entered.
      _invalidateEditedTiles(_gestureRegionBefore, _lassoCtrl.boundingBox);
      _gestureRegionBefore = null;
      _commitGesture();
      // The moved/resized/rotated rows keep their dbId → UPDATE in place.
      _markSelectionDirty();
      _persist();
    } else {
      _gestureRegionBefore = null;
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
  ///
  /// [includeShapes]: las figuras imantadas (p.ej. la barra de fracción dibujada
  /// como línea recta con snap) deben entrar al MATH OCR — sin ellas el modelo
  /// ve los números flotando. El OCR de texto (ML Kit) sí las excluye.
  List<List<Offset>> _selectedWritingStrokes({bool includeShapes = false}) {
    final strokes = <List<Offset>>[];
    for (final i in _lassoCtrl.selectedIndices) {
      if (i >= _data.strokes.length) continue;
      final s = _data.strokes[i];
      if (s.isHighlighter) continue;
      if (s.isShape && !includeShapes) continue;
      strokes.add(s.points.toOffsets());
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
    _commitSnapshot(before);
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
          onPersist: () async {
            _persist();
          },
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
        overlay = _liveGestureTransform(overlay, b.x, b.y);
      }
      out.add(Positioned(left: b.x, top: b.y, child: overlay));
    }
    return out;
  }

  /// Wraps a selected block overlay so it follows the live lasso gesture WITHOUT
  /// a full-tree rebuild: only this Transform reacts to _lassoGestureTick (the
  /// block content rides through as `child`, built once). Lets a 20-page note's
  /// blocks move smoothly — the old per-frame setState rebuilt every overlay.
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
          onPersist: () async {
            _persist();
          },
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
        overlay = _liveGestureTransform(overlay, b.x, b.y);
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

  _WhiteboardSnapshot _snapshot() {
    // Strokes are captured by REFERENCE — a shallow O(strokes) pointer copy, not
    // a deep clone of every point (which was 90-119ms on dense boards). The
    // invariant that keeps undo correct: any op that mutates a stroke IN PLACE
    // first calls _cloneSelectedStrokesInPlace, so no stroke referenced by a
    // live snapshot is ever mutated. Images/blocks are few → still deep-cloned.
    return (
      List<DrawingStroke>.of(_data.strokes),
      _data.images.map((im) => im.clone()).toList(),
      _data.taskBlocks.map((b) => b.clone()).toList(),
      _data.textBlocks.map((b) => b.clone()).toList(),
    );
  }

  /// Replace each currently-selected stroke with a fresh clone, so an imminent
  /// in-place geometry edit (move/resize/rotate/flip) mutates the clone and
  /// leaves the original — still referenced by snapshots on the undo stack —
  /// untouched. clone() preserves dbId, so the row is UPDATEd, not re-inserted.
  void _cloneSelectedStrokesInPlace() {
    for (final i in _lassoCtrl.selectedIndices) {
      if (i < _data.strokes.length) {
        _data.strokes[i] = _data.strokes[i].clone();
      }
    }
  }

  /// Flag the current selection's rows for an in-place UPDATE on the next
  /// persist (their geometry/color/width changed but identity and order did
  /// not). Freshly created strokes (duplicate/paste, dbId == null) are skipped —
  /// the insert pass picks them up.
  void _markSelectionDirty() {
    for (final i in _lassoCtrl.selectedIndices) {
      if (i < _data.strokes.length) {
        final id = _data.strokes[i].dbId;
        if (id != null) _dirtyStrokeIds.add(id);
      }
    }
  }

  void _pushHistory(_WhiteboardHistoryEntry entry) {
    _undoStack.add(entry);
    if (_undoStack.length > 60) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _commitSnapshot(_WhiteboardSnapshot before) {
    _markCanvasDirty();
    _pushHistory(_WhiteboardSnapshotEntry(before));
  }

  void _commitStrokeAdd(DrawingStroke stroke) {
    _markCanvasDirty();
    _pushHistory(_WhiteboardStrokeAddEntry(stroke.clone()));
  }

  void _restore(_WhiteboardSnapshot snap) {
    final before = _data.strokes.length;
    _markRestoreStrokeDirty(snap.$1);
    _data.strokes = snap.$1;
    _data.images = snap.$2;
    _data.taskBlocks = snap.$3;
    _data.textBlocks = snap.$4;
    _markCanvasDirty();
    _strokesNeedFullPersist = true;
    _overviewDirty = true;
    _disposeFocus();
    _strokeTiles.rebuild(_data.strokes);
    _scheduleOverviewBake();
    CrashLogger.instance.note(
      'PERF restore-pizarra: full, strokes $before->${_data.strokes.length}, '
      'tiles ${_strokeTiles.debugTileCount}/${_strokeTiles.debugEntryCount}, '
      'overviewDirty $_overviewDirty, baked $_overviewBakedCount',
    );
  }

  void _markRestoreStrokeDirty(List<DrawingStroke> target) {
    final currentById = <int, DrawingStroke>{
      for (final s in _data.strokes)
        if (s.dbId != null) s.dbId!: s,
    };
    for (final stroke in target) {
      final id = stroke.dbId;
      if (id == null || !_persistedStrokeIds.contains(id)) continue;
      final current = currentById[id];
      if (current != null && !identical(current, stroke)) {
        _dirtyStrokeIds.add(id);
      }
    }
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

  /// Invalidate only the tiles the last selection edit touched: the union of the
  /// selection box BEFORE the edit and AFTER it, inflated to cover stroke width
  /// (a resize can scale ink well past the point bounds). Falls back to a full
  /// invalidate when neither box is known.
  void _invalidateEditedTiles(Rect? before, Rect? after) {
    Rect? region = before;
    if (after != null) {
      region = region == null ? after : region.expandToInclude(after);
    }
    final selected = _lassoCtrl.selectedIndices.length;
    final forceRebuild = region == null || selected > 128;
    _overviewDirty = true;
    _disposeFocus();
    if (forceRebuild) {
      _strokeTiles.rebuild(_data.strokes);
      CrashLogger.instance.note(
        'PERF lasso-tiles-pizarra: rebuild, selected $selected, '
        'strokes ${_data.strokes.length}, tiles ${_strokeTiles.debugTileCount}/${_strokeTiles.debugEntryCount}, '
        'overviewDirty $_overviewDirty, baked $_overviewBakedCount',
      );
      return;
    }
    double maxW = 24;
    for (final i in _lassoCtrl.selectedIndices) {
      if (i < _data.strokes.length) {
        final w = _data.strokes[i].strokeWidth;
        if (w > maxW) maxW = w;
      }
    }
    final inflated = region.inflate(maxW + 48);
    _strokeTiles.invalidateRegion(inflated, _data.strokes);
    CrashLogger.instance.note(
      'PERF lasso-tiles-pizarra: region, selected $selected, '
      'strokes ${_data.strokes.length}, rect ${inflated.left.toStringAsFixed(1)},'
      '${inflated.top.toStringAsFixed(1)},${inflated.width.toStringAsFixed(1)}x'
      '${inflated.height.toStringAsFixed(1)}, '
      'tiles ${_strokeTiles.debugTileCount}/${_strokeTiles.debugEntryCount}, '
      'overviewDirty $_overviewDirty, baked $_overviewBakedCount',
    );
  }

  void _lassoMutate(VoidCallback op) {
    final sw = Stopwatch()..start();
    final before = _snapshot();
    final snapshotMs = sw.elapsedMilliseconds;
    // Protect the snapshot's references from any in-place edit inside op (flip
    // mutates points directly). Color/width/delete/duplicate don't mutate
    // existing objects, so this is a cheap no-harm clone of the selection.
    final selectedBefore = Set<int>.from(_lassoCtrl.selectedIndices);
    final countBefore = _data.strokes.length;
    final dirtyBefore = _dirtyStrokeIds.length;
    final nullIdsBefore = _data.strokes.where((s) => s.dbId == null).length;
    _cloneSelectedStrokesInPlace();
    final regionBefore = _lassoCtrl.boundingBox;
    op();
    final countAfterOp = _data.strokes.length;
    _invalidateEditedTiles(regionBefore, _lassoCtrl.boundingBox);
    _commitSnapshot(before);
    // Post-op selection: edited rows (color/width/flip) → UPDATE; new copies
    // (duplicate/paste, dbId == null) → insert pass; deleted → diff pass.
    _markSelectionDirty();
    _persist();
    sw.stop();
    final nullIdsAfter = _data.strokes.where((s) => s.dbId == null).length;
    CrashLogger.instance.note(
      'PERF lasso-mut-pizarra: selected ${selectedBefore.length}->${_lassoCtrl.selectedIndices.length}, '
      'strokes $countBefore->$countAfterOp, '
      'nullIds $nullIdsBefore->$nullIdsAfter, '
      'dirtyIds $dirtyBefore->${_dirtyStrokeIds.length}, persisted ${_persistedStrokeIds.length}, '
      'tileRev ${_strokeTiles.revision}, tiles ${_strokeTiles.debugTileCount}/${_strokeTiles.debugEntryCount}, '
      'overviewDirty $_overviewDirty, snapshot ${snapshotMs}ms, '
      'total ${sw.elapsedMilliseconds}ms',
    );
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    setState(() {
      if (entry is _WhiteboardSnapshotEntry) {
        _redoStack.add(_WhiteboardSnapshotEntry(_snapshot()));
        _restore(entry.snapshot);
      } else if (entry is _WhiteboardStrokeAddEntry &&
          _data.strokes.isNotEmpty) {
        final removed = _data.strokes.removeLast();
        _markCanvasDirty();
        _redoStack.add(_WhiteboardStrokeAddEntry(removed.clone()));
        _strokeTiles.invalidateRegion(
          strokeBounds(removed).inflate(removed.strokeWidth + 4),
          _data.strokes,
        );
        _overviewDirty = true;
        _disposeFocus();
        _scheduleOverviewBake();
        CrashLogger.instance.note(
          'PERF undo-pizarra: stroke-add undo, strokes ${_data.strokes.length}, '
          'overviewDirty $_overviewDirty, baked $_overviewBakedCount',
        );
      }
      _lassoCtrl.deselect();
      _active = null;
    });
    _persist();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    setState(() {
      if (entry is _WhiteboardSnapshotEntry) {
        _undoStack.add(_WhiteboardSnapshotEntry(_snapshot()));
        _restore(entry.snapshot);
      } else if (entry is _WhiteboardStrokeAddEntry) {
        // Same instance in _data.strokes and the tile index (identity-based
        // lasso hide); the undo entry keeps its own independent clone.
        final restored = entry.stroke.clone();
        _data.strokes.add(restored);
        _markCanvasDirty();
        _undoStack.add(_WhiteboardStrokeAddEntry(entry.stroke.clone()));
        _strokeTiles.append(restored);
        _overviewDirty = true;
        _disposeFocus();
        _scheduleOverviewBake();
        CrashLogger.instance.note(
          'PERF redo-pizarra: stroke-add redo, strokes ${_data.strokes.length}, '
          'overviewDirty $_overviewDirty, baked $_overviewBakedCount',
        );
      }
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
      await _ensureAllStrokesLoadedForGlobalOp();
      if (!mounted) return;
      final before = _snapshot();
      setState(() => _data.strokes = []);
      _strokeTiles.rebuild(_data.strokes);
      _commitSnapshot(before);
      _strokesNeedFullPersist = true;
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
  // Cached so the async bake/chunk paths never call MediaQuery.of(context):
  // a post-frame _chunkPump firing during teardown looked up a deactivated
  // widget's context → crash on close (whiteboard:4050). Refreshed below.
  double _dpr = 1.0;

  Rect? _contentBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in _data.strokes) {
      final sp = s.points;
      for (int i = 0; i < sp.length; i++) {
        final x = sp.x(i);
        final y = sp.y(i);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
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

  /// Debounced re-bake of the zoomed-out overview after the ink settles.
  void _scheduleOverviewBake() {
    _overviewBakePending = true;
    _overviewTimer?.cancel();
    _overviewTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_bakeOverview());
    });
  }

  /// Render all strokes once into a downsampled, strokes-only [ui.Image] used in
  /// place of the tile layer when zoomed out. Async (the raster runs off the UI
  /// thread); cheap to display (one blit) and to keep crisp (only shown while
  /// the image has at least as many pixels as the screen).
  /// True if every stroke from [from] onward fits inside [bounds] (so an
  /// incremental bake can blit the old image + draw only the new strokes).
  bool _strokesWithin(Rect bounds, List<DrawingStroke> strokes, int from) {
    for (int i = from; i < strokes.length; i++) {
      final b = strokeBounds(strokes[i]);
      if (b.left < bounds.left ||
          b.top < bounds.top ||
          b.right > bounds.right ||
          b.bottom > bounds.bottom) {
        return false;
      }
    }
    return true;
  }

  Future<void> _bakeOverview() async {
    if (!mounted) return;
    if (_overviewBaking) {
      _overviewBakePending = true;
      return;
    }
    _overviewBakePending = false;
    final fullBounds = _contentBounds();
    if (fullBounds == null || fullBounds.width <= 0 || fullBounds.height <= 0) {
      final old0 = _overviewImage;
      _overviewImage = null;
      _overviewBounds = null;
      _overviewThreshold = 0;
      _overviewBakedCount = 0;
      _overviewDirty = false;
      old0?.dispose();
      if (mounted) setState(() {});
      return;
    }
    _overviewBaking = true;
    try {
      final dpr = _dpr;
      const maxDim = 6144.0;
      const maxPixels = 36000000.0;
      final strokes = _data.strokes;
      final count = strokes.length;
      final oldImage = _overviewImage;
      final oldBounds = _overviewBounds;
      final oldBaked = _overviewBakedCount;
      final dirtyAtStart = _overviewDirty;

      // Incremental bake: only new strokes appended, all inside the existing
      // bounds → blit the old image + draw just the new ones. Avoids the raster
      // spike of re-rendering every stroke on each pen-up while zoomed out.
      final incremental =
          !dirtyAtStart &&
          oldImage != null &&
          oldBounds != null &&
          count > oldBaked &&
          _strokesWithin(oldBounds, strokes, oldBaked);

      final bounds = incremental ? oldBounds : fullBounds;
      final area = math.max(1.0, bounds.width * bounds.height);
      final dimScale = maxDim / bounds.longestSide;
      final areaScale = math.sqrt(maxPixels / area);
      final imgScale =
          math
              .min(2.0, math.min(dimScale, areaScale))
              .clamp(0.05, 2.0)
              .toDouble();
      final w = (bounds.width * imgScale).ceil();
      final h = (bounds.height * imgScale).ceil();
      if (w <= 0 || h <= 0) return;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(imgScale);
      canvas.translate(-bounds.left, -bounds.top);
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
          oldBounds, // same size 1:1 → no quality loss
          Paint()..filterQuality = FilterQuality.medium,
        );
        from = oldBaked;
      }
      for (int i = from; i < count; i++) {
        drawStroke(canvas, strokes[i]); // full fidelity — the master copy
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      // Free the previous image only AFTER the next frame composits the new one,
      // so a RawImage still referencing it never paints a disposed texture.
      final old = _overviewImage;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _overviewImage = image;
      _overviewBounds = bounds;
      _overviewBakedCount = count;
      _overviewDirty = false; // fresh image matches _data → overview safe again
      // Only show the overview while it stays crisp: screen px (zoom·dpr) must
      // not exceed the image density. Capped so it never replaces the detailed
      // zoomed-in view.
      _overviewThreshold = (imgScale / dpr).clamp(0.0, 0.65);
      CrashLogger.instance.note(
        'PERF bake-overview-pizarra: ${incremental ? 'incremental' : 'full'}, '
        'dirtyAtStart ${dirtyAtStart ? 'SI' : 'no'}, count $count, '
        'old $oldBaked, img ${w}x$h, '
        'threshold ${_overviewThreshold.toStringAsFixed(2)}',
      );
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeOverview pizarra');
    } finally {
      _overviewBaking = false;
      if (_overviewBakePending && mounted) {
        _overviewTimer?.cancel();
        _overviewTimer = Timer(const Duration(milliseconds: 80), () {
          if (mounted) unawaited(_bakeOverview());
        });
      }
    }
  }

  // ─── Settle watch + focus bake (Pyramid L0) ───────────────────────────────

  /// True while a view-transform gesture (pan/zoom, not draw/lasso) is moving
  /// the canvas → show the overview raster instead of re-rastering tiles per
  /// frame. Engages on 2 fingers at once, or 1 finger once it has actually moved.
  bool get _viewTransformActive =>
      _viewGestureActive &&
      !_isDrawing &&
      _lassoCtrl.phase != LassoPhase.moving &&
      _lassoCtrl.phase != LassoPhase.resizing &&
      _lassoCtrl.phase != LassoPhase.rotating &&
      (_activePointers.length >= 2 || _viewMoved);

  /// Start watching for the view to fully stop (finger lifted + fling done). A
  /// Ticker samples the transform each frame; once it's identical for
  /// [_settleStillFramesNeeded] frames we hand the overview back to crisp tiles
  /// (in stillness) and bake the focus — both invisible because nothing moves.
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
      if (_overviewLinger && mounted) {
        setState(() => _overviewLinger = false);
      }
      unawaited(_bakeFocus());
      // Pre-load / refresh the chunk ring for the settled zoom (or free it if we
      // dropped below the engage threshold). Budgeted; runs in stillness here.
      _scheduleChunkPump();
    }
  }

  void _disposeFocus() {
    final img = _focusImage;
    if (img != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
    }
    _focusImage = null;
    _focusBounds = null;
    _focusScale = 0;
    _focusBakedCount = 0;
  }

  /// Bake the high-res focus tile for the current view, culled to the strokes in
  /// the visible region (+ overscan). Only when zoomed in past where the base
  /// stays crisp; dropped otherwise. Runs in stillness (settle), main isolate.
  Future<void> _bakeFocus() async {
    if (_focusBaking || !mounted || _viewport == Size.zero) return;
    if (_viewGestureActive || _activePointers.isNotEmpty || _isDrawing) {
      _beginSettleWatch();
      return;
    }
    if (_viewScale <= _overviewThreshold) {
      _disposeFocus();
      return;
    }
    final strokes = _data.strokes;
    final content = _contentBounds();
    if (strokes.isEmpty || content == null) {
      _disposeFocus();
      return;
    }
    final visible = _visibleRectFor(_viewport);
    final overscan = math.max(visible.width, visible.height) * 0.5;
    final region = visible.inflate(overscan).intersect(content);
    if (region.width <= 0 || region.height <= 0) {
      _disposeFocus();
      return;
    }
    final dpr = _dpr;
    final cap = _focusMaxDim / region.longestSide;
    // Region too large for a denser-than-base image (low zoom, near the
    // threshold) → the base already covers this view. Skip focus: avoids an
    // inverted clamp AND a pointless bake that'd be blurrier than the base.
    if (cap < 2.0) {
      _disposeFocus();
      return;
    }
    final imgScale = math.min(_viewScale * dpr, cap);
    final count = strokes.length;
    // Resident focus already covers the viewport at this density+count → skip.
    if (_focusImage != null &&
        _focusBounds != null &&
        _focusBounds!.contains(visible.topLeft) &&
        _focusBounds!.contains(visible.bottomRight) &&
        (_focusScale - imgScale).abs() / imgScale < 0.12 &&
        _focusBakedCount == count) {
      CrashLogger.instance.note(
        'PERF bake-focus-pizarra: reuse, count $count, '
        'scale ${imgScale.toStringAsFixed(2)}, '
        'region ${region.left.toStringAsFixed(1)},${region.top.toStringAsFixed(1)},'
        '${region.width.toStringAsFixed(1)}x${region.height.toStringAsFixed(1)}',
      );
      return;
    }
    _focusBaking = true;
    try {
      final w = (region.width * imgScale).ceil();
      final h = (region.height * imgScale).ceil();
      if (w <= 0 || h <= 0) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(imgScale);
      canvas.translate(-region.left, -region.top);
      canvas.clipRect(region);
      for (int i = 0; i < count; i++) {
        final s = strokes[i];
        if (strokeBounds(s).overlaps(region)) drawStroke(canvas, s);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      final old = _focusImage;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _focusImage = image;
      _focusBounds = region;
      _focusScale = imgScale;
      _focusBakedCount = count;
      CrashLogger.instance.note(
        'PERF bake-focus-pizarra: done, count $count, img ${w}x$h, '
        'scale ${imgScale.toStringAsFixed(2)}, '
        'region ${region.left.toStringAsFixed(1)},${region.top.toStringAsFixed(1)},'
        '${region.width.toStringAsFixed(1)}x${region.height.toStringAsFixed(1)}',
      );
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeFocus pizarra');
    } finally {
      _focusBaking = false;
    }
  }

  // ── Chunk tile ring ────────────────────────────────────────────────────────

  /// Engaged only past where the focus tile can still be baked at full screen
  /// density (its overscan region tops out for large viewports / high zoom),
  /// where panning softens. Below it (zoomed out, base overview crisp, or small
  /// viewport where focus is pixel-perfect) chunks stay dormant.
  bool get _chunkEngaged {
    if (!_tilesEnabled || _viewport == Size.zero) return false;
    if (_viewScale <= _overviewThreshold) return false; // base overview is crisp
    final dpr = _dpr;
    final regionLongest = _visibleRectFor(_viewport).longestSide * 2; // focus overscan
    final cap = _focusMaxDim / regionLongest; // focus density ceiling
    return _viewScale * dpr > cap * 1.03; // focus can't reach screen density
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
    if (!_chunkEngaged || _viewport == Size.zero || _data.strokes.isEmpty) {
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
  /// ink-only, world-anchored, culled to the strokes overlapping the cell (the
  /// infinite-canvas analog of the notebook's per-page loop). Same `drawStroke`
  /// path as base/focus so tile↔base edges match chromatically.
  Future<void> _bakeChunk(int gx, int gy, Rect cell, double tileWorld) async {
    final key = _chunkKey(gx, gy);
    if (_chunkBaking.contains(key) || !mounted) return;
    final version = _chunkVersion;
    final dpr = _dpr;
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
      final strokes = _data.strokes;
      for (int i = 0; i < strokes.length; i++) {
        final s = strokes[i];
        if (strokeBounds(s).overlaps(cell)) drawStroke(canvas, s);
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
      _chunkTiles[key] = _WbChunkTile(cell, version, image);
      setState(() {});
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeChunk pizarra');
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
    if (!mounted || _viewGestureActive || _viewport == Size.zero) {
      return;
    }
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
      final dpr = _dpr;
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
    } catch (e, st) {
      CrashLogger.instance.record(e, st, context: 'bakeZoomSnapshot pizarra');
    } finally {
      _zoomSnapshotBaking = false;
      if (_zoomSnapshotPending && mounted) {
        _scheduleZoomSnapshotBake(delay: const Duration(milliseconds: 80));
      }
    }
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
    setState(() {
      _viewCtrl.value =
          Matrix4.translationValues(vw / 2, vh / 2, 0)
            ..multiply(Matrix4.diagonal3Values(s, s, 1))
            ..multiply(
              Matrix4.translationValues(-box.center.dx, -box.center.dy, 0),
            );
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

  Future<void> _captureLassoSelection() async {
    final bb = _lassoCtrl.boundingBox;
    if (bb == null || bb == Rect.zero) return;

    final selectedIndices = Set<int>.from(_lassoCtrl.selectedIndices);
    final selectedImageIndices = Set<int>.from(_lassoCtrl.selectedImageIndices);

    if (selectedIndices.isEmpty && selectedImageIndices.isEmpty) return;

    final strokes = _data.strokes;
    final images = _data.images;
    final imageCache = _imgCache;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

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
      final width = bb.width.ceil();
      final height = bb.height.ceil();
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

  Color get _accent => widget.note.color ?? widget.folder.color;

  Rect _activeStrokeRect() {
    final active = _active;
    if (active == null || active.points.isEmpty) return Rect.zero;
    final pad = (_strokeW * 6).clamp(24.0, 96.0);
    return strokeBounds(
      active,
    ).inflate(pad).intersect(const Rect.fromLTWH(0, 0, _kCanvasW, _kCanvasH));
  }

  Widget _buildWhiteboardBackgroundLayer(Size viewport) {
    return AnimatedBuilder(
      animation: Listenable.merge([_viewCtrl, _lassoPhaseTick]),
      builder: (_, _) {
        if (_zoomGestureActive && _zoomSnapshotImage != null) {
          return const SizedBox.shrink();
        }
        final visibleRect = _renderRectFor(viewport);
        return Positioned.fromRect(
          rect: visibleRect,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _CanvasPainter(
                strokes: _data.strokes,
                images: _data.images,
                imageCache: _imgCache,
                background: _data.background,
                paper: bgPaper(_data.bgColorValue, yCream),
                visibleRect: visibleRect,
                origin: visibleRect.topLeft,
                paintVersion: _paintVersion,
                hiddenImageIndices:
                    (_lassoCtrl.phase == LassoPhase.moving ||
                            _lassoCtrl.phase == LassoPhase.resizing ||
                            _lassoCtrl.phase == LassoPhase.rotating)
                        ? _lassoCtrl.selectedImageIndices
                        : null,
                drawStrokes: false,
              ),
              size: visibleRect.size,
            ),
          ),
        );
      },
    );
  }

  // Beyond this many visible tiles (zoomed way out) the per-tile RepaintBoundary
  // overhead isn't worth it — ink is tiny on screen anyway — so fall back to a
  // single direct painter.
  static const int _kMaxLiveTiles = 48;

  /// The zoomed-out overview: the cached ink image positioned in world space
  /// (the InteractiveViewer scales it), plus any strokes added since the last
  /// bake drawn live on top so editing while zoomed out shows instantly.
  Widget _overviewStrokeLayer(ui.Image image, Rect renderRect) {
    final bounds = _overviewBounds!;
    final baked = _overviewBakedCount.clamp(0, _data.strokes.length);
    final delta =
        baked < _data.strokes.length ? _data.strokes.sublist(baked) : null;
    final focus = _focusImage;
    final focusBounds = _focusBounds;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Base: the whole-board image (low density — blurry when zoomed in).
            Positioned.fromRect(
              rect: bounds,
              child: RawImage(
                image: image,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // Focus tile (Pyramid L0): crisp high-res of the visible region,
            // baked at the settled zoom, laid over the blurry base.
            if (focus != null && focusBounds != null)
              Positioned.fromRect(
                rect: focusBounds,
                child: RawImage(
                  image: focus,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            if (delta != null)
              Positioned.fromRect(
                rect: renderRect,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _CanvasPainter(
                      strokes: delta,
                      images: const [],
                      imageCache: null,
                      background: _data.background,
                      paper: yCream,
                      visibleRect: renderRect,
                      origin: renderRect.topLeft,
                      paintVersion: _paintVersion + _strokeTiles.revision,
                      drawBackground: false,
                      // Full detail so an un-baked stroke looks identical to the
                      // live preview and to the baked image — no visible "pop"
                      // when it moves between layers.
                      lod: 0,
                    ),
                    size: renderRect.size,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhiteboardStrokeLayer(Size viewport) {
    return AnimatedBuilder(
      // Rebuilds on pan/zoom, lasso phase, and any ink change (the index is a
      // ChangeNotifier). Each rebuild just re-emits tile widgets (cheap); only
      // tiles whose version changed actually re-rasterize.
      animation: Listenable.merge([_viewCtrl, _lassoPhaseTick, _strokeTiles]),
      builder: (_, _) {
        if (_zoomGestureActive && _zoomSnapshotImage != null) {
          _overviewActive = false;
          _strokeFallbackActive = false;
          _logWhiteboardLayerDecision(
            'zoom-snapshot',
            renderRect: _visibleRectFor(viewport),
            tileCount: 0,
            inGesture: false,
            hydrationActive: false,
            canOverview: false,
            lod: lodForScale(_viewScale),
          );
          return const SizedBox.shrink();
        }
        final inGesture =
            _lassoCtrl.phase == LassoPhase.moving ||
            _lassoCtrl.phase == LassoPhase.resizing ||
            _lassoCtrl.phase == LassoPhase.rotating;

        // Per-tile RepaintBoundaries cache their own raster, so a tight visible
        // rect + a one-tile lookahead ring is enough (no aggressive predictive
        // buffer needed — tiles entering view rasterize once and stay cached).
        final renderRect = _visibleRectFor(
          viewport,
        ).inflate(_strokeTiles.tileSize);
        final tileKeys = _strokeTiles.tilesInRect(renderRect).toList();
        _strokeFallbackActive = tileKeys.length > _kMaxLiveTiles;
        // Decimate stroke detail when zoomed out so dense tiles rasterize fast.
        final lod = lodForScale(_viewScale);

        // Zoomed-out overview: blit the cached ink image instead of re-drawing
        // every stroke per frame. Skipped during a lasso gesture (the image
        // can't hide the live selection) → tiles take over there.
        final overview = _overviewImage;
        final hydrationActive = false;
        final canOverview =
            overview != null &&
            _overviewBounds != null &&
            !inGesture &&
            !_overviewDirty &&
            !hydrationActive;
        // Show the overview whenever it's crisp (zoomed out), under tile
        // pressure, OR through ANY moving view gesture + the post-fling linger
        // (the focus tile keeps it crisp when zoomed in). Mirrors the notebook.
        _overviewActive =
            canOverview &&
            (_viewScale < _overviewThreshold ||
                _strokeFallbackActive ||
                _viewTransformActive ||
                _overviewLinger);
        // High-zoom chunk ring (pyramid L0): full-res world tiles composited OVER
        // the base+focus, per-cell. Schedule the baker whenever engaged (also
        // pre-loads at rest) or when tiles still need freeing after dropping below
        // the threshold.
        if (_chunkEngaged || _chunkTiles.isNotEmpty) _scheduleChunkPump();

        if (_overviewActive) {
          final delta = math.max(0, _data.strokes.length - _overviewBakedCount);
          _logWhiteboardLayerDecision(
            'overview',
            renderRect: renderRect,
            tileCount: tileKeys.length,
            inGesture: inGesture,
            hydrationActive: hydrationActive,
            canOverview: canOverview,
            lod: lod,
            delta: delta,
          );
          // Base/focus + delta only in the holes (even-odd clip), tiles on top →
          // zero doubling/seam. On any ink edit _chunkVersion bumps → curTiles
          // empties → yields to the overview layer below until the ring re-bakes.
          if (_chunkEngaged && _overviewBounds != null) {
            final curTiles = <(Rect, ui.Image)>[];
            for (final t in _chunkTiles.values) {
              if (t.version == _chunkVersion &&
                  t.worldRect.overlaps(renderRect)) {
                curTiles.add((t.worldRect, t.image));
              }
            }
            if (curTiles.isNotEmpty) {
              final baked = _overviewBakedCount.clamp(0, _data.strokes.length);
              final deltaStrokes =
                  baked < _data.strokes.length
                      ? _data.strokes.sublist(baked)
                      : null;
              return Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WhiteboardChunkOverlayPainter(
                        baseImage: overview!,
                        baseBounds: _overviewBounds!,
                        focusImage: _focusImage,
                        focusBounds: _focusBounds,
                        delta: deltaStrokes,
                        tiles: curTiles,
                        visibleWorld: renderRect,
                      ),
                      size: const Size(_kCanvasW, _kCanvasH),
                    ),
                  ),
                ),
              );
            }
          }
          return _overviewStrokeLayer(overview!, renderRect);
        }

        if (_strokeFallbackActive) {
          _logWhiteboardLayerDecision(
            'fallback-painter',
            renderRect: renderRect,
            tileCount: tileKeys.length,
            inGesture: inGesture,
            hydrationActive: hydrationActive,
            canOverview: canOverview,
            lod: lod,
          );
          // Zoomed-out fallback: one painter, strokes drawn directly + culled.
          return Positioned.fromRect(
            rect: renderRect,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CanvasPainter(
                    strokes: _data.strokes,
                    images: _data.images,
                    imageCache: _imgCache,
                    background: _data.background,
                    paper: bgPaper(_data.bgColorValue, yCream),
                    visibleRect: renderRect,
                    origin: renderRect.topLeft,
                    paintVersion: _paintVersion + _strokeTiles.revision,
                    hiddenIndices:
                        inGesture ? _lassoCtrl.selectedIndices : null,
                    drawBackground: false,
                    lod: lod,
                  ),
                  size: renderRect.size,
                ),
              ),
            ),
          );
        }

        // Hide the live selection in the base tiles; the lasso overlay draws it
        // following the pointer. Identity set so == overrides can't mismatch.
        Set<DrawingStroke>? hidden;
        if (inGesture && _lassoCtrl.selectedIndices.isNotEmpty) {
          hidden = Set<DrawingStroke>.identity();
          for (final i in _lassoCtrl.selectedIndices) {
            if (i < _data.strokes.length) hidden.add(_data.strokes[i]);
          }
        }

        _logWhiteboardLayerDecision(
          'tiles',
          renderRect: renderRect,
          tileCount: tileKeys.length,
          inGesture: inGesture,
          hydrationActive: hydrationActive,
          canOverview: canOverview,
          lod: lod,
        );
        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              children: strokeTileWidgets(
                index: _strokeTiles,
                localRect: renderRect,
                hiddenStrokes: hidden,
                lod: lod,
              ),
            ),
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
          color: bgPaper(_data.bgColorValue, yCream),
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

  Widget _buildWhiteboardLassoLayer(Size viewport) {
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
        // frame; without isolation that re-composites the whole canvas (all
        // pages) each tick. The boundary is clipped to the viewport, not 10k².
        return RepaintBoundary(
          child: CustomPaint(
            painter: LassoPainter(
              ctrl: _lassoCtrl,
              animValue: _lassoAnimCtrl.value,
              strokes: _data.strokes,
              images: _data.images,
              imageCache: _imgCache,
              visibleRect: visibleRect,
              liftedInk: _lassoCtrl.liftedInk,
            ),
            size: const Size(_kCanvasW, _kCanvasH),
          ),
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
                      onZoomToFit: _zoomToFit,
                      onExport: _startExport,
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
                          subtitle:
                              (widget.note.title?.trim().isNotEmpty == true)
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
                              onTap: _zoomToFit,
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
                                  YuLiIcons.discAlbum,
                                  color: yInk,
                                  size: 16,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _startExport,
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
                                  YuLiIcons.share,
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
                                child: RawGestureDetector(
                                  // A stylus must NEVER pan the InteractiveViewer.
                                  // This Eager recognizer (stylus-only) wins the gesture
                                  // arena the instant a pen touches, so the IV's pan
                                  // recognizer is rejected and never fights the stroke.
                                  // Fingers are unaffected (it ignores touch).
                                  gestures: <Type, GestureRecognizerFactory>{
                                    TapGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          TapGestureRecognizer
                                        >(
                                          () => TapGestureRecognizer(),
                                          (i) => i.onTapUp = _onLassoTap,
                                        ),
                                    EagerGestureRecognizer:
                                        GestureRecognizerFactoryWithHandlers<
                                          EagerGestureRecognizer
                                        >(
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
                                      onInteractionStart: (details) {
                                        _viewGestureActive = true;
                                        _viewMoved = false;
                                        _zoomGestureActive = false;
                                        _zoomGestureSeen = false;
                                        _zoomGestureScale = 1;
                                        // New gesture interrupts the prior fling's
                                        // settle watch (re-armed on its end); the
                                        // overview stays up across the chain.
                                        _stopSettleWatch();
                                      },
                                      onInteractionUpdate: (details) {
                                        final zooming =
                                            (details.scale - 1.0).abs() > 0.01;
                                        if (!_viewMoved &&
                                            (zooming ||
                                                details
                                                        .focalPointDelta
                                                        .distance >
                                                    0.5)) {
                                          // First real pan/zoom frame → swap to
                                          // the overview (not a bare touch).
                                          _viewMoved = true;
                                          if (mounted) setState(() {});
                                        }
                                        _zoomGestureScale = details.scale;
                                        _zoomGestureCurrentFocal =
                                            details.localFocalPoint;
                                        if (zooming && !_zoomGestureSeen) {
                                          _zoomGestureSeen = true;
                                          _zoomGestureActive = true;
                                          if (mounted) setState(() {});
                                        } else if (_zoomGestureActive) {
                                          if (mounted) setState(() {});
                                        }
                                      },
                                      onInteractionEnd: (_) {
                                        _viewGestureActive = false;
                                        _viewMoved = false;
                                        _zoomGestureActive = false;
                                        _zoomGestureSeen = false;
                                        _zoomGestureScale = 1;
                                        // Keep the overview up through the whole
                                        // fling; the settle Ticker drops it back to
                                        // crisp tiles + bakes the focus only once the
                                        // view truly stops (swap lands in stillness).
                                        _overviewLinger = true;
                                        _beginSettleWatch();
                                        if (mounted) setState(() {});
                                        // After a 2-finger pan/zoom the snapshot is
                                        // stale → recapture so the loupe keeps sampling
                                        // the right pixels (keeps its position).
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
                                        vertical: c.maxHeight,
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
                                            _buildWhiteboardBackgroundLayer(
                                              viewport,
                                            ),
                                            ...textBlockOverlays,
                                            _buildWhiteboardStrokeLayer(
                                              viewport,
                                            ),
                                            AnimatedBuilder(
                                              animation: _activeTick,
                                              builder: (_, _) {
                                                final activeRect =
                                                    _activeStrokeRect();
                                                if (activeRect == Rect.zero) {
                                                  return const SizedBox.shrink();
                                                }
                                                return Positioned.fromRect(
                                                  rect: activeRect,
                                                  child: IgnorePointer(
                                                    child: RepaintBoundary(
                                                      child: CustomPaint(
                                                        painter:
                                                            _ActiveStrokePainter(
                                                              active: _active,
                                                              tick:
                                                                  _activeTick
                                                                      .value,
                                                              viewScale:
                                                                  _viewScale,
                                                              origin:
                                                                  activeRect
                                                                      .topLeft,
                                                            ),
                                                        size: activeRect.size,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            ...taskBlockOverlays,
                                            _buildWhiteboardLassoLayer(
                                              viewport,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _buildZoomSnapshotLayer(viewport),
                            // Floating palettes — sibling of the canvas Listener so
                            // touching a palette never leaks a pointer into a stroke.
                            // They slide off toward their edge during the eyedropper.
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
                                                  (c) => _palettes?.addColor(c),
                                            ),
                                      ),
                                ),
                              ),
                            if (_pins.isNotEmpty)
                              Positioned.fill(
                                child: PinnedSnapshotsLayer(
                                  pins: _pins,
                                  onMove: _movePin,
                                  onResize: _resizePin,
                                  onClose: _closePin,
                                ),
                              ),
                            // Reactive to _lassoPhaseTick so a grab/release
                            // hides/shows it without a full-tree setState.
                            ValueListenableBuilder<int>(
                              valueListenable: _lassoPhaseTick,
                              builder: (_, _, _) {
                                if (_lassoCtrl.phase == LassoPhase.selected &&
                                    _toolbarVisible) {
                                  return _buildLassoMiniToolbar();
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            if (_showPasteAt != null) _buildPasteButton(),
                            if (_tool == DrawTool.eraser &&
                                _eraserCursor != null)
                              Positioned(
                                left: _eraserCursor!.dx - _eraserScreenRadius,
                                top: _eraserCursor!.dy - _eraserScreenRadius,
                                child: const EraserCursor(
                                  radius: _eraserScreenRadius,
                                ),
                              ),
                            // Eyedropper loupe (viewport-space, like the palettes).
                            if (_eyedropImg != null)
                              ..._buildLoupeOverlay(viewport),
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
                  onMoreColors:
                      () => setState(() {
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
                  onPreview:
                      (c) => setState(() => _data.bgColorValue = c.toARGB32()),
                  onCommit: _setBgColor,
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
                key: const ValueKey('rp-floating-toolbars'),
                open: _floatingToolbarsPopupOpen,
                onDismiss:
                    () => setState(() => _floatingToolbarsPopupOpen = false),
                child: _buildFloatingToolbarsPopup(),
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
    return Rect.fromLTRB(
      l < r ? l : r,
      t < b ? t : b,
      l < r ? r : l,
      t < b ? b : t,
    );
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
      await _ensureStrokesLoadedForRegion(region);
      if (!mounted) return;
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
  final VoidCallback onZoomToFit;
  final VoidCallback onExport;
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
    required this.onZoomToFit,
    required this.onExport,
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
              child: const Icon(YuLiIcons.scan, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onZoomToFit,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.discAlbum, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExport,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.share, color: yInk, size: 16),
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
              child: const Icon(YuLiIcons.chevronDown, color: yInk, size: 18),
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
  final Offset origin;
  final int paintVersion;
  final Set<int>? hiddenIndices;
  final Set<int>? hiddenImageIndices;

  /// Layer split so strokes can render ABOVE the text-block overlays: the bottom
  /// layer paints paper+pattern+images ([drawStrokes] false), and a second
  /// layer above the text overlays paints only strokes ([drawBackground] false).
  /// Strokes are drawn directly + culled — used for the background layer
  /// ([drawStrokes] false) and the zoomed-out fallback; the normal stroke layer
  /// is the tiled [strokeTileWidgets].
  final bool drawBackground;
  final bool drawStrokes;
  final int lod;

  _CanvasPainter({
    required this.strokes,
    required this.images,
    required this.imageCache,
    required this.background,
    required this.paper,
    required this.visibleRect,
    required this.origin,
    required this.paintVersion,
    this.hiddenIndices,
    this.hiddenImageIndices,
    this.drawBackground = true,
    this.drawStrokes = true,
    this.lod = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vr = visibleRect;
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
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
      canvas.save();
      canvas.clipRect(vr);
      final hidden = hiddenIndices;
      for (int i = 0; i < strokes.length; i++) {
        if (hidden != null && hidden.contains(i)) continue;
        if (strokeOverlapsRect(strokes[i], vr)) {
          drawStroke(canvas, strokes[i], lod: lod);
        }
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.paintVersion != paintVersion ||
      old.visibleRect != visibleRect ||
      old.origin != origin ||
      old.background != background ||
      old.paper != paper ||
      old.drawBackground != drawBackground ||
      old.drawStrokes != drawStrokes ||
      old.lod != lod ||
      old.hiddenIndices != hiddenIndices ||
      old.hiddenImageIndices != hiddenImageIndices;
}

/// Paints only the in-progress stroke (world coords), in its own
/// RepaintBoundary, so live point additions don't repaint the whole canvas.
class _ActiveStrokePainter extends CustomPainter {
  final DrawingStroke? active;
  final int tick;
  final double viewScale;
  final Offset origin;

  _ActiveStrokePainter({
    required this.active,
    required this.tick,
    this.viewScale = 1.0,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (active == null) return;
    canvas.translate(-origin.dx, -origin.dy);
    drawActiveStroke(canvas, active!, viewScale: viewScale);
  }

  @override
  bool shouldRepaint(_ActiveStrokePainter old) =>
      old.active != active ||
      old.tick != tick ||
      old.viewScale != viewScale ||
      old.origin != origin;
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
                    viewCtrl.value,
                    worldRect!.topLeft,
                  );
                  final b = MatrixUtils.transformPoint(
                    viewCtrl.value,
                    worldRect!.bottomRight,
                  );
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
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: yInk,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
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
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
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
                      border: Border.all(
                        color: yBorderStrong,
                        width: yLineHeavy,
                      ),
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
    canvas.drawRect(Rect.fromLTRB(0, sel.bottom, size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0, sel.top, sel.left, sel.bottom), dim);
    canvas.drawRect(
      Rect.fromLTRB(sel.right, sel.top, size.width, sel.bottom),
      dim,
    );
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
    final border =
        Paint()
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
