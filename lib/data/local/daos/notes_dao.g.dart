// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_dao.dart';

// ignore_for_file: type=lint
mixin _$NotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $NoteImagesTable get noteImages => attachedDatabase.noteImages;
  $NoteVersionsTable get noteVersions => attachedDatabase.noteVersions;
  $TasksTable get tasks => attachedDatabase.tasks;
  $NoteTaskLinksTable get noteTaskLinks => attachedDatabase.noteTaskLinks;
  $CanvasContextSourcesTable get canvasContextSources =>
      attachedDatabase.canvasContextSources;
  NotesDaoManager get managers => NotesDaoManager(this);
}

class NotesDaoManager {
  final _$NotesDaoMixin _db;
  NotesDaoManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$NoteImagesTableTableManager get noteImages =>
      $$NoteImagesTableTableManager(_db.attachedDatabase, _db.noteImages);
  $$NoteVersionsTableTableManager get noteVersions =>
      $$NoteVersionsTableTableManager(_db.attachedDatabase, _db.noteVersions);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$NoteTaskLinksTableTableManager get noteTaskLinks =>
      $$NoteTaskLinksTableTableManager(_db.attachedDatabase, _db.noteTaskLinks);
  $$CanvasContextSourcesTableTableManager get canvasContextSources =>
      $$CanvasContextSourcesTableTableManager(
        _db.attachedDatabase,
        _db.canvasContextSources,
      );
}
