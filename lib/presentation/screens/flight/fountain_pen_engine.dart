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

  /// Light low-pass on the polyline (weighted 0.25/0.5/0.25, endpoints fixed).
  /// Removes the high-frequency hand/digitizer jitter that an interpolating
  /// spline like [catmullRom] would otherwise amplify into visible ripples on
  /// near-straight strokes — without the corner-insetting (shrink) of Chaikin.
  /// [centerWeight] is how much each point keeps its own position (the rest is
  /// split between its two neighbors). 0.5 is a firm low-pass; higher values
  /// barely move the line, so the stroke stays faithful to what was drawn (the
  /// fountain pen uses a high value — its old 0.5 over-rounded small letters).
  static List<Offset> smoothPolyline(List<Offset> pts,
      {int passes = 1, double centerWeight = 0.5}) {
    if (pts.length < 3) return pts;
    final side = (1.0 - centerWeight) / 2.0;
    var cur = pts;
    for (int k = 0; k < passes; k++) {
      final out = <Offset>[cur.first];
      for (int i = 1; i < cur.length - 1; i++) {
        out.add(Offset(
          cur[i - 1].dx * side + cur[i].dx * centerWeight + cur[i + 1].dx * side,
          cur[i - 1].dy * side + cur[i].dy * centerWeight + cur[i + 1].dy * side,
        ));
      }
      out.add(cur.last);
      cur = out;
    }
    return cur;
  }

  /// Catmull-Rom spline subdivision. Unlike Chaikin (which cuts corners and
  /// pulls the curve *inside* the points, shrinking the stroke), this passes
  /// THROUGH every original point and only interpolates smoothly between them —
  /// so the smoothed stroke stays faithful to where the user actually drew.
  static List<Offset> catmullRom(List<Offset> pts, {int subdiv = 4}) {
    final n = pts.length;
    if (n < 3) return pts;
    final out = <Offset>[pts.first];
    for (int i = 0; i < n - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 >= n ? n - 1 : i + 2];
      for (int j = 1; j <= subdiv; j++) {
        final t = j / subdiv;
        final t2 = t * t;
        final t3 = t2 * t;
        final x = 0.5 *
            ((2 * p1.dx) +
                (-p0.dx + p2.dx) * t +
                (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
                (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
        final y = 0.5 *
            ((2 * p1.dy) +
                (-p0.dy + p2.dy) * t +
                (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
                (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);
        out.add(Offset(x, y));
      }
    }
    return out;
  }

  static Offset _bary(Offset a, Offset b, double wa, double wb) =>
      Offset(a.dx * wa + b.dx * wb, a.dy * wa + b.dy * wb);

  /// Centripetal Catmull-Rom (alpha = 0.5). Like [catmullRom] it passes through
  /// every point, but its chord-length knot spacing provably prevents the
  /// overshoots and self-intersecting loops that the uniform version produces at
  /// unevenly-spaced / sharply-angled points. Those loops are exactly what turns
  /// into lumps ("grumos") once the centerline is offset by the nib width, so
  /// this keeps the body clean while staying faithful to the drawn points.
  static List<Offset> catmullRomCentripetal(List<Offset> pts,
      {int subdiv = 4, double alpha = 0.5}) {
    final n = pts.length;
    if (n < 3) return pts;
    final out = <Offset>[pts.first];

    double nextKnot(double t, Offset a, Offset b) {
      final dx = b.dx - a.dx, dy = b.dy - a.dy;
      final d = math.sqrt(dx * dx + dy * dy);
      return t + math.pow(d, alpha).toDouble();
    }

    for (int i = 0; i < n - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 >= n ? n - 1 : i + 2];

      const t0 = 0.0;
      final t1 = nextKnot(t0, p0, p1);
      final t2 = nextKnot(t1, p1, p2);
      final t3 = nextKnot(t2, p2, p3);

      // Coincident points collapse a knot span → fall back to a straight segment
      // for this piece (avoids divide-by-zero).
      if (t1 == t0 || t2 == t1 || t3 == t2) {
        for (int j = 1; j <= subdiv; j++) {
          final t = j / subdiv;
          out.add(Offset(
              p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t));
        }
        continue;
      }

      for (int j = 1; j <= subdiv; j++) {
        final t = t1 + (t2 - t1) * (j / subdiv);
        final a1 = _bary(p0, p1, (t1 - t) / (t1 - t0), (t - t0) / (t1 - t0));
        final a2 = _bary(p1, p2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1));
        final a3 = _bary(p2, p3, (t3 - t) / (t3 - t2), (t - t2) / (t3 - t2));
        final b1 = _bary(a1, a2, (t2 - t) / (t2 - t0), (t - t0) / (t2 - t0));
        final b2 = _bary(a2, a3, (t3 - t) / (t3 - t1), (t - t1) / (t3 - t1));
        out.add(_bary(b1, b2, (t2 - t) / (t2 - t1), (t - t1) / (t2 - t1)));
      }
    }
    return out;
  }

  /// Compute per-point stroke width based on writing direction, velocity,
  /// and stylus pressure. Direction is the dominant factor (nib effect).
  ///
  /// [dirWindow] is the half-width (in points) of the neighbourhood used to
  /// estimate the writing direction. Now that the centerline is kept faithful
  /// (little position smoothing), the immediate-neighbour tangent jitters point
  /// to point, so the angle-driven nib width oscillates and the body reads
  /// lumpy. Averaging the direction over a few points smooths the WIDTH without
  /// touching the trajectory.
  /// [nibAmount] is the strength of the direction-driven nib swing (±fraction of
  /// base width). The diagnostic proved the lumps are this swing being too wide
  /// across the curves of cursive, not centerline noise — so this is the single
  /// knob that trades nib character against grumos. [pressureAmount] likewise
  /// scales how much stylus pressure moves the width (0 = ignore pressure).
  static List<double> computeWidths(
    List<Offset> centerline,
    double baseWidth,
    List<double> pressures,
    List<int> timestamps, {
    int dirWindow = 1,
    double nibAmount = 0.35,
    double pressureAmount = 1.0,
    double nibShape = 1.0,
  }) {
    final n = centerline.length;
    if (n < 2) return List.filled(n, baseWidth);
    final widths = List<double>.filled(n, baseWidth);
    final rawN = pressures.length;
    final w = dirWindow < 1 ? 1 : dirWindow;

    for (int i = 0; i < n; i++) {
      final rawIdx =
          rawN > 0 ? (i * rawN ~/ n).clamp(0, rawN - 1) : 0;

      final lo = (i - w) < 0 ? 0 : i - w;
      final hi = (i + w) >= n ? n - 1 : i + w;
      final dx = centerline[hi].dx - centerline[lo].dx;
      final dy = centerline[hi].dy - centerline[lo].dy;

      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 0.001) {
        if (i > 0) widths[i] = widths[i - 1];
        continue;
      }

      // 1. Direction factor (pointed-pen / Copperplate nib): ONLY downward travel
      //    thickens (the pressure swell of a downstroke); horizontal and upward
      //    travel stay thin hairlines. The old symmetric model left horizontals
      //    at neutral (mid-thick); biasing on the downward component only drops
      //    them into the thin band where they belong. [nibShape] < 1 bends the
      //    response so down-diagonals (most of real writing) swell nearly as much
      //    as pure verticals. vert = dy/|v| since sin(atan2(dy,dx)) == dy/|v|.
      final vert = dy / dist; // -1 (straight up) .. +1 (straight down)
      final down = vert > 0 ? vert : 0.0; // 0 = horizontal/up, 1 = straight down
      final shaped = math.pow(down, nibShape).toDouble(); // 0..1
      final directionFactor = (1.0 - nibAmount) + shaped * 2 * nibAmount;

      // 2. Pressure factor:  light → thinner, firm → thicker. Pulled toward 1.0
      //    by [pressureAmount] so pressure swells don't reintroduce lumps.
      final pressure = pressures.length > rawIdx ? pressures[rawIdx] : 0.5;
      final pressureFactor =
          1.0 + (pressureWidthFactor(pressure) - 1.0) * pressureAmount;

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
  ///
  /// [tangentWindow] is the half-width (in points) of the neighbourhood used to
  /// estimate each edge normal. The pencil keeps the tight default (1); the
  /// fountain widens it so the dense, faithful centerline doesn't make the
  /// perpendicular jitter point to point and pinch the outline into lumps.
  static Path tessellate(List<Offset> centerline, List<double> widths,
      {double noiseAmp = 0.15, int tangentWindow = 1}) {
    final path = Path();
    final n = centerline.length;
    if (n < 2) return path;
    final tw = tangentWindow < 1 ? 1 : tangentWindow;

    final left = <Offset>[];
    final right = <Offset>[];

    for (int i = 0; i < n; i++) {
      final lo = (i - tw) < 0 ? 0 : i - tw;
      final hi = (i + tw) >= n ? n - 1 : i + tw;
      final dx = centerline[hi].dx - centerline[lo].dx;
      final dy = centerline[hi].dy - centerline[lo].dy;

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

  /// The SINGLE source of geometry for a fountain stroke, shared by the live
  /// preview and the baked render so they are pixel-identical (no jump / shrink
  /// when the pen lifts). Input: raw `[x, y, pressure, timestamp]` points.
  static (List<Offset>, List<double>) bakeGeometry(
      List<List<double>> raw, double strokeWidth,
      {double viewScale = 1.0}) {
    final rawPts = raw.map((p) => Offset(p[0], p[1])).toList();
    final pressures = raw.map((p) => p.length > 2 ? p[2] : 0.5).toList();
    final timestamps = raw.map((p) => p.length > 3 ? p[3].toInt() : 0).toList();

    // Decimation distance is in WORLD pixels, but the gesture is perceptual:
    // zoomed in, a normal-looking letter occupies few world pixels, so a fixed
    // 2px threshold throws away most of its detail and the spline then rounds it
    // into mush. Scale by the canvas zoom so the kept-point spacing is constant
    // on screen (≈2 screen px) regardless of zoom.
    final scale = viewScale.isFinite && viewScale > 0 ? viewScale : 1.0;
    final minDist = (2.0 / scale).clamp(0.6, 2.0);

    // Filter out excess density from slow strokes, then de-jitter so the
    // interpolating spline doesn't amplify hand tremor into ripples. A high
    // centerWeight keeps the de-jitter from also rounding off the letters.
    final (dsPts, dsPre, dsTs) =
        downsample(rawPts, pressures, timestamps, minDist: minDist);
    final basePts = smoothPolyline(dsPts, passes: 1, centerWeight: 0.72);

    // The lumps were proven to live entirely in the WIDTH: a constant-width
    // stroke is perfectly smooth. So keep a GENTLE nib (and damped pressure) for
    // some thick/thin life without the swing that beads the body. De-noise the
    // pressure, then smooth the final width.
    final smPre = smoothWidths(dsPre, windowSize: 5);
    // Strong up-thin / down-thick nib contrast, kept lump-free by estimating the
    // direction over a WIDE window (dirWindow): the width follows the overall
    // up/down of each stroke, not the micro-wiggles, and the thick→thin swap at
    // cusps rounds itself instead of beading.
    final rawWidths = computeWidths(basePts, strokeWidth, smPre, dsTs,
        dirWindow: 4, nibAmount: 0.55, pressureAmount: 0.5, nibShape: 0.35);
    final smoothed = smoothWidths(rawWidths, windowSize: 11);
    taperWidths(smoothed, taperLength: 3);

    final dense = catmullRomCentripetal(basePts, subdiv: 3);
    final centerline = smoothPolyline(dense, passes: 1, centerWeight: 0.5);
    final widths = interpolateWidths(smoothed, centerline.length);
    return (centerline, widths);
  }

  /// Tessellated path for an in-progress (raw) fountain stroke — same geometry
  /// the finished stroke will have.
  static Path rawFountainPath(List<List<double>> raw, double strokeWidth,
      {double viewScale = 1.0}) {
    final (centerline, widths) =
        bakeGeometry(raw, strokeWidth, viewScale: viewScale);
    return tessellate(centerline, widths, tangentWindow: 3, noiseAmp: 0);
  }

  /// Finalize an active (raw) fountain-pen stroke into a baked DrawingStroke.
  ///
  /// Input points:  [x, y, pressure, timestamp]
  /// Output points: [x, y, bakedWidth]
  static DrawingStroke finishStroke(DrawingStroke active,
      {double viewScale = 1.0}) {
    final (centerline, widths) =
        bakeGeometry(active.points, active.strokeWidth, viewScale: viewScale);

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
