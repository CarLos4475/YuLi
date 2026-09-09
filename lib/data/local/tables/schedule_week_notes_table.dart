import 'package:drift/drift.dart';

@DataClassName('ScheduleWeekNoteRow')
class ScheduleWeekNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get weekStartDate => text().unique()();
  TextColumn get note => text()();
}
