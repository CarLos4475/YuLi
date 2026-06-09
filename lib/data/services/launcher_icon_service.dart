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

enum IconCycleSlot { slot1, slot2, slot3 }

extension IconCycleSlotX on IconCycleSlot {
  LauncherIconVariant get icon {
    switch (this) {
      case IconCycleSlot.slot1:
        return LauncherIconVariant.icon1;
      case IconCycleSlot.slot2:
        return LauncherIconVariant.icon2;
      case IconCycleSlot.slot3:
        return LauncherIconVariant.icon3;
    }
  }
}

class IconCycleRules {
  static const List<int> boundaryHours = [0, 4, 8, 12, 16, 20];
  static const int hoursPerSwap = 4;

  static IconCycleSlot currentSlot(DateTime time) {
    final bucket = (time.hour ~/ hoursPerSwap) % IconCycleSlot.values.length;
    return IconCycleSlot.values[bucket];
  }

  static LauncherIconVariant iconFor(DateTime time) => currentSlot(time).icon;

  static DateTime nextSwapAfter(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (final h in boundaryHours) {
      final candidate = today.add(Duration(hours: h));
      if (candidate.isAfter(now)) return candidate;
    }
    return today.add(const Duration(days: 1));
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
      return IconCycleRules.iconFor(DateTime.now());
    }
    final manualId = p.getString(_kManualOverride);
    if (manualId != null) return LauncherIconVariant.fromId(manualId);
    return IconCycleRules.iconFor(DateTime.now());
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
    return IconCycleRules.nextSwapAfter(DateTime.now());
  }

  Future<void> _scheduleNextSwapInternal() async {
    final next = IconCycleRules.nextSwapAfter(DateTime.now());
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
