import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Contiguous, growable point buffer for a stroke, backed by a single
/// [Float32List] with a uniform stride [comps] per point (2 = x,y; 3 = x,y plus
/// pressure/baked-width; 4 = raw fountain-pen samples).
///
/// Replaces the old `List<List<double>>`: a dense note holds millions of points,
/// and one sub-list per point was both the RAM ceiling (≈6-7× this) and the open
/// bottleneck (≈190k tiny allocations per page). Here a loaded stroke decodes
/// with a single bulk copy from the BLOB's float32 region (see
/// [DrawingStroke.fromBytes]) and reads by index with zero per-point allocation.
///
/// Mutable only by append ([add]) and in-place compaction ([removeWhere]) — used
/// for the single in-progress (active) stroke. Committed/loaded strokes are
/// treated as immutable; lasso/eraser/clone all build NEW buffers.
class StrokePoints {
  Float32List _data;
  int _length; // number of POINTS (not floats)
  final int comps;

  StrokePoints({this.comps = 2})
    : _data = _empty,
      _length = 0;

  StrokePoints._(this._data, this._length, this.comps);

  static final Float32List _empty = Float32List(0);

  /// Wrap an existing exact-size float buffer (decode path — no copy).
  factory StrokePoints.fromFloat32(Float32List data, int comps) =>
      StrokePoints._(data, comps == 0 ? 0 : data.length ~/ comps, comps);

  /// Build from the legacy nested representation (JSON path / migration).
  factory StrokePoints.fromNested(List<List<double>> pts) {
    if (pts.isEmpty) return StrokePoints();
    final comps = pts.first.length;
    final data = Float32List(pts.length * comps);
    var off = 0;
    for (final p in pts) {
      for (var c = 0; c < comps; c++) {
        data[off++] = c < p.length ? p[c] : 0.0;
      }
    }
    return StrokePoints._(data, pts.length, comps);
  }

  int get length => _length;
  bool get isEmpty => _length == 0;
  bool get isNotEmpty => _length != 0;

  double x(int i) => _data[i * comps];
  double y(int i) => _data[i * comps + 1];

  /// Third component (pencil pressure / fountain baked-width), 0 when absent.
  double z(int i) => comps > 2 ? _data[i * comps + 2] : 0.0;

  /// Arbitrary component [c] of point [i], 0 when the stride doesn't reach it.
  double comp(int i, int c) => c < comps ? _data[i * comps + c] : 0.0;

  Offset offset(int i) => Offset(_data[i * comps], _data[i * comps + 1]);

  // In-place coordinate setters for the lasso's commit-time transforms
  // (move/resize/rotate/flip mutate the selected strokes' geometry once).
  void setX(int i, double v) => _data[i * comps] = v;
  void setY(int i, double v) => _data[i * comps + 1] = v;
  void setZ(int i, double v) {
    if (comps > 2) _data[i * comps + 2] = v;
  }

  double get firstX => _data[0];
  double get firstY => _data[1];
  double get lastX => _data[(_length - 1) * comps];
  double get lastY => _data[(_length - 1) * comps + 1];

  /// Append one point. Components beyond what's passed are zero-filled; extras
  /// past [comps] are ignored. Grows the backing buffer geometrically.
  void add(double px, double py, [double? c2, double? c3]) {
    final need = (_length + 1) * comps;
    if (need > _data.length) {
      final grown = Float32List(need < 16 ? 16 : _data.length * 2);
      grown.setRange(0, _length * comps, _data);
      _data = grown;
    }
    final off = _length * comps;
    _data[off] = px;
    if (comps > 1) _data[off + 1] = py;
    if (comps > 2) _data[off + 2] = c2 ?? 0.0;
    if (comps > 3) _data[off + 3] = c3 ?? 0.0;
    _length++;
  }

  /// Append a point copying the current last point's extra components
  /// (pressure / baked-width), overriding only x,y. Mirrors the old
  /// `List<double>.from(last)` then set [0]/[1] used for the predicted tip.
  void addLikeLast(double px, double py) {
    if (_length == 0) {
      add(px, py);
      return;
    }
    final li = (_length - 1) * comps;
    add(px, py, comps > 2 ? _data[li + 2] : null, comps > 3 ? _data[li + 3] : null);
  }

  /// Drop every point for which [test] (by index) is true, compacting in place.
  /// Used by the active-stroke cleanup passes; no allocation.
  void removeWhere(bool Function(int i) test) {
    var w = 0;
    for (var r = 0; r < _length; r++) {
      if (test(r)) continue;
      if (w != r) {
        final src = r * comps;
        final dst = w * comps;
        for (var c = 0; c < comps; c++) {
          _data[dst + c] = _data[src + c];
        }
      }
      w++;
    }
    _length = w;
  }

  /// Shift every point by (dx,dy) in place (notebook page↔world conversions).
  void translate(double dx, double dy) {
    for (var i = 0; i < _length; i++) {
      _data[i * comps] += dx;
      _data[i * comps + 1] += dy;
    }
  }

  StrokePoints clone() {
    final data = Float32List(_length * comps);
    data.setRange(0, _length * comps, _data);
    return StrokePoints._(data, _length, comps);
  }

  /// Affine-map x,y of every point through [f], preserving extra components
  /// (baked-width / pressure). Used by lasso move/resize/rotate/flip.
  StrokePoints mapXY(Offset Function(double x, double y) f) {
    final data = Float32List(_length * comps);
    for (var i = 0; i < _length; i++) {
      final o = f(_data[i * comps], _data[i * comps + 1]);
      final off = i * comps;
      data[off] = o.dx;
      data[off + 1] = o.dy;
      for (var c = 2; c < comps; c++) {
        data[off + c] = _data[off + c];
      }
    }
    return StrokePoints._(data, _length, comps);
  }

  /// Exact-size float view for encoding ([DrawingStroke.toBytes]). Returns the
  /// backing array directly when already trimmed, else a trimmed copy.
  Float32List packed() {
    if (_data.length == _length * comps) return _data;
    final out = Float32List(_length * comps);
    out.setRange(0, out.length, _data);
    return out;
  }

  List<Offset> toOffsets() => [for (var i = 0; i < _length; i++) offset(i)];

  /// Rebuild the legacy nested form (cold consumers: JSON encode, export, OCR).
  List<List<double>> toNested() => [
    for (var i = 0; i < _length; i++)
      [for (var c = 0; c < comps; c++) _data[i * comps + c]],
  ];
}
