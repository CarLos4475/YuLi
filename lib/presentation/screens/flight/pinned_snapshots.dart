import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'pdf_pin_body.dart';
import 'video_pin_body.dart';

enum FloatingPinKind { snapshot, image, pdf, video }

/// Per-kind payload. Snapshot owns a volatile [ui.Image]; image references a
/// file on disk decoded through Flutter's ImageCache. Sealed so adding a kind
/// (pdf/video) forces every switch to handle it.
sealed class FloatingPinPayload {
  /// width / height. For aspect-locked kinds the resize keeps this ratio.
  double get aspectRatio;
  bool get aspectLocked;

  /// Filename under `floating_pins/{noteId}/` for media kinds (null = none).
  String? get mediaFilename;

  /// Fixed UI below an aspect-locked body (e.g. a video's study bar). The clamp
  /// reserves it so width still drives the 16:9 player height beneath it.
  double get bottomChromeHeight => 0;

  /// Kind-specific bits to persist in `metadata_json` (e.g. a PDF's page).
  Map<String, dynamic> metadataExtras() => const {};

  void dispose();
}

class SnapshotPinPayload extends FloatingPinPayload {
  final ui.Image image;
  @override
  final double aspectRatio;

  SnapshotPinPayload({required this.image})
      : aspectRatio = image.height == 0 ? 1.0 : image.width / image.height;

  @override
  bool get aspectLocked => true;
  @override
  String? get mediaFilename => null;
  @override
  void dispose() => image.dispose();
}

class ImagePinPayload extends FloatingPinPayload {
  /// Absolute path under `floating_pins/{noteId}/{uuid}.jpg`.
  final String filePath;
  @override
  final double aspectRatio;

  ImagePinPayload({required this.filePath, required this.aspectRatio});

  @override
  bool get aspectLocked => true;
  @override
  String get mediaFilename => filePath.split(Platform.pathSeparator).last;
  @override
  // ImageCache owns the decoded bitmap; nothing to free here.
  void dispose() {}
}

class PdfPinPayload extends FloatingPinPayload {
  /// Absolute path under `floating_pins/{noteId}/{uuid}.pdf`.
  final String filePath;

  /// Last page the user was on (1-based). Mutated as they navigate and
  /// persisted so the page survives collapse, leaving the note, and app restart.
  int page;

  PdfPinPayload({required this.filePath, this.page = 1});

  @override
  double get aspectRatio => 1.0; // unused: PDF resizes freely
  @override
  bool get aspectLocked => false;
  @override
  String get mediaFilename => filePath.split(Platform.pathSeparator).last;
  @override
  Map<String, dynamic> metadataExtras() => {'page': page};
  @override
  // pdfx controller is owned by the body widget's State, not the payload.
  void dispose() {}
}

class VideoPinPayload extends FloatingPinPayload {
  /// YouTube video id (online-only by nature; no file on disk).
  final String videoId;

  /// Last playback position (seconds), persisted so it resumes where you left.
  int lastPositionSeconds;

  VideoPinPayload({required this.videoId, this.lastPositionSeconds = 0});

  @override
  double get aspectRatio => 16 / 9; // the player; study bar is extra chrome
  @override
  bool get aspectLocked => true;
  @override
  double get bottomChromeHeight => kVideoStudyBarHeight;
  @override
  String? get mediaFilename => null; // remote — nothing for the file GC
  @override
  Map<String, dynamic> metadataExtras() =>
      {'videoId': videoId, 't': lastPositionSeconds};
  @override
  // YoutubePlayerController is owned by the body widget's State.
  void dispose() {}
}

class FloatingPin {
  final String id;

  /// Persisted-row id (null for volatile snapshots).
  final int? dbId;
  final FloatingPinKind kind;
  final FloatingPinPayload payload;
  final Rect rect;
  final bool collapsed;

  /// Shown after the kind tag in the header (`VIDEO · title`). Null = tag only.
  final String? title;

  const FloatingPin({
    required this.id,
    this.dbId,
    required this.kind,
    required this.payload,
    required this.rect,
    this.collapsed = false,
    this.title,
  });

  bool get persisted => kind != FloatingPinKind.snapshot;

  String get kindName => switch (kind) {
        FloatingPinKind.snapshot => 'snapshot',
        FloatingPinKind.image => 'image',
        FloatingPinKind.pdf => 'pdf',
        FloatingPinKind.video => 'video',
      };

  /// Header tag (uppercase per UI convention).
  String get kindTag => switch (kind) {
        FloatingPinKind.snapshot => 'PIN',
        FloatingPinKind.image => 'IMAGEN',
        FloatingPinKind.pdf => 'PDF',
        FloatingPinKind.video => 'VIDEO',
      };

  Map<String, dynamic> toMetadata() => {
        if (payload.mediaFilename != null) 'filename': payload.mediaFilename,
        'aspect': payload.aspectRatio,
        if (title != null) 'title': title,
        ...payload.metadataExtras(),
      };

  FloatingPin copyWith({Rect? rect, bool? collapsed, int? dbId}) => FloatingPin(
        id: id,
        dbId: dbId ?? this.dbId,
        kind: kind,
        payload: payload,
        rect: rect ?? this.rect,
        collapsed: collapsed ?? this.collapsed,
        title: title,
      );
}

/// Drift-free seam: the editor hands the controller an implementation that
/// writes persisted pins to the repo + storage. The controller never imports
/// Drift. All methods are fire-and-forget except [insert] (needs the new id).
abstract class FloatingPinPersistence {
  Future<int> insert(FloatingPin pin);
  void save(FloatingPin pin);
  void remove(FloatingPin pin);
  void reorder(List<FloatingPin> persistedFrontLast);
}

class FloatingPinController {
  FloatingPinController();

  final ValueNotifier<List<FloatingPin>> _pins =
      ValueNotifier<List<FloatingPin>>(const []);

  ValueListenable<List<FloatingPin>> get pins => _pins;
  List<FloatingPin> get value => _pins.value;

  FloatingPinPersistence? persistence;
  bool _persistedLoaded = false;
  bool get persistedLoaded => _persistedLoaded;

  /// Hydrates persisted pins ONCE per controller lifetime. Re-entering the note
  /// is a no-op (they already live in memory). Persisted pins sit BEHIND any
  /// volatile snapshots added this session.
  void loadPersisted(List<FloatingPin> persisted) {
    if (_persistedLoaded) return;
    _persistedLoaded = true;
    if (persisted.isEmpty) return;
    _pins.value = List.unmodifiable([...persisted, ..._pins.value]);
  }

  FloatingPin addSnapshot({
    required ui.Image image,
    required Rect rect,
    required Rect usableBounds,
  }) {
    final payload = SnapshotPinPayload(image: image);
    final pin = FloatingPin(
      id: _newId(),
      kind: FloatingPinKind.snapshot,
      payload: payload,
      rect: clampPinRect(rect, payload: payload, usableBounds: usableBounds),
    );
    _pins.value = List.unmodifiable([..._pins.value, pin]);
    return pin;
  }

  /// Adds a persisted image pin. Files are already copied by the caller; this
  /// inserts the row (awaiting the new id) before showing the pin so its dbId
  /// is never null in the list.
  Future<FloatingPin> addImage({
    required String filePath,
    required double aspectRatio,
    required Rect rect,
    required Rect usableBounds,
    String? title,
  }) async {
    final payload =
        ImagePinPayload(filePath: filePath, aspectRatio: aspectRatio);
    var pin = FloatingPin(
      id: _newId(),
      kind: FloatingPinKind.image,
      payload: payload,
      rect: clampPinRect(rect, payload: payload, usableBounds: usableBounds),
      title: title,
    );
    final dbId = await persistence?.insert(pin);
    pin = pin.copyWith(dbId: dbId);
    _pins.value = List.unmodifiable([..._pins.value, pin]);
    persistence?.reorder(_persistedOf(_pins.value));
    return pin;
  }

  /// Adds a persisted YouTube video pin (online-only, no file on disk).
  Future<FloatingPin> addVideo({
    required String videoId,
    required Rect rect,
    required Rect usableBounds,
    String? title,
  }) async {
    final payload = VideoPinPayload(videoId: videoId);
    var pin = FloatingPin(
      id: _newId(),
      kind: FloatingPinKind.video,
      payload: payload,
      rect: clampPinRect(rect, payload: payload, usableBounds: usableBounds),
      title: title,
    );
    final dbId = await persistence?.insert(pin);
    pin = pin.copyWith(dbId: dbId);
    _pins.value = List.unmodifiable([..._pins.value, pin]);
    persistence?.reorder(_persistedOf(_pins.value));
    return pin;
  }

  /// Adds a persisted PDF pin (free-resize). File already copied by the caller.
  Future<FloatingPin> addPdf({
    required String filePath,
    required Rect rect,
    required Rect usableBounds,
    String? title,
  }) async {
    final payload = PdfPinPayload(filePath: filePath);
    var pin = FloatingPin(
      id: _newId(),
      kind: FloatingPinKind.pdf,
      payload: payload,
      rect: clampPinRect(rect, payload: payload, usableBounds: usableBounds),
      title: title,
    );
    final dbId = await persistence?.insert(pin);
    pin = pin.copyWith(dbId: dbId);
    _pins.value = List.unmodifiable([..._pins.value, pin]);
    persistence?.reorder(_persistedOf(_pins.value));
    return pin;
  }

  void commitRect(String id, Rect rect, Rect usableBounds) {
    _replace(
      id,
      (pin) => pin.copyWith(
        rect: clampPinRect(rect, payload: pin.payload, usableBounds: usableBounds),
      ),
      persist: true,
    );
  }

  void toggleCollapsed(String id) {
    _replace(id, (pin) => pin.copyWith(collapsed: !pin.collapsed),
        persist: true);
  }

  /// Records the current PDF page so it survives collapse / re-open / restart.
  /// Mutates the payload in place (no layout change) and persists the row; the
  /// list is untouched so the layer doesn't rebuild.
  void updatePdfPage(String id, int page) {
    final idx = _pins.value.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pin = _pins.value[idx];
    final payload = pin.payload;
    if (payload is! PdfPinPayload || payload.page == page) return;
    payload.page = page;
    if (pin.persisted) persistence?.save(pin);
  }

  /// Records the video's playback position so it resumes where the user left.
  /// Mutates the payload in place + persists the row; no list rebuild.
  void updateVideoPosition(String id, int seconds) {
    final idx = _pins.value.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final pin = _pins.value[idx];
    final payload = pin.payload;
    if (payload is! VideoPinPayload || payload.lastPositionSeconds == seconds) {
      return;
    }
    payload.lastPositionSeconds = seconds;
    if (pin.persisted) persistence?.save(pin);
  }

  void bringToFront(String id) {
    final current = _pins.value;
    final index = current.indexWhere((pin) => pin.id == id);
    if (index < 0 || index == current.length - 1) return;
    final next = List<FloatingPin>.from(current);
    final pin = next.removeAt(index);
    next.add(pin);
    _pins.value = List.unmodifiable(next);
    persistence?.reorder(_persistedOf(next));
  }

  void close(String id) {
    final current = _pins.value;
    final index = current.indexWhere((pin) => pin.id == id);
    if (index < 0) return;
    final next = List<FloatingPin>.from(current);
    final removed = next.removeAt(index);
    if (removed.persisted) {
      persistence?.remove(removed);
    } else {
      removed.payload.dispose();
    }
    _pins.value = List.unmodifiable(next);
  }

  /// Frees in-memory resources WITHOUT touching persistence (e.g. clearing a
  /// test store). Persisted media stays on disk.
  void disposeAll() {
    for (final pin in _pins.value) {
      pin.payload.dispose();
    }
    _pins.value = const [];
  }

  List<FloatingPin> _persistedOf(List<FloatingPin> pins) =>
      [for (final p in pins) if (p.persisted) p];

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _replace(
    String id,
    FloatingPin Function(FloatingPin pin) update, {
    bool persist = false,
  }) {
    FloatingPin? updated;
    final next = <FloatingPin>[];
    for (final pin in _pins.value) {
      if (pin.id == id) {
        updated = update(pin);
        next.add(updated);
      } else {
        next.add(pin);
      }
    }
    if (updated == null) return;
    _pins.value = List.unmodifiable(next);
    if (persist && updated.persisted) persistence?.save(updated);
  }
}

class FloatingPinControllerStore {
  FloatingPinControllerStore._();
  static final FloatingPinControllerStore instance =
      FloatingPinControllerStore._();

  final Map<Object, FloatingPinController> _byNote = {};

  FloatingPinController forNote(Object noteId) =>
      _byNote.putIfAbsent(noteId, FloatingPinController.new);

  void clearForTesting() {
    for (final controller in _byNote.values) {
      controller.disposeAll();
    }
    _byNote.clear();
  }
}

const double floatingPinHeaderHeight = 24;
const double _kHandle = 22;
const double _kMinWidth = 100;
const Duration _kCollapseDuration = Duration(milliseconds: 200);

/// Clamps a pin rect into [usableBounds]. Aspect-locked kinds derive height
/// from width and the payload ratio; free kinds (future pdf) keep their height.
Rect clampPinRect(
  Rect rect, {
  required FloatingPinPayload payload,
  required Rect usableBounds,
}) {
  if (usableBounds.width <= 0 || usableBounds.height <= 0) return rect;
  final aspect = payload.aspectRatio <= 0 ? 1.0 : payload.aspectRatio;
  final chrome = floatingPinHeaderHeight + payload.bottomChromeHeight;
  final maxWidth = usableBounds.width;
  final maxBodyHeight =
      usableBounds.height <= chrome ? 0.0 : usableBounds.height - chrome;

  if (!payload.aspectLocked) {
    final width = rect.width.clamp(_kMinWidth, maxWidth).toDouble();
    final height = rect.height
        .clamp(floatingPinHeaderHeight, usableBounds.height)
        .toDouble();
    final left =
        rect.left.clamp(usableBounds.left, usableBounds.right - width).toDouble();
    final top = rect.top
        .clamp(usableBounds.top, usableBounds.bottom - height)
        .toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  final maxWidthByHeight = maxBodyHeight * aspect;
  final maxAllowedWidth =
      maxWidth < maxWidthByHeight ? maxWidth : maxWidthByHeight;
  final minAllowedWidth =
      maxAllowedWidth < _kMinWidth ? maxAllowedWidth : _kMinWidth;
  final width = rect.width.clamp(minAllowedWidth, maxAllowedWidth).toDouble();
  final height = chrome + width / aspect;
  final left =
      rect.left.clamp(usableBounds.left, usableBounds.right - width).toDouble();
  final top =
      rect.top.clamp(usableBounds.top, usableBounds.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

class FloatingPinsLayer extends StatefulWidget {
  final FloatingPinController controller;
  final Rect usableBounds;

  /// Note/folder accent — fills primary controls and the resize handle.
  ///final Color accent;

  const FloatingPinsLayer({
    super.key,
    required this.controller,
    required this.usableBounds,
  /// required this.accent,
  });

  @override
  State<FloatingPinsLayer> createState() => _FloatingPinsLayerState();
}

class _FloatingPinsLayerState extends State<FloatingPinsLayer>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _exits = {};
  final Set<String> _closing = {};

  @override
  void dispose() {
    for (final controller in _exits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _requestClose(String id) {
    if (_closing.contains(id)) return;
    _closing.add(id);
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _exits[id] = controller;
    controller.addListener(() => setState(() {}));
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _exits.remove(id)?.dispose();
      _closing.remove(id);
      widget.controller.close(id);
    });
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<FloatingPin>>(
      valueListenable: widget.controller.pins,
      builder: (context, pins, _) {
        if (pins.isEmpty) return const SizedBox.shrink();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final pin in pins)
              _FloatingPinWindow(
                key: ValueKey(pin.id),
                pin: pin,
                controller: widget.controller,
                usableBounds: widget.usableBounds,
                exitProgress: _exits[pin.id]?.value ?? 0,
                closing: _closing.contains(pin.id),
                onRequestClose: _requestClose,
              ),
          ],
        );
      },
    );
  }
}

class _FloatingPinWindow extends StatefulWidget {
  final FloatingPin pin;
  final FloatingPinController controller;
  final Rect usableBounds;
  final double exitProgress;
  final bool closing;
  final void Function(String id) onRequestClose;

  const _FloatingPinWindow({
    super.key,
    required this.pin,
    required this.controller,
    required this.usableBounds,
    required this.exitProgress,
    required this.closing,
    required this.onRequestClose,
  });

  @override
  State<_FloatingPinWindow> createState() => _FloatingPinWindowState();
}

class _FloatingPinWindowState extends State<_FloatingPinWindow>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<Rect> _liveRect = ValueNotifier<Rect>(
    widget.pin.rect,
  );
  // 0 = expanded, 1 = collapsed (header only). Independent of resize so a drag
  // never animates the body.
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: _kCollapseDuration,
    value: widget.pin.collapsed ? 1 : 0,
  );
  late Rect _gestureStartRect;
  late Offset _gestureStartPointer;
  bool _dragging = false;
  bool _gesturePrepared = false;

  @override
  void didUpdateWidget(covariant _FloatingPinWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.pin.rect != widget.pin.rect ||
            oldWidget.usableBounds != widget.usableBounds)) {
      _liveRect.value = _clamp(widget.pin.rect);
    }
    if (oldWidget.pin.collapsed != widget.pin.collapsed) {
      widget.pin.collapsed ? _collapse.forward() : _collapse.reverse();
    }
  }

  @override
  void dispose() {
    _liveRect.dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _prepareGesture(Offset pointer) {
    _gesturePrepared = true;
    _gestureStartRect = _liveRect.value;
    _gestureStartPointer = pointer;
  }

  void _beginGesture(Offset pointer) {
    if (!_gesturePrepared) _prepareGesture(pointer);
    _dragging = true;
    // Grabbing (move or resize) raises the pin. Once per gesture (onPanStart),
    // not per event — the reorder is cheap and the dragging State survives it
    // (stable ValueKey).
    widget.controller.bringToFront(widget.pin.id);
  }

  void _move(DragUpdateDetails details) {
    final next = _gestureStartRect.shift(
      details.globalPosition - _gestureStartPointer,
    );
    _liveRect.value = _clamp(next);
  }

  void _resize(DragUpdateDetails details) {
    final delta = details.globalPosition - _gestureStartPointer;
    final nextWidth = _gestureStartRect.width + delta.dx;
    // Free-resize kinds (pdf) grow in both axes from the corner; aspect-locked
    // kinds derive height from width in the clamp, so dy is ignored there.
    final nextHeight = widget.pin.payload.aspectLocked
        ? _gestureStartRect.height
        : _gestureStartRect.height + delta.dy;
    _liveRect.value = _clamp(
      Rect.fromLTWH(
        _gestureStartRect.left,
        _gestureStartRect.top,
        nextWidth,
        nextHeight,
      ),
    );
  }

  void _commitGesture() {
    if (!_dragging) return;
    _dragging = false;
    _gesturePrepared = false;
    widget.controller.commitRect(
      widget.pin.id,
      _liveRect.value,
      widget.usableBounds,
    );
  }

  Rect _clamp(Rect rect) => clampPinRect(
        rect,
        payload: widget.pin.payload,
        usableBounds: widget.usableBounds,
      );

  Widget _buildBody(double dpr) {
    final payload = widget.pin.payload;
    switch (payload) {
      case SnapshotPinPayload():
        return RawImage(image: payload.image, fit: BoxFit.fill);
      case ImagePinPayload():
        // Decode at the COMMITTED width (widget.pin.rect, not _liveRect) so a
        // resize stretches the cached bitmap during the gesture and only
        // re-decodes once on release (same raster-during-gesture trade-off).
        final cacheW = (widget.pin.rect.width * dpr).round().clamp(1, 4096);
        return Image.file(
          File(payload.filePath),
          fit: BoxFit.fill,
          cacheWidth: cacheW,
          gaplessPlayback: true,
        );
      case PdfPinPayload():
        return PdfPinBody(
          filePath: payload.filePath,
          initialPage: payload.page,
          onPageChanged: (p) =>
              widget.controller.updatePdfPage(widget.pin.id, p),
        );
      case VideoPinPayload():
        return VideoPinBody(
          videoId: payload.videoId,
          startSeconds: payload.lastPositionSeconds,
          // Collapsing pauses (the WebView stays mounted, just hidden).
          active: !widget.pin.collapsed,
          onPosition: (s) =>
              widget.controller.updateVideoPosition(widget.pin.id, s),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return ValueListenableBuilder<Rect>(
      valueListenable: _liveRect,
      builder: (context, rect, _) {
        final body = _buildBody(dpr);
        return AnimatedBuilder(
          animation: _collapse,
          builder: (context, _) {
            final factor = 1 - _collapse.value; // body-visible fraction
            final bodyHeight = (rect.height - floatingPinHeaderHeight)
                .clamp(0.0, double.infinity);
            // No explicit Container height: the Column min-size + border wrap
            // drive it, so the border insets never overflow the header (which
            // they would if a fixed body height fought them). The body clips
            // (not squishes) as it collapses.
            Widget card = RepaintBoundary(
              child: Container(
                width: rect.width,
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                  boxShadow: const [
                    BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PinHeader(
                      pinId: widget.pin.id,
                      tag: widget.pin.kindTag,
                      title: widget.pin.title,
                      collapsed: widget.pin.collapsed,
                      onMoveDown: _prepareGesture,
                      onMoveStart: _beginGesture,
                      onMoveUpdate: _move,
                      onMoveEnd: _commitGesture,
                      onTap: () =>
                          widget.controller.bringToFront(widget.pin.id),
                      onToggleCollapsed: () =>
                          widget.controller.toggleCollapsed(widget.pin.id),
                      onClose: () => widget.onRequestClose(widget.pin.id),
                    ),
                    // Body stays MOUNTED even when fully collapsed so stateful
                    // bodies — PDF page, video player — survive collapse/restore
                    // instead of resetting.  Offstage kicks in at 40% so the
                    // WebView is hidden before ClipRect reaches zero, sidestepping
                    // Android platform-view bleeding. At 40% the body is already
                    // ~60% clipped — the transition is seamless.
                    if (bodyHeight > 0)
                      Offstage(
                        offstage: _collapse.value > 0.4,
                        child: ClipRect(
                          child: SizedBox(
                            width: double.infinity,
                            height: bodyHeight * factor,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: bodyHeight,
                              maxHeight: bodyHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(child: body),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanDown: (d) =>
                                          _prepareGesture(d.globalPosition),
                                      onPanStart: (d) =>
                                          _beginGesture(d.globalPosition),
                                      onPanUpdate: _resize,
                                      onPanEnd: (_) => _commitGesture(),
                                      onPanCancel: _commitGesture,
                                      child: Container(
                                        width: _kHandle,
                                        height: _kHandle,
                                        decoration: const BoxDecoration(
                                          color: yCream,
                                          border: Border(
                                            left: BorderSide(
                                              color: yBorderStrong,
                                              width: yLineThin,
                                            ),
                                            top: BorderSide(
                                              color: yBorderStrong,
                                              width: yLineThin,
                                            ),
                                          ),
                                        ),
                                        child: Icon(
                                          YuLiIcons.maximize,
                                          size: 11,
                                          color: yInk,
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
                  ],
                ),
              ),
            );

            card = TweenAnimationBuilder<double>(
              key: ValueKey('enter-${widget.pin.id}'),
              tween: Tween(begin: 1.0, end: 0.0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: card,
              builder: (_, t, child) => Transform.translate(
                offset: Offset(t * rect.width, 0),
                child: child,
              ),
            );

            if (widget.closing) {
              final eased = Curves.easeInCubic.transform(widget.exitProgress);
              card = Transform.translate(
                offset: Offset(rect.width * 2 * eased, 0),
                child: card,
              );
            }

            return Positioned(left: rect.left, top: rect.top, child: card);
          },
        );
      },
    );
  }
}

class _PinHeader extends StatelessWidget {
  final String pinId;
  final String tag;
  final String? title;
  final bool collapsed;
  final void Function(Offset pointer) onMoveDown;
  final void Function(Offset pointer) onMoveStart;
  final void Function(DragUpdateDetails details) onMoveUpdate;
  final VoidCallback onMoveEnd;
  final VoidCallback onTap;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onClose;

  const _PinHeader({
    required this.pinId,
    required this.tag,
    required this.title,
    required this.collapsed,
    required this.onMoveDown,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onTap,
    required this.onToggleCollapsed,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final label = title == null ? tag : '$tag · $title';
    return GestureDetector(
      key: ValueKey('pin-header-$pinId'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanDown: (details) => onMoveDown(details.globalPosition),
      onPanStart: (details) => onMoveStart(details.globalPosition),
      onPanUpdate: onMoveUpdate,
      onPanEnd: (_) => onMoveEnd(),
      onPanCancel: onMoveEnd,
      child: Container(
        height: floatingPinHeaderHeight,
        color: yCream2,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Icon(YuLiIcons.pin, size: 12, color: yMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.1,
                  color: yMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleCollapsed,
              child: Icon(
                collapsed ? YuLiIcons.chevronDown : YuLiIcons.chevronUp,
                size: 15,
                color: yInk,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Icon(YuLiIcons.close, size: 15, color: yInk),
            ),
          ],
        ),
      ),
    );
  }
}
