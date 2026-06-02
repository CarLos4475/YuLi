import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';

/// Context sources feeding a lab space's AI chat. Space-owned mirror of
/// [CanvasContextSources]: same kinds (`note` / `folder` / `url`) and shape,
/// owned by a lab space instead of a canvas note. A `folder` source links a
/// whole folder (expands to its notes) — supersedes the old `space_folder_links`.
@DataClassName('SpaceContextSourceRow')
class SpaceContextSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  TextColumn get kind => text()(); // 'note' | 'folder' | 'url'
  TextColumn get ref => text()(); // note id / folder id / URL
  TextColumn get label => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {labSpaceId, kind, ref}
      ];
}
