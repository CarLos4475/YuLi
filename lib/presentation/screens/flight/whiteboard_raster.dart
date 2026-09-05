import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'drawing_engine.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

const double whiteboardMinScale = 0.1;
const int whiteboardRasterVersion = 2;
const int whiteboardPathCacheLimit = 60000;

ui.Picture recordWhiteboardPatch({
  required ui.Image base,
  required Rect bounds,
  required Rect region,
  required double scale,
  required void Function(Canvas, Rect) drawRegion,
}) {
  final clip = Rect.fromLTRB(
    ((region.left - bounds.left) * scale).floor() / scale + bounds.left,
    ((region.top - bounds.top) * scale).floor() / scale + bounds.top,
    ((region.right - bounds.left) * scale).ceil() / scale + bounds.left,
    ((region.bottom - bounds.top) * scale).ceil() / scale + bounds.top,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(
    base,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.none,
  );
  canvas.scale(scale);
  canvas.translate(-bounds.left, -bounds.top);
  canvas.clipRect(clip, doAntiAlias: false);
  canvas.drawRect(clip, Paint()..blendMode = BlendMode.clear);
  drawRegion(canvas, clip);
  return recorder.endRecording();
}

Rect whiteboardPatchRegion(
  Rect edited,
  List<DrawingStroke> strokes,
  int bakedCount, {
  Rect? pendingRegion,
}) {
  var region =
      pendingRegion == null ? edited : edited.expandToInclude(pendingRegion);
  for (var i = bakedCount.clamp(0, strokes.length); i < strokes.length; i++) {
    region = region.expandToInclude(strokeBounds(strokes[i]));
  }
  return region;
}

class WhiteboardRasterTile {
  final Rect worldRect;
  final int version;
  final ui.Image image;
  final Rect? source;

  const WhiteboardRasterTile(
    this.worldRect,
    this.version,
    this.image, {
    this.source,
  });
}

class WhiteboardRasterPainter extends CustomPainter {
  final ui.Image baseImage;
  final Rect baseBounds;
  final ui.Image? focusImage;
  final Rect? focusBounds;
  final List<DrawingStroke>? delta;
  final List<WhiteboardRasterTile> tiles;
  final List<WhiteboardRasterTile> prevTiles;
  final Rect visibleWorld;
  final List<DrawingStroke>? handoff;
  final List<Rect> refreshRegions;
  final Rect? replacementRegion;
  final List<DrawingStroke> replacementStrokes;

  const WhiteboardRasterPainter({
    required this.baseImage,
    required this.baseBounds,
    this.focusImage,
    this.focusBounds,
    this.delta,
    this.tiles = const [],
    this.prevTiles = const [],
    required this.visibleWorld,
    this.handoff,
    this.refreshRegions = const [],
    this.replacementRegion,
    this.replacementStrokes = const [],
  });

  void _outside(Canvas canvas, Iterable<Rect> regions) {
    final covered = Path();
    for (final region in regions) {
      covered.addRect(region);
    }
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(visibleWorld),
        covered,
      ),
      doAntiAlias: false,
    );
  }

  void _image(Canvas canvas, ui.Image image, Rect bounds, [Rect? source]) {
    canvas.drawImageRect(
      image,
      source ??
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds,
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.low,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (replacementRegion case final region?) _outside(canvas, [region]);
    final covered = [
      for (final tile in tiles) tile.worldRect,
      for (final tile in prevTiles) tile.worldRect,
    ];
    final focus = focusImage;
    final focusRect = focusBounds;
    canvas.save();
    _outside(canvas, [
      ...covered,
      if (focus != null && focusRect != null) focusRect,
    ]);
    _image(canvas, baseImage, baseBounds);
    canvas.restore();

    if (focus != null && focusRect != null) {
      canvas.save();
      _outside(canvas, covered);
      _image(canvas, focus, focusRect);
      canvas.restore();
    }
    canvas.save();
    _outside(canvas, covered);
    for (final stroke in delta ?? const <DrawingStroke>[]) {
      drawStroke(canvas, stroke);
    }
    canvas.restore();

    canvas.save();
    _outside(canvas, tiles.map((tile) => tile.worldRect));
    for (final tile in prevTiles) {
      _image(canvas, tile.image, tile.worldRect, tile.source);
    }
    canvas.restore();
    for (final tile in tiles) {
      _image(canvas, tile.image, tile.worldRect, tile.source);
    }

    if (handoff != null && refreshRegions.isNotEmpty) {
      canvas.save();
      final region = Path();
      for (final rect in refreshRegions) {
        region.addRect(rect);
      }
      canvas.clipPath(region, doAntiAlias: false);
      for (final stroke in handoff!) {
        drawStroke(canvas, stroke);
      }
      canvas.restore();
    }
    canvas.restore();
    if (replacementRegion case final region?) {
      canvas.save();
      canvas.clipRect(region, doAntiAlias: false);
      for (final stroke in replacementStrokes) {
        drawStroke(
          canvas,
          stroke,
          cache: replacementStrokes.length <= whiteboardPathCacheLimit,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(WhiteboardRasterPainter oldDelegate) => true;
}
