import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

/// A frozen raster cut-out of a lasso selection, pinned in viewport space so it
/// floats above the canvas like a Picture-in-Picture while the user scrolls /
/// zooms the ink underneath. Volatile: lives only while the editor is open.
class PinnedSnapshot {
  final String id;
  final ui.Image image;
  final double aspect; // imageW / imageH
  Offset pos; // top-left, viewport space
  double width; // display width in logical px (height follows the aspect)

  PinnedSnapshot({
    required this.id,
    required this.image,
    required this.pos,
    required this.width,
  }) : aspect = image.height == 0 ? 1.0 : image.width / image.height;

  double get bodyHeight => width / aspect;

  void dispose() => image.dispose();
}

/// Process-level holder so pinned windows survive the editor being disposed and
/// rebuilt (navigate to Lab and back → still there), keyed by note. Volatile:
/// nothing is written to disk, so killing the app process drops everything. A
/// window's [ui.Image] is freed only when the user closes it (X).
class PinnedSnapshotStore {
  PinnedSnapshotStore._();
  static final PinnedSnapshotStore instance = PinnedSnapshotStore._();

  final Map<Object, List<PinnedSnapshot>> _byNote = {};

  List<PinnedSnapshot> forNote(Object noteId) =>
      _byNote.putIfAbsent(noteId, () => []);
}

const double _kHeaderH = 24;
const double _kHandle = 22;

/// Sibling of the canvas Listener (never wrap in IgnorePointer here) so grabbing
/// a window never leaks a pointer into a stroke, and empty areas fall through to
/// the canvas below.
class PinnedSnapshotsLayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (pins.isEmpty) return const SizedBox.shrink();
    return Stack(
      clipBehavior: Clip.none,
      children: [for (final p in pins) _buildWindow(p)],
    );
  }

  Widget _buildWindow(PinnedSnapshot p) {
    return Positioned(
      key: ValueKey(p.id),
      left: p.pos.dx,
      top: p.pos.dy,
      child: Container(
        width: p.width,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
          boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(3, 3))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => onMove(p.id, d.delta),
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
                      onTap: () => onClose(p.id),
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
                    onPanUpdate: (d) => onResize(p.id, d.delta.dx),
                    child: Container(
                      width: _kHandle,
                      height: _kHandle,
                      decoration: const BoxDecoration(
                        color: yCream,
                        border: Border(
                          left: BorderSide(color: yBorderStrong, width: yLineThin),
                          top: BorderSide(color: yBorderStrong, width: yLineThin),
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
      ),
    );
  }
}
