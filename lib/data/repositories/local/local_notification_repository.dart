import '../../../domain/models/notification_item.dart';
import '../../../domain/repositories/notification_repository.dart';
import '../../local/database.dart';

class LocalNotificationRepository implements NotificationRepository {
  final AppDatabase _db;

  LocalNotificationRepository(this._db);

  @override
  Stream<List<NotificationItem>> watchAll() =>
      _db.notificationsDao.watchAll().map((rows) => rows.map(_rowToItem).toList());

  @override
  Future<void> delete(int id) => _db.notificationsDao.dismiss(id);

  @override
  Future<void> clearAll() => _db.notificationsDao.clearAll();

  NotificationItem _rowToItem(NotificationRow row) => NotificationItem(
        id: row.id,
        message: row.message,
        createdAt: row.createdAt,
      );
}
