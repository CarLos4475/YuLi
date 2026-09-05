import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/note.dart';

class FlightWorkspaceTarget {
  final int noteId;
  final int folderId;
  final int? canvasBlockId;
  final NoteKind kind;
  final String label;
  final String folderLabel;
  final Color? folderColor;

  const FlightWorkspaceTarget({
    required this.noteId,
    required this.folderId,
    required this.kind,
    required this.label,
    required this.folderLabel,
    this.canvasBlockId,
    this.folderColor,
  });

  String get key => '$noteId:${canvasBlockId ?? 0}';

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'folderId': folderId,
    'kind': kind.name,
    'label': label,
    'folderLabel': folderLabel,
    if (folderColor != null) 'folderColor': folderColor!.toARGB32(),
    if (canvasBlockId != null) 'canvasBlockId': canvasBlockId,
  };

  factory FlightWorkspaceTarget.fromJson(Map<String, dynamic> json) =>
      FlightWorkspaceTarget(
        noteId: (json['noteId'] as num).toInt(),
        folderId: (json['folderId'] as num).toInt(),
        canvasBlockId: (json['canvasBlockId'] as num?)?.toInt(),
        kind: NoteKind.fromString(json['kind'] as String? ?? ''),
        label: json['label'] as String? ?? 'Sin título',
        folderLabel: json['folderLabel'] as String? ?? 'Carpeta',
        folderColor:
            json['folderColor'] == null
                ? null
                : Color((json['folderColor'] as num).toInt()),
      );
}

class FlightWorkspaceTabsNotifier
    extends StateNotifier<List<FlightWorkspaceTarget>> {
  static const _key = 'flight_workspace_tabs_v1';
  static const _maxTabs = 10;
  static SharedPreferences? _prefs;
  final Set<String> _closedKeys = {};
  final Set<int> _closedNoteIds = {};
  final Set<int> _closedFolderIds = {};
  Set<String>? _retainedKeys;

  FlightWorkspaceTabsNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final loaded =
          (jsonDecode(raw) as List)
              .whereType<Map>()
              .map(
                (item) => FlightWorkspaceTarget.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where(_canRestore)
              .toList();
      final currentKeys = state.map((item) => item.key).toSet();
      final merged = [
        ...loaded.where((item) => !currentKeys.contains(item.key)),
        ...state,
      ];
      state =
          merged.length <= _maxTabs
              ? merged
              : merged.sublist(merged.length - _maxTabs);
    } catch (_) {}
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _key,
      jsonEncode(state.map((item) => item.toJson()).toList()),
    );
  }

  void open(FlightWorkspaceTarget target) {
    _closedKeys.remove(target.key);
    _closedNoteIds.remove(target.noteId);
    _closedFolderIds.remove(target.folderId);
    _retainedKeys?.add(target.key);
    final index = state.indexWhere((item) => item.key == target.key);
    if (index >= 0) {
      state = [...state]..[index] = target;
      _save();
      return;
    }
    state = [...state, target];
    if (state.length > _maxTabs) {
      state = state.sublist(state.length - _maxTabs);
    }
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex--;
    if (targetIndex < 0 || targetIndex >= state.length) return;
    final updated = [...state];
    final target = updated.removeAt(oldIndex);
    updated.insert(targetIndex, target);
    state = updated;
    _save();
  }

  void close(FlightWorkspaceTarget target) {
    _closedKeys.add(target.key);
    state = state.where((item) => item.key != target.key).toList();
    _save();
  }

  void closeNote(int noteId) {
    _closedNoteIds.add(noteId);
    final updated = state.where((item) => item.noteId != noteId).toList();
    if (updated.length == state.length) return;
    state = updated;
    _save();
  }

  void closeFolder(int folderId) {
    _closedFolderIds.add(folderId);
    final updated = state.where((item) => item.folderId != folderId).toList();
    if (updated.length == state.length) return;
    state = updated;
    _save();
  }

  void retainKeys(Set<String> keys) {
    _retainedKeys = {...keys};
    final updated = state.where((item) => keys.contains(item.key)).toList();
    if (updated.length == state.length) return;
    state = updated;
    _save();
  }

  bool _canRestore(FlightWorkspaceTarget target) {
    return !_closedKeys.contains(target.key) &&
        !_closedNoteIds.contains(target.noteId) &&
        !_closedFolderIds.contains(target.folderId) &&
        (_retainedKeys?.contains(target.key) ?? true);
  }

  void refresh(FlightWorkspaceTarget target) {
    final index = state.indexWhere((item) => item.key == target.key);
    if (index < 0) return;
    final updated = [...state]..[index] = target;
    state = updated;
    _save();
  }
}

final flightWorkspaceTabsProvider = StateNotifierProvider<
  FlightWorkspaceTabsNotifier,
  List<FlightWorkspaceTarget>
>((_) => FlightWorkspaceTabsNotifier());

class FlightWorkspaceExpansionNotifier extends StateNotifier<Set<String>> {
  static const _key = 'flight_workspace_expansion_v1';
  static SharedPreferences? _prefs;

  FlightWorkspaceExpansionNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final loaded = _prefs!.getStringList(_key)?.toSet() ?? const <String>{};
    state = {...loaded, ...state};
  }

  void ensureExpanded(String key) {
    if (state.contains(key)) return;
    state = {...state, key};
    _save();
  }

  void toggle(String key) {
    final updated = {...state};
    if (!updated.remove(key)) updated.add(key);
    state = updated;
    _save();
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_key, state.toList());
  }
}

final flightWorkspaceExpansionProvider =
    StateNotifierProvider<FlightWorkspaceExpansionNotifier, Set<String>>(
      (_) => FlightWorkspaceExpansionNotifier(),
    );
