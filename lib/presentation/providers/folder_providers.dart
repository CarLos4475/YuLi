import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/folder.dart';
import '../../domain/models/note.dart';
import 'database_providers.dart';

final activeFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchActive();
});

/// Count of active block notes in a folder — i.e. the notes a linked folder
/// would feed to the space AI (see kMaxFolderNotes). Shown in the Fuentes sheet
/// so the user sees how many notes the folder contributes and whether the cap
/// trims it. Reactive: re-counts as notes are added/removed in the folder.
final folderBlockNoteCountProvider =
    StreamProvider.family<int, int>((ref, folderId) {
  return ref.watch(noteRepositoryProvider).watchByFolder(folderId).map(
        (notes) =>
            notes.where((n) => n.isActive && n.kind == NoteKind.block).length,
      );
});

final folderByIdProvider = StreamProvider.family<Folder?, int>((ref, id) {
  return ref.watch(folderRepositoryProvider).watchActive().map(
    (folders) => folders.where((f) => f.id == id).firstOrNull,
  );
});
