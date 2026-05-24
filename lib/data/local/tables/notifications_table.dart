import 'package:drift/drift.dart';

@DataClassName('NotificationRow')
class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get message => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
