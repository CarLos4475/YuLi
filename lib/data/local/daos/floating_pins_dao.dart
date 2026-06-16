import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/floating_pins_table.dart';

part 'floating_pins_dao.g.dart';

@DriftAccessor(tables: [FloatingPins])
class FloatingPinsDao extends DatabaseAccessor<AppDatabase>
    with _$FloatingPinsDaoMixin {
  FloatingPinsDao(super.db);

  Future<List<FloatingPinRow>> forNote(int noteId) =>
      (select(floatingPins)
            ..where((p) => p.noteId.equals(noteId))
            ..orderBy([(p) => OrderingTerm.asc(p.sortOrder)]))
          .get();

  Future<int> insertRow(FloatingPinsCompanion row) =>
      into(floatingPins).insert(row);

  Future<void> updateRow(int id, FloatingPinsCompanion row) =>
      (update(floatingPins)..where((p) => p.id.equals(id))).write(row);

  Future<void> deleteRow(int id) =>
      (delete(floatingPins)..where((p) => p.id.equals(id))).go();

  /// Writes the z-order in one batch (called on bringToFront / reorder).
  Future<void> setSortOrders(Map<int, int> idToOrder) async {
    if (idToOrder.isEmpty) return;
    final now = DateTime.now();
    await batch((b) {
      idToOrder.forEach((id, order) {
        b.update(
          floatingPins,
          FloatingPinsCompanion(sortOrder: Value(order), updatedAt: Value(now)),
          where: (p) => p.id.equals(id),
        );
      });
    });
  }

  Future<List<FloatingPinRow>> allRows() => select(floatingPins).get();
}
