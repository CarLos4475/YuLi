import '../models/folder.dart';

abstract class FolderRepository {
  Stream<List<Folder>> watchActive();
  Future<List<Folder>> getActive();
  Future<Folder?> getById(int id);
  Future<Folder> create(String name, String colorHex);
  Future<void> update(Folder folder);
  Future<void> softDelete(int id);
  Future<void> restore(int id);
  Future<void> hardDelete(int id);
  Stream<List<Folder>> watchDeleted();
}
