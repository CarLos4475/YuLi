import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/yuli_design.dart';

/// Neobrutalist YuLi shell for the media-pin prompts (video / web / pdf): strong
/// border, hard offset shadow, a mono header with an accent icon chip, and a
/// footer row. The helpers below (field + buttons) keep all three consistent.
class PinDialogShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;
  final Widget footer;

  const PinDialogShell({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        width: 380,
        decoration: const BoxDecoration(
          color: yCream,
          border: Border.fromBorderSide(
            BorderSide(color: yBorderStrong, width: yLineMid),
          ),
          boxShadow: [BoxShadow(color: yBorderStrong, offset: Offset(5, 5))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: yCream2,
                border: Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineThin),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent,
                      border:
                          Border.all(color: yBorderStrong, width: yLineThin),
                    ),
                    child: Icon(icon, size: 15, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: yMono(
                        size: 12,
                        weight: FontWeight.w800,
                        tracking: 1.4,
                        color: yInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: child,
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: yBorderStrong, width: yLineThin),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: footer,
            ),
          ],
        ),
      ),
    );
  }
}

/// YuLi-styled text field for the dialogs (cream fill, hard border, mono text,
/// accent focus ring).
Widget pinDialogField({
  required TextEditingController controller,
  required String hint,
  required Color accent,
  bool autofocus = false,
  TextInputType? keyboardType,
}) {
  return TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: keyboardType,
    style: yMono(size: 12, color: yInk),
    cursorColor: accent,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: yMono(size: 11, color: yMuted),
      filled: true,
      fillColor: yCream2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: yBorderStrong, width: yLineThin),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: yBorderStrong, width: yLineThin),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: accent, width: yLineMid),
      ),
    ),
  );
}

/// Filled accent confirm button (the design's primary action).
class PinPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color accent;
  final VoidCallback onTap;

  const PinPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(2, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: yMono(
                size: 11,
                weight: FontWeight.w800,
                tracking: 1.0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ghost cancel button (no fill).
class PinGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const PinGhostButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          label,
          style: yMono(
            size: 11,
            weight: FontWeight.w700,
            tracking: 1.0,
            color: yMuted,
          ),
        ),
      ),
    );
  }
}

/// Full-width accent action (e.g. ELEGIR ARCHIVO in the PDF dialog).
class PinBigActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const PinBigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(3, 3))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: yMono(
                size: 12,
                weight: FontWeight.w800,
                tracking: 1.2,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
