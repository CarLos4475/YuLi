import 'package:drift/drift.dart';

import '../../../domain/models/schedule_block.dart';
import '../../../domain/models/schedule_settings.dart';
import '../../../domain/models/schedule_week_note.dart';
import '../../../domain/repositories/schedule_repository.dart';
import '../../local/database.dart';

class LocalScheduleRepository implements ScheduleRepository {
  final AppDatabase _db;

  LocalScheduleRepository(this._db);

  @override
  Stream<List<ScheduleBlock>> watchBySpace(int labSpaceId) =>
      _db.scheduleDao.watchBySpace(labSpaceId).map(
          (rows) => rows.map(_rowToBlock).toList());

  @override
  Future<ScheduleBlock> createBlock({
    required int labSpaceId,
    int? folderId,
    required String title,
    String? location,
    required String startTime,
    required String endTime,
    required List<String> days,
    required String color,
    bool useFolderColor = false,
  }) async {
    final row = await _db.scheduleDao.insertBlock(
      ScheduleBlocksCompanion.insert(
        labSpaceId: labSpaceId,
        folderId: Value(folderId),
        title: title,
        location: Value(location),
        startTime: startTime,
        endTime: endTime,
        days: ScheduleBlock.daysToJson(days),
        color: color,
        useFolderColor: Value(useFolderColor ? 1 : 0),
      ),
    );
    return _rowToBlock(row);
  }

  @override
  Future<void> updateBlock(ScheduleBlock block) async {
    await _db.scheduleDao.updateBlock(
      ScheduleBlocksCompanion(
        id: Value(block.id),
        labSpaceId: Value(block.labSpaceId),
        folderId: Value(block.folderId),
        title: Value(block.title),
        location: Value(block.location),
        startTime: Value(block.startTime),
        endTime: Value(block.endTime),
        days: Value(ScheduleBlock.daysToJson(block.days)),
        color: Value(block.color),
        useFolderColor: Value(block.useFolderColor ? 1 : 0),
      ),
    );
  }

  @override
  Future<void> deleteBlock(int id) => _db.scheduleDao.deleteBlock(id);

  @override
  Future<ScheduleSettings> getOrCreateSettings(int labSpaceId) async {
    final row = await _db.scheduleDao.getSettings(labSpaceId);
    if (row != null) return _rowToSettings(row);
    await _db.scheduleDao.insertSettings(
      ScheduleSettingsCompanion.insert(labSpaceId: Value(labSpaceId)),
    );
    return ScheduleSettings(labSpaceId: labSpaceId);
  }

  @override
  Future<void> updateSettings(ScheduleSettings settings) async {
    await _db.scheduleDao.updateSettings(
      ScheduleSettingsCompanion(
        labSpaceId: Value(settings.labSpaceId),
        showSaturday: Value(settings.showSaturday ? 1 : 0),
        showSunday: Value(settings.showSunday ? 1 : 0),
        dayStartTime: Value(settings.dayStartTime),
        dayEndTime: Value(settings.dayEndTime),
      ),
    );
  }

  @override
  Future<ScheduleWeekNote?> getWeekNote(
      int labSpaceId, DateTime weekStart) async {
    final startStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    final row = await _db.scheduleDao.getWeekNote(labSpaceId, startStr);
    return row != null ? _rowToWeekNote(row) : null;
  }

  @override
  Stream<ScheduleWeekNote?> watchWeekNote(
      int labSpaceId, DateTime weekStart) {
    final startStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    return _db.scheduleDao
        .watchWeekNote(labSpaceId, startStr)
        .map((row) => row != null ? _rowToWeekNote(row) : null);
  }

  @override
  Future<void> setWeekNote(
      int labSpaceId, DateTime weekStart, String note) async {
    final startStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    await _db.scheduleDao.upsertWeekNote(
      ScheduleWeekNotesCompanion(
        id: const Value.absent(),
        labSpaceId: Value(labSpaceId),
        weekStartDate: Value(startStr),
        note: Value(note),
      ),
    );
  }

  @override
  Future<void> deleteWeekNote(int id) =>
      _db.scheduleDao.deleteWeekNote(id);

  @override
  Future<List<ScheduleBlock>> getByFolderId(int folderId) async {
    final rows = await _db.scheduleDao.getByFolderId(folderId);
    return rows.map(_rowToBlock).toList();
  }

  ScheduleBlock _rowToBlock(ScheduleBlockRow row) => ScheduleBlock(
        id: row.id,
        labSpaceId: row.labSpaceId,
        folderId: row.folderId,
        title: row.title,
        location: row.location,
        startTime: row.startTime,
        endTime: row.endTime,
        days: ScheduleBlock.daysFromJson(row.days),
        color: row.color,
        useFolderColor: row.useFolderColor == 1,
        createdAt: row.createdAt,
      );

  ScheduleSettings _rowToSettings(ScheduleSettingsRow row) =>
      ScheduleSettings(
        labSpaceId: row.labSpaceId,
        showSaturday: (row.showSaturday ?? 0) == 1,
        showSunday: (row.showSunday ?? 0) == 1,
        dayStartTime: row.dayStartTime,
        dayEndTime: row.dayEndTime,
      );

  ScheduleWeekNote _rowToWeekNote(ScheduleWeekNoteRow row) =>
      ScheduleWeekNote(
        id: row.id,
        labSpaceId: row.labSpaceId,
        weekStartDate: DateTime.parse(row.weekStartDate),
        note: row.note,
      );
}
