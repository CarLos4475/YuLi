import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/models/floating_pin_record.dart';
import '../../../domain/repositories/floating_pin_repository.dart';
import '../../local/database.dart';
import '../../local/daos/floating_pins_dao.dart';

class LocalFloatingPinRepository implements FloatingPinRepository {
  final AppDatabase _db;
  late final FloatingPinsDao _dao = _db.floatingPinsDao;

  LocalFloatingPinRepository(this._db);

  FloatingPinRecord _toRecord(FloatingPinRow r) => FloatingPinRecord(
    id: r.id,
    noteId: r.noteId,
    kind: r.kind,
    left: r.left,
    top: r.top,
    width: r.width,
    height: r.height,
    collapsed: r.collapsed,
    sortOrder: r.sortOrder,
    metadata: _decodeMeta(r.metadataJson),
  );

  Map<String, dynamic> _decodeMeta(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  Future<List<FloatingPinRecord>> forNote(int noteId) async =>
      (await _dao.forNote(noteId)).map(_toRecord).toList();

  @override
  Future<int> insert(FloatingPinRecord record) => _dao.insertRow(
    FloatingPinsCompanion.insert(
      noteId: record.noteId,
      kind: record.kind,
      left: record.left,
      top: record.top,
      width: record.width,
      height: record.height,
      collapsed: Value(record.collapsed),
      sortOrder: Value(record.sortOrder),
      metadataJson: Value(jsonEncode(record.metadata)),
    ),
  );

  @override
  Future<void> update(FloatingPinRecord record) => _dao.updateRow(
    record.id,
    FloatingPinsCompanion(
      left: Value(record.left),
      top: Value(record.top),
      width: Value(record.width),
      height: Value(record.height),
      collapsed: Value(record.collapsed),
      sortOrder: Value(record.sortOrder),
      metadataJson: Value(jsonEncode(record.metadata)),
      updatedAt: Value(DateTime.now()),
    ),
  );

  @override
  Future<void> delete(int id) => _dao.deleteRow(id);

  @override
  Future<void> deleteForCanvas(int noteId, int canvasBlockId) async {
    final records = await forNote(noteId);
    for (final record in records) {
      if (record.canvasBlockId == canvasBlockId) {
        await _dao.deleteRow(record.id);
      }
    }
  }

  @override
  Future<void> setOrder(List<int> idsInOrder) {
    final map = <int, int>{};
    for (var i = 0; i < idsInOrder.length; i++) {
      map[idsInOrder[i]] = i;
    }
    return _dao.setSortOrders(map);
  }

  @override
  Future<Map<int, Set<String>>> referencedFilesByNote() async {
    final rows = await _dao.allRows();
    final out = <int, Set<String>>{};
    for (final r in rows) {
      final filename = _decodeMeta(r.metadataJson)['filename'];
      if (filename is! String || filename.isEmpty) continue;
      (out[r.noteId] ??= <String>{}).add(filename);
    }
    return out;
  }
}
