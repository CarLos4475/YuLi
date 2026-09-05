import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/data/local/database.dart';
import 'package:yuli/data/repositories/local/local_note_repository.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/domain/models/note_block.dart';
import 'package:yuli/presentation/providers/flight_workspace_providers.dart';
import 'package:yuli/presentation/widgets/flight_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('workspace target keeps stable note and canvas identity', () {
    const target = FlightWorkspaceTarget(
      noteId: 7,
      folderId: 3,
      canvasBlockId: 42,
      kind: NoteKind.whiteboard,
      label: 'Cálculo · Derivadas',
      folderLabel: 'Universidad',
      folderColor: Color(0xFF315C9E),
    );

    final restored = FlightWorkspaceTarget.fromJson(target.toJson());

    expect(restored.key, '7:42');
    expect(restored.label, target.label);
    expect(restored.kind, NoteKind.whiteboard);
    expect(restored.folderColor?.toARGB32(), 0xFF315C9E);
    expect(flightWikiLinkLabel(restored), 'Cálculo#Derivadas');
  });

  test('note workspace target emits a readable wiki label', () {
    const target = FlightWorkspaceTarget(
      noteId: 8,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Regla de la cadena',
      folderLabel: 'Universidad',
    );

    expect(target.key, '8:0');
    expect(flightWikiLinkLabel(target), 'Regla de la cadena');
  });

  test('wiki labels cannot break their own delimiter', () {
    const target = FlightWorkspaceTarget(
      noteId: 9,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Tema ]] peligroso\ncontinuación',
      folderLabel: 'Universidad',
    );

    expect(flightWikiLinkLabel(target), 'Tema peligroso continuación');
  });

  test('opening an existing workspace tab keeps its position', () {
    final notifier = FlightWorkspaceTabsNotifier();
    const first = FlightWorkspaceTarget(
      noteId: 1,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Primera',
      folderLabel: 'Universidad',
    );
    const second = FlightWorkspaceTarget(
      noteId: 2,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Segunda',
      folderLabel: 'Universidad',
    );
    notifier.open(first);
    notifier.open(second);
    notifier.open(
      const FlightWorkspaceTarget(
        noteId: 1,
        folderId: 3,
        kind: NoteKind.block,
        label: 'Primera actualizada',
        folderLabel: 'Universidad',
      ),
    );

    expect(notifier.state.map((item) => item.noteId), [1, 2]);
    expect(notifier.state.first.label, 'Primera actualizada');
  });

  test('workspace tabs support explicit reordering', () {
    final notifier = FlightWorkspaceTabsNotifier();
    for (var id = 1; id <= 3; id++) {
      notifier.open(
        FlightWorkspaceTarget(
          noteId: id,
          folderId: 3,
          kind: NoteKind.block,
          label: 'Nota $id',
          folderLabel: 'Universidad',
        ),
      );
    }

    notifier.reorder(0, 3);

    expect(notifier.state.map((item) => item.noteId), [2, 3, 1]);
  });

  test('workspace tabs prune deleted notes and unavailable canvases', () {
    final notifier = FlightWorkspaceTabsNotifier();
    const first = FlightWorkspaceTarget(
      noteId: 1,
      folderId: 3,
      canvasBlockId: 10,
      kind: NoteKind.whiteboard,
      label: 'Pizarra 1',
      folderLabel: 'Universidad',
    );
    const second = FlightWorkspaceTarget(
      noteId: 1,
      folderId: 3,
      canvasBlockId: 11,
      kind: NoteKind.whiteboard,
      label: 'Pizarra 2',
      folderLabel: 'Universidad',
    );
    const note = FlightWorkspaceTarget(
      noteId: 2,
      folderId: 3,
      kind: NoteKind.block,
      label: 'Nota',
      folderLabel: 'Universidad',
    );
    notifier.open(first);
    notifier.open(second);
    notifier.open(note);

    notifier.retainKeys({first.key, note.key});
    expect(notifier.state.map((item) => item.key).toSet(), {
      first.key,
      note.key,
    });

    notifier.closeNote(note.noteId);
    expect(notifier.state.map((item) => item.key).toSet(), {first.key});
  });

  test('whiteboards group canvases and recursive wiki children', () {
    final now = DateTime(2026, 9, 3);
    final folder = Folder(
      id: 3,
      name: 'Cálculo',
      color: const Color(0xFF2D3F8C),
      createdAt: now,
    );
    Note note(
      int id,
      String title,
      NoteKind kind, {
      int? parentNoteId,
      int? parentCanvasBlockId,
    }) => Note(
      id: id,
      folderId: folder.id,
      title: title,
      rawMarkdown: '',
      sizeBytes: 0,
      createdAt: now,
      updatedAt: now,
      kind: kind,
      parentNoteId: parentNoteId,
      parentCanvasBlockId: parentCanvasBlockId,
    );
    DrawingBlock canvas(int id, int noteId, int position, String name) =>
        DrawingBlock(
          id: id,
          noteId: noteId,
          position: position,
          height: 300,
          strokesJson: '[]',
          name: name,
        );
    final notes = [
      note(10, 'Temario', NoteKind.whiteboard),
      note(
        20,
        'Derivadas',
        NoteKind.whiteboard,
        parentNoteId: 10,
        parentCanvasBlockId: 102,
      ),
      note(
        30,
        'Regla de la cadena',
        NoteKind.block,
        parentNoteId: 20,
        parentCanvasBlockId: 201,
      ),
    ];
    final tree = buildFlightWorkspaceTree(
      folders: [folder],
      notes: notes,
      blocks: [
        canvas(101, 10, 0, 'Álgebra'),
        canvas(102, 10, 1, 'Cálculo'),
        canvas(201, 20, 0, 'Ejercicios'),
      ],
    );

    final mother = tree.rootsByFolder[folder.id]!.single;
    expect(mother.target, isNull);
    expect(mother.label, 'Temario');
    expect(mother.children.map((node) => node.label), ['Álgebra', 'Cálculo']);
    final childWhiteboard = mother.children[1].children.single;
    expect(childWhiteboard.target, isNull);
    expect(childWhiteboard.label, 'Derivadas');
    final childCanvas = childWhiteboard.children.single;
    expect(childCanvas.label, 'Ejercicios');
    expect(childCanvas.children.single.label, 'Regla de la cadena');
    expect(tree.targetsByFolder[folder.id], hasLength(4));
  });

  test(
    'wiki children persist their parent and survive parent deletion',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
      final repository = LocalNoteRepository(db);
      final parent = await repository.create(folderId, title: 'Derivadas');
      final child = await repository.create(
        folderId,
        title: 'Regla de la cadena',
        parentNoteId: parent.id,
        parentCanvasBlockId: 42,
      );

      final stored = await repository.getById(child.id);
      expect(stored?.parentNoteId, parent.id);
      expect(stored?.parentCanvasBlockId, 42);

      await db.hardDeleteNoteCascade(parent.id);

      final promoted = await repository.getById(child.id);
      expect(promoted, isNotNull);
      expect(promoted?.parentNoteId, isNull);
      expect(promoted?.parentCanvasBlockId, isNull);
    },
  );

  test('workspace branch deletion is recursive and restorable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
    final repository = LocalNoteRepository(db);
    final root = await repository.create(folderId, title: 'Temario');
    final branch = await repository.create(
      folderId,
      title: 'Derivadas',
      parentNoteId: root.id,
    );
    final grandchild = await repository.create(
      folderId,
      title: 'Regla de la cadena',
      parentNoteId: branch.id,
    );
    final sibling = await repository.create(
      folderId,
      title: 'Integrales',
      parentNoteId: root.id,
    );

    final deletedIds = await repository.softDeleteBranch(branch.id);

    expect(deletedIds.toSet(), {branch.id, grandchild.id});
    expect((await repository.getById(branch.id))?.isActive, isFalse);
    expect((await repository.getById(grandchild.id))?.isActive, isFalse);
    expect((await repository.getById(root.id))?.isActive, isTrue);
    expect((await repository.getById(sibling.id))?.isActive, isTrue);

    await repository.restore(branch.id);

    expect((await repository.getById(branch.id))?.isActive, isTrue);
    expect((await repository.getById(grandchild.id))?.isActive, isTrue);
  });

  test(
    'keeping children promotes direct children without flattening',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
      final repository = LocalNoteRepository(db);
      final root = await repository.create(folderId, title: 'Temario');
      final removed = await repository.create(
        folderId,
        title: 'Derivadas',
        parentNoteId: root.id,
      );
      final child = await repository.create(
        folderId,
        title: 'Reglas',
        parentNoteId: removed.id,
        parentCanvasBlockId: 42,
      );
      final grandchild = await repository.create(
        folderId,
        title: 'Cadena',
        parentNoteId: child.id,
      );

      await repository.softDeleteKeepingChildren(removed.id);

      expect((await repository.getById(removed.id))?.isActive, isFalse);
      final promoted = await repository.getById(child.id);
      expect(promoted?.isActive, isTrue);
      expect(promoted?.parentNoteId, isNull);
      expect(promoted?.parentCanvasBlockId, isNull);
      expect((await repository.getById(grandchild.id))?.parentNoteId, child.id);
    },
  );

  test(
    'moving a wiki branch changes its parent and folder atomically',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final firstFolder = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
      final secondFolder = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(name: 'Física', color: '#C7822F'));
      final repository = LocalNoteRepository(db);
      final originalParent = await repository.create(
        firstFolder,
        title: 'Temario',
      );
      final branch = await repository.create(
        firstFolder,
        title: 'Derivadas',
        parentNoteId: originalParent.id,
      );
      final child = await repository.create(
        firstFolder,
        title: 'Regla de la cadena',
        parentNoteId: branch.id,
      );
      final destination = await repository.create(
        secondFolder,
        title: 'Movimiento',
      );

      final movedIds = await repository.moveWorkspaceBranch(
        branch.id,
        folderId: secondFolder,
        parentNoteId: destination.id,
      );

      expect(movedIds.toSet(), {branch.id, child.id});
      final movedBranch = await repository.getById(branch.id);
      expect(movedBranch?.folderId, secondFolder);
      expect(movedBranch?.parentNoteId, destination.id);
      expect(movedBranch?.parentCanvasBlockId, isNull);
      final movedChild = await repository.getById(child.id);
      expect(movedChild?.folderId, secondFolder);
      expect(movedChild?.parentNoteId, branch.id);
    },
  );

  test('moving a wiki branch rejects cycles without changing data', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
    final repository = LocalNoteRepository(db);
    final root = await repository.create(folderId, title: 'Temario');
    final branch = await repository.create(
      folderId,
      title: 'Derivadas',
      parentNoteId: root.id,
    );
    final child = await repository.create(
      folderId,
      title: 'Regla de la cadena',
      parentNoteId: branch.id,
    );

    await expectLater(
      repository.moveWorkspaceBranch(
        branch.id,
        folderId: folderId,
        parentNoteId: child.id,
      ),
      throwsStateError,
    );

    expect((await repository.getById(branch.id))?.parentNoteId, root.id);
    expect((await repository.getById(child.id))?.parentNoteId, branch.id);
  });

  test('a wiki note stays movable after becoming a folder root', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
    final repository = LocalNoteRepository(db);
    final root = await repository.create(folderId, title: 'Temario');
    final wikiNote = await repository.create(
      folderId,
      title: 'Derivadas',
      parentNoteId: root.id,
    );

    await repository.moveWorkspaceBranch(wikiNote.id, folderId: folderId);
    final promoted = await repository.getById(wikiNote.id);
    expect(promoted?.parentNoteId, isNull);
    expect(promoted?.isWikiCreated, isTrue);

    await repository.moveWorkspaceBranch(
      wikiNote.id,
      folderId: folderId,
      parentNoteId: root.id,
    );
    expect((await repository.getById(wikiNote.id))?.parentNoteId, root.id);
    await expectLater(
      repository.moveWorkspaceBranch(root.id, folderId: folderId),
      throwsStateError,
    );
  });

  test('workspace order persists when wiki siblings are rearranged', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db
        .into(db.folders)
        .insert(FoldersCompanion.insert(name: 'Cálculo', color: '#2D3F8C'));
    final repository = LocalNoteRepository(db);
    final root = await repository.create(folderId, title: 'Temario');
    final first = await repository.create(
      folderId,
      title: 'A',
      parentNoteId: root.id,
    );
    final second = await repository.create(
      folderId,
      title: 'B',
      parentNoteId: root.id,
    );
    final third = await repository.create(
      folderId,
      title: 'C',
      parentNoteId: root.id,
    );
    expect(first.workspaceOrder, 0);
    expect(second.workspaceOrder, 1);
    expect(third.workspaceOrder, 2);

    await repository.moveWorkspaceBranch(
      third.id,
      folderId: folderId,
      parentNoteId: root.id,
      beforeNoteId: first.id,
    );

    final ordered = [
      await repository.getById(first.id),
      await repository.getById(second.id),
      await repository.getById(third.id),
    ]..sort(
      (left, right) => left!.workspaceOrder.compareTo(right!.workspaceOrder),
    );
    expect(ordered.map((note) => note?.displayTitle), ['C', 'A', 'B']);
  });
}
