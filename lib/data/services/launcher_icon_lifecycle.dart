import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'launcher_icon_service.dart';

class LauncherIconLifecycle with WidgetsBindingObserver {
  final LauncherIconService service;
  bool _pending = false;
  static const int _delayMs = 30000;

  LauncherIconLifecycle(this.service);

  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!LauncherIconService.isSupported) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _scheduleDeferred();
        break;
      case AppLifecycleState.resumed:
        _cancelDeferred();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _scheduleDeferred() async {
    if (_pending) return;
    _pending = true;
    try {
      await service.scheduleLifecycleSwap(delayMs: _delayMs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LauncherIconLifecycle: failed to schedule: $e');
      }
    }
  }

  Future<void> _cancelDeferred() async {
    if (!_pending) return;
    _pending = false;
    try {
      await service.cancelLifecycleSwap();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LauncherIconLifecycle: failed to cancel: $e');
      }
    }
  }
}
