import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'yuli_design.dart';

Widget aiWorkingDialog({required Color accent, String label = 'PENSANDO'}) {
  return Center(
    child: _AiWorkingPanel(accent: accent, label: label.toUpperCase()),
  );
}

class _AiWorkingPanel extends StatefulWidget {
  final Color accent;
  final String label;

  const _AiWorkingPanel({required this.accent, required this.label});

  @override
  State<_AiWorkingPanel> createState() => _AiWorkingPanelState();
}

class _AiWorkingPanelState extends State<_AiWorkingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [BoxShadow(color: yInk, offset: Offset(5, 5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                final phase = _ctrl.value * math.pi * 2;
                return _WorkingCube(
                  accent: widget.accent,
                  yaw: phase,
                  pitch: 0.42 + 0.18 * math.sin(phase),
                  roll: 0.10 * math.sin(phase * 2),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.6,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkingCube extends StatelessWidget {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;

  const _WorkingCube({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: CustomPaint(
        painter: _WorkingCubePainter(
          accent: accent,
          yaw: yaw,
          pitch: pitch,
          roll: roll,
        ),
      ),
    );
  }
}

class _WorkingCubePainter extends CustomPainter {
  final Color accent;
  final double yaw;
  final double pitch;
  final double roll;

  const _WorkingCubePainter({
    required this.accent,
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const r = 13.5;
    const camera = 58.0;
    final verts = <_CubePoint>[
      for (final x in [-r, r])
        for (final y in [-r, r])
          for (final z in [-r, r]) _rotate(x, y, z),
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
          ..strokeWidth = 2.3
          ..strokeJoin = StrokeJoin.bevel
          ..color = yInk;

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
  bool shouldRepaint(covariant _WorkingCubePainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.roll != roll;
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
