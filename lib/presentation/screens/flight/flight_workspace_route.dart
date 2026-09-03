import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart';
import '../../providers/database_providers.dart';
import '../../providers/flight_workspace_providers.dart';
import 'note_editor_screen.dart';
import 'notebook_editor_screen.dart';
import 'whiteboard_editor_screen.dart';

Future<void> openFlightWorkspaceTarget(
  BuildContext context,
  WidgetRef ref,
  FlightWorkspaceTarget target,
) async {
  final note = await ref.read(noteRepositoryProvider).getById(target.noteId);
  if (note == null || !note.isActive || !context.mounted) return;
  final folder = await ref
      .read(folderRepositoryProvider)
      .getById(note.folderId);
  if (folder == null || !folder.isActive || !context.mounted) return;
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder:
          (_) => switch (note.kind) {
            NoteKind.whiteboard => WhiteboardEditorScreen(
              note: note,
              folder: folder,
              initialCanvasBlockId: target.canvasBlockId,
            ),
            NoteKind.notebook => NotebookEditorScreen(
              note: note,
              folder: folder,
            ),
            _ => NoteEditorScreen(note: note, folder: folder),
          },
    ),
  );
}
