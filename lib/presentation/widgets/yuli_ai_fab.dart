import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'yuli_design.dart';

/// Floating 3D-cube button that opens YuLi AI. The cube spins slowly on its own
/// axis, bobs calmly up/down and emits a blinking glow (like the graph nodes).
/// Its colour is the view's accent (yFight/yFlight/yLab, a space/folder accent…).
class YuliAiFab extends StatefulWidget {
  final Color accent;
  final VoidCallback onTap;
  final double size;

  const YuliAiFab({
    super.key,
    required this.accent,
    required this.onTap,
    this.size = 72,
  });

  @override
  State<YuliAiFab> createState() => _YuliAiFabState();
}

class _YuliAiFabState extends State<YuliAiFab>
    with SingleTickerProviderStateMixin {
  // One slow cycle drives everything; the per-effect frequencies are whole
  // multiples of it so nothing jumps when the controller wraps 1→0.
  static const _cycleMs = 30000;
  static const _bobs = 3; // up/down bobs per cycle (calm)
  static const _pulses = 6; // glow blinks per cycle (~5s each, graph-like)

  late final AnimationController _ctrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              // Phase anchored to wall-clock time (not the controller's 0→1),
              // so the cube resists view changes: a freshly-built FAB picks up
              // the same continuous phase instead of restarting from zero. The
              // controller only ticks to schedule repaints.
              final t =
                  (DateTime.now().millisecondsSinceEpoch % _cycleMs) / _cycleMs;
              // Diagonal tumble: horizontal (yaw) + vertical (pitch) spin at
              // once, one slow revolution per cycle, so it rolls on a diagonal
              // axis instead of just spinning flat.
              final yaw = t * 2 * math.pi;
              final pitch = t * 2 * math.pi;
              final roll = math.sin(t * 2 * math.pi) * 0.05;
              final bob = math.sin(t * _bobs * 2 * math.pi) * size * 0.06;
              // Triangle-wave glow, eased like the graph alert pulse.
              final raw = (t * _pulses) % 1.0;
              final tri = raw <= 0.5 ? raw * 2 : (1 - raw) * 2;
              final glow = Curves.easeInOut.transform(tri);
              return Transform.translate(
                offset: Offset(0, bob),
                child: CustomPaint(
                  painter: _FabCubePainter(
                    accent: widget.accent,
                    yaw: yaw,
                    pitch: pitch,
                    roll: roll,
                    glow: glow,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Static cube mark (no glow, no motion) — YuLi's avatar in the chat. Same 3D
/// cube as the FAB, frozen at a pleasant 3-face angle.
class YuliCubeMark extends StatelessWidget {
  final Color color;
  final double size;
  final double yaw;
  final double pitch;
  final double roll;

  const YuliCubeMark({
    super.key,
    required this.color,
    this.size = 30,
    this.yaw = 0.62,
    this.pitch = 0.6,
    this.roll = -0.05,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FabCubePainter(
          accent: color,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
          glow: 0,
        ),
      ),
    );
  }
}

class _FabCubePainter extends CustomPainter {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;
  final double glow;

  const _FabCubePainter({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.21;
    final camera = size.width * 1.9;
    final cx = size.width / 2;
    final cy = size.height / 2;

    final verts = <_Pt>[
      for (final x in [-r, r])
        for (final y in [-r, r])
          for (final z in [-r, r]) _rotate(x, y, z),
    ];
    final points =
        verts
            .map(
              (p) => Offset(
                cx + p.x * camera / (camera - p.z),
                cy + p.y * camera / (camera - p.z),
              ),
            )
            .toList();

    _paintGlow(canvas, points, cx, cy);

    final faces =
        <_Face>[
            _Face([0, 1, 3, 2], _shade(0.88)),
            _Face([4, 6, 7, 5], _shade(1.04)),
            _Face([0, 4, 5, 1], _shade(0.72)),
            _Face([2, 3, 7, 6], _shade(1.12)),
            _Face([0, 2, 6, 4], _shade(0.8)),
            _Face([1, 5, 7, 3], _shade(0.96)),
          ].where((f) => f.faceVisible(verts)).toList()
          ..sort((a, b) => a.depth(verts).compareTo(b.depth(verts)));

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.045
          ..strokeJoin = StrokeJoin.round
          ..color = yInk.withValues(alpha: 0.5);

    for (final face in faces) {
      final path =
          Path()..moveTo(points[face.idx.first].dx, points[face.idx.first].dy);
      for (final i in face.idx.skip(1)) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      fill.color = face.color;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  /// Soft blinking halo around the cube silhouette (convex hull of the projected
  /// vertices, scaled out from the centroid and blurred).
  void _paintGlow(Canvas canvas, List<Offset> points, double cx, double cy) {
    final hull = _convexHull(points);
    if (hull.length < 3) return;
    final center = Offset(cx, cy);
    const scale = 1.18;
    final path =
        Path()..moveTo(
          center.dx + (hull.first.dx - center.dx) * scale,
          center.dy + (hull.first.dy - center.dy) * scale,
        );
    for (final p in hull.skip(1)) {
      path.lineTo(
        center.dx + (p.dx - center.dx) * scale,
        center.dy + (p.dy - center.dy) * scale,
      );
    }
    path.close();
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = accent.withValues(alpha: 0.06 + 0.14 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 5 * glow);
    canvas.drawPath(path, paint);
  }

  _Pt _rotate(double x, double y, double z) {
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);
    final cz = math.cos(roll);
    final sz = math.sin(roll);
    final x1 = x * cy + z * sy;
    final z1 = -x * sy + z * cy;
    final y2 = y * cx - z1 * sx;
    final z2 = y * sx + z1 * cx;
    final x3 = x1 * cz - y2 * sz;
    final y3 = x1 * sz + y2 * cz;
    return _Pt(x3, y3, z2);
  }

  Color _shade(double amount) {
    final argb = accent.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (((argb >> 16) & 0xFF) * amount).clamp(0, 255).round();
    final g = (((argb >> 8) & 0xFF) * amount).clamp(0, 255).round();
    final b = ((argb & 0xFF) * amount).clamp(0, 255).round();
    return Color.fromARGB(a, r, g, b);
  }

  // Andrew's monotone chain — fine for the cube's ≤8 projected points.
  List<Offset> _convexHull(List<Offset> pts) {
    final sorted = [...pts]..sort(
      (a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy),
    );
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  @override
  bool shouldRepaint(covariant _FabCubePainter old) =>
      old.accent != accent ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.roll != roll ||
      old.glow != glow;
}

class _Pt {
  final double x;
  final double y;
  final double z;
  const _Pt(this.x, this.y, this.z);
}

class _Face {
  final List<int> idx;
  final Color color;
  const _Face(this.idx, this.color);

  double depth(List<_Pt> v) =>
      idx.fold<double>(0, (s, i) => s + v[i].z) / idx.length;

  bool faceVisible(List<_Pt> v) {
    final a = v[idx[0]];
    final b = v[idx[1]];
    final c = v[idx[2]];
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0;
  }
}
