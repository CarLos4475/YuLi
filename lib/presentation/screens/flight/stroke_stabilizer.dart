import 'dart:ui' show Offset;

/// Live stroke stabilizer levels. [off] means raw input (no smoothing). Higher
/// levels lag the drawn point further behind the pointer, smoothing out hand
/// jitter as you write.
enum StabilizerLevel { off, low, medium, high }

extension StabilizerLevelX on StabilizerLevel {
  String get label => switch (this) {
        StabilizerLevel.off => 'OFF',
        StabilizerLevel.low => 'BAJO',
        StabilizerLevel.medium => 'MEDIO',
        StabilizerLevel.high => 'ALTO',
      };

  bool get isOn => this != StabilizerLevel.off;

  StabilizerLevel get next =>
      StabilizerLevel.values[(index + 1) % StabilizerLevel.values.length];

  /// EMA factor. Lower = more smoothing / lag.
  double get alpha => switch (this) {
        StabilizerLevel.off => 1.0,
        StabilizerLevel.low => 0.5,
        StabilizerLevel.medium => 0.3,
        StabilizerLevel.high => 0.16,
      };
}

/// Exponential-moving-average position filter, one instance per stroke.
/// Shared by the regular pen and the fountain pen — it only touches x/y,
/// leaving pressure/timestamp components untouched.
///
/// Plain fixed-alpha EMA: lower [alpha] = more smoothing / lag. No speed
/// adaptation — the adaptive variant added a laggy "extra ink" catch-up on fast
/// strokes that felt dirty, so it was removed; the level's alpha is enough.
class LiveStabilizer {
  final double alpha;
  double _x = 0;
  double _y = 0;
  bool _started = false;

  LiveStabilizer(this.alpha);

  Offset process(double x, double y) {
    if (!_started) {
      _started = true;
      _x = x;
      _y = y;
      return Offset(x, y);
    }
    _x += alpha * (x - _x);
    _y += alpha * (y - _y);
    return Offset(_x, _y);
  }
}
