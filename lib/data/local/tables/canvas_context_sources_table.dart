import 'package:drift/drift.dart';
import 'notes_table.dart';

/// Context sources feeding a canvas's AI chat. Generalises the old
/// `note_canvas_links` (one source per canvas) to **many** sources of two
/// kinds: an internal `note` (`ref` = note id) or an external `url` (`ref` =
/// the URL, content fetched once via Jina Reader and cached). [label] is the
/// display title (note title / page title). [fetchedAt] is set for urls.
@DataClassName('CanvasContextSourceRow')
class CanvasContextSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get canvasNoteId => integer().references(Notes, #id)();
  TextColumn get kind => text()(); // 'note' | 'url'
  TextColumn get ref => text()(); // note id (as text) or the URL
  TextColumn get label => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {canvasNoteId, kind, ref}
      ];
}
