import 'package:drift/drift.dart';
import 'notes_table.dart';

@DataClassName('NoteImageRow')
class NoteImages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId => integer().references(Notes, #id)();
  TextColumn get filename => text()(); // uuid.jpg
  TextColumn get filePath => text()(); // /app_documents/images/{note_id}/{uuid}.jpg
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
