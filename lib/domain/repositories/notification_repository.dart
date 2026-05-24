import '../models/notification_item.dart';

abstract class NotificationRepository {
  Stream<List<NotificationItem>> watchAll();
  Future<void> delete(int id);
  Future<void> clearAll();
}
