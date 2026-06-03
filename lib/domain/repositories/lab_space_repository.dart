import '../models/lab_space.dart';
import '../models/kanban_column.dart';
import '../models/canvas_context_source.dart';

abstract class LabSpaceRepository {
  Stream<List<LabSpace>> watchActive();
  Future<List<LabSpace>> getActive();
  Future<LabSpace?> getById(int id);
  Future<LabSpace> create(String name, String accentColorHex);
  Future<void> update(LabSpace space);
  Future<void> softDelete(int id);
  Future<void> restore(int id);
  Future<void> hardDelete(int id);

  Future<List<KanbanColumn>> getColumns(int labSpaceId);
  Stream<List<KanbanColumn>> watchColumns(int labSpaceId);
  Future<KanbanColumn> createColumn(int labSpaceId, String name);
  Future<void> updateColumn(KanbanColumn column);
  Future<void> deleteColumn(int columnId);
  Future<void> reorderColumns(int labSpaceId, List<int> orderedIds);

  Future<void> linkFolder(int labSpaceId, int folderId);
  Future<void> unlinkFolder(int labSpaceId, int folderId);
  Future<List<int>> getLinkedFolderIds(int labSpaceId);
  Future<List<int>> getLinkedSpaceIdsForFolder(int folderId);
  Stream<List<int>> watchLinkedSpaceIdsForFolder(int folderId);
  Stream<List<LabSpace>> watchDeleted();

  // Unified context sources owned by a space (note/folder/url).
  Future<void> addContextSource(
    int labSpaceId,
    CanvasSourceKind kind,
    String ref, {
    String? label,
    DateTime? fetchedAt,
  });
  Future<void> removeContextSource(int id);
  Future<void> setContextSourceEnabled(int id, bool enabled);
  Future<void> updateContextSourceFetch(
    int id, {
    String? label,
    DateTime? fetchedAt,
  });
  Stream<List<CanvasContextSource>> watchContextSources(int labSpaceId);
  Future<List<CanvasContextSource>> getContextSources(int labSpaceId);
}
