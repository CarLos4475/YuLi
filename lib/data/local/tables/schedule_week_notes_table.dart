import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';

@DataClassName('ScheduleWeekNoteRow')
class ScheduleWeekNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  TextColumn get weekStartDate => text()();
  TextColumn get note => text()();
}
