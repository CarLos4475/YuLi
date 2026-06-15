import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

class PinnedSnapshot {
  final String id;
  final ui.Image image;
  final double aspect;
  Offset pos;
  double width;

  PinnedSnapshot({
    required this.id,
    required this.image,
    required this.pos,
    required this.width,
  }) : aspect = image.height == 0 ? 1.0 : image.width / image.height;

  double get bodyHeight => width / aspect;

  void dispose() => image.dispose();
}

class PinnedSnapshotStore {
  PinnedSnapshotStore._();
  static final PinnedSnapshotStore instance = PinnedSnapshotStore._();

  final Map<Object, List<PinnedSnapshot>> _byNote = {};

  List<PinnedSnapshot> forNote(Object noteId) =>
      _byNote.putIfAbsent(noteId, () => []);
}

const double _kHeaderH = 24;
const double _kHandle = 22;

class PinnedSnapshotsLayer extends StatefulWidget {
  final List<PinnedSnapshot> pins;
  final void Function(String id, Offset delta) onMove;
  final void Function(String id, double dWidth) onResize;
  final void Function(String id) onClose;

  const PinnedSnapshotsLayer({
    super.key,
    required this.pins,
    required this.onMove,
    required this.onResize,
    required this.onClose,
  });

  @override
  State<PinnedSnapshotsLayer> createState() => _PinnedSnapshotsLayerState();
}

class _PinnedSnapshotsLayerState extends State<PinnedSnapshotsLayer>
    with TickerProviderStateMixin {
  final Map<String, AnimationController> _exits = {};
  final Map<String, PinnedSnapshot> _stash = {};

  @override
  void didUpdateWidget(PinnedSnapshotsLayer old) {
    super.didUpdateWidget(old);
    _stash.removeWhere(
      (id, _) =>
          widget.pins.where((p) => p.id == id).isEmpty &&
          !_exits.containsKey(id),
    );
  }

  void _handleClose(PinnedSnapshot p) {
    if (_exits.containsKey(p.id)) return;
    _stash[p.id] = p;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _exits[p.id] = ctrl;
    ctrl.addListener(() => setState(() {}));
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _exits.remove(p.id)?.dispose();
        _stash.remove(p.id);
        widget.onClose(p.id);
      }
    });
    ctrl.forward();
  }

  @override
  void dispose() {
    for (final c in _exits.values) { c.dispose(); }
    for (final s in _stash.values) { s.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinSet = <String>{for (final p in widget.pins) p.id};
    final allIds = <String>{...pinSet, ..._exits.keys};
    if (allIds.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final wins = <Widget>[];
        for (final id in allIds) {
          final p = pinSet.contains(id)
              ? widget.pins.firstWhere((x) => x.id == id)
              : _stash[id];
          if (p != null) wins.add(_buildWindow(p, vw));
        }
        return Stack(clipBehavior: Clip.none, children: wins);
      },
    );
  }

  Widget _buildWindow(PinnedSnapshot p, double viewportW) {
    final isExiting = _exits.containsKey(p.id);
    final exitAnim = _exits[p.id];

    Widget card = Container(
      width: p.width,
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => widget.onMove(p.id, d.delta),
            child: Container(
              height: _kHeaderH,
              color: yCream2,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Icon(YuLiIcons.pin, size: 12, color: yMuted),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleClose(p),
                    child: Icon(YuLiIcons.close, size: 15, color: yInk),
                  ),
                ],
              ),
            ),
          ),
          Stack(
            children: [
              SizedBox(
                width: p.width,
                height: p.bodyHeight,
                child: RawImage(image: p.image, fit: BoxFit.fill),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => widget.onResize(p.id, d.delta.dx),
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
                    child: Icon(YuLiIcons.maximize, size: 11, color: yInk),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (isExiting && exitAnim != null) {
      card = SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(2, 0),
        ).animate(
          CurvedAnimation(parent: exitAnim, curve: Curves.easeInCubic),
        ),
        child: card,
      );
    } else {
      card = TweenAnimationBuilder<double>(
        key: ValueKey('enter-${p.id}'),
        tween: Tween(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: card,
        builder: (_, t, child) => Transform.translate(
          offset: Offset(t * viewportW, 0),
          child: child,
        ),
      );
    }

    return Positioned(
      key: ValueKey(p.id),
      left: p.pos.dx,
      top: p.pos.dy,
      child: card,
    );
  }
}
