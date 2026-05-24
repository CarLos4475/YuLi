import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/lab_space.dart';
import '../../domain/models/kanban_card.dart';
import '../../domain/models/kanban_column.dart';
import 'database_providers.dart';

final activeLabSpacesProvider = StreamProvider<List<LabSpace>>((ref) {
  return ref.watch(labSpaceRepositoryProvider).watchActive();
});

final labSpaceByIdProvider = FutureProvider.family<LabSpace?, int>((ref, id) {
  return ref.watch(labSpaceRepositoryProvider).getById(id);
});

final kanbanColumnsProvider =
    StreamProvider.family<List<KanbanColumn>, int>((ref, labSpaceId) {
  return ref.watch(labSpaceRepositoryProvider).watchColumns(labSpaceId);
});

final kanbanCardsByColumnProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, columnId) {
  return ref.watch(kanbanCardRepositoryProvider).watchByColumn(columnId);
});

final kanbanCardsBySpaceProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, labSpaceId) {
  return ref.watch(kanbanCardRepositoryProvider).watchBySpace(labSpaceId);
});

final linkedFolderIdsProvider = FutureProvider.family<List<int>, int>((ref, spaceId) {
  return ref.watch(labSpaceRepositoryProvider).getLinkedFolderIds(spaceId);
});

final kanbanCardsByNoteProvider =
    StreamProvider.family<List<KanbanCard>, int>((ref, noteId) {
  return ref.watch(kanbanCardRepositoryProvider).watchBySourceNoteId(noteId);
});
