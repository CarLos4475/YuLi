// Off-screen rasterization of canvas text/task block overlays for export.
//
// Text and task blocks are interactive Flutter widgets layered ABOVE the
// painted canvas — the stroke/image painter never sees them. To export them
// faithfully we mount the SAME overlay widgets (with `interactive: false`) in a
// throwaway off-screen [OverlayEntry], let them lay out + paint (task blocks
// also need a frame or two to receive their async task data through Riverpod —
// which is why this runs inside the app tree, not a detached pipeline), capture
// each via its [RepaintBoundary], and tear the entry down. The live editor
// overlays are never touched.
//
// Rotation is captured at angle 0 (callers pass a rotation-zeroed block clone)
// and re-applied at composite time, so a rotated block isn't clipped to its
// unrotated layout box.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'canvas_export.dart';

class BlockRasterSpec {
  /// World position of the block's top-left (block.x / block.y).
  final Offset worldPos;

  /// Rotation (radians) to re-apply at composite time. The [child] must be
  /// built unrotated.
  final double rotation;

  /// The overlay widget, built with `interactive: false` and a rotation-zeroed
  /// block clone. It self-sizes to its width; height is measured after layout.
  final Widget child;

  const BlockRasterSpec({
    required this.worldPos,
    required this.rotation,
    required this.child,
  });
}

/// Rasterize [specs] off-screen and return composited-ready block images.
/// [pixelRatio] should match the export region's density so the raster stays
/// crisp when drawn 1:1 into the scaled export canvas.
Future<List<ExportBlockImage>> rasterizeCanvasBlocks({
  required BuildContext context,
  required List<BlockRasterSpec> specs,
  required double pixelRatio,
}) async {
  if (specs.isEmpty) return const [];

  final overlay = Overlay.of(context, rootOverlay: true);
  final keys = List.generate(specs.length, (_) => GlobalKey());

  final entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        for (int i = 0; i < specs.length; i++)
          // Off-screen but still in the layer tree, so it lays out and paints
          // (Stack does no viewport culling) without flashing on screen.
          Positioned(
            left: -100000,
            top: 0,
            child: RepaintBoundary(
              key: keys[i],
              child: Material(
                type: MaterialType.transparency,
                child: specs[i].child,
              ),
            ),
          ),
      ],
    ),
  );
  overlay.insert(entry);

  // Build + first paint, then a settle window for task blocks' async data to
  // arrive (StreamProvider) and re-paint.
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 350));
  await WidgetsBinding.instance.endOfFrame;

  final results = <ExportBlockImage>[];
  for (int i = 0; i < specs.length; i++) {
    final ro = keys[i].currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) continue;
    try {
      final img = await ro.toImage(pixelRatio: pixelRatio);
      final size = ro.size;
      results.add(
        ExportBlockImage(
          rect: Rect.fromLTWH(
            specs[i].worldPos.dx,
            specs[i].worldPos.dy,
            size.width,
            size.height,
          ),
          rotation: specs[i].rotation,
          image: img,
        ),
      );
    } catch (_) {}
  }

  entry.remove();
  return results;
}
