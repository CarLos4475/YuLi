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
/// leaving pressure/timestamp components untouched.
///
/// Smoothing is **speed-adaptive**: slow strokes keep detail (lighter
/// smoothing, so careful calligraphy stays faithful), fast strokes hide hand
/// tremor (full smoothing at the level's [baseAlpha]). Speed is the EMA of the
/// per-sample travel distance, in whatever coordinate space [process] is fed.
/// The adaptive factor only ever *reduces* smoothing below the baseline at low
/// speed; at high speed it equals the fixed-alpha behavior, so it never makes a
/// stroke worse than the non-adaptive filter did.
class LiveStabilizer {
  /// Heaviest smoothing factor (the level's configured alpha), used at speed.
  final double baseAlpha;

  /// Travel-per-sample (in the fed coord space) below which smoothing is at its
  /// lightest, and above which it reaches [baseAlpha]. Tuned for hand-writing.
  static const double _slowDist = 2.0;
  static const double _fastDist = 14.0;

  /// How far toward raw (alpha 1.0) the slow end backs off the smoothing.
  static const double _slowRelax = 0.6;

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
    // Asymmetric: speed builds slowly (responsive start) but DROPS fast on
    // deceleration. At the end of a fast stroke this relaxes the smoothing
    // immediately, so the lagged ink catches up as a small smooth transition
    // during the slow-down instead of snapping a long tail at lift-off.
    final react = d < _speed ? 0.6 : 0.25;
    _speed += react * (d - _speed);

    final t = ((_speed - _slowDist) / (_fastDist - _slowDist)).clamp(0.0, 1.0);
    final alphaSlow = baseAlpha + (1.0 - baseAlpha) * _slowRelax;
    final alpha = alphaSlow + (baseAlpha - alphaSlow) * t;

    _x += alpha * (x - _x);
    _y += alpha * (y - _y);
    return Offset(_x, _y);
  }
}
