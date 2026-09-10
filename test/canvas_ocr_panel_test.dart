import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/domain/models/canvas_ocr.dart';
import 'package:yuli/domain/repositories/canvas_ocr_repository.dart';
import 'package:yuli/domain/repositories/drawing_stroke_repository.dart';
import 'package:yuli/domain/services/ink_recognizer.dart';
import 'package:yuli/presentation/providers/canvas_ocr_provider.dart';
import 'package:yuli/presentation/providers/canvas_ocr_settings_provider.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/providers/ink_recognizer_provider.dart';
import 'package:yuli/presentation/screens/flight/canvas_ocr_panel.dart';

class _Repository implements CanvasOcrRepository {
  int reads = 0;
  int writes = 0;
  CanvasOcrPage page = const CanvasOcrPage(1, 1, true, [
    CanvasOcrSegment(
      hash: 'sample',
      bounds: Rect.fromLTWH(10, 120, 200, 25),
      text: 'Cancion y cancion',
      spellingChecked: true,
      alignmentVersion: 1,
      words: [
        CanvasOcrWord(0, 7, Rect.fromLTWH(10, 120, 70, 25)),
        CanvasOcrWord(10, 17, Rect.fromLTWH(120, 120, 70, 25)),
      ],
      spelling: [
        OcrSpellingSuggestion(0, 7, ['Canción']),
      ],
    ),
  ]);
  @override
  Future<CanvasOcrPage?> read(int blockId) async {
    reads++;
    return page;
  }

  @override
  Future<bool> save(
    int blockId,
    int revision,
    List<CanvasOcrSegment> segments,
  ) async {
    writes++;
    page = CanvasOcrPage(blockId, revision, true, segments);
    return true;
  }

  @override
  Future<List<CanvasOcrHit>> search(String query) async => [];
  @override
  Future<String> contextForNote(int noteId, {int? blockId}) async => '';
}

class _Ink implements InkRecognizer {
  @override
  Future<bool> isModelReady(String langTag) async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Strokes implements DrawingStrokeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [
    const Size(360, 640),
    const Size(1024, 768),
    const Size(640, 360),
  ]) {
    testWidgets(
      'Inline search fits $size, navigates occurrences and keeps ink visible',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final repo = _Repository();
        final ink = _Ink();
        final transform = TransformationController();
        addTearDown(transform.dispose);
        final coordinator = CanvasOcrCoordinator(
          repository: repo,
          strokes: _Strokes(),
          recognizer: ink,
          supported: false,
          onChanged: () {},
        );
        addTearDown(coordinator.dispose);
        Rect? located;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              canvasOcrRepositoryProvider.overrideWithValue(repo),
              canvasOcrCoordinatorProvider.overrideWithValue(coordinator),
              inkRecognizerProvider.overrideWithValue(ink),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    CanvasOcrHeader(
                      blockIds: const [1],
                      accent: Colors.blue,
                      onLocate: (_, box) => located = box,
                      child: const Row(
                        children: [
                          Expanded(child: Text('Pizarra')),
                          CanvasOcrButton(blockIds: [1], accent: Colors.blue),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          const Positioned.fill(child: Text('Mi lienzo')),
                          Positioned.fill(
                            child: CanvasOcrMarks(
                              blockId: 1,
                              transform: transform,
                              accent: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Buscar en la escritura'));
        await tester.pumpAndSettle();
        expect(find.text('Pizarra'), findsNothing);
        expect(find.text('Mi lienzo'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'cancion');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(located, const Rect.fromLTWH(10, 120, 70, 25));
        final reads = repo.reads;
        await tester.tap(find.byTooltip('Coincidencia siguiente'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(located, const Rect.fromLTWH(120, 120, 70, 25));
        await tester.tap(find.byTooltip('Coincidencia siguiente'));
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(repo.reads, reads);
        await tester.tap(find.byTooltip('Coincidencia anterior'));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.tap(find.byTooltip('Cerrar búsqueda'));
        await tester.pumpAndSettle();
        expect(find.text('Pizarra'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        final painter =
            tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((w) => w.painter)
                .whereType<CanvasOcrMarksPainter>()
                .single;
        expect(painter.highlight, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Finger shows an informational word hint; stylus passes through and never edits',
    (tester) async {
      final repo = _Repository();
      final transform = TransformationController();
      addTearDown(transform.dispose);
      var pointerDowns = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [canvasOcrRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder:
                    (context, ref, _) => Stack(
                      children: [
                        Positioned.fill(
                          child: Listener(
                            onPointerDown: (_) => pointerDowns++,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp:
                                  (d) => showCanvasSpellingAt(
                                    ref,
                                    1,
                                    transform.toScene(d.localPosition),
                                    d.kind,
                                  ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: CanvasOcrMarks(
                            blockId: 1,
                            transform: transform,
                            accent: Colors.blue,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final painter =
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<CanvasOcrMarksPainter>()
              .single;
      expect(painter.regions, [const Rect.fromLTWH(10, 120, 70, 25)]);
      expect(
        painter.shouldRepaint(
          CanvasOcrMarksPainter(
            List.of(painter.regions),
            transform,
            Colors.blue,
            null,
          ),
        ),
        isFalse,
      );
      final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await stylus.down(const Offset(40, 132));
      await stylus.up();
      await tester.pumpAndSettle();
      expect(find.text('El corrector sugiere'), findsNothing);
      await tester.tapAt(const Offset(40, 132));
      await tester.pumpAndSettle();
      expect(find.text('El corrector sugiere'), findsOneWidget);
      expect(find.text('Canción'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await stylus.down(const Offset(40, 132));
      await stylus.up();
      await tester.pumpAndSettle();
      expect(find.text('El corrector sugiere'), findsNothing);
      expect(pointerDowns, 3);
      await tester.tapAt(const Offset(40, 132));
      await tester.pumpAndSettle();
      transform.value = Matrix4.identity()..translateByDouble(5, 0, 0, 1);
      await tester.pumpAndSettle();
      expect(find.text('El corrector sugiere'), findsNothing);
      expect(repo.writes, 0);
      expect(repo.page.segments.single.text, 'Cancion y cancion');
      final settings = ProviderScope.containerOf(
        tester.element(find.byType(CanvasOcrMarks)),
      );
      await tester.runAsync(
        () => settings
            .read(canvasOcrSettingsProvider.notifier)
            .setOptions(spelling: false),
      );
      await tester.pumpAndSettle();
      final disabledPainter =
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<CanvasOcrMarksPainter>()
              .single;
      expect(disabledPainter.regions, isEmpty);
      await tester.tapAt(const Offset(45, 132));
      await tester.pumpAndSettle();
      expect(find.text('El corrector sugiere'), findsNothing);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
