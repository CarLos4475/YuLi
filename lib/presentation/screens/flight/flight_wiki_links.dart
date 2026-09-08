import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../providers/database_providers.dart';
import '../../providers/flight_workspace_providers.dart';

String normalizeFlightWikiLabel(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Future<List<FlightWorkspaceTarget>> findFlightWikiTargets(
  WidgetRef ref, {
  required int sourceNoteId,
  required String query,
  int? sourceCanvasBlockId,
  int limit = 6,
}) async {
  final source = await ref.read(noteRepositoryProvider).getById(sourceNoteId);
  final notes = await ref.read(noteRepositoryProvider).watchAllActive().first;
  final folders = await ref.read(folderRepositoryProvider).getActive();
  final blocks = await ref
      .read(noteBlockRepositoryProvider)
      .getByNoteIds(notes.map((note) => note.id).toList());
  final folderById = {for (final folder in folders) folder.id: folder};
  final blocksByNote = <int, List<NoteBlock>>{};
  for (final block in blocks) {
    blocksByNote.putIfAbsent(block.noteId, () => []).add(block);
  }
  final normalizedQuery = normalizeFlightWikiLabel(query);
  final matches = <FlightWorkspaceTarget>[];
  for (final note in notes) {
    final folder = folderById[note.folderId];
    if (folder == null) continue;
    final noteLabel = note.displayTitle.trim();
    if (noteLabel.isEmpty) continue;
    final canvases =
        (blocksByNote[note.id] ?? const <NoteBlock>[])
            .whereType<DrawingBlock>()
            .toList()
          ..sort((left, right) => left.position.compareTo(right.position));
    if (note.kind == NoteKind.whiteboard && canvases.isNotEmpty) {
      for (var index = 0; index < canvases.length; index++) {
        final canvas = canvases[index];
        if (note.id == sourceNoteId && canvas.id == sourceCanvasBlockId) {
          continue;
        }
        final canvasLabel =
            canvas.name?.trim().isNotEmpty == true
                ? canvas.name!.trim()
                : 'Pizarra ${index + 1}';
        final target = FlightWorkspaceTarget(
          noteId: note.id,
          folderId: note.folderId,
          canvasBlockId: canvas.id,
          kind: note.kind,
          label: '$noteLabel · $canvasLabel',
          folderLabel: folder.name,
          folderColor: folder.color,
        );
        if (!_matchesWikiQuery(target, normalizedQuery)) continue;
        matches.add(target);
      }
      continue;
    }
    if (note.id == sourceNoteId) continue;
    final target = FlightWorkspaceTarget(
      noteId: note.id,
      folderId: note.folderId,
      kind: note.kind,
      label: noteLabel,
      folderLabel: folder.name,
      folderColor: folder.color,
    );
    if (_matchesWikiQuery(target, normalizedQuery)) matches.add(target);
  }
  matches.sort((left, right) {
    final leftLocal = left.folderId == source?.folderId;
    final rightLocal = right.folderId == source?.folderId;
    if (leftLocal != rightLocal) return leftLocal ? -1 : 1;
    final leftExact = normalizeFlightWikiLabel(left.label) == normalizedQuery;
    final rightExact = normalizeFlightWikiLabel(right.label) == normalizedQuery;
    if (leftExact != rightExact) return leftExact ? -1 : 1;
    return left.label.toLowerCase().compareTo(right.label.toLowerCase());
  });
  return matches.take(limit).toList();
}

String flightWikiTargetLabel(FlightWorkspaceTarget target) {
  if (target.canvasBlockId == null) return target.label;
  final separator = target.label.lastIndexOf(' · ');
  if (separator < 0) return target.label;
  return '${target.label.substring(0, separator)}#${target.label.substring(separator + 3)}';
}

bool _matchesWikiQuery(FlightWorkspaceTarget target, String query) =>
    query.isEmpty ||
    normalizeFlightWikiLabel(target.label).contains(query) ||
    normalizeFlightWikiLabel(flightWikiTargetLabel(target)).contains(query);

Future<FlightWorkspaceTarget?> resolveFlightWikiTarget(
  WidgetRef ref, {
  required int sourceNoteId,
  required String label,
  NoteKind? createKind,
  int? sourceCanvasBlockId,
}) async {
  final cleanLabel = label.replaceAll(RegExp(r'[\[\]\r\n]'), ' ').trim();
  if (cleanLabel.isEmpty) return null;
  final source = await ref.read(noteRepositoryProvider).getById(sourceNoteId);
  if (source == null || !source.isActive) return null;
  final matches = await findFlightWikiTargets(
    ref,
    sourceNoteId: sourceNoteId,
    query: cleanLabel,
    sourceCanvasBlockId: sourceCanvasBlockId,
    limit: 100,
  );
  final normalized = normalizeFlightWikiLabel(cleanLabel);
  final exact = matches.where(
    (target) =>
        normalizeFlightWikiLabel(target.label) == normalized ||
        normalizeFlightWikiLabel(flightWikiTargetLabel(target)) == normalized,
  );
  FlightWorkspaceTarget? target;
  if (exact.isNotEmpty) {
    target = exact.firstWhere(
      (item) => item.folderId == source.folderId,
      orElse: () => exact.first,
    );
  }
  if (target != null) return target;
  if (!cleanLabel.contains('#')) {
    final notes = await ref.read(noteRepositoryProvider).watchAllActive().first;
    final directMatches = notes.where(
      (note) =>
          note.kind == NoteKind.whiteboard &&
          normalizeFlightWikiLabel(note.displayTitle) == normalized,
    );
    if (directMatches.isNotEmpty) {
      final note = directMatches.firstWhere(
        (item) => item.folderId == source.folderId,
        orElse: () => directMatches.first,
      );
      final folder = await ref
          .read(folderRepositoryProvider)
          .getById(note.folderId);
      if (folder == null || !folder.isActive) return null;
      return FlightWorkspaceTarget(
        noteId: note.id,
        folderId: note.folderId,
        kind: note.kind,
        label: note.displayTitle,
        folderLabel: folder.name,
        folderColor: folder.color,
      );
    }
  }
  final separator = cleanLabel.lastIndexOf('#');
  if (separator > 0 && separator < cleanLabel.length - 1) {
    final noteLabel = normalizeFlightWikiLabel(
      cleanLabel.substring(0, separator),
    );
    final canvasLabel = normalizeFlightWikiLabel(
      cleanLabel.substring(separator + 1),
    );
    final notes = await ref.read(noteRepositoryProvider).watchAllActive().first;
    final noteMatches = notes.where(
      (note) =>
          note.kind == NoteKind.whiteboard &&
          normalizeFlightWikiLabel(note.displayTitle) == noteLabel,
    );
    if (noteMatches.isNotEmpty) {
      final note = noteMatches.firstWhere(
        (item) => item.folderId == source.folderId,
        orElse: () => noteMatches.first,
      );
      final canvases =
          (await ref
                .read(noteBlockRepositoryProvider)
                .getByNote(note.id)).whereType<DrawingBlock>().toList()
            ..sort((left, right) => left.position.compareTo(right.position));
      for (var index = 0; index < canvases.length; index++) {
        final canvas = canvases[index];
        final name =
            canvas.name?.trim().isNotEmpty == true
                ? canvas.name!.trim()
                : 'Pizarra ${index + 1}';
        if (normalizeFlightWikiLabel(name) != canvasLabel) continue;
        final folder = await ref
            .read(folderRepositoryProvider)
            .getById(note.folderId);
        if (folder == null || !folder.isActive) return null;
        return FlightWorkspaceTarget(
          noteId: note.id,
          folderId: note.folderId,
          canvasBlockId: canvas.id,
          kind: note.kind,
          label: '${note.displayTitle} · $name',
          folderLabel: folder.name,
          folderColor: folder.color,
        );
      }
    }
  }
  if (createKind == null) return null;
  final folder = await ref
      .read(folderRepositoryProvider)
      .getById(source.folderId);
  if (folder == null || !folder.isActive) return null;
  final created = await ref
      .read(noteRepositoryProvider)
      .create(
        source.folderId,
        title: cleanLabel,
        rawMarkdown: '',
        color: source.color,
        kind: createKind,
        parentNoteId: source.id,
        parentCanvasBlockId: sourceCanvasBlockId,
      );
  return FlightWorkspaceTarget(
    noteId: created.id,
    folderId: created.folderId,
    kind: created.kind,
    label: created.displayTitle,
    folderLabel: folder.name,
    folderColor: folder.color,
  );
}
