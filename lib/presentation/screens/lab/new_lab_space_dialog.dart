import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

Future<Color?> showLabSpaceColorDialog(
  BuildContext context, {
  required String title,
  required String spaceName,
  required Color initialColor,
}) {
  return showDialog<Color>(
    context: context,
    builder:
        (context) => MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: _LabSpaceColorDialog(
            title: title,
            spaceName: spaceName,
            initialColor: initialColor,
          ),
        ),
  );
}

class NewLabSpaceDialog extends ConsumerStatefulWidget {
  const NewLabSpaceDialog({super.key});

  @override
  ConsumerState<NewLabSpaceDialog> createState() => _NewLabSpaceDialogState();
}

class _NewLabSpaceDialogState extends ConsumerState<NewLabSpaceDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = accentLab;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final hex =
        '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    await ref.read(labSpaceRepositoryProvider).create(name, hex);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = screen.width < 920 ? screen.width - 28 : 900.0;
    final dialogHeight = screen.height < 660 ? screen.height - 28 : 610.0;

    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: Dialog(
        backgroundColor: yCream,
        surfaceTintColor: yCream,
        insetPadding: const EdgeInsets.all(14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Container(
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
              boxShadow: const [
                BoxShadow(
                  color: yBorderStrong,
                  offset: Offset(5, 5),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogHeader(
                  title: 'Nuevo space',
                  onClose: () => Navigator.pop(context),
                ),
                const SizedBox(height: 12),
                _SectionLabel('Nombre del proyecto'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: ySans(size: 20, weight: FontWeight.w700, color: yInk),
                  decoration: InputDecoration(
                    hintText: 'Nombre del proyecto',
                    hintStyle: ySans(
                      size: 19,
                      weight: FontWeight.w600,
                      color: yInk.withValues(alpha: 0.34),
                    ),
                    border: _inputBorder(yLineMid),
                    enabledBorder: _inputBorder(yLineMid),
                    focusedBorder: _inputBorder(yLineHeavy),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final paletteWidth = math.min(
                        450.0,
                        constraints.maxWidth * 0.58,
                      );
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: paletteWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 18),
                              child: _LabPaletteRows(
                                selected: _selectedColor,
                                onChanged:
                                    (color) =>
                                        setState(() => _selectedColor = color),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(width: 1, color: yBorderStrong),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _LabPreviewColumn(
                              name: _previewName,
                              color: _selectedColor,
                              subtitle: 'Asi se vera tu space en LAB',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _DialogButton(
                        label: 'Cancelar',
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _DialogButton(
                        label: 'Crear space',
                        accent: _selectedColor,
                        trailingIcon: YuLiIcons.arrowRight,
                        onTap: _create,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _previewName {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'Nombre del proyecto' : name;
  }
}

class _LabSpaceColorDialog extends StatefulWidget {
  final String title;
  final String spaceName;
  final Color initialColor;

  const _LabSpaceColorDialog({
    required this.title,
    required this.spaceName,
    required this.initialColor,
  });

  @override
  State<_LabSpaceColorDialog> createState() => _LabSpaceColorDialogState();
}

class _LabSpaceColorDialogState extends State<_LabSpaceColorDialog> {
  late Color _selectedColor = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = screen.width < 1120 ? screen.width - 28 : 1080.0;
    final dialogHeight = screen.height < 690 ? screen.height - 28 : 640.0;
    return Dialog(
      backgroundColor: yCream,
      surfaceTintColor: yCream,
      insetPadding: const EdgeInsets.all(14),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Container(
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 2, height: 104, color: yBorderStrong),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: ySans(
                              size: 36,
                              weight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: yInk,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Elige el color de acento de tu space. Lo veras en tarjetas, etiquetas y cabeceras.',
                            style: yBody(size: 14, color: yInk),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    SizedBox(
                      width: 300,
                      child: _LabPreviewColumn(
                        name: widget.spaceName,
                        color: _selectedColor,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 2, color: yBorderStrong),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(34, 18, 34, 12),
                  child: _LabPaletteGrid(
                    selected: _selectedColor,
                    onChanged:
                        (color) => setState(() => _selectedColor = color),
                  ),
                ),
              ),
              Container(height: 2, color: yBorderStrong),
              Padding(
                padding: const EdgeInsets.fromLTRB(34, 18, 34, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 150,
                      child: _DialogButton(
                        label: 'Cancelar',
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 190,
                      child: _DialogButton(
                        label: 'Aplicar color',
                        accent: _selectedColor,
                        onTap: () => Navigator.pop(context, _selectedColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _DialogHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: ySans(
              size: 44,
              weight: FontWeight.w800,
              letterSpacing: -0.6,
              color: yInk,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child: const Icon(YuLiIcons.close, size: 22, color: yInk),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: yMono(
        size: 12,
        weight: FontWeight.w700,
        tracking: 2.2,
        color: yInk,
      ),
    );
  }
}

class _LabPaletteRows extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const _LabPaletteRows({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final sections =
        folderPaletteSections
            .where(
              (section) =>
                  section.label != 'ROSAS · VINO' &&
                  section.label != 'TIERRA · MOCHA',
            )
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Color de acento'),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final section in sections) ...[
                  _PaletteRow(
                    label: section.label,
                    colors: section.colors.take(6).toList(),
                    selected: selected,
                    onChanged: onChanged,
                  ),
                  const SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabPaletteGrid extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const _LabPaletteGrid({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final sections = folderPaletteSections;
    return SingleChildScrollView(
      child: Wrap(
        spacing: 30,
        runSpacing: 20,
        children: [
          for (final section in sections)
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.label
                        .replaceAll(' · VINO', '')
                        .replaceAll(' · MOCHA', ''),
                    style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 2.0,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 11,
                    runSpacing: 9,
                    children: [
                      for (final color in section.colors.take(6))
                        _ColorSwatch(
                          color: color,
                          selected: color.toARGB32() == selected.toARGB32(),
                          onTap: () => onChanged(color),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onChanged;

  const _PaletteRow({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              tracking: 1.6,
              color: yMuted,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 11,
            runSpacing: 9,
            children: [
              for (final color in colors)
                _ColorSwatch(
                  color: color,
                  selected: color.toARGB32() == selected.toARGB32(),
                  onTap: () => onChanged(color),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final checkColor = color.computeLuminance() > 0.5 ? yInk : yCream;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        padding: selected ? const EdgeInsets.all(3) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: selected ? yCream : color,
          border: Border.all(
            color: yBorderStrong,
            width: selected ? yLineMid : yLineThin,
          ),
        ),
        child: Container(
          color: color,
          alignment: Alignment.center,
          child:
              selected
                  ? Icon(YuLiIcons.check, size: 18, color: checkColor)
                  : null,
        ),
      ),
    );
  }
}

class _LabPreviewColumn extends StatelessWidget {
  final String name;
  final Color color;
  final String? subtitle;
  final bool compact;

  const _LabPreviewColumn({
    required this.name,
    required this.color,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredCardHeight = compact ? 116.0 : 260.0;
        final headerHeight = subtitle == null ? 30.0 : 46.0;
        final availableHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : desiredCardHeight + headerHeight;
        final cardHeight = math.min(
          desiredCardHeight,
          math.max(74.0, availableHeight - headerHeight),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Vista previa',
              style: yMono(
                size: 12,
                weight: FontWeight.w700,
                tracking: 2.0,
                color: yInk,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yMono(size: 10, weight: FontWeight.w700, color: yInk),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: cardHeight,
              width: double.infinity,
              child: FittedBox(
                alignment: Alignment.topCenter,
                fit: BoxFit.contain,
                child: SizedBox(
                  width:
                      constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 330,
                  height: desiredCardHeight,
                  child: _LabSpacePreviewCard(
                    name: name,
                    color: color,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LabSpacePreviewCard extends StatelessWidget {
  final String name;
  final Color color;
  final bool compact;

  const _LabSpacePreviewCard({
    required this.name,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 116.0 : 260.0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: compact ? 8 : 12,
            decoration: BoxDecoration(
              color: color,
              border: const Border(
                bottom: BorderSide(color: yBorderStrong, width: yLineMid),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, compact ? 10 : 14, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPACE',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.5,
                    color: yMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: ySans(
                    size: compact ? 19 : 23,
                    weight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: yInk,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: Text(
                    'Sin fechas',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w800,
                      tracking: 0.4,
                      color: yCream,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const Divider(height: 1, thickness: yLineMid, color: yBorderStrong),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '> DISTRIBUCION',
                        style: yMono(size: 10, color: yMuted, tracking: 1.4),
                      ),
                      Text(
                        '0 TAREAS',
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: yCream,
                      border: Border.all(color: yBorderStrong, width: 1.5),
                    ),
                    child: ClipRect(
                      child: CustomPaint(painter: _PreviewHatchPainter()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _LegendItem(label: 'BACKLOG 00', color: yMuted),
                      _LegendItem(label: 'EN PROCESO 00', color: color),
                      _LegendItem(label: 'ENTREGADO 00', color: yLab),
                      _LegendItem(label: 'VENCIDO 00', color: yFight),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      _PreviewStat(value: '0', label: 'Abiertas'),
                      SizedBox(width: 14),
                      _PreviewStat(value: '0', label: 'Vencidas'),
                      SizedBox(width: 14),
                      _PreviewStat(value: '0', label: 'Hechas'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: yBorderStrong, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: yMono(
            size: 9,
            weight: FontWeight.w700,
            tracking: 0.6,
            color: yInk,
          ),
        ),
      ],
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final String value;
  final String label;

  const _PreviewStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: ySans(size: 19, weight: FontWeight.w800, color: yInk),
        ),
        const SizedBox(width: 4),
        Text(label, style: yMono(size: 10, color: yMuted, tracking: 0.3)),
      ],
    );
  }
}

class _PreviewHatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = yBorderStrong.withValues(alpha: 0.18)
          ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color? accent;
  final IconData? trailingIcon;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    this.accent,
    this.trailingIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = accent != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yMono(
                  size: 13,
                  weight: FontWeight.w800,
                  tracking: 2.2,
                  color: primary ? yCream : yInk,
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 18),
              Icon(trailingIcon, size: 22, color: primary ? yCream : yInk),
            ],
          ],
        ),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(double width) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: yBorderStrong, width: width),
  );
}
