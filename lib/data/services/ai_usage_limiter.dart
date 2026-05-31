import 'package:shared_preferences/shared_preferences.dart';

/// Local daily cap on AI requests — defends against runaway cost (a loop, or
/// over-iterating). Counts one per message sent to the model; resets at
/// midnight (local date). No backend; for production this would move to a proxy.
class AiUsageLimiter {
  static const _kDate = 'ai_usage_date_v1';
  static const _kCount = 'ai_usage_count_v1';

  final int dailyLimit;
  const AiUsageLimiter({this.dailyLimit = 150});

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<int> _countToday(SharedPreferences p) async =>
      p.getString(_kDate) == _today() ? (p.getInt(_kCount) ?? 0) : 0;

  Future<int> remaining() async {
    final p = await SharedPreferences.getInstance();
    return (dailyLimit - await _countToday(p)).clamp(0, dailyLimit);
  }

  Future<bool> canSend() async => (await remaining()) > 0;

  /// Record one request against today's quota.
  Future<void> record() async {
    final p = await SharedPreferences.getInstance();
    final today = _today();
    final cur = p.getString(_kDate) == today ? (p.getInt(_kCount) ?? 0) : 0;
    await p.setString(_kDate, today);
    await p.setInt(_kCount, cur + 1);
  }
}
