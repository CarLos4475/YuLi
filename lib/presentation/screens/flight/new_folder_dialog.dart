import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart';
import '../../providers/database_providers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

Future<Color?> showFolderColorDialog(
  BuildContext context, {
  required String title,
  required String folderName,
  required int noteCount,
  required Color initialColor,
}) {
  return showDialog<Color>(
    context: context,
    builder:
        (context) => MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: _FlightColorDialog(
            title: title,
            metaLeft: 'CARPETA · $folderName',
            initialColor: initialColor,
            preview:
                (color) => _FolderPreview(
                  title: folderName,
                  noteCount: noteCount,
                  color: color,
                ),
          ),
        ),
  );
}

Future<Color?> showNoteColorDialog(
  BuildContext context, {
  required String title,
  required String noteName,
  required NoteKind kind,
  required String excerpt,
  required Color initialColor,
}) {
  final kindLabel = switch (kind) {
    NoteKind.notebook => 'Cuaderno',
    NoteKind.whiteboard => 'Pizarra',
    NoteKind.block => 'Nota',
  };
  return showDialog<Color>(
    context: context,
    builder:
        (context) => MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: _FlightColorDialog(
            title: title,
            metaLeft: 'NOTA · $noteName',
            metaRight: 'TIPO · $kindLabel',
            initialColor: initialColor,
            preview:
                (color) => _NotePreview(
                  title: noteName,
                  kind: kind,
                  excerpt: excerpt,
                  color: color,
                ),
          ),
        ),
  );
}

class NewFolderDialog extends ConsumerStatefulWidget {
  const NewFolderDialog({super.key});

  @override
  ConsumerState<NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends ConsumerState<NewFolderDialog> {
  final _nameController = TextEditingController();
  Color _selectedColor = folderPalette.first;

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
    await ref.read(folderRepositoryProvider).create(name, hex);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = screen.width < 900 ? screen.width - 28 : 860.0;
    final dialogHeight = screen.height < 700 ? screen.height - 28 : 660.0;

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
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogHeader(
                  title: 'Nueva carpeta',
                  onClose: () => Navigator.pop(context),
                ),
                const SizedBox(height: 12),
                _SectionLabel('Nombre'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  style: ySans(size: 20, weight: FontWeight.w700, color: yInk),
                  decoration: InputDecoration(
                    hintText: 'Nombre de la carpeta',
                    hintStyle: ySans(
                      size: 20,
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
                const SizedBox(height: 14),
                Container(height: yLineThin, color: yBorderStrong),
                const SizedBox(height: 14),
                Expanded(
                  child: _ColorPreviewSplit(
                    selected: _selectedColor,
                    onChanged:
                        (color) => setState(() => _selectedColor = color),
                    preview: _FolderPreview(
                      title: _previewName,
                      noteCount: 0,
                      color: _selectedColor,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(height: yLineThin, color: yBorderStrong),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 210,
                      child: _DialogButton(
                        label: 'Cancelar',
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 280,
                      child: _DialogButton(
                        label: 'Crear carpeta',
                        accent: _selectedColor,
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
    final text = _nameController.text.trim();
    return text.isEmpty ? 'Nombre de carpeta' : text;
  }
}

class _FlightColorDialog extends StatefulWidget {
  final String title;
  final String metaLeft;
  final String? metaRight;
  final Color initialColor;
  final Widget Function(Color color) preview;

  const _FlightColorDialog({
    required this.title,
    required this.metaLeft,
    this.metaRight,
    required this.initialColor,
    required this.preview,
  });

  @override
  State<_FlightColorDialog> createState() => _FlightColorDialogState();
}

class _FlightColorDialogState extends State<_FlightColorDialog> {
  late Color _selectedColor = widget.initialColor;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = screen.width < 900 ? screen.width - 28 : 860.0;
    final dialogHeight = screen.height < 680 ? screen.height - 28 : 635.0;
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
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(
                title: widget.title,
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _MetaText(widget.metaLeft)),
                  if (widget.metaRight != null) _MetaText(widget.metaRight!),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: yLineThin, color: yBorderStrong),
              const SizedBox(height: 14),
              Expanded(
                child: _ColorPreviewSplit(
                  selected: _selectedColor,
                  onChanged: (color) => setState(() => _selectedColor = color),
                  preview: widget.preview(_selectedColor),
                ),
              ),
              const SizedBox(height: 14),
              Container(height: yLineThin, color: yBorderStrong),
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: _DialogButton(
                      label: 'Cancelar',
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 280,
                    child: _DialogButton(
                      label: 'Aplicar color',
                      accent: _selectedColor,
                      onTap: () => Navigator.pop(context, _selectedColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPreviewSplit extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;
  final Widget preview;

  const _ColorPreviewSplit({
    required this.selected,
    required this.onChanged,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paletteWidth = math.min(390.0, constraints.maxWidth * 0.48);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: paletteWidth,
              child: _FlightPaletteRows(
                selected: selected,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 14),
            Container(width: yLineThin, color: yBorderStrong),
            const SizedBox(width: 26),
            Expanded(child: _PreviewPanel(child: preview)),
          ],
        );
      },
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final Widget child;

  const _PreviewPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Vista previa'),
        const SizedBox(height: 16),
        Expanded(child: Center(child: child)),
      ],
    );
  }
}

class _FlightPaletteRows extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;

  const _FlightPaletteRows({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final sections = folderPaletteSections.take(7).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Color'),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final section in sections) ...[
                  _PaletteRow(
                    label: section.label,
                    colors: section.colors.take(7).toList(),
                    selected: selected,
                    onChanged: onChanged,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: yMono(
              size: 11,
              weight: FontWeight.w800,
              tracking: 1.4,
              color: yInk,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
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
        height: 28,
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

class _FolderPreview extends StatelessWidget {
  final String title;
  final int noteCount;
  final Color color;

  const _FolderPreview({
    required this.title,
    required this.noteCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          1.0,
          math.min(constraints.maxWidth / 370, constraints.maxHeight / 230),
        );
        final previewLines = noteCount <= 0 ? 0 : math.min(noteCount, 3);
        return SizedBox(
          width: 360 * scale,
          height: 220 * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 220,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    left: 8,
                    top: 8,
                    right: -8,
                    bottom: -8,
                    child: CustomPaint(
                      painter: _FolderShapePreviewPainter(color: yInk),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FolderShapePreviewPainter(
                        color: color,
                        border: true,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 58, 18, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ySans(
                                    size: 28,
                                    weight: FontWeight.w700,
                                    color: yCream,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'NOTAS',
                                    style: yMono(
                                      size: 9,
                                      weight: FontWeight.w700,
                                      tracking: 1.2,
                                      color: yCream.withValues(alpha: 0.85),
                                    ),
                                  ),
                                  Text(
                                    noteCount.toString().padLeft(2, '0'),
                                    style: yMono(
                                      size: 24,
                                      weight: FontWeight.w700,
                                      tracking: 1,
                                      color: yCream,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            noteCount == 0 ? 'SIN NOTAS' : 'EDITADA HACE 0M',
                            style: yMono(
                              size: 10,
                              tracking: 1.4,
                              color: yCream.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            height: 1.5,
                            color: yCream.withValues(alpha: 0.32),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 54,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var i = 0; i < previewLines; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Opacity(
                                      opacity: 1 - i * 0.18,
                                      child: _MiniLine(
                                        label: 'Ejemplo de nota ${i + 1}',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(height: 2, color: yBorderStrong),
                          SizedBox(
                            height: 44,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ABRIR CARPETA',
                                  style: yMono(
                                    size: 10,
                                    weight: FontWeight.w700,
                                    tracking: 1.4,
                                    color: yCream.withValues(alpha: 0.85),
                                  ),
                                ),
                                Icon(
                                  YuLiIcons.arrowRight,
                                  size: 20,
                                  color: yCream,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniLine extends StatelessWidget {
  final String label;

  const _MiniLine({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          YuLiIcons.chevronRight,
          size: 12,
          color: yCream.withValues(alpha: 0.72),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: yBody(size: 12, color: yCream, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _NotePreview extends StatelessWidget {
  final String title;
  final NoteKind kind;
  final String excerpt;
  final Color color;

  const _NotePreview({
    required this.title,
    required this.kind,
    required this.excerpt,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(1.0, constraints.maxHeight / 300);
        return SizedBox(
          width: 260 * scale,
          height: 300 * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 260,
              height: 300,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 8,
                    top: 8,
                    child: CustomPaint(
                      size: const Size(252, 284),
                      painter: _NoteShapePreviewPainter(
                        kind: kind,
                        color: yInk,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(252, 284),
                      painter: _NoteShapePreviewPainter(
                        kind: kind,
                        color: color,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    left: kind == NoteKind.notebook ? 42 : 22,
                    top: 24,
                    right: kind == NoteKind.block ? 50 : 18,
                    bottom: 56,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _NoteBadge(kind: kind),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ySans(
                            size: 28,
                            weight: FontWeight.w800,
                            color: yCream,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          excerpt.isEmpty ? 'Sin contenido todavia' : excerpt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: yBody(
                            size: 14,
                            weight: FontWeight.w700,
                            color: yCream.withValues(alpha: 0.9),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 8,
                    bottom: 16,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: yCream.withValues(alpha: 0.45),
                            width: 1.4,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'ED. HACE 0M',
                        style: yMono(
                          size: 11,
                          weight: FontWeight.w800,
                          tracking: 1.4,
                          color: yCream,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoteBadge extends StatelessWidget {
  final NoteKind kind;

  const _NoteBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final meta = switch (kind) {
      NoteKind.notebook => (icon: YuLiIcons.notebook, label: 'CUADERNO'),
      NoteKind.whiteboard => (icon: YuLiIcons.pencil, label: 'PIZARRA'),
      NoteKind.block => (icon: YuLiIcons.textInitial, label: 'NOTA'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 9, 4),
      decoration: BoxDecoration(
        color: yCream.withValues(alpha: 0.14),
        border: Border.all(color: yCream, width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 13, color: yCream),
          const SizedBox(width: 6),
          Text(
            meta.label,
            style: yMono(
              size: 10,
              weight: FontWeight.w800,
              tracking: 1.3,
              color: yCream,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderShapePreviewPainter extends CustomPainter {
  final Color color;
  final bool border;

  const _FolderShapePreviewPainter({required this.color, this.border = false});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyTop = size.height * 0.17;
    final tabEnd = size.width * 0.40;
    final tabDrop = size.height * 0.105;
    final path =
        Path()
          ..moveTo(0, bodyTop)
          ..lineTo(16, bodyTop - tabDrop)
          ..lineTo(tabEnd, bodyTop - tabDrop)
          ..lineTo(tabEnd + 34, bodyTop)
          ..lineTo(size.width, bodyTop)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = color);
    if (border) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..strokeJoin = StrokeJoin.round
          ..color = yBorderStrong,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FolderShapePreviewPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.border != border;
  }
}

class _NoteShapePreviewPainter extends CustomPainter {
  final NoteKind kind;
  final Color color;

  const _NoteShapePreviewPainter({required this.kind, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        kind == NoteKind.block
            ? (Path()
              ..moveTo(0, 0)
              ..lineTo(size.width - 58, 0)
              ..lineTo(size.width, 58)
              ..lineTo(size.width, size.height)
              ..lineTo(0, size.height)
              ..close())
            : (Path()..addRect(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = yLineMid
        ..color = yBorderStrong,
    );
    if (kind == NoteKind.block) {
      final fold =
          Path()
            ..moveTo(size.width - 58, 0)
            ..lineTo(size.width - 58, 58)
            ..lineTo(size.width, 58)
            ..close();
      canvas.drawPath(fold, Paint()..color = yCream);
      canvas.drawPath(
        fold,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..color = yBorderStrong,
      );
    }
    if (kind == NoteKind.notebook) {
      final ring = Paint()..color = yBorderStrong;
      for (var i = 0; i < 7; i++) {
        canvas.drawRect(Rect.fromLTWH(-8, 28 + i * 34, 28, 10), ring);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoteShapePreviewPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ySans(
              size: 42,
              weight: FontWeight.w800,
              letterSpacing: 0,
              color: yInk,
            ),
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
            child: const Icon(YuLiIcons.close, size: 22, color: yInk),
          ),
        ),
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  final String text;

  const _MetaText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: yMono(
        size: 12,
        weight: FontWeight.w800,
        tracking: 1.1,
        color: yInk,
      ),
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
        size: 13,
        weight: FontWeight.w800,
        tracking: 1.8,
        color: yInk,
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color? accent;
  final VoidCallback onTap;

  const _DialogButton({required this.label, this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = accent != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
          boxShadow:
              primary
                  ? const [
                    BoxShadow(
                      color: yBorderStrong,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ]
                  : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ySans(
            size: 17,
            weight: FontWeight.w800,
            color: primary ? yInk : yInk,
          ),
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
