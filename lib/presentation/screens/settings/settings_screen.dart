import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/app_section_divider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── HEADER MONOLITO ──
            Container(
              width: double.infinity,
              color: inkColor(context),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: paperColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AJUSTES',
                    style: labelBold.copyWith(
                      color: paperColor(context),
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: borderWidthHeavy,
              color: inkColor(context),
            ),

            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'TEMA'),
            ),
            const SizedBox(height: 12),

            // ── BLOQUES DE TEMA ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _ThemeBlock(
                      label: 'CLARO',
                      color: paperLight,
                      textColor: inkBlack,
                      selected: themeMode == ThemeMode.light,
                      onTap: () => ref.read(themeModeProvider.notifier).set(ThemeMode.light),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ThemeBlock(
                      label: 'OSCURO',
                      color: paperDark,
                      textColor: paperLight,
                      selected: themeMode == ThemeMode.dark,
                      onTap: () => ref.read(themeModeProvider.notifier).set(ThemeMode.dark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SplitThemeBlock(
                      selected: themeMode == ThemeMode.system,
                      onTap: () => ref.read(themeModeProvider.notifier).set(ThemeMode.system),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'INFO'),
            ),
            const SizedBox(height: 12),

            // ── BLOQUES DE INFO ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoBlock(
                      label: 'VERSIÓN',
                      value: '1.0.0',
                      color: accentJournal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _InfoBlock(
                      label: 'MODO',
                      value: 'OFFLINE',
                      color: accentLab,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── MARCA ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: inkColor(context),
                  border: Border.all(color: inkBlack, width: borderWidth),
                  boxShadow: const [
                    BoxShadow(
                      color: inkBlack,
                      offset: shadowOffset,
                      blurRadius: shadowBlurRadius,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YuLi',
                      style: displayL.copyWith(color: paperColor(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Segundo Cerebro',
                      style: bodyS.copyWith(
                        color: paperColor(context).withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── WIDGETS PRIVADOS ──

class _ThemeBlock extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeBlock({
    required this.label,
    required this.color,
    required this.textColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: labelBold.copyWith(
                color: textColor,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: textColor, width: borderWidth),
              ),
              child: selected
                  ? Container(
                      margin: const EdgeInsets.all(2),
                      color: accentFight,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitThemeBlock extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _SplitThemeBlock({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DiagonalSplitPainter(
                  colorA: paperLight,
                  colorB: inkBlack,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SISTEMA',
                    style: labelBold.copyWith(
                      color: inkBlack,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(color: inkBlack, width: borderWidth),
                    ),
                    child: selected
                        ? Container(
                            margin: const EdgeInsets.all(2),
                            color: accentFight,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagonalSplitPainter extends CustomPainter {
  final Color colorA;
  final Color colorB;

  _DiagonalSplitPainter({required this.colorA, required this.colorB});

  @override
  void paint(Canvas canvas, Size size) {
    final pathA = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();

    final pathB = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(pathA, Paint()..color = colorA);
    canvas.drawPath(pathB, Paint()..color = colorB);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoBlock({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: inkBlack, width: borderWidth),
        boxShadow: const [
          BoxShadow(
            color: inkBlack,
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: labelBold.copyWith(
              color: paperLight.withAlpha(220),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: displayM.copyWith(color: paperLight, height: 1.0),
          ),
        ],
      ),
    );
  }
}
