import 'package:drift/drift.dart';
import 'notes_table.dart';
import 'tasks_table.dart';

@DataClassName('NoteTaskLinkRow')
class NoteTaskLinks extends Table {
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get taskId => integer().references(Tasks, #id)();

  @override
  Set<Column> get primaryKey => {noteId, taskId};
}
