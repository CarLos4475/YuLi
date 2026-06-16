import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/note.dart';

Future<NewNoteDetails?> showNewNoteDialog(
  BuildContext context, {
  required Color folderAccent,
}) {
  return showDialog<NewNoteDetails>(
    context: context,
    builder:
        (context) => MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: _NewNoteDialog(folderAccent: folderAccent),
        ),
  );
}

class _NewNoteDialog extends StatefulWidget {
  final Color folderAccent;

  const _NewNoteDialog({required this.folderAccent});

  @override
  State<_NewNoteDialog> createState() => _NewNoteDialogState();
}

class _NewNoteDialogState extends State<_NewNoteDialog> {
  final _nameCtrl = TextEditingController();
  NoteKind _selectedKind = NoteKind.notebook;
  late Color _selectedColor = widget.folderAccent;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screen.width - 28, 690.0);
    final dialogHeight = math.min(screen.height - 28, 720.0);

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
            boxShadow: const [
              BoxShadow(
                color: yBorderStrong,
                offset: Offset(5, 5),
                blurRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                accent: widget.folderAccent,
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                style: ySans(size: 22, weight: FontWeight.w700, color: yInk),
                decoration: InputDecoration(
                  hintText: 'Nombre de la nota',
                  hintStyle: ySans(
                    size: 22,
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
                onSubmitted: (_) => _doCreate(),
              ),
              const SizedBox(height: 18),
              _SectionLabel('Tipo'),
              const SizedBox(height: 10),
              _KindSelector(
                selected: _selectedKind,
                accent: widget.folderAccent,
                onChanged: (kind) => setState(() => _selectedKind = kind),
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: yBorderSoft),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 590;
                    final palette = _PaletteGrid(
                      selected: _selectedColor,
                      onChanged:
                          (color) => setState(() => _selectedColor = color),
                    );
                    final preview = _PreviewColumn(
                      kind: _selectedKind,
                      color: _selectedColor,
                      title: _previewTitle,
                    );
                    if (!wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: palette),
                          const SizedBox(width: 16),
                          SizedBox(width: 160, child: preview),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: palette),
                        const SizedBox(width: 30),
                        SizedBox(width: 178, child: preview),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: yBorderSoft),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _DialogButton(
                    label: 'Cancelar',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 18),
                  _DialogButton(
                    label: 'Crear nota',
                    accent: widget.folderAccent,
                    onTap: _doCreate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _previewTitle {
    final text = _nameCtrl.text.trim();
    if (text.isNotEmpty) return text;
    return 'Nombre';
  }

  void _doCreate() {
    Navigator.pop(
      context,
      NewNoteDetails(
        kind: _selectedKind,
        title: _nameCtrl.text.trim(),
        color: _selectedColor,
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

class _Header extends StatelessWidget {
  final Color accent;
  final VoidCallback onClose;

  const _Header({required this.accent, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: Text(
                  'NUEVA NOTA',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 2.0,
                    color: yCream,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Nueva nota',
                style: ySans(
                  size: 36,
                  weight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child: const Icon(YuLiIcons.close, size: 23, color: yInk),
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
        size: 11,
        weight: FontWeight.w700,
        tracking: 1.8,
        color: yInk,
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  final NoteKind selected;
  final Color accent;
  final ValueChanged<NoteKind> onChanged;

  const _KindSelector({
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KindButton(
            label: 'Cuaderno',
            icon: YuLiIcons.notebook,
            kind: NoteKind.notebook,
            accent: accent,
            selected: selected == NoteKind.notebook,
            onTap: onChanged,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _KindButton(
            label: 'Pizarra',
            icon: YuLiIcons.pencil,
            kind: NoteKind.whiteboard,
            accent: accent,
            selected: selected == NoteKind.whiteboard,
            onTap: onChanged,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _KindButton(
            label: 'Nota',
            icon: YuLiIcons.fileText,
            kind: NoteKind.block,
            accent: accent,
            selected: selected == NoteKind.block,
            onTap: onChanged,
          ),
        ),
      ],
    );
  }
}

class _KindButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final NoteKind kind;
  final Color accent;
  final bool selected;
  final ValueChanged<NoteKind> onTap;

  const _KindButton({
    required this.label,
    required this.icon,
    required this.kind,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? yCream : yInk;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(kind),
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: yBody(
                  size: 15,
                  weight: FontWeight.w700,
                  color: fg,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteGrid extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const _PaletteGrid({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Color'),
        const SizedBox(height: 12),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final section in folderPaletteSections) ...[
                    _PaletteRow(
                      label: section.label,
                      colors: section.colors,
                      selected: selected,
                      onChanged: onChanged,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          height: 26,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: yInk,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 7,
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
        width: 28,
        height: 26,
        padding: selected ? const EdgeInsets.all(2) : EdgeInsets.zero,
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
                  ? Icon(YuLiIcons.check, size: 16, color: checkColor)
                  : null,
        ),
      ),
    );
  }
}

class _PreviewColumn extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  final String title;

  const _PreviewColumn({
    required this.kind,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = math.max(160.0, constraints.maxHeight - 28);
        final cardHeight = math.min(252.0, maxCardHeight);
        final scale = cardHeight / 252.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('Vista previa'),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 156 * scale,
                height: cardHeight,
                child: FittedBox(
                  alignment: Alignment.topCenter,
                  fit: BoxFit.contain,
                  child: _PreviewCard(kind: kind, color: color, title: title),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  final String title;

  const _PreviewCard({
    required this.kind,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      height: 252,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 10,
            top: 12,
            child: CustomPaint(
              size: const Size(148, 240),
              painter: _PreviewShadowPainter(kind: kind),
            ),
          ),
          Positioned.fill(
            right: 8,
            bottom: 8,
            child: CustomPaint(
              painter: _PreviewShapePainter(kind: kind, color: color),
            ),
          ),
          Positioned.fill(
            right: 8,
            bottom: 8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
              child: _PreviewContent(kind: kind, color: color, title: title),
            ),
          ),
          if (kind == NoteKind.notebook)
            for (var i = 0; i < 7; i++)
              Positioned(
                left: -2,
                top: 34 + i * 28,
                child: Container(
                  width: 26,
                  height: 11,
                  decoration: BoxDecoration(
                    color: yBorderStrong,
                    border: Border.all(color: yBorderStrong, width: 1),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  final String title;

  const _PreviewContent({
    required this.kind,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      NoteKind.notebook => 'CUADERNO',
      NoteKind.whiteboard => 'PIZARRA',
      NoteKind.block => 'NOTA',
    };
    final icon = switch (kind) {
      NoteKind.notebook => YuLiIcons.notebook,
      NoteKind.whiteboard => YuLiIcons.pencil,
      NoteKind.block => YuLiIcons.fileText,
    };
    final hex =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: yCream, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: yCream),
              const SizedBox(width: 5),
              Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yCream,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ySans(
            size: 21,
            weight: FontWeight.w800,
            letterSpacing: -0.2,
            color: yCream,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        if (kind == NoteKind.notebook) ...[
          _PreviewLine(label: 'Paginas', value: '01'),
          _PreviewRule(),
          _PreviewLine(label: 'Color', value: hex),
          _PreviewRule(),
          const _PreviewLine(label: 'Patron', value: 'Blanco'),
        ] else if (kind == NoteKind.whiteboard) ...[
          const Text(
            'Lienzo infinito',
            style: TextStyle(
              color: yCream,
              fontFamily: 'SpaceMono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pan + zoom',
            style: TextStyle(
              color: yCream,
              fontFamily: 'SpaceMono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ] else ...[
          const Text(
            'Texto y bloques para capturar ideas, listas y apuntes.',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: yCream,
              fontSize: 12,
              fontFamily: 'SpaceMono',
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ],
        const Spacer(),
        Container(height: 1, color: yCream.withValues(alpha: 0.45)),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'HACE 0M',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.5,
                color: yCream,
              ),
            ),
            const Spacer(),
            Text(
              kind == NoteKind.notebook
                  ? '01 P'
                  : kind == NoteKind.whiteboard
                  ? '00 EL'
                  : '0B',
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.5,
                color: yCream,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label\n$value',
      style: yMono(
        size: 10,
        weight: FontWeight.w700,
        tracking: 1.5,
        color: yCream.withValues(alpha: 0.84),
      ).copyWith(height: 1.22),
    );
  }
}

class _PreviewRule extends StatelessWidget {
  const _PreviewRule();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      height: 1,
      color: yCream.withValues(alpha: 0.26),
    );
  }
}

class _PreviewShapePainter extends CustomPainter {
  final NoteKind kind;
  final Color color;

  const _PreviewShapePainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..color = yBorderStrong;
    final fillPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color;

    final path = switch (kind) {
      NoteKind.block => _notePath(size),
      _ => Path()..addRect(Offset.zero & size),
    };
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);

    if (kind == NoteKind.block) _paintFold(canvas, size, borderPaint);
    if (kind == NoteKind.whiteboard) _paintWhiteboardMarks(canvas, size);
    if (kind == NoteKind.notebook) _paintNotebookLines(canvas, size);
  }

  Path _notePath(Size size) {
    const fold = 36.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  void _paintFold(Canvas canvas, Size size, Paint borderPaint) {
    const fold = 36.0;
    final foldPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yCream;
    final foldPath =
        Path()
          ..moveTo(size.width - fold, 0)
          ..lineTo(size.width - fold, fold)
          ..lineTo(size.width, fold)
          ..close();
    canvas.drawPath(foldPath, foldPaint);
    canvas.drawPath(
      Path()
        ..moveTo(size.width - fold, 0)
        ..lineTo(size.width - fold, fold)
        ..lineTo(size.width, fold),
      borderPaint,
    );
  }

  void _paintNotebookLines(Canvas canvas, Size size) {
    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = yCream.withValues(alpha: 0.2);
    for (var y = 126.0; y < size.height - 58; y += 18) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 18, y), linePaint);
    }
    canvas.drawLine(
      const Offset(34, 104),
      Offset(34, size.height - 62),
      linePaint,
    );
  }

  void _paintWhiteboardMarks(Canvas canvas, Size size) {
    final dotPaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yCream.withValues(alpha: 0.12);
    for (var x = 20.0; x < size.width - 18; x += 16) {
      for (var y = 20.0; y < size.height - 48; y += 16) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    final markPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.square
          ..color = yCream.withValues(alpha: 0.72);
    canvas.drawRect(Rect.fromLTWH(42, 102, 44, 40), markPaint);
    canvas.drawLine(const Offset(96, 122), const Offset(132, 122), markPaint);
    canvas.drawCircle(const Offset(144, 122), 26, markPaint);
    canvas.drawLine(const Offset(134, 108), const Offset(154, 136), markPaint);
    canvas.drawLine(const Offset(154, 108), const Offset(134, 136), markPaint);
  }

  @override
  bool shouldRepaint(covariant _PreviewShapePainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

class _PreviewShadowPainter extends CustomPainter {
  final NoteKind kind;

  const _PreviewShadowPainter({required this.kind});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = yBorderStrong;
    final path = switch (kind) {
      NoteKind.block => _notePath(size),
      _ => Path()..addRect(Offset.zero & size),
    };
    canvas.drawPath(path, paint);
  }

  Path _notePath(Size size) {
    const fold = 36.0;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _PreviewShadowPainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color? accent;
  final VoidCallback onTap;

  const _DialogButton({required this.label, this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPrimary = accent != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 150),
        height: 54,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: isPrimary ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Text(
          label,
          style: yMono(
            size: 13,
            weight: FontWeight.w700,
            tracking: 2.0,
            color: isPrimary ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

class NewNoteDetails {
  final NoteKind kind;
  final String? title;
  final Color color;

  const NewNoteDetails({required this.kind, this.title, required this.color});
}
