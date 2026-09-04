import 'package:drift/drift.dart';
import 'folders_table.dart';

@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get folderId => integer().references(Folders, #id)();
  TextColumn get title => text().nullable()();
  TextColumn get rawMarkdown => text().withDefault(const Constant(''))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get color => text().nullable()();

  /// Note variant. 'block' = block-based editor (default). 'whiteboard' =
  /// infinite canvas, drawing-only.
  TextColumn get kind => text().withDefault(const Constant('block'))();
  IntColumn get parentNoteId => integer().nullable().references(Notes, #id)();
  IntColumn get parentCanvasBlockId => integer().nullable()();
  IntColumn get workspaceOrder => integer().withDefault(const Constant(0))();
  BoolColumn get createdFromWiki =>
      boolean().withDefault(const Constant(false))();
}
