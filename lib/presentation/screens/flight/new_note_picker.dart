import 'package:flutter/material.dart';
import '../../../domain/models/note.dart';
import 'new_folder_dialog.dart';

Future<NewNoteDetails?> showNewNoteDialog(
  BuildContext context, {
  required Color folderAccent,
}) async {
  final details = await showDialog<FlightItemDetails>(
    context: context,
    builder:
        (_) => FlightItemDialog(
          title: 'Nueva nota',
          initialColor: folderAccent,
          isNote: true,
          chooseKind: true,
          allowEmptyName: true,
          actionLabel: 'Crear nota',
        ),
  );
  if (details == null) return null;
  return NewNoteDetails(
    kind: details.kind,
    title: details.name,
    color: details.color,
  );
}

class NewNoteDetails {
  final NoteKind kind;
  final String? title;
  final Color color;
  const NewNoteDetails({required this.kind, this.title, required this.color});
}
