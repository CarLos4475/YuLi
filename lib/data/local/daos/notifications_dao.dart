import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notifications_table.dart';

part 'notifications_dao.g.dart';

@DriftAccessor(tables: [Notifications])
class NotificationsDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationsDaoMixin {
  NotificationsDao(super.db);

  Stream<List<NotificationRow>> watchAll() =>
      (select(notifications)..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
          .watch();

  Future<void> insert(NotificationsCompanion row) =>
      into(notifications).insert(row);

  Future<void> dismiss(int id) =>
      (delete(notifications)..where((n) => n.id.equals(id))).go();

  Future<void> clearAll() => (delete(notifications)).go();
}
