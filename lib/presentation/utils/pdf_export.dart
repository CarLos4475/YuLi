import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/note_block.dart';
import '../screens/flight/note_cell_model.dart';

Future<void> exportNoteToPdf({
  required BuildContext context,
  required String title,
  required List<NoteBlock> blocks,
}) async {
  final regular = await _loadFont('assets/fonts/Inter-Regular.ttf');
  final bold = await _loadFont('assets/fonts/Inter-Bold.ttf');
  final display = await _loadFont('assets/fonts/SpaceGrotesk-Bold.ttf');
  final mono = pw.Font.courier();

  final baseStyle = pw.TextStyle(font: regular, fontSize: 11, lineSpacing: 1.6);
  final boldStyle = pw.TextStyle(font: bold, fontSize: 11, lineSpacing: 1.6);
  final h1Style = pw.TextStyle(font: display, fontSize: 22, lineSpacing: 1.3);
  final h2Style = pw.TextStyle(font: display, fontSize: 18, lineSpacing: 1.3);
  final h3Style = pw.TextStyle(font: display, fontSize: 14, lineSpacing: 1.3);
  final monoStyle = pw.TextStyle(font: mono, fontSize: 9.5, lineSpacing: 1.4);
  final italicStyle = pw.TextStyle(
      font: regular, fontSize: 11, fontStyle: pw.FontStyle.italic, lineSpacing: 1.6);

  final widgets = <pw.Widget>[];

  // Title
  final cleanTitle = title.trim().isEmpty ? 'Sin título' : title.trim();
  widgets.add(pw.Text(cleanTitle.toUpperCase(), style: pw.TextStyle(
    font: display, fontSize: 24, letterSpacing: 1.5,
  )));
  widgets.add(pw.SizedBox(height: 10));
  widgets.add(pw.Container(width: double.infinity, height: 2, color: PdfColors.black));
  widgets.add(pw.SizedBox(height: 16));

  for (final block in blocks) {
    switch (block) {
      case TextBlock t:
        if (t.markdown.trim().isEmpty) continue;
        final mdWidgets = _parseMarkdown(
          t.markdown,
          base: baseStyle,
          bold: boldStyle,
          italic: italicStyle,
          h1: h1Style,
          h2: h2Style,
          h3: h3Style,
          mono: monoStyle,
        );
        widgets.addAll(mdWidgets);
        widgets.add(pw.SizedBox(height: 8));

      case MathBlock m:
        if (m.latex.trim().isEmpty) continue;
        widgets.add(pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#2A241C'),
            border: pw.Border.all(color: PdfColors.black, width: 1.5),
          ),
          child: pw.Center(
            child: pw.Text(m.latex, style: pw.TextStyle(
              font: mono, fontSize: 12, color: PdfColor.fromHex('#F2EFE6'),
            )),
          ),
        ));
        widgets.add(pw.SizedBox(height: 8));

      case BulletsBlock bl:
        for (final item in bl.items) {
          if (item.trim().isEmpty) continue;
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 5, height: 5,
                  margin: const pw.EdgeInsets.only(top: 5, right: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.black),
                ),
                pw.Expanded(child: pw.Text(item, style: baseStyle)),
              ],
            ),
          ));
        }
        widgets.add(pw.SizedBox(height: 8));

      case TareasBlock _:
        continue;

      case DrawingBlock d:
        final imgBytes = await _renderDrawingToPng(d);
        if (imgBytes != null) {
          widgets.add(pw.Container(
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Image(pw.MemoryImage(imgBytes), fit: pw.BoxFit.fitWidth),
          ));
        } else {
          widgets.add(pw.Container(
            width: double.infinity,
            height: 40,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Center(
              child: pw.Text('[dibujo]', style: pw.TextStyle(
                font: mono, fontSize: 9, color: PdfColors.grey,
              )),
            ),
          ));
        }
        widgets.add(pw.SizedBox(height: 8));
    }
  }

  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => widgets,
    ),
  );

  final dir = await getTemporaryDirectory();
  final safeTitle = cleanTitle.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
  final filename = '${safeTitle.isEmpty ? 'nota' : safeTitle}.pdf';
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(await pdf.save());

  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Nota exportada desde YuLi',
  );
}

Future<pw.Font> _loadFont(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return pw.Font.ttf(data);
}

// ─── Markdown → PDF widgets parser ───────────────────────────────────────

List<pw.Widget> _parseMarkdown(
  String md, {
  required pw.TextStyle base,
  required pw.TextStyle bold,
  required pw.TextStyle italic,
  required pw.TextStyle h1,
  required pw.TextStyle h2,
  required pw.TextStyle h3,
  required pw.TextStyle mono,
}) {
  final result = <pw.Widget>[];
  final lines = md.split('\n');
  bool inCodeBlock = false;
  final codeLines = <String>[];
  String? codeLang;
  bool inAlignBlock = false;
  pw.TextAlign currentAlign = pw.TextAlign.left;
  final alignLines = <String>[];

  for (final line in lines) {
    final trimmed = line.trimLeft();

    // Alignment block fences (::: center / ::: left / ::: right / :::)
    final alignOpen = RegExp(r'^:::\s*(left|center|right)\s*$').firstMatch(trimmed);
    if (alignOpen != null && !inCodeBlock) {
      inAlignBlock = true;
      currentAlign = switch (alignOpen.group(1)) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        _ => pw.TextAlign.left,
      };
      alignLines.clear();
      continue;
    }
    if (inAlignBlock && RegExp(r'^:::\s*$').hasMatch(trimmed)) {
      inAlignBlock = false;
      for (final al in alignLines) {
        result.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.SizedBox(
            width: double.infinity,
            child: pw.Text(al, style: base, textAlign: currentAlign),
          ),
        ));
      }
      result.add(pw.SizedBox(height: 4));
      continue;
    }
    if (inAlignBlock) {
      alignLines.add(line);
      continue;
    }

    // Code block fences
    if (trimmed.startsWith('```')) {
      if (!inCodeBlock) {
        inCodeBlock = true;
        codeLang = line.trimLeft().substring(3).trim();
        codeLines.clear();
      } else {
        inCodeBlock = false;
        result.add(_buildCodeBlock(codeLines.join('\n'), mono, lang: codeLang));
        result.add(pw.SizedBox(height: 6));
      }
      continue;
    }
    if (inCodeBlock) {
      codeLines.add(line);
      continue;
    }

    // Horizontal rule
    if (RegExp(r'^-{3,}\s*$').hasMatch(trimmed)) {
      result.add(pw.Container(
        width: double.infinity, height: 1,
        margin: const pw.EdgeInsets.symmetric(vertical: 8),
        color: PdfColors.grey400,
      ));
      continue;
    }

    // Headers
    if (trimmed.startsWith('### ')) {
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(trimmed.substring(4), style: h3),
      ));
      continue;
    }
    if (trimmed.startsWith('## ')) {
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(trimmed.substring(3), style: h2),
      ));
      continue;
    }
    if (trimmed.startsWith('# ')) {
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(trimmed.substring(2), style: h1),
      ));
      continue;
    }

    // Blockquote
    if (trimmed.startsWith('> ')) {
      result.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        padding: const pw.EdgeInsets.only(left: 12),
        decoration: const pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: PdfColors.grey, width: 3)),
        ),
        child: pw.Text(trimmed.substring(2), style: pw.TextStyle(
          font: base.font, fontSize: 11, color: PdfColors.grey700,
          fontStyle: pw.FontStyle.italic,
        )),
      ));
      continue;
    }

    // Bullet list
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 4, height: 4,
              margin: const pw.EdgeInsets.only(top: 5, right: 8),
              decoration: const pw.BoxDecoration(color: PdfColors.black),
            ),
            pw.Expanded(child: _buildRichText(trimmed.substring(2), base, bold, italic, mono)),
          ],
        ),
      ));
      continue;
    }

    // Checkbox list
    if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ')) {
      final checked = trimmed.startsWith('- [x] ');
      final text = trimmed.substring(6);
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 10, height: 10,
              margin: const pw.EdgeInsets.only(top: 3, right: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 1),
              ),
              child: checked
                  ? pw.Center(child: pw.Text('✓', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))
                  : null,
            ),
            pw.Expanded(child: pw.Text(text, style: base)),
          ],
        ),
      ));
      continue;
    }

    // Table
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      final cells = trimmed.split('|')
          .where((c) => c.trim().isNotEmpty)
          .map((c) => c.trim())
          .toList();
      if (cells.isEmpty) continue;
      // Skip separator rows like |---|---|
      if (cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) continue;
      result.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1),
        child: pw.Row(
          children: cells.map((c) => pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              ),
              child: pw.Text(c, style: base),
            ),
          )).toList(),
        ),
      ));
      continue;
    }

    // Empty line
    if (trimmed.isEmpty) {
      result.add(pw.SizedBox(height: 6));
      continue;
    }

    // Regular paragraph with inline formatting
    result.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: _buildRichText(trimmed, base, bold, italic, mono),
    ));
  }

  // Flush unclosed code block
  if (inCodeBlock && codeLines.isNotEmpty) {
    result.add(_buildCodeBlock(codeLines.join('\n'), mono));
  }

  return result;
}

pw.Widget _buildCodeBlock(String code, pw.TextStyle mono, {String? lang}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#EBE6D9'),
      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (lang != null && lang.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(lang.toUpperCase(), style: pw.TextStyle(
              font: mono.font, fontSize: 7, color: PdfColors.grey,
              letterSpacing: 1.2,
            )),
          ),
        pw.Text(code, style: mono),
      ],
    ),
  );
}

pw.Widget _buildRichText(
  String text,
  pw.TextStyle base,
  pw.TextStyle bold,
  pw.TextStyle italic,
  pw.TextStyle mono,
) {
  final spans = <pw.TextSpan>[];
  final regex = RegExp(
    r'(\*\*(.+?)\*\*)'       // **bold**
    r'|(\*(.+?)\*)'          // *italic*
    r'|(~~(.+?)~~)'          // ~~strike~~
    r'|(`(.+?)`)'            // `code`
    r'|(\$(.+?)\$)',         // $latex$
  );

  int lastEnd = 0;
  for (final match in regex.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(pw.TextSpan(text: text.substring(lastEnd, match.start), style: base));
    }
    if (match.group(2) != null) {
      spans.add(pw.TextSpan(text: match.group(2), style: bold));
    } else if (match.group(4) != null) {
      spans.add(pw.TextSpan(text: match.group(4), style: italic));
    } else if (match.group(6) != null) {
      spans.add(pw.TextSpan(text: match.group(6), style: base));
    } else if (match.group(8) != null) {
      spans.add(pw.TextSpan(text: match.group(8), style: mono));
    } else if (match.group(10) != null) {
      spans.add(pw.TextSpan(text: match.group(10), style: mono));
    }
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(pw.TextSpan(text: text.substring(lastEnd), style: base));
  }

  if (spans.isEmpty) return pw.Text(text, style: base);
  return pw.RichText(text: pw.TextSpan(children: spans));
}

// ─── Drawing → PNG ───────────────────────────────────────────────────────

Future<Uint8List?> _renderDrawingToPng(DrawingBlock d) async {
  try {
    final data = DrawingData.fromJson(d.payloadJson());
    if (data.strokes.isEmpty) return null;

    const renderWidth = 800.0;
    final renderHeight = data.height * (renderWidth / 400);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, renderWidth, renderHeight));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, renderWidth, renderHeight),
      Paint()..color = const Color(0xFFF2EFE6),
    );

    for (final stroke in data.strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = Color(stroke.colorValue)
        ..strokeWidth = stroke.strokeWidth * (renderWidth / 400)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      final pts = stroke.points;
      path.moveTo(
        pts[0][0] * (renderWidth / 400),
        pts[0][1] * (renderHeight / data.height),
      );
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(
          pts[i][0] * (renderWidth / 400),
          pts[i][1] * (renderHeight / data.height),
        );
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(renderWidth.toInt(), renderHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
