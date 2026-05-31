import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/theme_provider.dart';
import '../../providers/ink_recognizer_provider.dart';
import '../../providers/ai_providers.dart';
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
              child: AppSectionDivider(label: 'RECONOCIMIENTO (OCR)'),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _OcrModelBlock(),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'ASISTENTE IA (DEEPSEEK)'),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _AiKeyBlock(),
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

class _OcrModelBlock extends ConsumerStatefulWidget {
  const _OcrModelBlock();

  @override
  ConsumerState<_OcrModelBlock> createState() => _OcrModelBlockState();
}

class _OcrModelBlockState extends ConsumerState<_OcrModelBlock> {
  bool? _ready; // null = checking
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final r =
        await ref.read(inkRecognizerProvider).isModelReady(kInkDefaultLang);
    if (mounted) setState(() => _ready = r);
  }

  Future<void> _toggle() async {
    if (_busy || _ready == null) return;
    setState(() => _busy = true);
    final rec = ref.read(inkRecognizerProvider);
    try {
      if (_ready == true) {
        await rec.deleteModel(kInkDefaultLang);
      } else {
        await rec.downloadModel(kInkDefaultLang);
      }
    } catch (_) {}
    await _check();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    final status = ready == null
        ? 'Comprobando…'
        : (ready ? 'Descargado' : 'No descargado');
    final actionLabel = ready == true ? 'BORRAR' : 'DESCARGAR';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: inkColor(context), width: borderWidth),
        boxShadow: const [
          BoxShadow(
            color: inkBlack,
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MODELO · ESPAÑOL',
                  style: labelBold.copyWith(
                    color: inkColor(context),
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: bodyS.copyWith(color: inkColor(context).withAlpha(180)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Escritura → texto, sin conexión tras descargar.',
                  style: bodyS.copyWith(
                    color: inkColor(context).withAlpha(140),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (ready == null || _busy) ? null : _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: ready == true ? paperColor(context) : accentJournal,
                border: Border.all(color: inkColor(context), width: borderWidth),
              ),
              child: _busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: inkColor(context)),
                    )
                  : Text(
                      actionLabel,
                      style: labelBold.copyWith(
                        color: ready == true ? inkColor(context) : paperLight,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiKeyBlock extends ConsumerStatefulWidget {
  const _AiKeyBlock();

  @override
  ConsumerState<_AiKeyBlock> createState() => _AiKeyBlockState();
}

class _AiKeyBlockState extends ConsumerState<_AiKeyBlock> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty || _busy) return;
    setState(() => _busy = true);
    await ref.read(aiKeyStoreProvider).write(v);
    _ctrl.clear();
    ref.invalidate(aiHasKeyProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key guardada')),
    );
  }

  Future<void> _clearKey() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(aiKeyStoreProvider).clear();
    ref.invalidate(aiHasKeyProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key borrada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = ref.watch(aiHasKeyProvider).valueOrNull ?? false;
    final ink = inkColor(context);
    final paper = paperColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: ink, width: borderWidth),
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
          Row(
            children: [
              Text(
                'DEEPSEEK API KEY',
                style: labelBold.copyWith(
                    color: ink, fontSize: 11, letterSpacing: 1.2),
              ),
              const Spacer(),
              Text(
                hasKey ? 'Configurada ✓' : 'No configurada',
                style: bodyS.copyWith(
                    color: hasKey ? accentLab : ink.withAlpha(150)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: bodyS.copyWith(color: ink),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              hintText: hasKey ? 'Pega una nueva key para reemplazar…' : 'Pega tu API key…',
              hintStyle: bodyS.copyWith(color: ink.withAlpha(120)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: ink, width: borderWidth),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: ink, width: borderWidth),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: ink, width: borderWidth),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _save,
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accentJournal,
                      border: Border.all(color: ink, width: borderWidth),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: paperLight))
                        : Text('GUARDAR',
                            style: labelBold.copyWith(
                                color: paperLight,
                                fontSize: 11,
                                letterSpacing: 1.2)),
                  ),
                ),
              ),
              if (hasKey) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _busy ? null : _clearKey,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: paper,
                      border: Border.all(color: ink, width: borderWidth),
                    ),
                    child: Text('BORRAR',
                        style: labelBold.copyWith(
                            color: ink, fontSize: 11, letterSpacing: 1.2)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Se guarda cifrada en el dispositivo. No sale de aquí (ni a git ni a la nube).',
            style: bodyS.copyWith(color: ink.withAlpha(140), fontSize: 11),
          ),
        ],
      ),
    );
  }
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
