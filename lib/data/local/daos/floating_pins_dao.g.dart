// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'floating_pins_dao.dart';

// ignore_for_file: type=lint
mixin _$FloatingPinsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $NotesTable get notes => attachedDatabase.notes;
  $FloatingPinsTable get floatingPins => attachedDatabase.floatingPins;
  FloatingPinsDaoManager get managers => FloatingPinsDaoManager(this);
}

class FloatingPinsDaoManager {
  final _$FloatingPinsDaoMixin _db;
  FloatingPinsDaoManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$FloatingPinsTableTableManager get floatingPins =>
      $$FloatingPinsTableTableManager(_db.attachedDatabase, _db.floatingPins);
}
