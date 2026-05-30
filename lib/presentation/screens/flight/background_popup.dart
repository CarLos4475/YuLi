import 'package:flutter/material.dart';

import '../../../domain/models/page_background.dart';
import '../../widgets/yuli_design.dart';
import 'background_paint.dart';

/// Background chooser popup: pattern + paper color, plus a page/all-notebook
/// scope toggle. Applies live via callbacks; the editor owns the state.
class BackgroundPopup extends StatelessWidget {
  final PageBackground pattern;
  final Color color;
  final bool showScope;
  final bool allPages;
  final Color accent;
  final ValueChanged<PageBackground> onPattern;
  final ValueChanged<Color> onColor;
  final VoidCallback onMoreColors;
  final ValueChanged<bool> onScope;
  final VoidCallback onClose;

  const BackgroundPopup({
    super.key,
    required this.pattern,
    required this.color,
    required this.showScope,
    required this.allPages,
    required this.accent,
    required this.onPattern,
    required this.onColor,
    required this.onMoreColors,
    required this.onScope,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('FONDO',
                  style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const Icon(Icons.close, size: 16, color: yInk),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final pb in PageBackground.values)
                _chip(pb.label, pb == pattern, () => onPattern(pb)),
            ],
          ),
          const SizedBox(height: 12),
          Text('COLOR',
              style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final c in kBgDefaultColors) ...[
                _swatch(c),
                const SizedBox(width: 8),
              ],
              _moreSwatch(),
            ],
          ),
          if (showScope) ...[
            const SizedBox(height: 12),
            Text('APLICAR A',
                style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                    child: _scope('PÁGINA ACTUAL', !allPages,
                        () => onScope(false))),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        _scope('TODO EL CUADERNO', allPages, () => onScope(true))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yInk, width: active ? 2.5 : yLineThin),
        ),
        child: Text(label,
            style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.1,
                color: active ? yCream : yInk)),
      ),
    );
  }

  Widget _swatch(Color c) {
    final selected = c.toARGB32() == color.toARGB32();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onColor(c),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: c,
          border: Border.all(
            color: selected ? accent : yInk,
            width: selected ? 3 : 1.5,
          ),
        ),
      ),
    );
  }

  Widget _moreSwatch() {
    final isDefault =
        kBgDefaultColors.any((c) => c.toARGB32() == color.toARGB32());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onMoreColors,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDefault ? yCream : color,
          border: Border.all(
            color: !isDefault ? accent : yInk,
            width: !isDefault ? 3 : 1.5,
          ),
        ),
        child: Icon(Icons.more_horiz,
            size: 16, color: isDefault ? yInk : _on(color)),
      ),
    );
  }

  Color _on(Color c) =>
      c.computeLuminance() < 0.4 ? Colors.white : yInk;

  Widget _scope(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yInk, width: active ? 2.5 : yLineThin),
        ),
        child: Text(label,
            style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.1,
                color: active ? yCream : yInk)),
      ),
    );
  }
}
