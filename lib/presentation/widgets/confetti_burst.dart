import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

const _black = Color(0xFF0A0A0A);
final _rnd = Random();

/// Fires a one-shot neo-brutalist confetti burst (black + [accent] squares and
/// triangles) anchored at [globalPosition]. Pure presentation: inserts a
/// self-disposing [OverlayEntry], never touches task/card state — safe to call
/// from any gesture handler.
void burstConfetti(
  BuildContext context,
  Offset globalPosition, {
  required Color accent,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder:
        (_) => _ConfettiBurst(
          origin: globalPosition,
          accent: accent,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
  );
  overlay.insert(entry);
}

class _ConfettiBurst extends StatefulWidget {
  final Offset origin;
  final Color accent;
  final VoidCallback onDone;

  const _ConfettiBurst({
    required this.origin,
    required this.accent,
    required this.onDone,
  });

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst> {
  late final ConfettiController _ctrl = ConfettiController(
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.play();
    Future.delayed(const Duration(milliseconds: 1400), widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Brutalist particles: hard-edged squares and triangles, no rounding.
  Path _particlePath(Size size) {
    if (_rnd.nextBool()) {
      return Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    return Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.origin.dx,
      top: widget.origin.dy,
      child: IgnorePointer(
        child: ConfettiWidget(
          confettiController: _ctrl,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          numberOfParticles: 24,
          maxBlastForce: 20,
          minBlastForce: 8,
          gravity: 0.3,
          particleDrag: 0.05,
          minimumSize: const Size(7, 7),
          maximumSize: const Size(13, 13),
          colors: [_black, widget.accent, widget.accent, _black],
          createParticlePath: _particlePath,
          // Non-zero size so the CustomPaint reliably paints inside the overlay.
          child: const SizedBox(width: 2, height: 2),
        ),
      ),
    );
  }
}
