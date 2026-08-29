import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/yuli_design.dart';

const aiPaper = Color(0xFFF7F4EC);
const aiPaperSoft = Color(0xFFF0ECE2);
const aiInk = Color(0xFF171714);
const aiMuted = Color(0xFF777269);
const aiHairline = Color(0x24171410);

LinearGradient aiAccentMetalGradient(Color accent) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color.lerp(accent, Colors.white, 0.28)!,
    accent,
    Color.lerp(accent, Colors.black, 0.16)!,
  ],
  stops: const [0, 0.52, 1],
);

List<BoxShadow> aiAccentMetalShadow(Color accent) => [
  BoxShadow(
    color: accent.withValues(alpha: 0.30),
    blurRadius: 12,
    spreadRadius: -3,
    offset: const Offset(0, 5),
  ),
  BoxShadow(
    color: Colors.white.withValues(alpha: 0.20),
    blurRadius: 2,
    offset: const Offset(0, -1),
  ),
];

LinearGradient aiSilverGlassGradient(Color accent) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Colors.white.withValues(alpha: 0.58),
    Color.lerp(const Color(0xFFD8DBDF), accent, 0.10)!.withValues(alpha: 0.46),
    Color.lerp(const Color(0xFFB9BEC4), accent, 0.15)!.withValues(alpha: 0.36),
  ],
  stops: const [0, 0.56, 1],
);

List<BoxShadow> aiSilverGlassShadow(Color accent) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.11),
    blurRadius: 9,
    spreadRadius: -5,
    offset: const Offset(0, 4),
  ),
  BoxShadow(
    color: accent.withValues(alpha: 0.09),
    blurRadius: 12,
    spreadRadius: -7,
    offset: const Offset(0, 4),
  ),
  BoxShadow(
    color: Colors.white.withValues(alpha: 0.32),
    blurRadius: 2,
    offset: const Offset(0, -1),
  ),
];

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
    duration: const Duration(milliseconds: 1350),
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
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < 3; index++) ...[
                Builder(
                  builder: (_) {
                    final wave = (math.sin(phase - index * 0.9) + 1) / 2;
                    return Transform.translate(
                      offset: Offset(0, -2 * wave),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.accent.withValues(
                            alpha: 0.28 + wave * 0.62,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (index < 2) const SizedBox(width: 5),
              ],
            ],
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
  final bool accented;

  const AiStatusPill({
    super.key,
    this.icon,
    required this.label,
    required this.accent,
    this.onTap,
    this.active = false,
    this.highImpact = false,
    this.accented = true,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        accented
            ? Colors.white
            : Color.lerp(const Color(0xFF3D4248), accent, 0.18)!;
    final radius = BorderRadius.circular(15);
    final content = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient:
            accented
                ? aiAccentMetalGradient(accent)
                : aiSilverGlassGradient(accent),
        borderRadius: radius,
        border: Border.all(
          color:
              accented
                  ? Colors.white.withValues(alpha: 0.46)
                  : Color.lerp(
                    Colors.white,
                    accent,
                    0.10,
                  )!.withValues(alpha: 0.64),
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
                color: accented ? Colors.white : accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: yBody(size: 11, weight: FontWeight.w700, color: foreground),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 30,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow:
              accented
                  ? aiAccentMetalShadow(accent)
                  : aiSilverGlassShadow(accent),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child:
              accented
                  ? content
                  : BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                    child: content,
                  ),
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

class AiInteractiveSurface extends StatelessWidget {
  final Widget child;
  final Color accent;
  final BorderRadius borderRadius;

  const AiInteractiveSurface({
    super.key,
    required this.child,
    required this.accent,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.62),
            Colors.white.withValues(alpha: 0.36),
            accent.withValues(alpha: 0.09),
          ],
          stops: const [0, 0.62, 1],
        ),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.68)),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.11),
            blurRadius: 22,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.11),
            blurRadius: 18,
            spreadRadius: -12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: surface,
        ),
      ),
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
