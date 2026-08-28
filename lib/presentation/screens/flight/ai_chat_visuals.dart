import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

const aiPaper = Color(0xFFF7F4EC);
const aiPaperSoft = Color(0xFFF0ECE2);
const aiInk = Color(0xFF171714);
const aiMuted = Color(0xFF777269);
const aiHairline = Color(0x24171410);

enum AiFrostedSurfaceRole { panel, dialog }

class AiThinkingIndicator extends ConsumerStatefulWidget {
  final Color accent;

  const AiThinkingIndicator({super.key, required this.accent});

  @override
  ConsumerState<AiThinkingIndicator> createState() =>
      _AiThinkingIndicatorState();
}

class _AiThinkingIndicatorState extends ConsumerState<AiThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'YuLi está pensando',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = _controller.value * math.pi * 2;
          final pulse = 0.5 + math.sin(phase) * 0.5;
          return Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.52),
                  widget.accent.withValues(alpha: 0.09 + pulse * 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.accent.withValues(alpha: 0.18 + pulse * 0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.1 + pulse * 0.06),
                  blurRadius: 16,
                  spreadRadius: -7,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: 0.82 + pulse * 0.22,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.accent.withValues(
                              alpha: 0.08 + pulse * 0.08,
                            ),
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: phase * 0.16,
                        child: Icon(
                          YuLiIcons.sparkles,
                          size: 14,
                          color: widget.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pensando',
                  style: yBody(size: 12, weight: FontWeight.w700, color: aiInk),
                ),
                const SizedBox(width: 7),
                for (var index = 0; index < 3; index++) ...[
                  Transform.translate(
                    offset: Offset(0, -2.5 * math.sin(phase - index * 0.75)),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accent.withValues(
                          alpha:
                              0.35 +
                              0.65 * ((math.sin(phase - index * 0.75) + 1) / 2),
                        ),
                      ),
                    ),
                  ),
                  if (index < 2) const SizedBox(width: 4),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class AiFrostedSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool blur;
  final EdgeInsetsGeometry? padding;
  final Color? accent;
  final AiFrostedSurfaceRole role;

  const AiFrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = true,
    this.padding,
    this.accent,
    this.role = AiFrostedSurfaceRole.panel,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? aiPaper;
    final isDialog = role == AiFrostedSurfaceRole.dialog;
    final surface = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: isDialog ? 0.76 : 0.32),
                  aiPaper.withValues(alpha: isDialog ? 0.68 : 0.22),
                  Color.alphaBlend(
                    tint.withValues(
                      alpha: accent == null ? 0 : (isDialog ? 0.035 : 0.07),
                    ),
                    aiPaper,
                  ).withValues(alpha: isDialog ? 0.72 : 0.24),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
        if (isDialog)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: aiPaperSoft.withValues(alpha: 0.2),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.85, -0.92),
                radius: 1.05,
                colors: [
                  tint.withValues(alpha: accent == null ? 0.03 : 0.08),
                  Colors.transparent,
                ],
                stops: const [0, 0.72],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ],
    );
    final glass = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: surface,
    );
    final clipped = ClipRRect(
      borderRadius: borderRadius,
      child:
          blur
              ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: isDialog ? 14 : 6,
                  sigmaY: isDialog ? 14 : 6,
                ),
                child: glass,
              )
              : glass,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 44,
            spreadRadius: -8,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: tint.withValues(alpha: accent == null ? 0 : 0.12),
            blurRadius: 30,
            spreadRadius: -16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: clipped,
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
