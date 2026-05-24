import 'package:drift/drift.dart';

@DataClassName('LabSpaceRow')
class LabSpaces extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get accentColor => text()(); // hex from curated palette
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // active | completed | archived
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}
