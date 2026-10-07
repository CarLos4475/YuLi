import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/presentation/screens/flight/flight_note_preview.dart';
import 'package:yuli/presentation/screens/flight/new_folder_dialog.dart';
import 'package:yuli/presentation/widgets/yuli_action_sheet.dart';
import 'package:yuli/presentation/widgets/yuli_design.dart';
import 'package:yuli/presentation/theme/lab_icons.dart';

void main() {
  for (final size in [
    const Size(1280, 840),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    for (final keyboard in [0.0, 180.0]) {
      testWidgets('Flight dialogs fit $size with keyboard $keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        for (final kind in [null, ...NoteKind.values]) {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: FlightItemDialog(
                    title: kind == null ? 'Editar carpeta' : 'Nueva nota',
                    initialName:
                        'Un nombre largo para comprobar el contenido de la vista previa',
                    initialColor: yFlight,
                    initialKind: kind ?? NoteKind.notebook,
                    isNote: kind != null,
                    chooseKind: kind != null,
                    noteCount: 3,
                    actionLabel: 'Guardar cambios',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final button = tester.getRect(find.text('Guardar cambios'));
          expect(button.bottom, lessThanOrEqualTo(size.height - keyboard));
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }

  testWidgets('Whiteboard decoration stays inside the paper', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const FlightNotePreview(
              kind: NoteKind.whiteboard,
              color: yFlight,
              title: 'Nombre',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image =
        (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
    final pixels =
        (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
    for (var y = 150; y < 205; y++) {
      for (var x = 174; x < 180; x++) {
        final offset = (y * image.width + x) * 4;
        expect(pixels.getUint8(offset), lessThan(40));
        expect(pixels.getUint8(offset + 1), lessThan(40));
        expect(pixels.getUint8(offset + 2), lessThan(40));
      }
    }
    image.dispose();
  });

  testWidgets('All action sheet content scrolls in short windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: YuLiActionSheet(
                title: 'Una carpeta con nombre largo',
                badge: 'Carpeta',
                badgeIcon: YuLiIcons.folder,
                accent: yFlight,
                children: [
                  for (final label in ['Editar', 'Fijar', 'Eliminar'])
                    YuLiActionTile(
                      icon: YuLiIcons.pen,
                      label: label,
                      accent: yFlight,
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Eliminar'));
    expect(find.text('Eliminar').hitTestable(), findsOneWidget);
  });
}
