// YuLi V1 design system — Command Triptych
// Shared tokens + chrome widgets (ModeHeader, BottomNav, brutal atoms)
// used by Home/Fight/Flight/Lab screens.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_providers.dart';

// ─── DESIGN TOKENS ────────────────────────────────────────────────────────

const Color yCream = Color(0xFFF2EFE6);
const Color yCream2 = Color(0xFFEBE6D9);
const Color yInk = Color(0xFF0A0A0A);
const Color yInk2 = Color(0xFF2A241C);
const Color yMuted = Color(0xFF7A6F60);
const Color yAmber = Color(0xFFC7822F);
const Color yAmber2 = Color(0xFFE29A3A);

const Color yFight = Color(0xFFC8332C);
const Color yFlight = Color(0xFF2D3F8C);
const Color yLab = Color(0xFF3F6E3E);

const double yLineHeavy = 3.0;
const double yLineMid = 2.5;
const double yLineThin = 2.0;

Color colorForMode(AppMode mode) {
  switch (mode) {
    case AppMode.fight:
      return yFight;
    case AppMode.flight:
      return yFlight;
    case AppMode.lab:
      return yLab;
    case AppMode.home:
      return yInk;
  }
}

TextStyle yMono({
  double size = 11,
  Color color = yMuted,
  double tracking = 1.4,
  FontWeight weight = FontWeight.w500,
}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontSize: size,
      letterSpacing: tracking,
      color: color,
      fontWeight: weight,
      height: 1.2,
    );

TextStyle ySans({
  double size = 16,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
  Color color = yInk,
  double height = 1.2,
}) =>
    TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );

TextStyle yBody({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color color = yInk,
  double height = 1.4,
}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

// ─── MODE HEADER ──────────────────────────────────────────────────────────

class ModeHeader extends StatelessWidget {
  final String mode;
  final String subtitle;
  final Color color;
  final List<Widget> headerRight;
  final VoidCallback? onBack;

  const ModeHeader({
    super.key,
    required this.mode,
    required this.subtitle,
    required this.color,
    this.headerRight = const [],
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: const Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onBack != null) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: yCream, width: yLineMid),
                ),
                child: const Icon(Icons.arrow_back, color: yCream, size: 18),
              ),
            ),
            const SizedBox(width: 18),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode,
                  style: ySans(
                    size: 52,
                    weight: FontWeight.w700,
                    letterSpacing: -2,
                    color: yCream,
                    height: 0.9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: yMono(
                    size: 11,
                    color: yCream.withValues(alpha: 0.8),
                    tracking: 1.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ...headerRight.map((w) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: w,
              )),
        ],
      ),
    );
  }
}

// ─── BOTTOM NAV (used globally by main.dart) ──────────────────────────────

class YuliBottomNav extends ConsumerWidget {
  const YuliBottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentModeProvider);
    final tabs = const [
      _NavTab(mode: AppMode.fight, label: 'captura', color: yFight),
      _NavTab(mode: AppMode.flight, label: 'notas', color: yFlight),
      _NavTab(mode: AppMode.lab, label: 'lab', color: yLab),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    ref.read(currentModeProvider.notifier).state = AppMode.home,
                child: Container(
                  width: 56,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: yInk, width: yLineMid),
                    ),
                  ),
                  child: const Icon(Icons.home_outlined,
                      color: yInk, size: 22),
                ),
              ),
              for (int i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavTabButton(
                    tab: tabs[i],
                    active: tabs[i].mode == current,
                    showBorder: i < tabs.length - 1,
                    onTap: () => ref
                        .read(currentModeProvider.notifier)
                        .state = tabs[i].mode,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab {
  final AppMode mode;
  final String label;
  final Color color;
  const _NavTab(
      {required this.mode, required this.label, required this.color});
}

class _NavTabButton extends StatelessWidget {
  final _NavTab tab;
  final bool active;
  final bool showBorder;
  final VoidCallback onTap;

  const _NavTabButton({
    required this.tab,
    required this.active,
    required this.showBorder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final modeName = tab.mode.name.toUpperCase();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? tab.color : Colors.transparent,
              border: showBorder
                  ? const Border(
                      right: BorderSide(color: yInk, width: yLineMid),
                    )
                  : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  modeName,
                  style: ySans(
                    size: 22,
                    weight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: active ? yCream : yInk,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  tab.label,
                  style: yMono(
                    size: 10,
                    color: active ? yCream : yInk.withValues(alpha: 0.5),
                    tracking: 1.4,
                  ),
                ),
              ],
            ),
            if (active)
              Text(
                '● activo',
                style: yMono(
                  size: 9,
                  color: yCream,
                  tracking: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── MENTION HELPERS ──────────────────────────────────────────────────────

final _mentionRegex = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)');

String cleanMention(String content) {
  final cleaned = content.replaceAll(_mentionRegex, '').trim();
  return cleaned.isEmpty ? content : cleaned;
}

/// The "@mention" tokens in [content] (folder tags), space-joined; '' if none.
/// Lets a cleaned title be edited without dropping its folder tag.
String extractMentions(String content) =>
    _mentionRegex.allMatches(content).map((m) => m.group(0)!).join(' ');

Widget buildMentionText({
  required String content,
  required TextStyle style,
  Color? folderColor,
  int? maxLines,
  TextOverflow? overflow,
}) {
  final matches = _mentionRegex.allMatches(content).toList();
  if (matches.isEmpty || folderColor == null) {
    return Text(
      content,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  final spans = <InlineSpan>[];
  int last = 0;
  for (final m in matches) {
    if (m.start > last) {
      spans.add(TextSpan(text: content.substring(last, m.start), style: style));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.fromLTRB(6, 1, 6, 2),
        decoration: BoxDecoration(
          color: folderColor,
          border: Border.all(color: yInk, width: 1.5),
        ),
        child: Text(
          '@${m.group(1)}',
          style: yMono(size: 10, weight: FontWeight.w700, color: yCream, tracking: 0.3),
        ),
      ),
    ));
    last = m.end;
  }
  if (last < content.length) {
    spans.add(TextSpan(text: content.substring(last), style: style));
  }
  return Text.rich(
    TextSpan(children: spans),
    maxLines: maxLines,
    overflow: overflow,
  );
}

// ─── BRUTAL ATOMS ─────────────────────────────────────────────────────────

class BrutalSlab extends StatelessWidget {
  final Color bg;
  final Widget child;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;

  const BrutalSlab({
    super.key,
    required this.bg,
    required this.child,
    this.border,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: border ?? Border.all(color: yInk, width: yLineHeavy),
      ),
      padding: padding,
      child: child,
    );
  }
}

class YBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final double fontSize;

  const YBadge({
    super.key,
    required this.label,
    required this.bg,
    this.fg = yCream,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      child: Text(
        label,
        style: yBody(
          size: fontSize,
          weight: FontWeight.w700,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }
}

class IconSquareBtn extends StatelessWidget {
  final IconData icon;
  final String? text;
  final bool fill;
  final Color color;
  final VoidCallback? onTap;
  final double size;

  const IconSquareBtn({
    super.key,
    required this.icon,
    this.text,
    this.fill = false,
    this.color = yCream,
    this.onTap,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ? color : Colors.transparent,
          border: Border.all(color: fill ? yInk : color, width: yLineMid),
        ),
        child: Icon(icon,
            size: size * 0.45, color: fill ? yInk : color),
      ),
    );
  }
}

class CapChip extends StatelessWidget {
  final String kind;
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  const CapChip({
    super.key,
    required this.kind,
    required this.active,
    this.color = yInk,
    this.onTap,
  });

  static const _meta = {
    'Kanban': '▣',
    'Horario': '◷',
    'Timeline': '═',
    'Calendario': '▦',
  };

  @override
  Widget build(BuildContext context) {
    final glyph = _meta[kind] ?? '·';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              glyph,
              style: TextStyle(
                fontSize: 11,
                color: active ? yCream : color,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              kind.toUpperCase(),
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: active ? yCream : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModeSection extends StatelessWidget {
  final String label;
  final int? count;
  final Widget? trailing;
  final Widget child;

  const ModeSection({
    super.key,
    required this.label,
    this.count,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                '── ${label.toUpperCase()}',
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.6,
                  color: yInk,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 10),
                Text(
                  '· ${count.toString().padLeft(2, '0')}',
                  style: yMono(size: 11, color: yMuted, tracking: 1.4),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: yInk.withValues(alpha: 0.15),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class PillTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const PillTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
        decoration: BoxDecoration(
          color: active ? yLab : Colors.transparent,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(
            size: 11,
            weight: FontWeight.w700,
            color: active ? yCream : yInk,
            height: 1.1,
          ).copyWith(letterSpacing: 1.4),
        ),
      ),
    );
  }
}

class ToolChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const ToolChip({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(label.toUpperCase(),
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted,
                )),
            const SizedBox(width: 8),
            Text(value,
                style: yBody(
                  size: 12,
                  weight: FontWeight.w700,
                  color: yInk,
                )),
            const SizedBox(width: 6),
            const Text('▾',
                style: TextStyle(fontSize: 10, color: yInk, height: 1.0)),
          ],
        ),
      ),
    );
  }
}

class ViewToggleBtn extends StatelessWidget {
  final String glyph;
  final bool active;
  final VoidCallback onTap;

  const ViewToggleBtn({
    super.key,
    required this.glyph,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? yFlight : yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 16,
            color: active ? yCream : yInk,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

// ─── VIEW HEAD ─────────────────────────────────────────────────────────────

/// Section header inside a space view (Kanban / Horario / Timeline /
/// Calendario). Title in lab green + mono kicker + right action slot.
class ViewHead extends StatelessWidget {
  final String title;
  final String? kicker;
  final List<Widget> right;
  final Color? titleColor;

  const ViewHead({
    super.key,
    required this.title,
    this.kicker,
    this.right = const [],
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: yInk, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: ySans(
                      size: 26,
                      weight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: titleColor ?? yLab,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (kicker != null) ...[
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      kicker!,
                      style: yMono(
                        size: 11,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          for (final w in right) ...[
            w,
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// Pill button shown in ViewHead right slot.
class HeadBtn extends StatelessWidget {
  final String label;
  final bool primary;
  final IconData? leadingIcon;
  final VoidCallback? onTap;

  const HeadBtn({
    super.key,
    required this.label,
    this.primary = false,
    this.leadingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        decoration: BoxDecoration(
          color: primary ? yLab : yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon,
                  size: 14, color: primary ? yCream : yInk),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: yBody(
                  size: 12,
                  weight: FontWeight.w700,
                  color: primary ? yCream : yInk,
                ).copyWith(letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// Compact nav button (36×36 square w/ glyph).
class NavBtn extends StatelessWidget {
  final String glyph;
  final VoidCallback? onTap;

  const NavBtn({super.key, required this.glyph, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Text(
          glyph,
          style: const TextStyle(
            fontSize: 16,
            color: yInk,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

Color parseHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return yMuted;
}
