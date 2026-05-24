import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/presentation/providers/database_providers.dart';
import 'package:yuli/presentation/screens/flight/note_editor_screen.dart';

void main() {
  testWidgets('NoteEditorScreen LaTeX preview test', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    
    final folder = Folder(
      id: 1,
      name: 'Matemáticas',
      color: Colors.red,
      createdAt: DateTime.now(),
    );

    final note = Note(
      id: 1,
      folderId: 1,
      title: 'Apuntes de Álgebra',
      rawMarkdown: 'Testing inline \$x^2\$ and block \$\$e = mc^2\$\$ in note.',
      sizeBytes: 100,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          home: NoteEditorScreen(note: note, folder: folder),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify we start in edit mode (the text field containing the rawMarkdown is visible)
    expect(find.textContaining('Testing inline'), findsOneWidget);

    // Tap the preview toggle button
    await tester.tap(find.text('preview'));
    await tester.pumpAndSettle();

    // Verify we are in preview mode
    expect(find.text('editar'), findsOneWidget);

    // Verify that we can find the Math widgets
    final mathFinder = find.byType(Math);
    expect(mathFinder, findsNWidgets(2));
    print('SUCCESS: Found 2 Math widgets rendered in the preview!');

    // Dispose the widget tree to cleanup visibility detector timers
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 600));

    await db.close();
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
