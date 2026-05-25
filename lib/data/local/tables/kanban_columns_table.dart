import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';

@DataClassName('KanbanColumnRow')
class KanbanColumns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  TextColumn get name => text()();
  IntColumn get position => integer()();
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant(false))();

  /// Terminal columns mark the end of the kanban flow. Cards in terminal
  /// columns count as "done" for space stats and visually appear
  /// strike-through. Defaults: Entregado + Vencido are terminal.
  BoolColumn get isTerminal =>
      boolean().withDefault(const Constant(false))();
}
