import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';

@DataClassName('ScheduleBlockRow')
class ScheduleBlocks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  IntColumn get folderId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get location => text().nullable()();
  TextColumn get startTime => text()();
  TextColumn get endTime => text()();
  TextColumn get days => text()();
  TextColumn get color => text()();
  IntColumn get useFolderColor =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
