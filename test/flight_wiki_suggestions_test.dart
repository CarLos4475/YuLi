import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/presentation/providers/flight_workspace_providers.dart';
import 'package:yuli/presentation/screens/flight/canvas_text_block.dart';
import 'package:yuli/presentation/screens/flight/flight_wiki_suggestions.dart';
import 'package:yuli/presentation/screens/flight/note_cell_model.dart';
import 'package:yuli/presentation/screens/flight/note_block_widgets.dart';

void main() {
  testWidgets('moving canvas text reuses Markdown without searches or saves', (
    tester,
  ) async {
    final block = CanvasTextBlock(
      x: 0,
      y: 0,
      w: 260,
      h: 100,
      markdown: 'Texto [[Referencia]]',
    );
    var searches = 0;
    var saves = 0;
    var measurements = 0;
    final position = ValueNotifier<double>(0);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, x, child) {
                return Stack(
                  children: [
                    Positioned(
                      left: x,
                      top: 0,
                      child: CanvasTextBlockOverlay(
                        block: block,
                        accent: const Color(0xFF315C9E),
                        interactive: true,
                        wikiTargetSearch: (_) async {
                          searches++;
                          return [];
                        },
                        onPersist: () async {
                          saves++;
                        },
                        onChanged: () {},
                        onHeightMeasured: (h) {
                          measurements++;
                          block.h = h;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final markdown = tester.widget<NoteMarkdownPreview>(
      find.byType(NoteMarkdownPreview),
    );
    final initialMeasurements = measurements;
    for (var i = 1; i <= 60; i++) {
      position.value = i.toDouble();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        identical(tester.widget(find.byType(NoteMarkdownPreview)), markdown),
        isTrue,
      );
    }
    expect(searches, 0);
    expect(saves, 0);
    expect(measurements, initialMeasurements);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canvas muestra sugerencias wiki con el color de la carpeta destino',
    (tester) async {
      const target = FlightWorkspaceTarget(
        noteId: 2,
        folderId: 2,
        kind: NoteKind.block,
        label: 'Derivadas',
        folderLabel: 'Destino',
        folderColor: Color(0xFFC8332C),
      );
      final block = CanvasTextBlock(x: 0, y: 0, w: 260, h: 100, markdown: '');
      var opened = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CanvasTextBlockOverlay(
                block: block,
                accent: const Color(0xFF2D3F8C),
                sourceNoteId: 1,
                wikiTargetSearch: (_) async => const [target],
                interactive: true,
                onPersist: () async {},
                onChanged: () {},
                onHeightMeasured: (_) {},
                onWikiLinkTap: (_) => opened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Toca para editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '[[Deri');
      await tester.pumpAndSettle();

      expect(find.byType(FlightWikiLinkSuggestions), findsOneWidget);
      final suggestions = tester.widget<FlightWikiLinkSuggestions>(
        find.byType(FlightWikiLinkSuggestions),
      );
      expect(
        (await suggestions.matches).map((target) => target.label),
        contains('Derivadas'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Derivadas'), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      expect(
        tester
            .widgetList<Icon>(find.byType(Icon))
            .any((icon) => icon.color?.toARGB32() == 0xFFC8332C),
        isTrue,
      );

      await tester.tap(find.text('Derivadas'));
      await tester.pumpAndSettle();

      expect(block.markdown, '[[Derivadas]]');
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
