import '../models/lab_space.dart';
import '../models/kanban_column.dart';

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
  Stream<List<LabSpace>> watchDeleted();
}
