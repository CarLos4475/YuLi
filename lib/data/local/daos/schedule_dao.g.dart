// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schedule_dao.dart';

// ignore_for_file: type=lint
mixin _$ScheduleDaoMixin on DatabaseAccessor<AppDatabase> {
  $LabSpacesTable get labSpaces => attachedDatabase.labSpaces;
  $ScheduleBlocksTable get scheduleBlocks => attachedDatabase.scheduleBlocks;
  $ScheduleSettingsTable get scheduleSettings =>
      attachedDatabase.scheduleSettings;
  $ScheduleWeekNotesTable get scheduleWeekNotes =>
      attachedDatabase.scheduleWeekNotes;
  ScheduleDaoManager get managers => ScheduleDaoManager(this);
}

class ScheduleDaoManager {
  final _$ScheduleDaoMixin _db;
  ScheduleDaoManager(this._db);
  $$LabSpacesTableTableManager get labSpaces =>
      $$LabSpacesTableTableManager(_db.attachedDatabase, _db.labSpaces);
  $$ScheduleBlocksTableTableManager get scheduleBlocks =>
      $$ScheduleBlocksTableTableManager(
        _db.attachedDatabase,
        _db.scheduleBlocks,
      );
  $$ScheduleSettingsTableTableManager get scheduleSettings =>
      $$ScheduleSettingsTableTableManager(
        _db.attachedDatabase,
        _db.scheduleSettings,
      );
  $$ScheduleWeekNotesTableTableManager get scheduleWeekNotes =>
      $$ScheduleWeekNotesTableTableManager(
        _db.attachedDatabase,
        _db.scheduleWeekNotes,
      );
}
