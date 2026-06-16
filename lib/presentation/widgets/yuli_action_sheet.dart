import 'package:flutter/material.dart';

import '../theme/lab_icons.dart';
import 'yuli_design.dart';

class YuLiActionSheet extends StatelessWidget {
  final String title;
  final String badge;
  final IconData badgeIcon;
  final Color accent;
  final List<Widget> children;

  const YuLiActionSheet({
    super.key,
    required this.title,
    required this.badge,
    required this.badgeIcon,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${accent.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    return Material(
      color: yCream,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineMid),
              left: BorderSide(color: yBorderStrong, width: yLineMid),
              right: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
            boxShadow: [
              BoxShadow(
                color: yBorderStrong,
                offset: Offset(7, 7),
                blurRadius: 0,
              ),
            ],
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Container(width: 56, height: 5, color: accent)),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ySans(
                            size: 22,
                            weight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: yInk,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            _SheetBadge(icon: badgeIcon, label: badge),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 27, height: 27, color: accent),
                                const SizedBox(width: 8),
                                Text(
                                  hex,
                                  style: yMono(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    tracking: 1.4,
                                    color: yMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: yBorderStrong.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class YuLiActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool destructive;
  final bool useAccentFill;

  const YuLiActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.destructive = false,
    this.useAccentFill = true,
  });

  @override
  Widget build(BuildContext context) {
    final actionColor = destructive ? yFight : accent;
    final iconBg = destructive || useAccentFill ? actionColor : yCream;
    final iconFg = destructive || useAccentFill ? yCream : yInk;
    final textColor = destructive ? yFight : yInk;
    final borderColor = destructive ? yFight : yBorderStrong;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: destructive ? yFight.withValues(alpha: 0.08) : yCream,
            border: Border.all(color: borderColor, width: yLineThin),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  border: Border(
                    right: BorderSide(color: borderColor, width: yLineThin),
                  ),
                ),
                child: Icon(icon, size: 20, color: iconFg),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ySans(
                    size: 16,
                    weight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              Icon(
                YuLiIcons.chevronRight,
                size: 22,
                color: destructive ? yFight : yInk,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SheetBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 10, 3),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: yInk),
          const SizedBox(width: 7),
          Text(
            label,
            style: yMono(
              size: 13,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yInk,
            ),
          ),
        ],
      ),
    );
  }
}
