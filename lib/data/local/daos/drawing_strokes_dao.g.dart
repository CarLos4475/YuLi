// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drawing_strokes_dao.dart';

// ignore_for_file: type=lint
mixin _$DrawingStrokesDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $NoteBlocksTable get noteBlocks => attachedDatabase.noteBlocks;
  $DrawingStrokesTable get drawingStrokes => attachedDatabase.drawingStrokes;
  DrawingStrokesDaoManager get managers => DrawingStrokesDaoManager(this);
}

class DrawingStrokesDaoManager {
  final _$DrawingStrokesDaoMixin _db;
  DrawingStrokesDaoManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$NoteBlocksTableTableManager get noteBlocks =>
      $$NoteBlocksTableTableManager(_db.attachedDatabase, _db.noteBlocks);
  $$DrawingStrokesTableTableManager get drawingStrokes =>
      $$DrawingStrokesTableTableManager(
        _db.attachedDatabase,
        _db.drawingStrokes,
      );
}
