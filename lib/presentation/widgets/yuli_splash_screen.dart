import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'yuli_design.dart';

class YuliSplashScreen extends StatefulWidget {
  const YuliSplashScreen({super.key});

  @override
  State<YuliSplashScreen> createState() => _YuliSplashScreenState();
}

class _YuliSplashScreenState extends State<YuliSplashScreen> {
  static const _accentKey = 'yuli_splash_accent_index_v1';
  static const _accents = [yFight, yFlight, yLab];

  Color _accent = yFight;

  @override
  void initState() {
    super.initState();
    _loadAccent();
  }

  Future<void> _loadAccent() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_accentKey) ?? 0;
    await prefs.setInt(_accentKey, (index + 1) % _accents.length);
    if (!mounted) return;
    setState(() => _accent = _accents[index % _accents.length]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: yCream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YuliAnimatedCube(accent: _accent, size: 76),
            const SizedBox(height: 22),
            Text(
              'YuLi',
              style: ySans(
                size: 56,
                weight: FontWeight.w800,
                letterSpacing: 0,
                color: yInk,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 12),
            Container(width: 74, height: yLineHeavy, color: _accent),
          ],
        ),
      ),
    );
  }
}

class YuliAnimatedCube extends StatefulWidget {
  final Color accent;
  final List<Color>? accents;
  final double size;

  const YuliAnimatedCube({
    super.key,
    required this.accent,
    this.accents,
    this.size = 54,
  });

  @override
  State<YuliAnimatedCube> createState() => _YuliAnimatedCubeState();
}

class _YuliAnimatedCubeState extends State<YuliAnimatedCube>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _cycleMs = 2800;
  @override
  void initState() {
    super.initState();
    final colorCount = widget.accents?.length ?? 1;
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _cycleMs * colorCount),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final cycleT = _cycleProgress();
        final accent = _currentAccent();
        final yawOut = _segment(cycleT, 0.00, 0.33);
        final pitchOut = _segment(cycleT, 0.33, 0.66);
        final yawBack = _segment(cycleT, 0.66, 1.00);
        final pitchBack = _segment(cycleT, 0.66, 1.00);
        final yaw = (yawOut - yawBack) * math.pi / 2;
        final pitch = 0.78 + (pitchOut - pitchBack) * math.pi / 2;
        final roll = -0.08 + math.sin(cycleT * math.pi * 2) * 0.08;
        return _SplashCube(
          accent: accent,
          size: widget.size,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
          depth: 1,
        );
      },
    );
  }

  double _cycleProgress() {
    final colorCount = widget.accents?.length ?? 1;
    return (_ctrl.value * colorCount) % 1;
  }

  double _segment(double t, double start, double end) {
    final local = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(local);
  }

  Color _currentAccent() {
    final accents = widget.accents;
    if (accents == null || accents.isEmpty) return widget.accent;
    if (accents.length == 1) return accents.first;

    final scaled = _ctrl.value * accents.length;
    final index = scaled.floor() % accents.length;
    final nextIndex = (index + 1) % accents.length;
    final local = scaled - scaled.floor();
    const transitionStart = 0.72;
    if (local < transitionStart) return accents[index];

    final transition = (local - transitionStart) / (1 - transitionStart);
    final eased = Curves.easeInOutCubic.transform(transition);
    return Color.lerp(accents[index], accents[nextIndex], eased)!;
  }
}

class _SplashCube extends StatelessWidget {
  final Color accent;
  final double size;
  final double yaw;
  final double pitch;
  final double roll;
  final double depth;

  const _SplashCube({
    required this.accent,
    this.size = 76,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SplashCubePainter(
          accent: accent,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
          depth: depth,
        ),
      ),
    );
  }
}

class _SplashCubePainter extends CustomPainter {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;
  final double depth;

  const _SplashCubePainter({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.depth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 23.0;
    const camera = 96.0;
    final zDepth = r * depth.clamp(0.0, 1.0);
    final verts = <_CubePoint>[
      for (final x in [-r, r])
        for (final y in [-r, r])
          for (final z in [-zDepth, zDepth]) _rotate(x, y, z),
    ];
    final points =
        verts
            .map(
              (p) => Offset(
                size.width / 2 + p.x * camera / (camera - p.z),
                size.height / 2 + p.y * camera / (camera - p.z),
              ),
            )
            .toList();
    final faces =
        <_CubeFace>[
            _CubeFace([0, 1, 3, 2], _shade(0.88)),
            _CubeFace([4, 6, 7, 5], _shade(1.04)),
            _CubeFace([0, 4, 5, 1], _shade(0.72)),
            _CubeFace([2, 3, 7, 6], _shade(1.12)),
            _CubeFace([0, 2, 6, 4], _shade(0.8)),
            _CubeFace([1, 5, 7, 3], _shade(0.96)),
          ].where((face) => face.visibleFromCamera(verts)).toList()
          ..sort((a, b) => a.depth(verts).compareTo(b.depth(verts)));

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.bevel
          ..color = yInk.withValues(alpha: 0.46);

    for (final face in faces) {
      final path =
          Path()..moveTo(
            points[face.indexes.first].dx,
            points[face.indexes.first].dy,
          );
      for (final i in face.indexes.skip(1)) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      fill.color = face.color;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  _CubePoint _rotate(double x, double y, double z) {
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
    return _CubePoint(x3, y3, z2);
  }

  Color _shade(double amount) {
    final argb = accent.toARGB32();
    final a = (argb >> 24) & 0xFF;
    final r = (((argb >> 16) & 0xFF) * amount).clamp(0, 255).round();
    final g = (((argb >> 8) & 0xFF) * amount).clamp(0, 255).round();
    final b = ((argb & 0xFF) * amount).clamp(0, 255).round();
    return Color.fromARGB(a, r, g, b);
  }

  @override
  bool shouldRepaint(covariant _SplashCubePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.roll != roll ||
        oldDelegate.depth != depth;
  }
}

class _CubePoint {
  final double x;
  final double y;
  final double z;

  const _CubePoint(this.x, this.y, this.z);
}

class _CubeFace {
  final List<int> indexes;
  final Color color;

  const _CubeFace(this.indexes, this.color);

  double depth(List<_CubePoint> verts) {
    return indexes.fold<double>(0, (sum, i) => sum + verts[i].z) /
        indexes.length;
  }

  bool visibleFromCamera(List<_CubePoint> verts) {
    final a = verts[indexes[0]];
    final b = verts[indexes[1]];
    final c = verts[indexes[2]];
    final ux = b.x - a.x;
    final uy = b.y - a.y;
    final vx = c.x - a.x;
    final vy = c.y - a.y;
    return ux * vy - uy * vx > 0;
  }
}
