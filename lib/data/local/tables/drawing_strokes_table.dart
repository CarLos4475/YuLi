import 'package:drift/drift.dart';

import 'note_blocks_table.dart';

@DataClassName('DrawingStrokeRow')
class DrawingStrokes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get blockId =>
      integer().references(NoteBlocks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  BlobColumn get data => blob()();
  RealColumn get minX => real()();
  RealColumn get minY => real()();
  RealColumn get maxX => real()();
  RealColumn get maxY => real()();
  IntColumn get pointCount => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
