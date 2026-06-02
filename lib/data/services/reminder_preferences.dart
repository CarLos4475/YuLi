import 'package:shared_preferences/shared_preferences.dart';

class ReminderPreferences {
  static const _dailyEnabled = 'reminders_daily_enabled_v1';
  static const _dailyHour = 'reminders_daily_hour_v1';
  static const _dailyMinute = 'reminders_daily_minute_v1';
  static const _exact = 'reminders_exact_enabled_v1';

  Future<bool> dailySummaryEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dailyEnabled) ?? true;
  }

  Future<void> setDailySummaryEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyEnabled, value);
  }

  Future<({int hour, int minute})> dailySummaryTime() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      hour: prefs.getInt(_dailyHour) ?? 8,
      minute: prefs.getInt(_dailyMinute) ?? 0,
    );
  }

  Future<void> setDailySummaryTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyHour, hour);
    await prefs.setInt(_dailyMinute, minute);
  }

  Future<bool> exactRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_exact) ?? true;
  }

  Future<void> setExactRemindersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_exact, value);
  }
}
