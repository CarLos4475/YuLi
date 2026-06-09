import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_tokens.dart';
import '../theme/lab_icons.dart';
import '../providers/database_providers.dart';
import '../screens/trash/trash_screen.dart';
import '../screens/settings/settings_screen.dart';

class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(currentModeProvider);
    final ink = inkColor(context);

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: _ModeTab(
            label: 'FIGHT',
            icon: YuLiIcons.listChecks,
            mode: AppMode.fight,
            accentColor: accentFight,
            currentMode: currentMode,
            onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
          ),
        ),
        _Separator(),
        Expanded(
          child: _ModeTab(
            label: 'FLIGHT',
            icon: YuLiIcons.fileText,
            mode: AppMode.flight,
            accentColor: accentFlight,
            currentMode: currentMode,
            onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
          ),
        ),
        _Separator(),
        Expanded(
          child: _ModeTab(
            label: 'LAB',
            icon: YuLiIcons.layoutDashboard,
            mode: AppMode.lab,
            accentColor: accentLab,
            currentMode: currentMode,
            onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.lab,
          ),
        ),
        _Separator(),
        _OverflowTab(ink: ink),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: inkGray.withAlpha(60),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final AppMode mode;
  final Color accentColor;
  final AppMode currentMode;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.mode,
    required this.accentColor,
    required this.currentMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentMode == mode;
    final color = isActive ? accentColor : inkGray;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isActive ? accentColor : Colors.transparent,
              width: borderWidthHeavy,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: labelBold.copyWith(color: color, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverflowTab extends StatelessWidget {
  final Color ink;

  const _OverflowTab({required this.ink});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showOverflowMenu(context),
      child: SizedBox(
        width: 48,
        height: 56,
        child: Align(
          alignment: Alignment.center,
          child: Text(
            '•••',
            style: labelBold.copyWith(color: inkGray, fontSize: 12),
          ),
        ),
      ),
    );
  }

  void _showOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: paperColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) => const _OverflowMenu(),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu();

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: borderWidth,
          color: ink,
        ),
        _MenuItem(
          label: 'CONFIGURACIÓN',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          textColor: ink,
        ),
        _MenuItem(
          label: 'PAPELERA',
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            );
          },
          textColor: ink,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'JOURNAL',
                style: labelBold.copyWith(
                  color: inkGray.withAlpha(128),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Próximamente',
                style: bodyS.copyWith(color: inkGray.withAlpha(100)),
              ),
            ],
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color textColor;

  const _MenuItem({
    required this.label,
    required this.onTap,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: labelBold.copyWith(color: textColor),
        ),
      ),
    );
  }
}
