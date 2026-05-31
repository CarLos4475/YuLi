import 'package:drift/drift.dart';
import 'notes_table.dart';

/// Links a canvas note (whiteboard / notebook) to a source "block" note whose
/// content feeds the AI chat context. One canvas → at most one source
/// ([canvasNoteId] is the primary key / unique). A source note can feed many
/// canvases (no unique on [sourceNoteId]). No circularity: the sets are
/// disjoint (a note is either a block or a canvas, never both).
@DataClassName('NoteCanvasLinkRow')
class NoteCanvasLinks extends Table {
  IntColumn get canvasNoteId => integer().references(Notes, #id)();
  IntColumn get sourceNoteId => integer().references(Notes, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {canvasNoteId};
}
