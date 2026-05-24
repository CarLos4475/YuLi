import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/repositories/folder_repository.dart';
import '../../local/database.dart';

class LocalFolderRepository implements FolderRepository {
  final AppDatabase _db;

  LocalFolderRepository(this._db);

  @override
  Stream<List<Folder>> watchActive() =>
      _db.foldersDao.watchActive().map((rows) => rows.map(_rowToFolder).toList());

  @override
  Future<List<Folder>> getActive() async {
    final rows = await _db.foldersDao.getActive();
    return rows.map(_rowToFolder).toList();
  }

  @override
  Future<Folder?> getById(int id) async {
    final row = await _db.foldersDao.getById(id);
    return row != null ? _rowToFolder(row) : null;
  }

  @override
  Future<Folder> create(String name, String colorHex) async {
    final row = await _db.foldersDao.insertFolder(
      FoldersCompanion.insert(name: name, color: colorHex),
    );
    return _rowToFolder(row);
  }

  @override
  Future<void> update(Folder folder) async {
    await _db.foldersDao.updateFolder(
      FoldersCompanion(
        id: Value(folder.id),
        name: Value(folder.name),
        color: Value(_colorToHex(folder.color)),
        deletedAt: Value(folder.deletedAt),
      ),
    );
  }

  @override
  Future<void> softDelete(int id) => _db.foldersDao.softDelete(id);

  @override
  Future<void> restore(int id) => _db.foldersDao.restore(id);

  @override
  Future<void> hardDelete(int id) => _db.foldersDao.hardDelete(id);

  @override
  Stream<List<Folder>> watchDeleted() =>
      _db.foldersDao.watchDeleted().map((rows) => rows.map(_rowToFolder).toList());

  Folder _rowToFolder(FolderRow row) => Folder(
        id: row.id,
        name: row.name,
        color: _hexToColor(row.color),
        createdAt: row.createdAt,
        deletedAt: row.deletedAt,
      );

  Color _hexToColor(String hex) {
    final val = hex.replaceFirst('#', '');
    return Color(int.parse('FF$val', radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}
