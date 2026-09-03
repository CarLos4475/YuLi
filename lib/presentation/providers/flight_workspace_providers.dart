import 'dart:convert';

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

  const FlightWorkspaceTarget({
    required this.noteId,
    required this.folderId,
    required this.kind,
    required this.label,
    required this.folderLabel,
    this.canvasBlockId,
  });

  String get key => '$noteId:${canvasBlockId ?? 0}';

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'folderId': folderId,
    'kind': kind.name,
    'label': label,
    'folderLabel': folderLabel,
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
      );
}

class FlightWorkspaceTabsNotifier
    extends StateNotifier<List<FlightWorkspaceTarget>> {
  static const _key = 'flight_workspace_tabs_v1';
  static const _maxTabs = 10;
  static SharedPreferences? _prefs;

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
    final remaining = state.where((item) => item.key != target.key).toList();
    state = [...remaining, target];
    if (state.length > _maxTabs) {
      state = state.sublist(state.length - _maxTabs);
    }
    _save();
  }

  void close(FlightWorkspaceTarget target) {
    state = state.where((item) => item.key != target.key).toList();
    _save();
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
