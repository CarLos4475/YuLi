import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LauncherIconVariant {
  icon1('icon1', 'Icono 1'),
  icon2('icon2', 'Icono 2'),
  icon3('icon3', 'Icono 3');

  final String id;
  final String label;

  const LauncherIconVariant(this.id, this.label);

  static LauncherIconVariant fromId(String? id) {
    return values.firstWhere(
      (variant) => variant.id == id,
      orElse: () => icon1,
    );
  }
}

enum TimeBand { morning, afternoon, evening }

extension TimeBandX on TimeBand {
  String get label {
    switch (this) {
      case TimeBand.morning:
        return 'Mañana';
      case TimeBand.afternoon:
        return 'Tarde';
      case TimeBand.evening:
        return 'Noche';
    }
  }

  LauncherIconVariant get icon {
    switch (this) {
      case TimeBand.morning:
        return LauncherIconVariant.icon1;
      case TimeBand.afternoon:
        return LauncherIconVariant.icon2;
      case TimeBand.evening:
        return LauncherIconVariant.icon3;
    }
  }
}

class TimeBandRules {
  static const int morningStart = 6;
  static const int afternoonStart = 12;
  static const int eveningStart = 18;

  static TimeBand bandFor(DateTime time) {
    final h = time.hour;
    if (h >= morningStart && h < afternoonStart) return TimeBand.morning;
    if (h >= afternoonStart && h < eveningStart) return TimeBand.afternoon;
    return TimeBand.evening;
  }

  static LauncherIconVariant iconFor(DateTime time) =>
      bandFor(time).icon;

  static DateTime nextSwapAfter(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final candidates = <DateTime>[
      today.add(const Duration(hours: morningStart)),
      today.add(const Duration(hours: afternoonStart)),
      today.add(const Duration(hours: eveningStart)),
      today.add(Duration(days: 1, hours: morningStart)),
    ];
    return candidates.firstWhere(
      (c) => c.isAfter(now),
      orElse: () => today.add(const Duration(days: 1, hours: morningStart)),
    );
  }
}

class LauncherIconService {
  static const _channel = MethodChannel('yuli/launcher_icon');
  static const _kAutoMode = 'auto_mode';
  static const _kManualOverride = 'manual_override';

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  Future<LauncherIconVariant> current() async {
    if (!isSupported) return LauncherIconVariant.icon1;
    final id = await _channel.invokeMethod<String>('current');
    return LauncherIconVariant.fromId(id);
  }

  Future<void> set(LauncherIconVariant variant) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('set', variant.id);
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<bool> isAutoMode() async {
    final p = await _prefs();
    return p.getBool(_kAutoMode) ?? true;
  }

  Future<void> setAutoMode(bool on) async {
    final p = await _prefs();
    await p.setBool(_kAutoMode, on);
    if (on) {
      await p.remove(_kManualOverride);
    }
    if (isSupported) {
      if (on) {
        await _scheduleNextSwapInternal();
      } else {
        await _channel.invokeMethod<void>('cancelSchedule');
      }
    }
  }

  Future<LauncherIconVariant?> manualOverride() async {
    final p = await _prefs();
    final id = p.getString(_kManualOverride);
    if (id == null) return null;
    return LauncherIconVariant.fromId(id);
  }

  Future<void> setManualOverride(LauncherIconVariant variant) async {
    final p = await _prefs();
    await p.setString(_kManualOverride, variant.id);
  }

  Future<void> clearManualOverride() async {
    final p = await _prefs();
    await p.remove(_kManualOverride);
  }

  Future<LauncherIconVariant> targetForNow() async {
    final p = await _prefs();
    final auto = p.getBool(_kAutoMode) ?? true;
    if (!auto) {
      final id = p.getString(_kManualOverride);
      if (id != null) return LauncherIconVariant.fromId(id);
      return TimeBandRules.iconFor(DateTime.now());
    }
    final manualId = p.getString(_kManualOverride);
    if (manualId != null) return LauncherIconVariant.fromId(manualId);
    return TimeBandRules.iconFor(DateTime.now());
  }

  Future<DateTime> nextSwapAt() async {
    final p = await _prefs();
    final auto = p.getBool(_kAutoMode) ?? true;
    if (!auto) {
      final id = p.getString(_kManualOverride);
      if (id != null) {
        return DateTime.now().add(const Duration(days: 365));
      }
    }
    return TimeBandRules.nextSwapAfter(DateTime.now());
  }

  Future<void> _scheduleNextSwapInternal() async {
    final next = TimeBandRules.nextSwapAfter(DateTime.now());
    await _channel.invokeMethod<void>('scheduleNextSwap', next.millisecondsSinceEpoch);
  }

  Future<void> scheduleNextSwap() async {
    if (!isSupported) return;
    await _scheduleNextSwapInternal();
  }

  Future<void> cancelSchedule() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancelSchedule');
  }

  Future<void> scheduleLifecycleSwap({int delayMs = 30000}) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('scheduleLifecycleSwap', delayMs);
  }

  Future<void> cancelLifecycleSwap() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('cancelLifecycleSwap');
  }
}
