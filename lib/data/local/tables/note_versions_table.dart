import 'package:drift/drift.dart';
import 'notes_table.dart';

@DataClassName('NoteVersionRow')
class NoteVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId => integer().references(Notes, #id)();
  TextColumn get rawMarkdown => text()();
  DateTimeColumn get savedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
