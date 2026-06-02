import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/canvas_context_source.dart';
import '../../../domain/repositories/lab_space_repository.dart';
import '../../local/database.dart';

class LocalLabSpaceRepository implements LabSpaceRepository {
  final AppDatabase _db;

  LocalLabSpaceRepository(this._db);

  @override
  Stream<List<LabSpace>> watchActive() =>
      _db.labSpacesDao.watchActive().map((rows) => rows.map(_rowToSpace).toList());

  @override
  Future<List<LabSpace>> getActive() async {
    final rows = await _db.labSpacesDao.getActive();
    return rows.map(_rowToSpace).toList();
  }

  @override
  Future<LabSpace?> getById(int id) async {
    final row = await _db.labSpacesDao.getById(id);
    return row != null ? _rowToSpace(row) : null;
  }

  @override
  Future<LabSpace> create(String name, String accentColorHex) async {
    final row = await _db.labSpacesDao.insertSpace(
      LabSpacesCompanion.insert(name: name, accentColor: accentColorHex),
    );
    // Create default columns: Backlog, En Proceso, Entregado, Vencido.
    // Entregado + Vencido are marked terminal so cards there count as done.
    final spaceId = row.id;
    for (var i = 0; i < _defaultColumns.length; i++) {
      final name = _defaultColumns[i];
      await _db.labSpacesDao.insertColumn(
        KanbanColumnsCompanion.insert(
          labSpaceId: spaceId,
          name: name,
          position: i,
          isDefault: const Value(true),
          isTerminal: Value(name == 'Entregado'),
          isExpired: Value(name == 'Vencido'),
          isInProgress: Value(name == 'En Proceso'),
        ),
      );
    }
    return _rowToSpace(row);
  }

  static const _defaultColumns = ['Backlog', 'En Proceso', 'Entregado', 'Vencido'];

  @override
  Future<void> update(LabSpace space) async {
    await _db.labSpacesDao.updateSpace(
      LabSpacesCompanion(
        id: Value(space.id),
        name: Value(space.name),
        accentColor: Value(_colorToHex(space.accentColor)),
        status: Value(space.status.toDbString()),
        startDate: Value(space.startDate),
        dueDate: Value(space.dueDate),
        deletedAt: Value(space.deletedAt),
      ),
    );
  }

  @override
  Future<void> softDelete(int id) => _db.labSpacesDao.softDelete(id);

  @override
  Future<void> restore(int id) => _db.labSpacesDao.restore(id);

  @override
  Future<void> hardDelete(int id) => _db.hardDeleteSpaceCascade(id);

  @override
  Stream<List<LabSpace>> watchDeleted() =>
      _db.labSpacesDao.watchDeleted().map((rows) => rows.map(_rowToSpace).toList());

  @override
  Future<List<KanbanColumn>> getColumns(int labSpaceId) async {
    final rows = await _db.labSpacesDao.getColumns(labSpaceId);
    return rows.map(_rowToColumn).toList();
  }

  @override
  Stream<List<KanbanColumn>> watchColumns(int labSpaceId) =>
      _db.labSpacesDao.watchColumns(labSpaceId).map((rows) => rows.map(_rowToColumn).toList());

  @override
  Future<KanbanColumn> createColumn(int labSpaceId, String name) async {
    final existing = await _db.labSpacesDao.getColumns(labSpaceId);
    final row = await _db.labSpacesDao.insertColumn(
      KanbanColumnsCompanion.insert(
        labSpaceId: labSpaceId,
        name: name,
        position: existing.length,
      ),
    );
    return _rowToColumn(row);
  }

  @override
  Future<void> updateColumn(KanbanColumn column) async {
    await _db.labSpacesDao.updateColumn(
      KanbanColumnsCompanion(
        id: Value(column.id),
        name: Value(column.name),
        position: Value(column.position),
        isDefault: Value(column.isDefault),
        isTerminal: Value(column.isTerminal),
        isExpired: Value(column.isExpired),
        isInProgress: Value(column.isInProgress),
      ),
    );
  }

  @override
  Future<void> deleteColumn(int columnId) =>
      _db.labSpacesDao.deleteColumn(columnId);

  @override
  Future<void> reorderColumns(int labSpaceId, List<int> orderedIds) =>
      _db.labSpacesDao.reorderColumns(labSpaceId, orderedIds);

  @override
  Future<void> linkFolder(int labSpaceId, int folderId) =>
      _db.labSpacesDao.linkFolder(labSpaceId, folderId);

  @override
  Future<void> unlinkFolder(int labSpaceId, int folderId) =>
      _db.labSpacesDao.unlinkFolder(labSpaceId, folderId);

  @override
  Future<List<int>> getLinkedFolderIds(int labSpaceId) =>
      _db.labSpacesDao.getLinkedFolderIds(labSpaceId);

  @override
  Future<List<int>> getLinkedSpaceIdsForFolder(int folderId) =>
      _db.labSpacesDao.getLinkedSpaceIds(folderId);

  @override
  Stream<List<int>> watchLinkedSpaceIdsForFolder(int folderId) =>
      _db.labSpacesDao.watchLinkedSpaceIds(folderId);

  @override
  Future<void> addContextSource(
    int labSpaceId,
    CanvasSourceKind kind,
    String ref, {
    String? label,
    DateTime? fetchedAt,
  }) =>
      _db.labSpacesDao.addSpaceSource(
        labSpaceId,
        kind.toDbString(),
        ref,
        label: label,
        fetchedAt: fetchedAt,
      );

  @override
  Future<void> removeContextSource(int id) =>
      _db.labSpacesDao.removeSpaceSource(id);

  @override
  Future<void> updateContextSourceFetch(
    int id, {
    String? label,
    DateTime? fetchedAt,
  }) =>
      _db.labSpacesDao
          .updateSpaceSourceFetch(id, label: label, fetchedAt: fetchedAt);

  @override
  Stream<List<CanvasContextSource>> watchContextSources(int labSpaceId) =>
      _db.labSpacesDao
          .watchSpaceSources(labSpaceId)
          .map((rows) => rows.map(_rowToSource).toList());

  @override
  Future<List<CanvasContextSource>> getContextSources(int labSpaceId) async {
    final rows = await _db.labSpacesDao.getSpaceSources(labSpaceId);
    return rows.map(_rowToSource).toList();
  }

  CanvasContextSource _rowToSource(SpaceContextSourceRow row) =>
      CanvasContextSource(
        id: row.id,
        labSpaceId: row.labSpaceId,
        kind: CanvasSourceKind.fromString(row.kind),
        ref: row.ref,
        label: row.label,
        fetchedAt: row.fetchedAt,
        createdAt: row.createdAt,
      );

  LabSpace _rowToSpace(LabSpaceRow row) => LabSpace(
        id: row.id,
        name: row.name,
        accentColor: _hexToColor(row.accentColor),
        status: LabSpaceStatus.fromString(row.status),
        startDate: row.startDate,
        dueDate: row.dueDate,
        createdAt: row.createdAt,
        deletedAt: row.deletedAt,
      );

  KanbanColumn _rowToColumn(KanbanColumnRow row) => KanbanColumn(
        id: row.id,
        labSpaceId: row.labSpaceId,
        name: row.name,
        position: row.position,
        isDefault: row.isDefault,
        isTerminal: row.isTerminal,
        isExpired: row.isExpired,
        isInProgress: row.isInProgress,
      );

  Color _hexToColor(String hex) {
    final val = hex.replaceFirst('#', '');
    return Color(int.parse('FF$val', radix: 16));
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}
