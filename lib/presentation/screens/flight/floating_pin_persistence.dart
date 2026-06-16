import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../data/services/floating_pin_storage.dart';
import '../../../domain/models/floating_pin_record.dart';
import '../../../domain/repositories/floating_pin_repository.dart';
import 'pinned_snapshots.dart';

/// Bridges the Drift-free [FloatingPinController] to the repo + on-disk media.
/// One per open note. Writes are fire-and-forget; [insert] awaits the new id.
class RepoFloatingPinPersistence implements FloatingPinPersistence {
  final FloatingPinRepository repo;
  final int noteId;

  RepoFloatingPinPersistence({required this.repo, required this.noteId});

  FloatingPinRecord _record(FloatingPin pin) => FloatingPinRecord(
        id: pin.dbId ?? 0,
        noteId: noteId,
        kind: pin.kindName,
        left: pin.rect.left,
        top: pin.rect.top,
        width: pin.rect.width,
        height: pin.rect.height,
        collapsed: pin.collapsed,
        sortOrder: 0, // real order is written by reorder()
        metadata: pin.toMetadata(),
      );

  @override
  Future<int> insert(FloatingPin pin) => repo.insert(_record(pin));

  @override
  void save(FloatingPin pin) {
    if (pin.dbId == null) return;
    repo.update(_record(pin));
  }

  @override
  void remove(FloatingPin pin) async {
    if (pin.dbId != null) {
      await repo.delete(pin.dbId!);
    }
    final filename = pin.payload.mediaFilename;
    if (filename != null) {
      try {
        final dir = await floatingPinsNoteDir(noteId);
        final file = File(p.join(dir.path, filename));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  @override
  void reorder(List<FloatingPin> persistedFrontLast) {
    final ids = [
      for (final pin in persistedFrontLast)
        if (pin.dbId != null) pin.dbId!,
    ];
    if (ids.isNotEmpty) repo.setOrder(ids);
  }
}

/// Hydrates persisted records into renderable [FloatingPin]s. Files resolve
/// against `floating_pins/{noteId}/`. Records whose media is missing are
/// skipped (a half-GC'd folder shouldn't crash the open).
Future<List<FloatingPin>> loadFloatingPins({
  required FloatingPinRepository repo,
  required int noteId,
}) async {
  final records = await repo.forNote(noteId);
  if (records.isEmpty) return const [];
  final dir = await floatingPinsNoteDir(noteId);
  final out = <FloatingPin>[];
  for (final r in records) {
    final pin = _pinFromRecord(r, dir.path);
    if (pin != null) out.add(pin);
  }
  return out;
}

FloatingPin? _pinFromRecord(FloatingPinRecord r, String noteDirPath) {
  switch (r.kind) {
    case 'image':
      final filename = r.metadata['filename'];
      if (filename is! String || filename.isEmpty) return null;
      final path = p.join(noteDirPath, filename);
      if (!File(path).existsSync()) return null;
      final aspect = (r.metadata['aspect'] as num?)?.toDouble() ?? 1.0;
      final title = r.metadata['title'] as String?;
      return FloatingPin(
        id: 'db${r.id}',
        dbId: r.id,
        kind: FloatingPinKind.image,
        payload: ImagePinPayload(filePath: path, aspectRatio: aspect),
        rect: r.rect,
        collapsed: r.collapsed,
        title: title,
      );
    case 'pdf':
      final filename = r.metadata['filename'];
      if (filename is! String || filename.isEmpty) return null;
      final path = p.join(noteDirPath, filename);
      if (!File(path).existsSync()) return null;
      final page = (r.metadata['page'] as num?)?.toInt() ?? 1;
      return FloatingPin(
        id: 'db${r.id}',
        dbId: r.id,
        kind: FloatingPinKind.pdf,
        payload: PdfPinPayload(filePath: path, page: page < 1 ? 1 : page),
        rect: r.rect,
        collapsed: r.collapsed,
        title: r.metadata['title'] as String?,
      );
    case 'video':
      // Remote — no file on disk, so no existence check.
      final videoId = r.metadata['videoId'];
      if (videoId is! String || videoId.isEmpty) return null;
      final t = (r.metadata['t'] as num?)?.toInt() ?? 0;
      return FloatingPin(
        id: 'db${r.id}',
        dbId: r.id,
        kind: FloatingPinKind.video,
        payload: VideoPinPayload(
          videoId: videoId,
          lastPositionSeconds: t < 0 ? 0 : t,
        ),
        rect: r.rect,
        collapsed: r.collapsed,
        title: r.metadata['title'] as String?,
      );
    case 'web':
      // Remote — no file on disk, so no existence check.
      final url = r.metadata['url'];
      if (url is! String || url.isEmpty) return null;
      return FloatingPin(
        id: 'db${r.id}',
        dbId: r.id,
        kind: FloatingPinKind.web,
        payload: WebPinPayload(url: url),
        rect: r.rect,
        collapsed: r.collapsed,
        title: r.metadata['title'] as String?,
      );
    default:
      return null;
  }
}
