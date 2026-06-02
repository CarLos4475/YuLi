import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/services/reminder_scheduler.dart';

class LocalReminderScheduler implements ReminderScheduler {
  static const _channelId = 'yuli_reminders';
  static const _channelName = 'YuLi recordatorios';
  static const _channelDescription = 'Recordatorios de tareas y resumen diario';
  static const _nativeChannel = MethodChannel('yuli/notifications');

  final FlutterLocalNotificationsPlugin _plugin;
  final _tapController = StreamController<String>.broadcast();
  bool _initialized = false;
  bool _exactEnabled = false;

  LocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  // Target real = Android. Se usa el OS del host (no defaultTargetPlatform, que
  // en flutter_test siempre es android) para que el plugin nativo solo se toque
  // en un dispositivo Android real: en el desktop GUI de pruebas y en el harness
  // de tests hace no-op en vez de tronar (ArgumentError / plugin ausente).
  bool get _supported => Platform.isAndroid;

  @override
  Stream<String> get taps => _tapController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_supported) return;
    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {}

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _tapController.add(payload);
      },
    );
    // Re-establece la capacidad de alarmas exactas en cada arranque: el flag
    // vivía solo en memoria (se perdía al reiniciar) y caía a inexacto.
    final androidPlugin =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    _exactEnabled =
        await androidPlugin?.canScheduleExactNotifications() ?? false;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) _tapController.add(payload);
  }

  @override
  Future<bool> requestNotificationPermission() async {
    await initialize();
    if (!_supported) return false;
    final android =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<bool> requestExactPermission() async {
    await initialize();
    if (!_supported) return false;
    final android =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    final granted = await android?.requestExactAlarmsPermission() ?? false;
    _exactEnabled = granted;
    return granted;
  }

  @override
  Future<void> schedule(ReminderRequest request) async {
    await initialize();
    if (!_supported) return;
    final at = request.scheduledAt;
    if (!at.isAfter(DateTime.now())) {
      await cancel(request.id);
      return;
    }
    final mode =
        request.exact && _exactEnabled
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle;
    await _plugin.zonedSchedule(
      id: request.id,
      title: request.title,
      body: request.body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          subText: request.subText,
          styleInformation: BigTextStyleInformation(
            request.body,
            contentTitle: request.title,
            summaryText: request.subText,
          ),
        ),
      ),
      androidScheduleMode: mode,
      payload: request.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<List<int>> pendingIds() async {
    if (!_supported) return const [];
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((r) => r.id).toList();
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    if (!_supported) return true;
    final android =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    return await android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<void> openNotificationSettings() async {
    if (!_supported) return;
    try {
      await _nativeChannel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }
}
