import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/image_storage.dart';
import 'database_providers.dart';

/// Garbage-collects image folders whose note no longer exists. Fired once at
/// startup (after the expiry sweep). Fire-and-forget — never blocks the UI.
final imageCleanupProvider = FutureProvider<void>((ref) async {
  final ids = await ref.read(noteRepositoryProvider).getAllNoteIds();
  await cleanupOrphanedImages(ids.toSet());
});

/// Total bytes used by stored note images (disk scan). Invalidate to refresh.
final imageStorageBytesProvider =
    FutureProvider<int>((ref) => noteImagesTotalBytes());

typedef StoredImage = ({String path, int sizeBytes, int noteId, String label});

/// All image files on disk with a human label. Scans disk (not the
/// `note_images` table) so canvas/whiteboard images — which never write a table
/// row — also show up, matching the size readout.
final allNoteImagesProvider = FutureProvider<List<StoredImage>>((ref) async {
  final files = await listNoteImageFiles();
  final repo = ref.watch(noteRepositoryProvider);
  final labels = <int, String>{};
  for (final f in files) {
    if (labels.containsKey(f.noteId)) continue;
    final note = await repo.getById(f.noteId);
    final t = note?.title?.trim();
    labels[f.noteId] = note == null
        ? 'Nota eliminada #${f.noteId}'
        : (t != null && t.isNotEmpty ? t : 'Nota #${f.noteId}');
  }
  return [
    for (final f in files)
      (
        path: f.path,
        sizeBytes: f.sizeBytes,
        noteId: f.noteId,
        label: labels[f.noteId]!
      ),
  ];
});
