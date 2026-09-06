// Faithful export of a drawing canvas (whiteboard page / notebook pages) to
// PNG and PDF. Runs entirely OFF the live render path: it reads a [DrawingData]
// snapshot and re-paints it cold into a [ui.PictureRecorder], reusing the exact
// same primitives as the on-screen painters (`drawStroke`, `drawCanvasImage`,
// `paintBgPattern`) so the output matches the editor pixel-for-pixel. Text/task
// blocks are widget overlays (not painted), so they are rasterized separately
// by the caller and handed in as [ExportBlockImage]s to composite.
//
// Nothing here touches RepaintBoundary caching, visible-rect culling or the
// render-rect hysteresis used live — those optimizations are untouched.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../screens/flight/background_paint.dart';
import '../screens/flight/drawing_engine.dart';
import '../screens/flight/note_cell_model.dart';
import '../screens/flight/stroke_bounds.dart';

/// A pre-rasterized text/task block to composite at its world rect. The caller
/// produces [image] off-screen (see the editors' export flows) and owns its
/// lifetime; this module only reads it.
class ExportBlockImage {
  final Rect rect; // world-space x/y/w/h
  final double rotation;
  final ui.Image image;
  const ExportBlockImage({
    required this.rect,
    required this.rotation,
    required this.image,
  });
}

/// One page of a PDF: the rendered raster plus its world size (used as the PDF
/// page format in points, so the physical proportions match the canvas).
class ExportPage {
  final ui.Image image;
  final Size worldSize;
  const ExportPage({required this.image, required this.worldSize});
}

/// Decode the image files referenced by [images] (under [dirPath]) into
/// `ui.Image`, keyed by filename. The live [CanvasImageCache] may not have
/// everything decoded yet, so export loads its own copies. Caller MUST call
/// [disposeExportImages] when done. Missing/corrupt files are skipped (the
/// painter then draws the placeholder box, matching the editor).
Future<Map<String, ui.Image>> loadExportImages(
  String? dirPath,
  List<CanvasImage> images,
) async {
  final map = <String, ui.Image>{};
  if (dirPath == null) return map;
  for (final im in images) {
    if (map.containsKey(im.filename)) continue;
    try {
      final bytes = await File(p.join(dirPath, im.filename)).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      map[im.filename] = frame.image;
    } catch (_) {}
  }
  return map;
}

void disposeExportImages(Map<String, ui.Image> images) {
  for (final img in images.values) {
    img.dispose();
  }
}

/// Bounding box (world space) of all content in [data]: strokes, images and the
/// given [blockRects]. Returns null when there is nothing to export. Used by
/// "export everything" so the user doesn't have to marquee the whole canvas.
Rect? contentBounds(DrawingData data, {List<Rect> blockRects = const []}) {
  Rect? acc;
  void add(Rect r) => acc = acc == null ? r : acc!.expandToInclude(r);
  for (final s in data.strokes) {
    if (s.points.isEmpty) continue;
    add(strokeBounds(s));
  }
  for (final im in data.images) {
    add(Rect.fromLTWH(im.x, im.y, im.w, im.h));
  }
  for (final r in blockRects) {
    add(r);
  }
  return acc;
}

/// px-per-world-unit for a region, targeting [desired] density but capping the
/// longest output side at [maxDim] px so a huge selection can't OOM.
double exportPixelRatio(
  Rect region, {
  double desired = 3.0,
  double maxDim = 4096,
}) {
  final longest = region.longestSide;
  if (longest <= 0) return desired;
  final cap = maxDim / longest;
  return desired < cap ? desired : cap;
}

/// Render [region] of [data] into a [ui.Image] at [pixelRatio] px/world-unit.
/// Layer order mirrors the on-screen painters exactly: paper color → pattern →
/// images → text/task block rasters → strokes (strokes sit on top).
Future<ui.Image> renderCanvasRegion({
  Future<void> Function()? checkpoint,
  required DrawingData data,
  required Rect region,
  required double pixelRatio,
  required Color paper,
  Map<String, ui.Image> images = const {},
  List<ExportBlockImage> blocks = const [],
}) async {
  final pxW = (region.width * pixelRatio).round().clamp(1, 1 << 14);
  final pxH = (region.height * pixelRatio).round().clamp(1, 1 << 14);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
  );
  canvas.scale(pixelRatio);
  canvas.translate(-region.left, -region.top);
  canvas.clipRect(region);

  canvas.drawRect(region, Paint()..color = paper);
  paintBgPattern(canvas, region, data.background, bgMark(paper));

  for (final im in data.images) {
    if (!Rect.fromLTWH(im.x, im.y, im.w, im.h).overlaps(region)) continue;
    drawCanvasImage(canvas, images[im.filename], im);
  }

  final blockPaint = Paint()..filterQuality = FilterQuality.high;
  for (final b in blocks) {
    if (!b.rect.overlaps(region)) continue;
    canvas.save();
    if (b.rotation != 0) {
      final c = b.rect.center;
      canvas
        ..translate(c.dx, c.dy)
        ..rotate(b.rotation)
        ..translate(-c.dx, -c.dy);
    }
    final src = Rect.fromLTWH(
      0,
      0,
      b.image.width.toDouble(),
      b.image.height.toDouble(),
    );
    canvas.drawImageRect(b.image, src, b.rect, blockPaint);
    canvas.restore();
  }

  var batch = 0;
  try {
    for (final s in data.strokes) {
      if (checkpoint != null && batch++ % 200 == 0) await checkpoint();
      if (!strokeOverlapsRect(s, region)) continue;
      drawStroke(canvas, s);
    }
  } catch (_) {
    recorder.endRecording().dispose();
    rethrow;
  }

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(pxW, pxH);
  } finally {
    picture.dispose();
  }
}

/// Stack [images] top-to-bottom into one image (centered horizontally), with
/// [gap] px of [background] between them. Used to flatten multiple notebook
/// pages into a single PNG / single-page PDF. Inputs are NOT disposed.
Future<ui.Image> stackImagesVertically(
  List<ui.Image> images, {
  double gap = 0,
  Color background = const Color(0xFFFFFFFF),
}) async {
  var width = 0;
  var height = 0.0;
  for (int i = 0; i < images.length; i++) {
    if (images[i].width > width) width = images[i].width;
    height += images[i].height;
    if (i != images.length - 1) height += gap;
  }
  final totalH = height.round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), totalH.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), totalH.toDouble()),
    Paint()..color = background,
  );
  var y = 0.0;
  final paint = Paint()..filterQuality = FilterQuality.high;
  for (final img in images) {
    final x = (width - img.width) / 2;
    canvas.drawImage(img, Offset(x, y), paint);
    y += img.height + gap;
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(width, totalH);
  picture.dispose();
  return out;
}

Future<Uint8List> imageToPngBytes(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Build a PDF where each [ExportPage] becomes one page sized to its world
/// dimensions (in points), with the raster filling it. Multi-page = notebook.
Future<Uint8List> buildCanvasPdf(List<ExportPage> pages) async {
  final doc = pw.Document();
  for (final page in pages) {
    final png = await imageToPngBytes(page.image);
    final mem = pw.MemoryImage(png);
    final w = page.worldSize.width.clamp(1.0, 14400.0);
    final h = page.worldSize.height.clamp(1.0, 14400.0);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(mem, fit: pw.BoxFit.fill),
      ),
    );
  }
  return doc.save();
}

String sanitizeFilename(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
  return cleaned.isEmpty ? 'yuli' : cleaned;
}

/// Write [bytes] to a temp file and open the system share sheet.
Future<void> shareExportBytes(
  Uint8List bytes,
  String filename, {
  String? text,
  Future<void> Function(File)? uploadToDrive,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes);
  if (uploadToDrive != null) {
    await uploadToDrive(file);
  } else {
    await Share.shareXFiles([XFile(file.path)], text: text);
  }
}
