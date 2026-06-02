import 'package:shared_preferences/shared_preferences.dart';

/// Deterministic FNV-1a hash (stable across runs, unlike String.hashCode) — so
/// the on-disk caches survive app restarts.
String contextStableHash(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h.toRadixString(16);
}

// ─── Per-source compaction cache ──────────────────────────────────────────
// Key = a stable source key ("note:<id>" / "url:<hash>"); value =
// "<contentHash> <compacted>". Lets a long source compact ONCE and be reused on
// every resync/re-open while its content is unchanged (no request, no tokens).

const _kCompactPrefix = 'ai_cpt_v2_';

Future<String?> readCompactCache(String sourceKey, String content) async {
  final p = await SharedPreferences.getInstance();
  final stored = p.getString('$_kCompactPrefix$sourceKey');
  if (stored == null) return null;
  final sep = stored.indexOf(' ');
  if (sep < 0) return null;
  if (stored.substring(0, sep) != contextStableHash(content)) return null; // stale
  return stored.substring(sep + 1);
}

Future<void> writeCompactCache(
    String sourceKey, String content, String compacted) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(
      '$_kCompactPrefix$sourceKey', '${contextStableHash(content)} $compacted');
}

/// Drops a source's compaction cache entry (call when the source is removed,
/// so SharedPreferences doesn't keep orphaned entries).
Future<void> clearCompactCache(String sourceKey) async {
  final p = await SharedPreferences.getInstance();
  await p.remove('$_kCompactPrefix$sourceKey');
}

// ─── Fetched URL content cache ──────────────────────────────────────────────
// External pages are fetched ONCE (on add / explicit refresh) and frozen here.
// Resync/re-open reads from this cache and never touches the network.

const _kUrlPrefix = 'ai_url_v1_';

Future<String?> readUrlContent(String url) async {
  final p = await SharedPreferences.getInstance();
  return p.getString('$_kUrlPrefix${contextStableHash(url)}');
}

Future<void> writeUrlContent(String url, String content) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('$_kUrlPrefix${contextStableHash(url)}', content);
}

/// Drops a fetched URL's cached content (call when its source is removed).
Future<void> clearUrlContent(String url) async {
  final p = await SharedPreferences.getInstance();
  await p.remove('$_kUrlPrefix${contextStableHash(url)}');
}
