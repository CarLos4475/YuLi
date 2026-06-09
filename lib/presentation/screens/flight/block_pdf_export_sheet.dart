import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

enum BlockPdfPageSize { a4, letter }

enum BlockPdfOrientation { portrait, landscape }

enum BlockPdfMargins { normal, compact, wide }

class BlockPdfExportOptions {
  final BlockPdfPageSize pageSize;
  final BlockPdfOrientation orientation;
  final BlockPdfMargins margins;
  final bool includeTitle;
  final bool includeTasks;

  const BlockPdfExportOptions({
    required this.pageSize,
    required this.orientation,
    required this.margins,
    required this.includeTitle,
    required this.includeTasks,
  });
}

Future<BlockPdfExportOptions?> showBlockPdfExportSheet(
  BuildContext context, {
  required Color accent,
  required bool hasTasks,
}) {
  return showModalBottomSheet<BlockPdfExportOptions>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _BlockPdfExportSheet(accent: accent, hasTasks: hasTasks),
  );
}

class _BlockPdfExportSheet extends StatefulWidget {
  final Color accent;
  final bool hasTasks;

  const _BlockPdfExportSheet({required this.accent, required this.hasTasks});

  @override
  State<_BlockPdfExportSheet> createState() => _BlockPdfExportSheetState();
}

class _BlockPdfExportSheetState extends State<_BlockPdfExportSheet> {
  BlockPdfPageSize _pageSize = BlockPdfPageSize.a4;
  BlockPdfOrientation _orientation = BlockPdfOrientation.portrait;
  BlockPdfMargins _margins = BlockPdfMargins.normal;
  bool _includeTitle = true;
  bool _includeTasks = true;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border: Border(
            top: BorderSide(color: yBorderStrong, width: yLineHeavy),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'EXPORTAR NOTA',
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.6,
                  color: yMuted,
                ),
              ),
              const SizedBox(height: 14),
              const _SectionLabel('PAPEL'),
              _Segmented<BlockPdfPageSize>(
                accent: widget.accent,
                value: _pageSize,
                options: const [
                  (BlockPdfPageSize.a4, 'A4', YuLiIcons.fileText),
                  (BlockPdfPageSize.letter, 'CARTA', YuLiIcons.fileText),
                ],
                onChanged: (v) => setState(() => _pageSize = v),
              ),
              const SizedBox(height: 14),
              _Segmented<BlockPdfOrientation>(
                accent: widget.accent,
                value: _orientation,
                options: const [
                  (BlockPdfOrientation.portrait, 'VERTICAL', YuLiIcons.arrowUp),
                  (
                    BlockPdfOrientation.landscape,
                    'HORIZONTAL',
                    YuLiIcons.arrowRight,
                  ),
                ],
                onChanged: (v) => setState(() => _orientation = v),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('MARGEN'),
              _Segmented<BlockPdfMargins>(
                accent: widget.accent,
                value: _margins,
                options: const [
                  (BlockPdfMargins.compact, 'CHICO', YuLiIcons.minus),
                  (BlockPdfMargins.normal, 'NORMAL', YuLiIcons.square),
                  (BlockPdfMargins.wide, 'AMPLIO', YuLiIcons.plus),
                ],
                onChanged: (v) => setState(() => _margins = v),
              ),
              const SizedBox(height: 16),
              const _SectionLabel('CONTENIDO'),
              _ToggleRow(
                label: 'Incluir titulo',
                value: _includeTitle,
                accent: widget.accent,
                onChanged: (v) => setState(() => _includeTitle = v),
              ),
              if (widget.hasTasks) ...[
                const SizedBox(height: 10),
                _ToggleRow(
                  label: 'Incluir tareas',
                  value: _includeTasks,
                  accent: widget.accent,
                  onChanged: (v) => setState(() => _includeTasks = v),
                ),
              ],
              const SizedBox(height: 18),
              _ConfirmBtn(
                accent: widget.accent,
                label: 'EXPORTAR',
                onTap:
                    () => Navigator.pop(
                      context,
                      BlockPdfExportOptions(
                        pageSize: _pageSize,
                        orientation: _orientation,
                        margins: _margins,
                        includeTitle: _includeTitle,
                        includeTasks: _includeTasks,
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: yMono(
        size: 9,
        weight: FontWeight.w700,
        tracking: 1.4,
        color: yInk,
      ),
    ),
  );
}

class _Segmented<T> extends StatelessWidget {
  final List<(T, String, IconData)> options;
  final T value;
  final Color accent;
  final ValueChanged<T> onChanged;

  const _Segmented({
    required this.options,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in options) ...[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(option.$1);
              },
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == option.$1 ? accent : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      option.$3,
                      size: 15,
                      color: value == option.$1 ? yCream : yInk,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        option.$2,
                        overflow: TextOverflow.ellipsis,
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1,
                          color: value == option.$1 ? yCream : yInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (option != options.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? accent : yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child:
                value
                    ? const Icon(YuLiIcons.check, size: 15, color: yCream)
                    : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: yBody(size: 14, color: yInk))),
        ],
      ),
    );
  }
}

class _ConfirmBtn extends StatelessWidget {
  final Color accent;
  final String label;
  final VoidCallback onTap;

  const _ConfirmBtn({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [
            BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
          ],
        ),
        child: Text(
          label,
          style: yMono(
            size: 12,
            weight: FontWeight.w700,
            tracking: 1.4,
            color: yCream,
          ),
        ),
      ),
    );
  }
}
