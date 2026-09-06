// Block-note → PDF export, raster (WYSIWYG) approach.
//
// Instead of re-parsing markdown into PDF widgets (a second rendering engine
// that never matched the on-screen `markdown_widget` output), this rasterizes
// the SAME read-only widgets the preview pane uses ([buildNoteExportItems]) and
// drops the images into the PDF. The output is pixel-identical to the preview by
// construction. Trade-off: text is not selectable and files are larger — the
// same trade-off the whiteboard/notebook export already makes.
//
// Mirrors the off-screen technique in `canvas_block_raster.dart`: mount each
// item in a throwaway OverlayEntry at a FIXED page-content width (with a
// MediaQuery override so width-relative layout — e.g. image max width — uses the
// page width, not the always-landscape screen), let it lay out + paint, capture
// via RepaintBoundary, tear down. Helpers (`imageToPngBytes`, `sanitizeFilename`,
// `shareExportBytes`) are reused from `canvas_export.dart` unchanged.

import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/note_block.dart';
import '../../domain/models/task.dart';
import '../screens/flight/block_pdf_export_sheet.dart';
import '../screens/flight/note_cell_model.dart';
import '../screens/flight/note_export_view.dart';
import '../widgets/yuli_design.dart';
import 'canvas_export.dart';

/// Density of the rasterized items. 3x keeps text crisp at print scale; 1
/// logical point maps to 1 PDF point, so a rendered item of logical height H
/// occupies H points in the PDF.
const double _pixelRatio = 3.0;

/// PDF page background = the app's cream paper, so margins/gaps between item
/// rasters match the editor's canvas.
final PdfColor _paperPdf = PdfColor.fromInt(yCream.toARGB32());

Future<void> exportNoteToPdf({
  Future<void> Function(Uint8List)? onBytes,
  Future<void> Function()? checkpoint,
  Future<void> Function(File)? uploadToDrive,
  required BuildContext context,
  required String title,
  required List<NoteBlock> blocks,
  required Color accent,
  BlockPdfExportOptions options = const BlockPdfExportOptions(
    pageSize: BlockPdfPageSize.a4,
    orientation: BlockPdfOrientation.portrait,
    margins: BlockPdfMargins.normal,
    includeTitle: true,
    includeTasks: true,
  ),
  Map<int, Task> tasksById = const {},
  Map<int, List<DrawingStroke>> drawingStrokesByBlock = const {},
}) async {
  final format = _pageFormat(options);
  final margin = _marginValue(options.margins);
  final contentW = (format.width - margin * 2).clamp(1.0, format.width);
  final contentH = (format.height - margin * 2).clamp(1.0, format.height);

  final cleanTitle = title.trim().isEmpty ? 'Sin titulo' : title.trim();
  final items = buildNoteExportItems(
    blocks: blocks,
    accent: accent,
    title: options.includeTitle ? cleanTitle : null,
    tasksById: tasksById,
    drawingStrokesByBlock: drawingStrokesByBlock,
    includeTasks: options.includeTasks,
  );

  final images =
      checkpoint != null
          ? <ui.Image>[]
          : await _rasterizeItems(
            context: context,
            items: items,
            widthLogical: contentW,
            checkpoint: checkpoint,
          );
  if (items.isEmpty || (checkpoint == null && images.isEmpty)) {
    // Nothing renderable (empty note): emit a single near-blank page.
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (_) => pw.SizedBox(),
      ),
    );
    if (onBytes != null) return onBytes(await doc.save());
    await shareExportBytes(
      await doc.save(),
      '${sanitizeFilename(cleanTitle)}.pdf',
      text: 'Nota · YuLi',
      uploadToDrive: uploadToDrive,
    );
    return;
  }

  final maxStripPx = (contentH * _pixelRatio).floor().clamp(1, 1 << 14);
  final widgets = <pw.Widget>[];
  Stream<ui.Image> frames() async* {
    if (checkpoint == null) {
      yield* Stream.fromIterable(images);
      return;
    }
    for (final item in items) {
      await checkpoint();
      if (!context.mounted) throw StateError('Exportación interrumpida.');
      final batch = await _rasterizeItems(
        context: context,
        items: [item],
        widthLogical: contentW,
        checkpoint: checkpoint,
      );
      yield* Stream.fromIterable(batch);
    }
  }

  final toDispose = <ui.Image>{...images};
  try {
    await for (final img in frames()) {
      toDispose.add(img);
      await checkpoint?.call();
      final strips = await _sliceImage(img, maxStripPx);
      for (final strip in strips) {
        if (!identical(strip, img)) toDispose.add(strip);
        final png = await imageToPngBytes(strip);
        final wPts = strip.width / _pixelRatio;
        final hPts = strip.height / _pixelRatio;
        widgets.add(pw.Image(pw.MemoryImage(png), width: wPts, height: hPts));
        widgets.add(pw.SizedBox(height: 8));
      }
      for (final image in {img, ...strips}) {
        image.dispose();
        toDispose.remove(image);
      }
    }
  } finally {
    for (final img in toDispose) {
      img.dispose();
    }
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      maxPages: 2000,
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        buildBackground:
            (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: _paperPdf),
            ),
      ),
      build: (_) => widgets,
    ),
  );

  await checkpoint?.call();
  if (onBytes != null) return onBytes(await doc.save());
  await shareExportBytes(
    await doc.save(),
    '${sanitizeFilename(cleanTitle)}.pdf',
    text: 'Nota · YuLi',
    uploadToDrive: uploadToDrive,
  );
}

PdfPageFormat _pageFormat(BlockPdfExportOptions options) {
  final base = switch (options.pageSize) {
    BlockPdfPageSize.a4 => PdfPageFormat.a4,
    BlockPdfPageSize.letter => PdfPageFormat.letter,
  };
  return switch (options.orientation) {
    BlockPdfOrientation.portrait => base,
    BlockPdfOrientation.landscape => base.landscape,
  };
}

double _marginValue(BlockPdfMargins margins) => switch (margins) {
  BlockPdfMargins.compact => 28.0,
  BlockPdfMargins.normal => 40.0,
  BlockPdfMargins.wide => 56.0,
};

/// Mount each item off-screen at [widthLogical] and capture it as a [ui.Image].
/// Failed captures are skipped (kept aligned by index isn't needed — order is
/// preserved and missing items simply drop out). Caller owns the images.
Future<List<ui.Image>> _rasterizeItems({
  required BuildContext context,
  required List<Widget> items,
  required double widthLogical,
  Future<void> Function()? checkpoint,
}) async {
  if (checkpoint != null && items.length > 1) {
    final result = <ui.Image>[];
    try {
      for (final item in items) {
        await checkpoint();
        if (!context.mounted) throw StateError('Exportación interrumpida.');
        result.addAll(
          await _rasterizeItems(
            context: context,
            items: [item],
            widthLogical: widthLogical,
            checkpoint: checkpoint,
          ),
        );
      }
      return result;
    } catch (_) {
      for (final image in result) {
        image.dispose();
      }
      rethrow;
    }
  }
  if (items.isEmpty) return const [];
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return const [];

  final keys = List.generate(items.length, (_) => GlobalKey());
  // Height is unbounded for layout; only width drives image sizing and the
  // markdown image-width heuristic (MediaQuery.size.width * 0.75).
  final mq = MediaQueryData(size: Size(widthLogical, 100000));

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder:
        (_) => Stack(
          children: [
            for (int i = 0; i < items.length; i++)
              // Off-screen but still in the layer tree → lays out and paints
              // (Stack does no viewport culling) without flashing on screen.
              Positioned(
                left: -100000,
                top: 0,
                child: RepaintBoundary(
                  key: keys[i],
                  child: MediaQuery(
                    data: mq,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          width: widthLogical,
                          child: ColoredBox(color: yCream, child: items[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
  );
  overlay.insert(entry);

  // First paint, then a settle window for async content (e.g. network images,
  // Riverpod-driven widgets) and a re-paint.
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await WidgetsBinding.instance.endOfFrame;

  final out = <ui.Image>[];
  try {
    for (final key in keys) {
      final ro = key.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        if (checkpoint != null) {
          throw StateError('No se pudo renderizar el apunte.');
        }
        continue;
      }
      try {
        out.add(await ro.toImage(pixelRatio: _pixelRatio));
      } catch (_) {
        if (checkpoint != null) rethrow;
      }
    }
  } catch (_) {
    for (final image in out) {
      image.dispose();
    }
    rethrow;
  } finally {
    entry.remove();
    entry.dispose();
  }
  return out;
}

/// Cut [img] into vertical strips no taller than [maxPxH] so a single item taller
/// than one page can flow across pages. Returns [img] itself when it already
/// fits (caller checks identity before disposing).
Future<List<ui.Image>> _sliceImage(ui.Image img, int maxPxH) async {
  if (img.height <= maxPxH) return [img];
  final out = <ui.Image>[];
  final w = img.width;
  for (int top = 0; top < img.height; top += maxPxH) {
    final h = (top + maxPxH <= img.height) ? maxPxH : img.height - top;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = yCream,
    );
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, top.toDouble(), w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    out.add(await picture.toImage(w, h));
    picture.dispose();
  }
  return out;
}
