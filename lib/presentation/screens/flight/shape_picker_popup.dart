import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
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
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('RECT', YuLiIcons.square, ShapeKind.rectangle),
          const SizedBox(width: 8),
          _chip('ÓVALO', YuLiIcons.circle, ShapeKind.ellipse),
          const SizedBox(width: 8),
          _chip('TRIÁNGULO', YuLiIcons.triangle, ShapeKind.triangle),
          const SizedBox(width: 8),
          _chip('ESTRELLA', YuLiIcons.star, ShapeKind.star),
          const SizedBox(width: 8),
          _chip('LÍNEA', YuLiIcons.minus, ShapeKind.line),
          const SizedBox(width: 8),
          _chip('FLECHA', YuLiIcons.arrowRight, ShapeKind.arrow),
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
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: yInk),
            const SizedBox(height: 4),
            Text(
              label,
              style: yMono(
                size: 8,
                weight: FontWeight.w700,
                tracking: 1.0,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
