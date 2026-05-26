import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/lab_space.dart';
import '../../domain/models/note.dart';
import 'database_providers.dart';

// ─── Folder enrichment ────────────────────────────────────────────────────

class FolderEnrichment {
  final int noteCount;
  final DateTime? lastEditedAt;
  final List<Note> recentNotes;
  final List<LabSpace> linkedSpaces;

  const FolderEnrichment({
    required this.noteCount,
    required this.lastEditedAt,
    required this.recentNotes,
    required this.linkedSpaces,
  });
}

final folderEnrichmentProvider =
    StreamProvider.family<FolderEnrichment, int>((ref, folderId) async* {
  final noteRepo = ref.watch(noteRepositoryProvider);
  final labRepo = ref.watch(labSpaceRepositoryProvider);

  await for (final notes in noteRepo.watchByFolder(folderId)) {
    final spaceIds = await labRepo.getLinkedSpaceIdsForFolder(folderId);
    final allSpaces = await labRepo.getActive();
    final linked =
        allSpaces.where((s) => spaceIds.contains(s.id)).toList();
    yield FolderEnrichment(
      noteCount: notes.length,
      lastEditedAt: notes.isEmpty ? null : notes.first.updatedAt,
      recentNotes: notes.take(3).toList(),
      linkedSpaces: linked,
    );
  }
});

// ─── Pinned folders (SharedPreferences-backed) ────────────────────────────

class PinnedFoldersNotifier extends StateNotifier<Set<int>> {
  static const _key = 'pinned_folder_ids';
  static SharedPreferences? _prefs;

  PinnedFoldersNotifier() : super(<int>{}) {
    _load();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<int>();
      state = list.toSet();
    } catch (_) {
      // ignore corrupt prefs
    }
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(state.toList()));
  }

  void toggle(int folderId) {
    if (state.contains(folderId)) {
      state = {...state}..remove(folderId);
    } else {
      state = {...state, folderId};
    }
    _save();
  }

  bool isPinned(int folderId) => state.contains(folderId);
}

final pinnedFoldersProvider =
    StateNotifierProvider<PinnedFoldersNotifier, Set<int>>(
        (ref) => PinnedFoldersNotifier());

// ─── Pinned notes ─────────────────────────────────────────────────────────

class PinnedNotesNotifier extends StateNotifier<Set<int>> {
  static const _key = 'pinned_note_ids';
  static SharedPreferences? _prefs;

  PinnedNotesNotifier() : super(<int>{}) {
    _load();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<int>();
      state = list.toSet();
    } catch (_) {}
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(state.toList()));
  }

  void toggle(int noteId) {
    if (state.contains(noteId)) {
      state = {...state}..remove(noteId);
    } else {
      state = {...state, noteId};
    }
    _save();
  }

  bool isPinned(int noteId) => state.contains(noteId);
}

final pinnedNotesProvider =
    StateNotifierProvider<PinnedNotesNotifier, Set<int>>(
        (ref) => PinnedNotesNotifier());

// ─── FLIGHT toolbar state ─────────────────────────────────────────────────

enum FlightSort { recent, alphabetical, count }

enum FlightView { grid, list }

enum FlightFilter { all, withNotes, empty, pinned }

class FlightToolbarState {
  final FlightSort sort;
  final FlightView view;
  final String query;
  final FlightFilter filter;

  const FlightToolbarState({
    this.sort = FlightSort.recent,
    this.view = FlightView.grid,
    this.query = '',
    this.filter = FlightFilter.all,
  });

  FlightToolbarState copyWith({
    FlightSort? sort,
    FlightView? view,
    String? query,
    FlightFilter? filter,
  }) =>
      FlightToolbarState(
        sort: sort ?? this.sort,
        view: view ?? this.view,
        query: query ?? this.query,
        filter: filter ?? this.filter,
      );
}

class FlightToolbarNotifier extends StateNotifier<FlightToolbarState> {
  FlightToolbarNotifier() : super(const FlightToolbarState());

  void setSort(FlightSort s) => state = state.copyWith(sort: s);
  void setView(FlightView v) => state = state.copyWith(view: v);
  void setQuery(String q) => state = state.copyWith(query: q);
  void setFilter(FlightFilter f) => state = state.copyWith(filter: f);
}

final flightToolbarProvider =
    StateNotifierProvider<FlightToolbarNotifier, FlightToolbarState>(
        (ref) => FlightToolbarNotifier());

// ─── Global note search ───────────────────────────────────────────────────

class NoteSearchHit {
  final Note note;
  final String folderName;
  final int folderId;
  const NoteSearchHit({
    required this.note,
    required this.folderName,
    required this.folderId,
  });
}

final globalNoteSearchProvider =
    FutureProvider.family<List<NoteSearchHit>, String>(
        (ref, query) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final noteRepo = ref.watch(noteRepositoryProvider);
  final folders = await ref.watch(folderRepositoryProvider).getActive();
  final folderById = {for (final f in folders) f.id: f};
  final results = <NoteSearchHit>[];
  for (final f in folders) {
    final notes = await noteRepo.getByFolder(f.id);
    for (final n in notes) {
      final title = (n.title ?? '').toLowerCase();
      final body = n.rawMarkdown.toLowerCase();
      if (title.contains(q) || body.contains(q)) {
        results.add(NoteSearchHit(
          note: n,
          folderId: f.id,
          folderName: folderById[f.id]?.name ?? '',
        ));
      }
    }
  }
  return results;
});
