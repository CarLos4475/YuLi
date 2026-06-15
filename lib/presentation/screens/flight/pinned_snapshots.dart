import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

enum FloatingPinKind { snapshot }

class SnapshotPinPayload {
  final ui.Image image;
  final double aspectRatio;

  SnapshotPinPayload({required this.image})
    : aspectRatio = image.height == 0 ? 1.0 : image.width / image.height;

  void dispose() => image.dispose();
}

class FloatingPin {
  final String id;
  final FloatingPinKind kind;
  final SnapshotPinPayload payload;
  final Rect rect;
  final bool collapsed;

  const FloatingPin({
    required this.id,
    required this.kind,
    required this.payload,
    required this.rect,
    this.collapsed = false,
  });

  FloatingPin copyWith({Rect? rect, bool? collapsed}) => FloatingPin(
    id: id,
    kind: kind,
    payload: payload,
    rect: rect ?? this.rect,
    collapsed: collapsed ?? this.collapsed,
  );
}

class FloatingPinController {
  FloatingPinController();

  final ValueNotifier<List<FloatingPin>> _pins =
      ValueNotifier<List<FloatingPin>>(const []);

  ValueListenable<List<FloatingPin>> get pins => _pins;
  List<FloatingPin> get value => _pins.value;

  FloatingPin addSnapshot({
    required ui.Image image,
    required Rect rect,
    required Rect usableBounds,
  }) {
    final payload = SnapshotPinPayload(image: image);
    final pin = FloatingPin(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: FloatingPinKind.snapshot,
      payload: payload,
      rect: clampSnapshotRect(
        rect,
        aspectRatio: payload.aspectRatio,
        usableBounds: usableBounds,
      ),
    );
    _pins.value = List.unmodifiable([..._pins.value, pin]);
    return pin;
  }

  void commitRect(String id, Rect rect, Rect usableBounds) {
    _replace(
      id,
      (pin) => pin.copyWith(
        rect: clampSnapshotRect(
          rect,
          aspectRatio: pin.payload.aspectRatio,
          usableBounds: usableBounds,
        ),
      ),
    );
  }

  void toggleCollapsed(String id) {
    _replace(id, (pin) => pin.copyWith(collapsed: !pin.collapsed));
  }

  void bringToFront(String id) {
    final current = _pins.value;
    final index = current.indexWhere((pin) => pin.id == id);
    if (index < 0 || index == current.length - 1) return;
    final next = List<FloatingPin>.from(current);
    final pin = next.removeAt(index);
    next.add(pin);
    _pins.value = List.unmodifiable(next);
  }

  void close(String id) {
    final current = _pins.value;
    final index = current.indexWhere((pin) => pin.id == id);
    if (index < 0) return;
    final next = List<FloatingPin>.from(current);
    final removed = next.removeAt(index);
    removed.payload.dispose();
    _pins.value = List.unmodifiable(next);
  }

  void disposeAll() {
    for (final pin in _pins.value) {
      pin.payload.dispose();
    }
    _pins.value = const [];
  }

  void _replace(String id, FloatingPin Function(FloatingPin pin) update) {
    var changed = false;
    final next = <FloatingPin>[];
    for (final pin in _pins.value) {
      if (pin.id == id) {
        next.add(update(pin));
        changed = true;
      } else {
        next.add(pin);
      }
    }
    if (changed) _pins.value = List.unmodifiable(next);
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

Rect clampSnapshotRect(
  Rect rect, {
  required double aspectRatio,
  required Rect usableBounds,
}) {
  if (usableBounds.width <= 0 || usableBounds.height <= 0) return rect;
  final aspect = aspectRatio <= 0 ? 1.0 : aspectRatio;
  final maxWidth = usableBounds.width;
  final maxBodyHeight =
      usableBounds.height <= floatingPinHeaderHeight
          ? 0.0
          : usableBounds.height - floatingPinHeaderHeight;
  final maxWidthByHeight = maxBodyHeight * aspect;
  final maxAllowedWidth =
      maxWidth < maxWidthByHeight ? maxWidth : maxWidthByHeight;
  final minAllowedWidth =
      maxAllowedWidth < _kMinWidth ? maxAllowedWidth : _kMinWidth;
  final width = rect.width.clamp(minAllowedWidth, maxAllowedWidth).toDouble();
  final height = floatingPinHeaderHeight + width / aspect;
  final left =
      rect.left.clamp(usableBounds.left, usableBounds.right - width).toDouble();
  final top =
      rect.top.clamp(usableBounds.top, usableBounds.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

class FloatingPinsLayer extends StatefulWidget {
  final FloatingPinController controller;
  final Rect usableBounds;

  const FloatingPinsLayer({
    super.key,
    required this.controller,
    required this.usableBounds,
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

class _FloatingPinWindowState extends State<_FloatingPinWindow> {
  late final ValueNotifier<Rect> _liveRect = ValueNotifier<Rect>(
    widget.pin.rect,
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
  }

  @override
  void dispose() {
    _liveRect.dispose();
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
    // Grabbing a pin (header move or resize) raises it. Fires once per gesture
    // (onPanStart), not per pointer event, so the list reorder is cheap and the
    // dragging State/_liveRect survive the rebuild (stable ValueKey).
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
    _liveRect.value = _clamp(
      Rect.fromLTWH(
        _gestureStartRect.left,
        _gestureStartRect.top,
        nextWidth,
        _gestureStartRect.height,
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

  Rect _clamp(Rect rect) => clampSnapshotRect(
    rect,
    aspectRatio: widget.pin.payload.aspectRatio,
    usableBounds: widget.usableBounds,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Rect>(
      valueListenable: _liveRect,
      builder: (context, rect, _) {
        final isCollapsed = widget.pin.collapsed;
        final height = isCollapsed ? floatingPinHeaderHeight : rect.height;
        Widget card = RepaintBoundary(
          child: Container(
            width: rect.width,
            height: height,
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
                  collapsed: isCollapsed,
                  onMoveDown: _prepareGesture,
                  onMoveStart: _beginGesture,
                  onMoveUpdate: _move,
                  onMoveEnd: _commitGesture,
                  onTap: () => widget.controller.bringToFront(widget.pin.id),
                  onToggleCollapsed:
                      () => widget.controller.toggleCollapsed(widget.pin.id),
                  onClose: () => widget.onRequestClose(widget.pin.id),
                ),
                if (!isCollapsed)
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RawImage(
                            image: widget.pin.payload.image,
                            fit: BoxFit.fill,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanDown:
                                (details) =>
                                    _prepareGesture(details.globalPosition),
                            onPanStart:
                                (details) =>
                                    _beginGesture(details.globalPosition),
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
          builder:
              (_, t, child) =>
                  Transform.translate(offset: Offset(t * rect.width, 0), child: child),
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
  }
}

class _PinHeader extends StatelessWidget {
  final String pinId;
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
            const Spacer(),
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
