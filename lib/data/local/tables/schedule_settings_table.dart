import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';

@DataClassName('ScheduleSettingsRow')
class ScheduleSettings extends Table {
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  IntColumn get showWeekends =>
      integer().withDefault(const Constant(0))();
  TextColumn get dayStartTime =>
      text().withDefault(const Constant('07:00'))();
  TextColumn get dayEndTime =>
      text().withDefault(const Constant('22:00'))();

  @override
  Set<Column> get primaryKey => {labSpaceId};
}
