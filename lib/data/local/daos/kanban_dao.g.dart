// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kanban_dao.dart';

// ignore_for_file: type=lint
mixin _$KanbanDaoMixin on DatabaseAccessor<AppDatabase> {
  $LabSpacesTable get labSpaces => attachedDatabase.labSpaces;
  $KanbanColumnsTable get kanbanColumns => attachedDatabase.kanbanColumns;
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $TasksTable get tasks => attachedDatabase.tasks;
  $KanbanCardsTable get kanbanCards => attachedDatabase.kanbanCards;
  KanbanDaoManager get managers => KanbanDaoManager(this);
}

class KanbanDaoManager {
  final _$KanbanDaoMixin _db;
  KanbanDaoManager(this._db);
  $$LabSpacesTableTableManager get labSpaces =>
      $$LabSpacesTableTableManager(_db.attachedDatabase, _db.labSpaces);
  $$KanbanColumnsTableTableManager get kanbanColumns =>
      $$KanbanColumnsTableTableManager(_db.attachedDatabase, _db.kanbanColumns);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$KanbanCardsTableTableManager get kanbanCards =>
      $$KanbanCardsTableTableManager(_db.attachedDatabase, _db.kanbanCards);
}
