// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_blocks_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteBlocksDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $NoteBlocksTable get noteBlocks => attachedDatabase.noteBlocks;
  NoteBlocksDaoManager get managers => NoteBlocksDaoManager(this);
}

class NoteBlocksDaoManager {
  final _$NoteBlocksDaoMixin _db;
  NoteBlocksDaoManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$NoteBlocksTableTableManager get noteBlocks =>
      $$NoteBlocksTableTableManager(_db.attachedDatabase, _db.noteBlocks);
}
