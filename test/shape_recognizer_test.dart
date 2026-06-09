import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuli/presentation/screens/flight/shape_recognizer.dart';

// Synthetic strokes that mimic how a hand draws each shape, with light jitter,
// so the recognizer is exercised on realistic (not perfect) input.

List<List<double>> _jitter(List<List<double>> pts, double amp, int seed) {
  final rnd = math.Random(seed);
  return [
    for (final p in pts)
      [p[0] + (rnd.nextDouble() - 0.5) * amp, p[1] + (rnd.nextDouble() - 0.5) * amp]
  ];
}

List<List<double>> _denseLine(List<double> a, List<double> b, int n) => [
      for (int i = 0; i <= n; i++)
        [a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n]
    ];

/// Outline star: tip → valley → tip … (no crossings).
List<List<double>> _outlineStar(double cx, double cy, double R) {
  final r = R * 0.382;
  final verts = <List<double>>[];
  for (int k = 0; k < 5; k++) {
    final ao = -math.pi / 2 + k * 2 * math.pi / 5;
    verts.add([cx + R * math.cos(ao), cy + R * math.sin(ao)]);
    final ai = ao + math.pi / 5;
    verts.add([cx + r * math.cos(ai), cy + r * math.sin(ai)]);
  }
  verts.add(verts.first);
  final out = <List<double>>[];
  for (int i = 0; i < verts.length - 1; i++) {
    out.addAll(_denseLine(verts[i], verts[i + 1], 6));
  }
  return out;
}

/// Pentagram: tips joined skipping one (0→2→4→1→3→0), edges cross in the centre.
/// [tipScale] lets a test pull individual tips in/out to add asymmetry.
List<List<double>> _pentagram(double cx, double cy, double R,
    {List<double>? tipScale}) {
  final tips = <List<double>>[
    for (int k = 0; k < 5; k++)
      [
        cx + R * (tipScale?[k] ?? 1) * math.cos(-math.pi / 2 + k * 2 * math.pi / 5),
        cy + R * (tipScale?[k] ?? 1) * math.sin(-math.pi / 2 + k * 2 * math.pi / 5),
      ]
  ];
  const order = [0, 2, 4, 1, 3, 0];
  final out = <List<double>>[];
  for (int i = 0; i < order.length - 1; i++) {
    out.addAll(_denseLine(tips[order[i]], tips[order[i + 1]], 12));
  }
  return out;
}

List<List<double>> _circle(double cx, double cy, double r) =>
    [for (int i = 0; i <= 48; i++) (i / 48 * 2 * math.pi).let((t) => [cx + r * math.cos(t), cy + r * math.sin(t)])];

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void main() {
  test('clean outline star → ShapeKind.star', () {
    final s = ShapeRecognizer.detect(_jitter(_outlineStar(200, 200, 120), 4, 1));
    expect(s, isNotNull);
    expect(s!.kind, ShapeKind.star);
  });

  test('crossing pentagram → ShapeKind.pentagram', () {
    final s = ShapeRecognizer.detect(_jitter(_pentagram(200, 200, 120), 4, 2));
    expect(s, isNotNull);
    expect(s!.kind, ShapeKind.pentagram);
  });

  test('circle is not mistaken for a star', () {
    final s = ShapeRecognizer.detect(_jitter(_circle(200, 200, 110), 3, 3));
    expect(s?.kind, isNot(ShapeKind.star));
    expect(s?.kind, isNot(ShapeKind.pentagram));
  });

  test('small star still snaps (lower size threshold)', () {
    final s = ShapeRecognizer.detect(_jitter(_outlineStar(80, 80, 16), 2, 7));
    expect(s, isNotNull);
    expect(s!.kind, ShapeKind.star);
  });

  test('pentagram snap preserves the user-drawn asymmetry', () {
    // One tip (index 0, pointing up) pulled far out; the rest normal.
    final asym = _pentagram(200, 200, 110, tipScale: [1.6, 1, 1, 1, 1]);
    final s = ShapeRecognizer.detect(_jitter(asym, 3, 8));
    expect(s, isNotNull);
    expect(s!.kind, ShapeKind.pentagram);
    // The stretched tip sits at ~ (200, 200 - 176). A regularized star would
    // place every tip at radius 110; the asymmetric one keeps it far out.
    final stretchedTipY = 200 - 110 * 1.6;
    final hasFarTip = s.points.any((p) =>
        (p[0] - 200).abs() < 30 && (p[1] - stretchedTipY).abs() < 30);
    expect(hasFarTip, isTrue,
        reason: 'snapped pentagram should keep the elongated tip');
  });

  test('star detection survives heavier jitter', () {
    for (int seed = 10; seed < 20; seed++) {
      final outline = ShapeRecognizer.detect(_jitter(_outlineStar(180, 220, 100), 7, seed));
      expect(outline?.kind, ShapeKind.star, reason: 'outline seed $seed');
      final penta = ShapeRecognizer.detect(_jitter(_pentagram(180, 220, 100), 7, seed));
      expect(penta?.kind, ShapeKind.pentagram, reason: 'pentagram seed $seed');
    }
  });
}
