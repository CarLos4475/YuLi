import 'package:drift/drift.dart';
import 'notes_table.dart';

/// Context sources feeding a canvas's AI chat. Many sources of kinds: an
/// internal `note` (`ref` = note id), a `folder` (`ref` = folder id, expands to
/// its notes) or an external `url` (`ref` = the URL, fetched once via Jina and
/// cached). [label] is the display title; [fetchedAt] is set for urls. Mirrored
/// for lab spaces by [SpaceContextSources] (same shape, space owner).
@DataClassName('CanvasContextSourceRow')
class CanvasContextSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get canvasNoteId => integer().references(Notes, #id)();
  TextColumn get kind => text()(); // 'note' | 'folder' | 'url'
  TextColumn get ref => text()(); // note id / folder id / URL
  TextColumn get label => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime().nullable()();
  // Whether this source is fed to the AI chat context (user toggle).
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {canvasNoteId, kind, ref}
      ];
}
