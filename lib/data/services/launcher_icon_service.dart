import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

class LauncherIconService {
  static const _channel = MethodChannel('yuli/launcher_icon');

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
}
