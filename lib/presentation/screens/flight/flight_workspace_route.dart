import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart';
import '../../providers/database_providers.dart';
import '../../providers/flight_workspace_providers.dart';
import 'note_editor_screen.dart';
import 'notebook_editor_screen.dart';
import 'whiteboard_editor_screen.dart';
import 'flight_wiki_links.dart';

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
  ref.read(flightWorkspaceTabsProvider.notifier).open(target);
  Navigator.pushReplacement(
    context,
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder:
          (_, _, _) => switch (note.kind) {
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

Future<void> openFlightWikiLink(
  BuildContext context,
  WidgetRef ref, {
  required int sourceNoteId,
  required String label,
  int? sourceCanvasBlockId,
}) async {
  final target = await resolveFlightWikiTarget(
    ref,
    sourceNoteId: sourceNoteId,
    label: label,
    createKind: NoteKind.block,
    sourceCanvasBlockId: sourceCanvasBlockId,
  );
  if (target == null || !context.mounted) return;
  await openFlightWorkspaceTarget(context, ref, target);
}
