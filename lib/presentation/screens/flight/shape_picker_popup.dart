import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import 'shape_recognizer.dart';

/// Tiny popup to insert a clean shape onto the canvas. Each chip drops the
/// shape at the viewport centre, already selected with the lasso so the user
/// can move/resize it right away.
class ShapePickerPopup extends StatelessWidget {
  final Color accent;
  final ValueChanged<ShapeKind> onPick;

  const ShapePickerPopup({
    super.key,
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
          _chip('RECT', Icons.crop_square, ShapeKind.rectangle),
          const SizedBox(width: 8),
          _chip('ÓVALO', Icons.circle_outlined, ShapeKind.ellipse),
          const SizedBox(width: 8),
          _chip('TRIÁNGULO', Icons.change_history, ShapeKind.triangle),
          const SizedBox(width: 8),
          _chip('LÍNEA', Icons.horizontal_rule, ShapeKind.line),
          const SizedBox(width: 8),
          _chip('FLECHA', Icons.trending_flat, ShapeKind.arrow),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, ShapeKind kind) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: yInk),
            const SizedBox(height: 4),
            Text(label,
                style: yMono(
                    size: 8,
                    weight: FontWeight.w700,
                    tracking: 1.0,
                    color: yInk)),
          ],
        ),
      ),
    );
  }
}
