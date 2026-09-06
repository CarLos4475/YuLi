import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuli/domain/models/folder.dart';
import 'package:yuli/domain/models/note.dart';
import 'package:yuli/presentation/providers/ai_providers.dart';
import 'package:yuli/presentation/providers/flight_workspace_providers.dart';
import 'package:yuli/presentation/providers/lab_space_providers.dart';
import 'package:yuli/presentation/providers/note_block_providers.dart';
import 'package:yuli/presentation/screens/flight/note_editor_screen.dart';

void main() {
  testWidgets('opening a note updates watched tabs after mounting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026);
    final container = ProviderContainer(
      overrides: [
        noteBlocksProvider(1).overrideWith((ref) => Stream.value([])),
        activeLabSpacesProvider.overrideWith((ref) => Stream.value([])),
        aiHasKeyProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              ref.watch(flightWorkspaceTabsProvider);
              return NoteEditorScreen(
                note: Note(
                  id: 1,
                  folderId: 1,
                  title: 'Prueba',
                  rawMarkdown: '',
                  sizeBytes: 0,
                  createdAt: date,
                  updatedAt: date,
                ),
                folder: Folder(
                  id: 1,
                  name: 'Carpeta',
                  color: const Color(0xFF315C9E),
                  createdAt: date,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(container.read(flightWorkspaceTabsProvider).single.noteId, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
