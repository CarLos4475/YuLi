import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/canvas_export_sheet.dart';
import 'package:yuli/presentation/screens/flight/block_pdf_export_sheet.dart';
import 'package:yuli/presentation/theme/app_tokens.dart';

void main() {
  testWidgets('notebook Drive destination fits a short landscape viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CanvasExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          result = await showNotebookExportSheet(
                            context,
                            accent: accentJournal,
                            selectedCount: 5,
                            hasTasks: true,
                          ),
                  child: const Text('Abrir'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final drive = find.text('Guardar en Google Drive (Conectar en Ajustes)');
    await tester.ensureVisible(drive);
    await tester.tap(drive);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('EXPORTAR'));
    await tester.tap(find.text('EXPORTAR'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result?.toDrive, isTrue);
    expect(result?.format, ExportFormat.pdf);
  });

  testWidgets('note PDF exposes an optional Drive destination', (tester) async {
    BlockPdfExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme(),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          result = await showBlockPdfExportSheet(
                            context,
                            accent: accentJournal,
                            hasTasks: true,
                          ),
                  child: const Text('Abrir'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final drive = find.text('Guardar en Google Drive (Conectar en Ajustes)');
    await tester.ensureVisible(drive);
    await tester.tap(drive);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('EXPORTAR'));
    await tester.tap(find.text('EXPORTAR'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result?.toDrive, isTrue);
  });
}
