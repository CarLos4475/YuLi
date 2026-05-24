import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final labTabsProvider =
    StateNotifierProvider.family<LabTabsNotifier, List<String>, int>(
  (ref, spaceId) => LabTabsNotifier(spaceId),
);

const _baseTabs = ['Kanban'];
const _availableTabs = ['Calendario', 'Timeline'];

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
      state = List<String>.from(decoded);
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
    if (tab == 'Kanban') return; // Kanban nunca se quita
    if (state.contains(tab)) {
      state = state.where((t) => t != tab).toList();
      _save();
    }
  }

  void setTabs(List<String> tabs) {
    // Asegurar que Kanban siempre esté primero
    final hasKanban = tabs.contains('Kanban');
    final ordered = [
      if (hasKanban) 'Kanban',
      ...tabs.where((t) => t != 'Kanban' && _availableTabs.contains(t)),
    ];
    state = ordered;
    _save();
  }
}
