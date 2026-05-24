import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';
import 'kanban_columns_table.dart';
import 'notes_table.dart';
import 'tasks_table.dart';

@DataClassName('KanbanCardRow')
class KanbanCards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  IntColumn get columnId => integer().references(KanbanColumns, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get priority =>
      text().withDefault(const Constant('none'))(); // none | low | medium | high
  IntColumn get position => integer()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get sourceNoteId =>
      integer().nullable().references(Notes, #id)();
  TextColumn get sourceAnchor => text().nullable()();
  IntColumn get originTaskId =>
      integer().nullable().references(Tasks, #id)();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
