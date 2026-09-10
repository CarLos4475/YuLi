import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CanvasOcrSettings {
  final bool automatic;
  final bool spelling;

  const CanvasOcrSettings({this.automatic = true, this.spelling = true});
}

final canvasOcrSettingsProvider =
    AsyncNotifierProvider<CanvasOcrSettingsNotifier, CanvasOcrSettings>(
      CanvasOcrSettingsNotifier.new,
    );

class CanvasOcrSettingsNotifier extends AsyncNotifier<CanvasOcrSettings> {
  static const preferenceKey = 'canvas_ocr_settings_v1';
  bool _saving = false;

  @override
  Future<CanvasOcrSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return const CanvasOcrSettings();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return CanvasOcrSettings(
      automatic: data['automatic'] as bool,
      spelling: data['spelling'] as bool,
    );
  }

  Future<void> setOptions({bool? automatic, bool? spelling}) async {
    if (_saving) return;
    final previous = state.requireValue;
    final next = CanvasOcrSettings(
      automatic: automatic ?? previous.automatic,
      spelling: spelling ?? previous.spelling,
    );
    _saving = true;
    state = AsyncData(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        preferenceKey,
        jsonEncode({'automatic': next.automatic, 'spelling': next.spelling}),
      )) {
        throw StateError('No se pudieron guardar los ajustes de OCR');
      }
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    } finally {
      _saving = false;
    }
  }
}
