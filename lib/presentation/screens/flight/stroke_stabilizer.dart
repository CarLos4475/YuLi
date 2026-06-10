import 'dart:math' as math;
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
/// leaving pressure/timestamp components untouched. Only runs when the user
/// turns the stabilizer on (it's OFF by default).
///
/// Smoothing is **speed-adaptive**: slow strokes get the level's full smoothing
/// (de-jitters careful writing, where positional lag is tiny because speed is
/// low), while fast strokes track the pen closely (alpha→[_fastAlpha]) so the
/// filter never builds up lag that would snap back as an "extra ink" catch-up
/// tail. Speed is the EMA of the per-sample travel distance.
class LiveStabilizer {
  final double baseAlpha;

  static const double _slowDist = 2.0;
  static const double _fastDist = 14.0;

  /// Near-raw smoothing at high speed: the ink tracks the pen with almost no
  /// lag, so a fast stroke leaves no catch-up tail.
  static const double _fastAlpha = 0.9;

  double _x = 0;
  double _y = 0;
  double _rawX = 0;
  double _rawY = 0;
  double _speed = 0;
  bool _started = false;

  LiveStabilizer(this.baseAlpha);

  Offset process(double x, double y) {
    if (!_started) {
      _started = true;
      _x = x;
      _y = y;
      _rawX = x;
      _rawY = y;
      return Offset(x, y);
    }

    final d = math.sqrt((x - _rawX) * (x - _rawX) + (y - _rawY) * (y - _rawY));
    _rawX = x;
    _rawY = y;
    // Speed reacts fast to acceleration, slowly to deceleration: ramps to
    // low-lag tracking as soon as you speed up and keeps tracking through the
    // slow-down, so a fast stroke leaves no laggy catch-up tail.
    final react = d > _speed ? 0.5 : 0.2;
    _speed += react * (d - _speed);

    final t = ((_speed - _slowDist) / (_fastDist - _slowDist)).clamp(0.0, 1.0);
    final alpha = baseAlpha + (_fastAlpha - baseAlpha) * t;

    _x += alpha * (x - _x);
    _y += alpha * (y - _y);
    return Offset(_x, _y);
  }
}
