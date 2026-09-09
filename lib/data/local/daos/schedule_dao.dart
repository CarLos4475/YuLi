import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/schedule_blocks_table.dart';
import '../tables/schedule_settings_table.dart';
import '../tables/schedule_week_notes_table.dart';

part 'schedule_dao.g.dart';

@DriftAccessor(tables: [ScheduleBlocks, ScheduleSettings, ScheduleWeekNotes])
class ScheduleDao extends DatabaseAccessor<AppDatabase>
    with _$ScheduleDaoMixin {
  ScheduleDao(super.db);

  Stream<List<ScheduleBlockRow>> watchBySpace(int labSpaceId) =>
      (select(scheduleBlocks)
        ..where((c) => c.labSpaceId.equals(labSpaceId))).watch();

  Stream<List<ScheduleBlockRow>> watchAll() => select(scheduleBlocks).watch();

  Future<ScheduleBlockRow> insertBlock(ScheduleBlocksCompanion row) async {
    final id = await into(scheduleBlocks).insert(row);
    return (select(scheduleBlocks)..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> updateBlock(ScheduleBlocksCompanion row) =>
      (update(scheduleBlocks)
        ..where((c) => c.id.equals(row.id.value))).write(row);

  Future<void> deleteBlock(int id) =>
      (delete(scheduleBlocks)..where((c) => c.id.equals(id))).go();

  Future<ScheduleSettingsRow?> getSettings() =>
      (select(scheduleSettings)
        ..where((c) => c.id.equals(1))).getSingleOrNull();

  Future<void> insertSettings(ScheduleSettingsCompanion row) =>
      into(scheduleSettings).insert(row);

  Future<void> updateSettings(ScheduleSettingsCompanion row) =>
      (update(scheduleSettings)..where((c) => c.id.equals(1))).write(row);

  Future<ScheduleWeekNoteRow?> getWeekNote(String weekStartDate) =>
      (select(
        scheduleWeekNotes,
      )..where((c) => c.weekStartDate.equals(weekStartDate))).getSingleOrNull();

  Stream<ScheduleWeekNoteRow?> watchWeekNote(String weekStartDate) =>
      (select(scheduleWeekNotes)..where(
        (c) => c.weekStartDate.equals(weekStartDate),
      )).watchSingleOrNull();

  Future<void> upsertWeekNote(ScheduleWeekNotesCompanion row) =>
      into(scheduleWeekNotes).insertOnConflictUpdate(row);

  Future<void> deleteWeekNote(int id) =>
      (delete(scheduleWeekNotes)..where((c) => c.id.equals(id))).go();

  Future<List<ScheduleBlockRow>> getByFolderId(int folderId) =>
      (select(scheduleBlocks)..where((c) => c.folderId.equals(folderId))).get();
}
