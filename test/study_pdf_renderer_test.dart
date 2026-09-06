import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/presentation/utils/study_pdf_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Inter', 'SpaceGrotesk']) {
      final loader =
          FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/$family-Bold.ttf'));
      await loader.load();
    }
  });
  final date = DateTime(2026);
  final folder = Folder(
    id: 1,
    name: 'Carpeta',
    color: const Color(0xFF315C9E),
    createdAt: date,
  );
  StudySnapshot snapshot(NoteKind kind, List<NoteBlock> blocks) =>
      StudySnapshot(
        Note(
          id: 1,
          folderId: 1,
          title: 'Apunte de prueba',
          rawMarkdown: '',
          sizeBytes: 0,
          createdAt: date,
          updatedAt: date,
          kind: kind,
        ),
        folder,
        blocks,
        {},
        {},
        [],
      );

  test('snapshot fingerprint is stable and reflects edited content', () async {
    final a = snapshot(NoteKind.block, [
      const TextBlock(id: 1, noteId: 1, position: 0, markdown: 'Uno'),
    ]);
    final b = snapshot(NoteKind.block, [
      const TextBlock(id: 1, noteId: 1, position: 0, markdown: 'Dos'),
    ]);
    expect(await a.fingerprint(), await a.fingerprint());
    expect(await a.fingerprint(), isNot(await b.fingerprint()));
  });

  for (final kind in NoteKind.values) {
    testWidgets('renders ${kind.name} from saved data without an editor', (
      tester,
    ) async {
      late BuildContext exportContext;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  exportContext = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final root = Directory('build/study_samples/${kind.name}');
      final data = snapshot(
        kind,
        kind == NoteKind.block
            ? [
              const TextBlock(
                id: 1,
                noteId: 1,
                position: 0,
                markdown: '# Tema\nTexto de prueba con **énfasis**.',
              ),
            ]
            : [
              DrawingBlock(
                id: 1,
                noteId: 1,
                position: 0,
                height: 842,
                strokesJson:
                    '[{"c":4281425054,"w":4,"p":[[40,260],[220,170],[380,260]]}]',
                imagesJson: '[]',
                textBlocksJson:
                    '[{"id":"text","x":40,"y":40,"w":300,"h":100,"md":"# Tema\\nTexto de prueba"}]',
              ),
            ],
      );
      File? result;
      Object? failure;
      var finished = false;
      await tester.runAsync(() async {
        await root.create(recursive: true);
        final operation = data
            .render(exportContext, root, () async {})
            .then(
              (file) {
                result = file;
                finished = true;
              },
              onError: (Object error) {
                failure = error;
                finished = true;
              },
            );
        for (var i = 0; i < 500 && !finished; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        if (finished) await operation;
      });
      expect(failure, isNull);
      expect(finished, isTrue);
      expect(result, isNotNull);
      await tester.runAsync(() async {
        final bytes = await result!.readAsBytes();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(500));
        await result!.copy('build/study_samples/${kind.name}.pdf');
      });
      expect(tester.takeException(), isNull);
    });
  }
}
