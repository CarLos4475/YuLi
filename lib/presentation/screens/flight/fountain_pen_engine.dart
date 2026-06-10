import 'dart:math' as math;
import 'dart:ui';

import 'note_cell_model.dart';

/// Non-linear (sigmoid-ish) pressure→width response. A real metal nib opens up
/// progressively under pressure rather than 1:1, so light variations near the
/// resting pressure feel subtle and firm presses pop. Smoothstep keeps the same
/// [0.75, 1.25] output range as the old linear map (base width unchanged).
double pressureWidthFactor(double pressure) {
  final p = pressure.clamp(0.0, 1.0);
  final s = p * p * (3 - 2 * p);
  return 0.75 + s * 0.50;
}

class FountainPenEngine {
  /// Remove excess points that are closer than [minDist] pixels.
  /// Slow strokes produce very dense points that destabilize direction vectors.
  static (List<Offset>, List<double>, List<int>) downsample(
    List<Offset> pts,
    List<double> pressures,
    List<int> timestamps, {
    double minDist = 2.0,
  }) {
    if (pts.length < 3) return (pts, pressures, timestamps);
    final minDist2 = minDist * minDist;
    final outPts = <Offset>[pts.first];
    final outPre = <double>[pressures.first];
    final outTs = <int>[timestamps.first];
    for (int i = 1; i < pts.length - 1; i++) {
      final dx = pts[i].dx - outPts.last.dx;
      final dy = pts[i].dy - outPts.last.dy;
      if (dx * dx + dy * dy >= minDist2) {
        outPts.add(pts[i]);
        outPre.add(pressures[i]);
        outTs.add(timestamps[i]);
      }
    }
    outPts.add(pts.last);
    outPre.add(pressures.last);
    outTs.add(timestamps.last);
    return (outPts, outPre, outTs);
  }

  /// Chaikin corner cutting — eliminates hand jitter while preserving curve
  /// shape.
  static List<Offset> chaikinSmooth(List<Offset> pts, {int iterations = 1}) {
    if (pts.length < 3) return pts;
    var current = pts;
    for (int iter = 0; iter < iterations; iter++) {
      final out = <Offset>[current[0]];
      for (int i = 0; i < current.length - 1; i++) {
        final p0 = current[i];
        final p1 = current[i + 1];
        out.add(Offset(
          p0.dx * 0.75 + p1.dx * 0.25,
          p0.dy * 0.75 + p1.dy * 0.25,
        ));
        out.add(Offset(
          p0.dx * 0.25 + p1.dx * 0.75,
          p0.dy * 0.25 + p1.dy * 0.75,
        ));
      }
      out.add(current.last);
      current = out;
    }
    return current;
  }

  /// Compute per-point stroke width based on writing direction, velocity,
  /// and stylus pressure. Direction is the dominant factor (nib effect).
  static List<double> computeWidths(
    List<Offset> centerline,
    double baseWidth,
    List<double> pressures,
    List<int> timestamps,
  ) {
    final n = centerline.length;
    if (n < 2) return List.filled(n, baseWidth);
    final widths = List<double>.filled(n, baseWidth);
    final rawN = pressures.length;

    for (int i = 0; i < n; i++) {
      final rawIdx =
          rawN > 0 ? (i * rawN ~/ n).clamp(0, rawN - 1) : 0;

      double dx, dy;
      if (i == 0) {
        dx = centerline[1].dx - centerline[0].dx;
        dy = centerline[1].dy - centerline[0].dy;
      } else if (i == n - 1) {
        dx = centerline[i].dx - centerline[i - 1].dx;
        dy = centerline[i].dy - centerline[i - 1].dy;
      } else {
        dx = centerline[i + 1].dx - centerline[i - 1].dx;
        dy = centerline[i + 1].dy - centerline[i - 1].dy;
      }

      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 0.001) {
        if (i > 0) widths[i] = widths[i - 1];
        continue;
      }

      // 1. Direction factor (nib effect):
      //    vertical/down strokes → thicker, horizontal/up → thinner.
      final angle = math.atan2(dy, dx);
      final directionFactor = 1.0 + math.sin(angle) * 0.35;

      // 2. Pressure factor:  light → thinner, firm → thicker.
      final pressure = pressures.length > rawIdx ? pressures[rawIdx] : 0.5;
      final pressureFactor = pressureWidthFactor(pressure);

      // No velocity thinning: the live preview doesn't apply it, so applying it
      // only at bake time made the finished stroke shrink vs what the user drew.
      // Keep the baked width faithful to the live preview.
      widths[i] = baseWidth * directionFactor * pressureFactor;
    }

    return widths;
  }

  /// Smooth start/end tapering using smoothstep.
  /// Makes stroke beginnings feel elegant and endings natural.
  static void taperWidths(List<double> widths, {int taperLength = 5}) {
    final n = widths.length;
    if (n < 3) return;
    final len = taperLength.clamp(1, n ~/ 2);
    for (int i = 0; i < len; i++) {
      final t = (i + 1) / len;
      final eased = t * t * (3 - 2 * t);
      widths[i] *= eased;
      widths[n - 1 - i] *= eased;
    }
  }

  /// Linearly interpolate a width array from [rawLength] to [targetLength].
  static List<double> interpolateWidths(
      List<double> rawWidths, int targetLength) {
    if (rawWidths.isEmpty) return List.filled(targetLength, 1.0);
    if (rawWidths.length == 1) return List.filled(targetLength, rawWidths[0]);
    if (targetLength == rawWidths.length) return List.of(rawWidths);
    final result = List<double>.filled(targetLength, 0);
    for (int i = 0; i < targetLength; i++) {
      final t = i / (targetLength - 1) * (rawWidths.length - 1);
      final idx = t.floor().clamp(0, rawWidths.length - 2);
      final frac = t - idx;
      result[i] = rawWidths[idx] * (1 - frac) + rawWidths[idx + 1] * frac;
    }
    return result;
  }

  /// Moving-average smoother for width arrays.
  static List<double> smoothWidths(List<double> widths, {int windowSize = 3}) {
    if (widths.length < windowSize) return widths;
    final result = List<double>.filled(widths.length, 0);
    final half = windowSize ~/ 2;
    for (int i = 0; i < widths.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - half; j <= i + half; j++) {
        if (j >= 0 && j < widths.length) {
          sum += widths[j];
          count++;
        }
      }
      result[i] = sum / count;
    }
    return result;
  }

  /// Tessellate a centerline + per-point widths into a filled polygon Path.
  /// [noiseAmp] adds sub-pixel deterministic edge wobble for an organic feel
  /// (the fountain pen wants it; the pencil passes 0 — its texture is the grain
  /// fill, and edge wobble would only fight it).
  static Path tessellate(List<Offset> centerline, List<double> widths,
      {double noiseAmp = 0.15}) {
    final path = Path();
    final n = centerline.length;
    if (n < 2) return path;

    final left = <Offset>[];
    final right = <Offset>[];

    for (int i = 0; i < n; i++) {
      double dx, dy;
      if (i == 0) {
        dx = centerline[1].dx - centerline[0].dx;
        dy = centerline[1].dy - centerline[0].dy;
      } else if (i == n - 1) {
        dx = centerline[i].dx - centerline[i - 1].dx;
        dy = centerline[i].dy - centerline[i - 1].dy;
      } else {
        dx = centerline[i + 1].dx - centerline[i - 1].dx;
        dy = centerline[i + 1].dy - centerline[i - 1].dy;
      }

      final len = math.sqrt(dx * dx + dy * dy);
      final halfW = widths[i] / 2;

      if (len < 0.001) {
        left.add(centerline[i]);
        right.add(centerline[i]);
        continue;
      }

      final perpX = -dy / len;
      final perpY = dx / len;

      // Deterministic sub-pixel noise — breaks mathematical perfection
      // without visible roughness.
      final noise = math.sin(i * 0.37) * noiseAmp;
      final w = halfW + noise;

      left.add(Offset(
        centerline[i].dx + perpX * w,
        centerline[i].dy + perpY * w,
      ));
      right.add(Offset(
        centerline[i].dx - perpX * w,
        centerline[i].dy - perpY * w,
      ));
    }

    path.moveTo(left[0].dx, left[0].dy);
    for (int i = 1; i < left.length; i++) {
      path.lineTo(left[i].dx, left[i].dy);
    }
    for (int i = right.length - 1; i >= 0; i--) {
      path.lineTo(right[i].dx, right[i].dy);
    }
    path.close();
    return path;
  }

  /// Finalize an active (raw) fountain-pen stroke into a baked DrawingStroke.
  ///
  /// Input points:  [x, y, pressure, timestamp]
  /// Output points: [x, y, bakedWidth]
  static DrawingStroke finishStroke(DrawingStroke active) {
    final raw = active.points;
    final rawPts = raw.map((p) => Offset(p[0], p[1])).toList();
    final pressures =
        raw.map((p) => p.length > 2 ? p[2] : 0.5).toList();
    final timestamps =
        raw.map((p) => p.length > 3 ? p[3].toInt() : 0).toList();

    // Filter out excess density from slow strokes.
    final (dsPts, dsPre, dsTs) = downsample(rawPts, pressures, timestamps);

    final rawWidths = computeWidths(dsPts, active.strokeWidth, dsPre, dsTs);
    final smoothed = smoothWidths(rawWidths, windowSize: 3);
    taperWidths(smoothed);

    final centerline = chaikinSmooth(dsPts, iterations: 1);

    // Interpolate widths to match the densified centerline.
    final widths = interpolateWidths(smoothed, centerline.length);

    final baked = <List<double>>[];
    for (int i = 0; i < centerline.length; i++) {
      baked.add([centerline[i].dx, centerline[i].dy, widths[i]]);
    }

    return DrawingStroke(
      colorValue: active.colorValue,
      strokeWidth: active.strokeWidth,
      isFountainPen: true,
      points: baked,
    );
  }
}
