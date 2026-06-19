import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/yuli_design.dart';

/// Entry point for the YuLi AI chat (YuLi AI 2). Opened from the floating cube
/// FAB across Fight / Lab / Flight-general / folder-detail. [accent] is the
/// view's colour so the chat can theme itself to the context it was opened from.
///
/// PLACEHOLDER: the real chat (function-calling, single base mode) lands here
/// once its design is in. Keep this signature stable so the FAB call sites and
/// the cube→chat seam don't have to change.
Future<void> showYuliAiChat(
  BuildContext context,
  WidgetRef ref, {
  required Color accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _Placeholder(accent: accent),
  );
}

class _Placeholder extends StatelessWidget {
  final Color accent;
  const _Placeholder({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, color: accent),
                const SizedBox(width: 8),
                Text(
                  'YuLi · AI',
                  style: yMono(
                    size: 12,
                    weight: FontWeight.w700,
                    tracking: 1.6,
                    color: yInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Próximamente.',
              style: ySans(size: 16, weight: FontWeight.w700, color: yInk),
            ),
          ],
        ),
      ),
    );
  }
}
