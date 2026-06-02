class ReminderRequest {
  final int id;
  final String title;
  final String body;
  final DateTime scheduledAt;
  final String payload;
  final bool exact;

  const ReminderRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
    required this.payload,
    this.exact = false,
  });
}

abstract class ReminderScheduler {
  Stream<String> get taps;
  Future<void> initialize();
  Future<bool> requestNotificationPermission();
  Future<bool> requestExactPermission();
  Future<void> schedule(ReminderRequest request);
  Future<void> cancel(int id);
  Future<List<int>> pendingIds();
  Future<bool> areNotificationsEnabled();
  Future<void> openNotificationSettings();
}
