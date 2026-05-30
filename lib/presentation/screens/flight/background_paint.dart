import 'package:flutter/material.dart';

import '../../../domain/models/page_background.dart';

/// Default paper colors offered as quick swatches in the background popup.
const Color kBgWhite = Color(0xFFFFFFFF);
const Color kBgCream = Color(0xFFFBF7EE);
const Color kBgGray = Color(0xFF4A4A4A);
const Color kBgBlack = Color(0xFF121212);

const List<Color> kBgDefaultColors = [kBgWhite, kBgCream, kBgGray, kBgBlack];

/// Resolve a stored paper color value, falling back to the editor default.
Color bgPaper(int? value, Color fallback) =>
    value != null ? Color(value) : fallback;

/// Pattern mark color auto-contrasted to the paper (dark paper → light marks).
Color bgMark(Color paper) => paper.computeLuminance() < 0.4
    ? const Color(0x59FFFFFF) // white ~35%
    : const Color(0x1F000000); // black ~12%

double _gridStep(PageBackground bg) =>
    bg == PageBackground.gridSmall ? 15.0 : 30.0;

/// Tile a background pattern across [bounds] with the [mark] color. Used by the
/// whiteboard (over the visible rect) and the notebook (over each page rect).
void paintBgPattern(
    Canvas canvas, Rect bounds, PageBackground pattern, Color mark) {
  switch (pattern) {
    case PageBackground.blank:
      return;
    case PageBackground.lined:
      final paint = Paint()
        ..color = mark
        ..strokeWidth = 0.8;
      const step = 30.0;
      final start = (bounds.top / step).ceil() * step;
      for (double y = start; y < bounds.bottom; y += step) {
        canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
      }
    case PageBackground.grid:
    case PageBackground.gridSmall:
      final step = _gridStep(pattern);
      final paint = Paint()
        ..color = mark
        ..strokeWidth = 0.6;
      final sx = (bounds.left / step).ceil() * step;
      final sy = (bounds.top / step).ceil() * step;
      for (double x = sx; x < bounds.right; x += step) {
        canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
      }
      for (double y = sy; y < bounds.bottom; y += step) {
        canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
      }
    case PageBackground.dotted:
      final dot = Paint()..color = mark;
      const step = 26.0;
      final sx = (bounds.left / step).ceil() * step;
      final sy = (bounds.top / step).ceil() * step;
      for (double x = sx; x < bounds.right; x += step) {
        for (double y = sy; y < bounds.bottom; y += step) {
          canvas.drawCircle(Offset(x, y), 1.2, dot);
        }
      }
  }
}
