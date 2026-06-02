import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Root folder where compressed note images live, grouped by note:
/// `{appDocuments}/note_images/{noteId}/{uuid}.jpg`.
Future<Directory> noteImagesDir() async {
  final appDir = await getApplicationDocumentsDirectory();
  return Directory(p.join(appDir.path, 'note_images'));
}

/// Reconciliation sweep: deletes any `note_images/{id}` folder whose note no
/// longer exists in the DB. Catches both freshly deleted notes (the DB cascade
/// only removes the rows, not the files) and any previously leaked folders.
/// [validNoteIds] must include soft-deleted notes (their images are kept until
/// the note is purged).
Future<void> cleanupOrphanedImages(Set<int> validNoteIds) async {
  final dir = await noteImagesDir();
  if (!await dir.exists()) return;
  await for (final entity in dir.list()) {
    if (entity is! Directory) continue;
    final id = int.tryParse(p.basename(entity.path));
    if (id == null || !validNoteIds.contains(id)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// One image file on disk under `note_images/{noteId}/`. The source of truth
/// for "what occupies space" — canvas/whiteboard images live here + in the
/// DrawingData payload, NOT in the `note_images` table (only note-editor inline
/// images write a table row), so the viewer must scan disk, not the table.
class NoteImageFile {
  final String path;
  final int sizeBytes;
  final int noteId;
  const NoteImageFile(
      {required this.path, required this.sizeBytes, required this.noteId});
}

/// All image files on disk, biggest first (for storage management).
Future<List<NoteImageFile>> listNoteImageFiles() async {
  final dir = await noteImagesDir();
  if (!await dir.exists()) return [];
  final out = <NoteImageFile>[];
  await for (final sub in dir.list()) {
    if (sub is! Directory) continue;
    final noteId = int.tryParse(p.basename(sub.path));
    if (noteId == null) continue;
    await for (final f in sub.list()) {
      if (f is! File) continue;
      try {
        out.add(NoteImageFile(
            path: f.path, sizeBytes: await f.length(), noteId: noteId));
      } catch (_) {}
    }
  }
  out.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return out;
}

/// Total bytes used by all stored note images (recursive).
Future<int> noteImagesTotalBytes() async {
  final dir = await noteImagesDir();
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final e in dir.list(recursive: true)) {
    if (e is File) {
      try {
        total += await e.length();
      } catch (_) {}
    }
  }
  return total;
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
