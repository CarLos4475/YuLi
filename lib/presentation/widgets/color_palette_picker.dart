import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/lab_icons.dart';
import 'yuli_design.dart' show yBorderStrong;

/// Brutalist color picker for folders / spaces / notes. Shows [folderPaletteSections]
/// grouped by hue family (category) with a tonal ramp inside each. It's a plain
/// (unscrolled) Column — the HOST provides the scroll (e.g. a dialog wrapped in a
/// SingleChildScrollView), so there's one scroll, no nested-scroll jank, and the
/// dialog stays keyboard-safe. Selected swatch gets a heavy ink ring + check.
class ColorPalettePicker extends StatelessWidget {
  const ColorPalettePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.swatchSize = 34,
  });

  final Color selected;
  final ValueChanged<Color> onChanged;
  final double swatchSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < folderPaletteSections.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Text(
            folderPaletteSections[i].label,
            style: labelBold.copyWith(color: inkGray, letterSpacing: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in folderPaletteSections[i].colors)
                _Swatch(
                  color: c,
                  size: swatchSize,
                  selected: c.toARGB32() == selected.toARGB32(),
                  onTap: () => onChanged(c),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor =
        color.computeLuminance() > 0.5 ? inkBlack : paperLight;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: yBorderStrong,
            width: selected ? borderWidthHeavy : 1.2,
          ),
        ),
        child: selected ? Icon(YuLiIcons.check, size: 16, color: checkColor) : null,
      ),
    );
  }
}
