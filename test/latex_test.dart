import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/note_block_widgets.dart';

void main() {
  // Crear cards/tareas dispara la sincronización de recordatorios, que lee
  // SharedPreferences; sin el mock el method channel nunca responde y cuelga.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('LaTeX inline + block renderizan como widgets Math en el preview', (
    WidgetTester tester,
  ) async {
    // Apunta al widget de preview reusable (la ruta de preview del editor por
    // bloques), no a toda la NoteEditorScreen → robusto ante rediseños del
    // chrome del editor. Cubre el valor real: que `$...$` y `$$...$$` se
    // rendericen como widgets Math (flutter_math_fork).
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoteMarkdownPreview(
                data: r'Testing inline $x^2$ and block $$e = mc^2$$ in note.',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Uno inline ($...$) + uno en bloque ($$...$$) → dos widgets Math.
    expect(find.byType(Math), findsNWidgets(2));

    // Limpia timers del visibility detector antes de cerrar.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));
  });

  test('Note to Kanban and Folder to Space link integration test', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    final labRepo = container.read(labSpaceRepositoryProvider);
    final noteRepo = container.read(noteRepositoryProvider);
    final folderRepo = container.read(folderRepositoryProvider);
    final kanbanRepo = container.read(kanbanCardRepositoryProvider);

    // 1. Create entities
    final space = await labRepo.create('Proyecto Final', '#3D6B4F');
    final folder = await folderRepo.create('Investigación', '#42A5F5');
    final note = await noteRepo.create(
      folder.id,
      title: 'Resumen de Lecturas',
      rawMarkdown: 'Contenido de prueba',
    );

    // 2. Link Folder to Lab Space
    await labRepo.linkFolder(space.id, folder.id);
    final linkedIds = await labRepo.getLinkedFolderIds(space.id);
    expect(linkedIds, contains(folder.id));

    // 3. Create Kanban card from Note
    final columns = await labRepo.getColumns(space.id);
    final backlogColumn = columns.firstWhere((c) => c.name == 'Backlog');

    final card = await kanbanRepo.create(
      labSpaceId: space.id,
      columnId: backlogColumn.id,
      title: note.displayTitle,
      sourceNoteId: note.id,
    );

    expect(card.sourceNoteId, note.id);
    expect(card.title, 'Resumen de Lecturas');

    // 4. Clean up
    await db.close();
  });
}
