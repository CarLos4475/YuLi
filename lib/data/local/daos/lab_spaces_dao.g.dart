// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lab_spaces_dao.dart';

// ignore_for_file: type=lint
mixin _$LabSpacesDaoMixin on DatabaseAccessor<AppDatabase> {
  $LabSpacesTable get labSpaces => attachedDatabase.labSpaces;
  $KanbanColumnsTable get kanbanColumns => attachedDatabase.kanbanColumns;
  $FoldersTable get folders => attachedDatabase.folders;
  $SpaceFolderLinksTable get spaceFolderLinks =>
      attachedDatabase.spaceFolderLinks;
  LabSpacesDaoManager get managers => LabSpacesDaoManager(this);
}

class LabSpacesDaoManager {
  final _$LabSpacesDaoMixin _db;
  LabSpacesDaoManager(this._db);
  $$LabSpacesTableTableManager get labSpaces =>
      $$LabSpacesTableTableManager(_db.attachedDatabase, _db.labSpaces);
  $$KanbanColumnsTableTableManager get kanbanColumns =>
      $$KanbanColumnsTableTableManager(_db.attachedDatabase, _db.kanbanColumns);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$SpaceFolderLinksTableTableManager get spaceFolderLinks =>
      $$SpaceFolderLinksTableTableManager(
        _db.attachedDatabase,
        _db.spaceFolderLinks,
      );
}
