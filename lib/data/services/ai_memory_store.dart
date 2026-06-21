import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const kAiUserMemoryKey = 'yuli_user_memory_v1';

class AiMemoryRecord {
  final String key;
  final String label;
  final String value;
  final String scope;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final int? linkedTaskId;

  const AiMemoryRecord({
    required this.key,
    required this.label,
    required this.value,
    required this.scope,
    required this.createdAt,
    this.expiresAt,
    this.linkedTaskId,
  });

  bool get isExpired {
    final expires = expiresAt;
    return expires != null && !expires.isAfter(DateTime.now());
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'value': value,
    'scope': scope,
    'expiresAt': expiresAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    if (linkedTaskId != null) 'linkedTaskId': linkedTaskId,
  };

  static AiMemoryRecord? fromJson(Map<String, dynamic> json) {
    final value = _string(json['value'] ?? json['text'], '');
    if (value.isEmpty) return null;
    return AiMemoryRecord(
      key: _string(json['key'], 'memory'),
      label: _string(json['label'], _string(json['key'], 'Memoria')),
      value: value,
      scope: _normalizeScope(_string(json['scope'], 'global')),
      expiresAt: DateTime.tryParse(_string(json['expiresAt'], '')),
      createdAt:
          DateTime.tryParse(_string(json['createdAt'], '')) ?? DateTime.now(),
      linkedTaskId: _int(json['linkedTaskId']),
    );
  }
}

class AiMemoryStore {
  const AiMemoryStore();

  Future<List<AiMemoryRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final memories = _decode(prefs.getString(kAiUserMemoryKey));
    final active = memories.where((m) => !m.isExpired).toList();
    if (active.length != memories.length) {
      await prefs.setString(
        kAiUserMemoryKey,
        jsonEncode(active.map((m) => m.toJson()).toList()),
      );
    }
    active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  Future<void> saveFromWidgetItem(
    Map<String, dynamic> item, {
    int? linkedTaskId,
  }) async {
    final record = AiMemoryRecord.fromJson({
      ...item,
      'createdAt': DateTime.now().toIso8601String(),
      if (linkedTaskId != null) 'linkedTaskId': linkedTaskId,
    });
    if (record == null) return;
    await save(record);
  }

  Future<void> save(AiMemoryRecord record) async {
    if (record.value.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing =
        _decode(
          prefs.getString(kAiUserMemoryKey),
        ).where((m) => !m.isExpired).toList();
    existing.removeWhere(
      (m) =>
          m.key == record.key &&
          m.scope == record.scope &&
          _normalize(m.value) == _normalize(record.value),
    );
    existing.add(record);
    await prefs.setString(
      kAiUserMemoryKey,
      jsonEncode(existing.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> delete(AiMemoryRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        _decode(
          prefs.getString(kAiUserMemoryKey),
        ).where((m) => !m.isExpired).toList();
    existing.removeWhere(
      (m) =>
          m.key == record.key &&
          m.scope == record.scope &&
          _normalize(m.value) == _normalize(record.value) &&
          m.createdAt.toIso8601String() == record.createdAt.toIso8601String(),
    );
    await prefs.setString(
      kAiUserMemoryKey,
      jsonEncode(existing.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> clearExpired() async {
    await load();
  }

  Future<String> promptForTurn(
    String query, {
    String? noteScope,
    String? folderScope,
    int k = 6,
  }) async {
    final memories = await load();
    final q = _normalize(query);
    final scoped = {
      'global',
      if (noteScope != null && noteScope.trim().isNotEmpty) noteScope.trim(),
      if (folderScope != null && folderScope.trim().isNotEmpty)
        folderScope.trim(),
    };
    final scored = <({AiMemoryRecord memory, int score})>[];
    for (final memory in memories) {
      var score = 0;
      if (scoped.contains(memory.scope)) score += 5;
      if (memory.scope.startsWith('temp')) score += 2;
      if (memory.expiresAt != null) score += 1;
      final text = _normalize('${memory.label} ${memory.value} ${memory.key}');
      for (final token in q.split(' ')) {
        if (token.length >= 3 && text.contains(token)) score += 2;
      }
      if (score > 0) scored.add((memory: memory, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.memory.createdAt.compareTo(a.memory.createdAt);
    });
    final selected = scored.take(k).map((e) => e.memory).toList();
    if (selected.isEmpty) return '';
    return 'Memorias confirmadas del usuario. Usalas solo si ayudan, con '
        'naturalidad y sin mencionar almacenamiento interno. Si alguna memoria '
        'entra en conflicto con el mensaje actual, prioriza el mensaje actual.\n\n'
        '<user_memory>\n'
        '${selected.map(_line).join('\n')}\n'
        '</user_memory>';
  }

  List<AiMemoryRecord> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AiMemoryRecord.fromJson(Map<String, dynamic>.from(e)))
          .whereType<AiMemoryRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

String _line(AiMemoryRecord memory) {
  final expires =
      memory.expiresAt == null
          ? ''
          : ' (temporal hasta ${_date(memory.expiresAt!)})';
  return '- [${memory.scope}] ${memory.label}: ${memory.value}$expires';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _normalizeScope(String raw) {
  final scope = raw.trim();
  if (scope.isEmpty) return 'global';
  if (scope == 'temporary') return 'temp';
  return scope;
}

String _normalize(String value) {
  final lower = value.toLowerCase();
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final idx = from.indexOf(char);
    buf.write(idx >= 0 ? to[idx] : char);
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _string(Object? value, String fallback) {
  final raw = value?.toString().trim() ?? '';
  return raw.isEmpty ? fallback : raw;
}

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}
