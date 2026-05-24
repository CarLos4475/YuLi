import 'package:drift/drift.dart';
import 'lab_spaces_table.dart';
import 'folders_table.dart';

@DataClassName('SpaceFolderLinkRow')
class SpaceFolderLinks extends Table {
  IntColumn get labSpaceId => integer().references(LabSpaces, #id)();
  IntColumn get folderId => integer().references(Folders, #id)();

  @override
  Set<Column> get primaryKey => {labSpaceId, folderId};
}
