import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final labTabsProvider =
    StateNotifierProvider.family<LabTabsNotifier, List<String>, int>(
  (ref, spaceId) => LabTabsNotifier(spaceId),
);

const _baseTabs = ['Kanban', 'Grafo'];
const _availableTabs = ['Calendario', 'Timeline', 'Horario'];

class LabTabsNotifier extends StateNotifier<List<String>> {
  final int spaceId;
  static SharedPreferences? _prefs;

  LabTabsNotifier(this.spaceId) : super(List.from(_baseTabs)) {
    _load();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final tabs = List<String>.from(decoded);
      // Migration: spaces saved before the Grafo tab existed don't have it.
      // Inject it right after Kanban so it shows by default.
      if (!tabs.contains('Grafo')) {
        final i = tabs.indexOf('Kanban');
        tabs.insert(i >= 0 ? i + 1 : 0, 'Grafo');
        state = tabs;
        _save();
        return;
      }
      state = tabs;
    }
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(state));
  }

  String get _key => 'lab_space_tabs_$spaceId';

  List<String> get available =>
      _availableTabs.where((t) => !state.contains(t)).toList();

  void addTab(String tab) {
    if (!state.contains(tab) && _availableTabs.contains(tab)) {
      state = [...state, tab];
      _save();
    }
  }

  void removeTab(String tab) {
    if (_baseTabs.contains(tab)) return; // Kanban y Grafo nunca se quitan
    if (state.contains(tab)) {
      state = state.where((t) => t != tab).toList();
      _save();
    }
  }

  void setTabs(List<String> tabs) {
    // Kanban y Grafo siempre presentes y primero (tabs base).
    final ordered = [
      ..._baseTabs,
      ...tabs.where((t) => _availableTabs.contains(t)),
    ];
    state = ordered;
    _save();
  }
}
