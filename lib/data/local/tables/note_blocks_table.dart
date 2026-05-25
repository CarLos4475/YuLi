import 'package:drift/drift.dart';

import 'notes_table.dart';

/// Typed blocks for the new block-based note editor.
///
/// `type` is one of: text | math | heading | bullets | tareas | drawing.
/// `payload` is JSON with the type-specific data:
///   text     → {"md": "raw markdown including inline \\(...\\) latex"}
///   math     → {"latex": "displayed formula"}
///   heading  → {"level": 1|2|3, "text": "..."}
///   bullets  → {"items": ["...", "..."]}
///   tareas   → {"taskIds": [12, 34]}
///   drawing  → {"h": 300, "s": [strokes]}  (mirrors note_cell_model)
@DataClassName('NoteBlockRow')
class NoteBlocks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get type => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
