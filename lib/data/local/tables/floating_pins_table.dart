import 'package:drift/drift.dart';
import 'notes_table.dart';

/// Persisted floating pins (PiN multimedia): image / pdf / video windows that
/// float over a canvas, viewport-pinned. Snapshot pins are volatile (memory
/// only) and never land here. Files (image/pdf) live under
/// `floating_pins/{noteId}/` and are referenced by `filename` inside
/// [metadataJson]; a startup sweep GCs anything no row references.
@DataClassName('FloatingPinRow')
class FloatingPins extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId => integer().references(Notes, #id)();
  TextColumn get kind => text()(); // 'image' | 'pdf' | 'video'
  RealColumn get left => real()();
  RealColumn get top => real()();
  RealColumn get width => real()();
  RealColumn get height => real()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // Per-kind blob: image → {filename, aspect, title}; pdf/video added later.
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
