import 'package:drift/drift.dart';

@DataClassName('ScheduleSettingsRow')
class ScheduleSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get showSaturday => integer().nullable()();
  IntColumn get showSunday => integer().nullable()();
  TextColumn get dayStartTime => text().withDefault(const Constant('07:00'))();
  TextColumn get dayEndTime => text().withDefault(const Constant('22:00'))();

  @override
  Set<Column> get primaryKey => {id};
}
