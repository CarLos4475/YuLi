import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Root for floating-pin media (image/pdf), grouped by note:
/// `{appDocuments}/floating_pins/{noteId}/{uuid}.ext`. Kept SEPARATE from
/// `note_images/` so its own GC never touches inline note images.
Future<Directory> floatingPinsDir() async {
  final appDir = await getApplicationDocumentsDirectory();
  return Directory(p.join(appDir.path, 'floating_pins'));
}

/// Per-note media folder, created on demand.
Future<Directory> floatingPinsNoteDir(int noteId) async {
  final dir = Directory(p.join((await floatingPinsDir()).path, '$noteId'));
  await dir.create(recursive: true);
  return dir;
}

/// Copies [src] into the note's pin folder under a unique [filename] and
/// returns the destination file (flushed). Caller writes the DB row AFTER this
/// resolves, never before — so the GC can never see a row without its file.
Future<File> copyIntoFloatingPins({
  required int noteId,
  required File src,
  required String filename,
}) async {
  final dir = await floatingPinsNoteDir(noteId);
  final dest = File(p.join(dir.path, filename));
  await src.copy(dest.path);
  return dest;
}

/// Startup-only sweep. [referencedByNote] maps noteId → the filenames its rows
/// reference. Deletes (a) folders whose note has no rows (absent from the map),
/// and (b) files no row references. Must run ONLY at startup, never mid-session
/// (a freshly added pin's file is written before its row, but a sweep racing a
/// session could still see an in-flight create).
Future<void> cleanupOrphanedFloatingPins(
  Map<int, Set<String>> referencedByNote,
) async {
  final dir = await floatingPinsDir();
  if (!await dir.exists()) return;
  await for (final entity in dir.list()) {
    if (entity is! Directory) continue;
    final noteId = int.tryParse(p.basename(entity.path));
    final referenced = noteId == null ? null : referencedByNote[noteId];
    if (referenced == null || referenced.isEmpty) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
      continue;
    }
    await for (final f in entity.list()) {
      if (f is! File) continue;
      if (!referenced.contains(p.basename(f.path))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
