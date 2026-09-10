import 'package:drift/drift.dart';

import 'note_blocks_table.dart';

@DataClassName('CanvasOcrPageRow')
class CanvasOcrPages extends Table {
  IntColumn get blockId => integer().references(NoteBlocks, #id)();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  IntColumn get indexedRevision => integer().nullable()();
  TextColumn get segments => text().withDefault(const Constant('[]'))();
  TextColumn get searchText => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {blockId};
}
