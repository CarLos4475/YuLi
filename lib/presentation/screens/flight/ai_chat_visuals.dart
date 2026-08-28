import 'dart:ui';

import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';

const aiPaper = Color(0xFFF7F4EC);
const aiPaperSoft = Color(0xFFF0ECE2);
const aiInk = Color(0xFF171714);
const aiMuted = Color(0xFF777269);
const aiHairline = Color(0x24171410);

class AiFrostedSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool blur;
  final EdgeInsetsGeometry? padding;

  const AiFrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: aiPaper.withValues(alpha: 0.91),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
    if (!blur) return ClipRRect(borderRadius: borderRadius, child: surface);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: surface,
      ),
    );
  }
}

class AiSoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;

  const AiSoftIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? Colors.white.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: aiHairline),
        ),
        child: Icon(icon, size: size * 0.43, color: color ?? aiInk),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class AiStatusPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final bool active;
  final bool highImpact;

  const AiStatusPill({
    super.key,
    this.icon,
    required this.label,
    required this.accent,
    this.onTap,
    this.active = false,
    this.highImpact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color:
              active
                  ? accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.42) : aiHairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (highImpact) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 13, color: active ? accent : aiMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: yBody(
                size: 11,
                weight: FontWeight.w700,
                color: active ? accent : aiMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AiSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: aiHairline),
      ),
      child: child,
    );
  }
}

class AiSoftToggle extends StatelessWidget {
  final bool value;
  final Color accent;

  const AiSoftToggle({super.key, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 42,
      height: 24,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? accent : aiPaperSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? accent : aiHairline),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
