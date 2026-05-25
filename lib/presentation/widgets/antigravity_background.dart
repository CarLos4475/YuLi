import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AntigravityBackground extends StatefulWidget {
  final Widget child;

  const AntigravityBackground({super.key, required this.child});

  @override
  State<AntigravityBackground> createState() => _AntigravityBackgroundState();
}

class _AntigravityBackgroundState extends State<AntigravityBackground>
    with SingleTickerProviderStateMixin {
  ui.FragmentProgram? _program;
  double _elapsed = 0;
  Offset _mousePos = Offset.zero;
  bool _mouseActive = false;
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed.inMicroseconds / 1000000.0;
      if (_program != null) setState(() {});
    });
    _ticker.start();
    _loadShader();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('assets/shaders/antigravity.frag');
    if (!mounted) return;
    setState(() => _program = program);
  }

  void _onPointerMove(PointerEvent e) {
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(e.position);
    final clamped = Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
    _mousePos = clamped;
    _mouseActive = true;
  }

  @override
  Widget build(BuildContext context) {
    final painter = (_program != null)
        ? _AntigravityPainter(
            program: _program!,
            elapsed: _elapsed,
            mousePos: _mousePos,
            mouseActive: _mouseActive ? 1.0 : 0.0,
          )
        : null;

    return Stack(
      children: [
        widget.child,
        if (painter != null)
          Positioned.fill(
            child: MouseRegion(
              onExit: (_) {
                _mousePos = const Offset(-1, -1);
                _mouseActive = false;
              },
              child: Listener(
                onPointerMove: _onPointerMove,
                onPointerUp: (_) => _mouseActive = false,
                onPointerCancel: (_) => _mouseActive = false,
                child: IgnorePointer(
                  child: CustomPaint(painter: painter),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AntigravityPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final double elapsed;
  final Offset mousePos;
  final double mouseActive;

  _AntigravityPainter({
    required this.program,
    required this.elapsed,
    required this.mousePos,
    required this.mouseActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, elapsed);
    shader.setFloat(3, mousePos.dx);
    shader.setFloat(4, mousePos.dy);
    shader.setFloat(5, mouseActive);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_AntigravityPainter old) {
    return old.elapsed != elapsed ||
        old.mousePos != mousePos ||
        old.mouseActive != mouseActive;
  }
}
