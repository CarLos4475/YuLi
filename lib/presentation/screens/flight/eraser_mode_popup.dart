import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import 'note_cell_model.dart';

/// A ring that follows the eraser tip to preview what it will erase.
class EraserCursor extends StatelessWidget {
  final double radius;
  const EraserCursor({super.key, required this.radius});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: yInk.withValues(alpha: 0.08),
          border: Border.all(color: yInk.withValues(alpha: 0.55), width: 1.5),
        ),
      ),
    );
  }
}

/// Tiny popup to pick the eraser mode: TRAZO (whole-stroke) or PRECISO
/// (partial — erases only the touched portion, splitting the stroke).
class EraserModePopup extends StatelessWidget {
  final EraserMode mode;
  final Color accent;
  final ValueChanged<EraserMode> onPick;

  const EraserModePopup({
    super.key,
    required this.mode,
    required this.accent,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('TRAZO', Icons.auto_fix_high, EraserMode.stroke),
          const SizedBox(width: 8),
          _chip('PRECISO', Icons.cleaning_services_outlined, EraserMode.partial),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, EraserMode m) {
    final active = mode == m;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yInk, width: active ? 2.5 : yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? yCream : yInk),
            const SizedBox(width: 6),
            Text(label,
                style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: active ? yCream : yInk)),
          ],
        ),
      ),
    );
  }
}
