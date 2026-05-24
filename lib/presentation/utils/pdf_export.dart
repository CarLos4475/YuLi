import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exports a note as PDF and triggers the platform share sheet.
Future<void> exportNoteToPdf({
  required BuildContext context,
  required String title,
  required String content,
}) async {
  final pdf = pw.Document();

  // Clean content: strip markdown syntax for plain text
  final cleanTitle = title.trim().isEmpty ? 'Sin título' : title.trim();
  final cleanContent = content
      .replaceAll(RegExp(r'[#*_`\[\]\(\)!\-]'), ' ')
      .replaceAll(RegExp(r'\n+'), '\n')
      .trim();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              cleanTitle.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              height: 2,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              cleanContent,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
            ),
          ],
        );
      },
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
