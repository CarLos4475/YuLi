import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/note.dart';
import '../../providers/database_providers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'flight_note_preview.dart';

class FlightItemDetails {
  final String name;
  final Color color;
  final NoteKind kind;
  const FlightItemDetails({
    required this.name,
    required this.color,
    required this.kind,
  });
}

Future<FlightItemDetails?> showEditFolderDialog(
  BuildContext context, {
  required String folderName,
  required int noteCount,
  required Color initialColor,
}) {
  return showDialog<FlightItemDetails>(
    context: context,
    builder:
        (_) => FlightItemDialog(
          title: 'Editar carpeta',
          initialName: folderName,
          initialColor: initialColor,
          noteCount: noteCount,
          actionLabel: 'Guardar cambios',
        ),
  );
}

Future<FlightItemDetails?> showEditNoteDialog(
  BuildContext context, {
  required String noteName,
  required NoteKind kind,
  required String excerpt,
  required Color initialColor,
}) {
  return showDialog<FlightItemDetails>(
    context: context,
    builder:
        (_) => FlightItemDialog(
          title: switch (kind) {
            NoteKind.notebook => 'Editar cuaderno',
            NoteKind.whiteboard => 'Editar pizarra',
            NoteKind.block => 'Editar nota',
          },
          initialName: noteName,
          initialColor: initialColor,
          initialKind: kind,
          excerpt: excerpt,
          isNote: true,
          actionLabel: 'Guardar cambios',
        ),
  );
}

class NewFolderDialog extends ConsumerWidget {
  const NewFolderDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FlightItemDialog(
      title: 'Nueva carpeta',
      initialColor: folderPalette.first,
      actionLabel: 'Crear carpeta',
      onSubmit: (details) async {
        final color = details.color;
        final hex =
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        await ref.read(folderRepositoryProvider).create(details.name, hex);
      },
    );
  }
}

class FlightItemDialog extends ConsumerStatefulWidget {
  final String title;
  final String initialName;
  final Color initialColor;
  final NoteKind initialKind;
  final bool isNote;
  final bool chooseKind;
  final bool allowEmptyName;
  final String excerpt;
  final int noteCount;
  final String actionLabel;
  final Future<void> Function(FlightItemDetails)? onSubmit;
  const FlightItemDialog({
    super.key,
    required this.title,
    this.initialName = '',
    required this.initialColor,
    this.initialKind = NoteKind.notebook,
    this.isNote = false,
    this.chooseKind = false,
    this.allowEmptyName = false,
    this.excerpt = '',
    this.noteCount = 0,
    required this.actionLabel,
    this.onSubmit,
  });
  @override
  ConsumerState<FlightItemDialog> createState() => _FlightItemDialogState();
}

class _FlightItemDialogState extends ConsumerState<FlightItemDialog> {
  late final _nameController = TextEditingController(text: widget.initialName);
  late Color _color = widget.initialColor;
  late NoteKind _kind = widget.initialKind;
  bool _saving = false;
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (_saving || (!widget.allowEmptyName && name.isEmpty)) return;
    final details = FlightItemDetails(name: name, color: _color, kind: _kind);
    setState(() => _saving = true);
    try {
      if (widget.onSubmit != null) await widget.onSubmit!(details);
      if (mounted) Navigator.pop(context, details);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(860.0, constraints.maxWidth);
          final compact = width < 600;
          return SizedBox(
            width: width,
            height: math.min(720.0, constraints.maxHeight),
            child: Container(
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
                boxShadow: const [BoxShadow(color: yInk, offset: Offset(5, 5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    decoration: const BoxDecoration(
                      color: yCream2,
                      border: Border(
                        bottom: BorderSide(
                          color: yBorderStrong,
                          width: yLineThin,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          color: _color,
                          child: Icon(
                            widget.isNote
                                ? YuLiIcons.fileText
                                : YuLiIcons.folder,
                            color: yCream,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ySans(
                              size: compact ? 22 : 28,
                              weight: FontWeight.w800,
                              color: yInk,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          icon: const Icon(YuLiIcons.close, color: yInk),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(compact ? 16 : 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('Nombre'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            style: yBody(size: 18, color: yInk),
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText:
                                  widget.isNote
                                      ? 'Nombre de la nota'
                                      : 'Nombre de la carpeta',
                              filled: true,
                              fillColor: yCream2,
                              border: _inputBorder(yBorderStrong),
                              enabledBorder: _inputBorder(yBorderStrong),
                              focusedBorder: _inputBorder(_color),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submit(),
                          ),
                          if (widget.chooseKind) ...[
                            const SizedBox(height: 18),
                            const _SectionLabel('Tipo'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final kind in [
                                  NoteKind.notebook,
                                  NoteKind.whiteboard,
                                  NoteKind.block,
                                ])
                                  _KindChoice(
                                    kind: kind,
                                    selected: _kind == kind,
                                    accent: _color,
                                    onTap: () => setState(() => _kind = kind),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, splitConstraints) {
                              final preview = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _SectionLabel('Vista previa'),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: widget.isNote ? 320 : 290,
                                    child: Center(
                                      child: MediaQuery.withNoTextScaling(
                                        child:
                                            widget.isNote
                                                ? FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: FlightNotePreview(
                                                    title:
                                                        _nameController.text
                                                                .trim()
                                                                .isEmpty
                                                            ? 'Nombre'
                                                            : _nameController
                                                                .text
                                                                .trim(),
                                                    kind: _kind,
                                                    color: _color,
                                                    excerpt: widget.excerpt,
                                                  ),
                                                )
                                                : _FolderPreview(
                                                  title:
                                                      _nameController.text
                                                              .trim()
                                                              .isEmpty
                                                          ? 'Nombre de carpeta'
                                                          : _nameController.text
                                                              .trim(),
                                                  noteCount: widget.noteCount,
                                                  color: _color,
                                                ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              final palette = _FlightPaletteRows(
                                selected: _color,
                                onChanged:
                                    (color) => setState(() => _color = color),
                              );
                              if (splitConstraints.maxWidth < 660) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    preview,
                                    const SizedBox(height: 20),
                                    palette,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: palette),
                                  const SizedBox(width: 24),
                                  Expanded(child: preview),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: yBorderStrong, width: yLineThin),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _DialogButton(
                            label: 'Cancelar',
                            onTap:
                                _saving ? null : () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DialogButton(
                            label:
                                _saving ? 'Guardando...' : widget.actionLabel,
                            accent: _color,
                            onTap:
                                _saving ||
                                        (!widget.allowEmptyName &&
                                            _nameController.text.trim().isEmpty)
                                    ? null
                                    : _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KindChoice extends StatelessWidget {
  final NoteKind kind;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _KindChoice({
    required this.kind,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (kind) {
      NoteKind.notebook => ('Cuaderno', YuLiIcons.notebook),
      NoteKind.whiteboard => ('Pizarra', YuLiIcons.pencil),
      NoteKind.block => ('Nota', YuLiIcons.fileText),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? yCream : yInk),
            const SizedBox(width: 8),
            Text(
              label,
              style: yBody(
                size: 14,
                weight: FontWeight.w700,
                color: selected ? yCream : yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlightPaletteRows extends StatelessWidget {
  final Color selected;
  final ValueChanged<Color> onChanged;
  const _FlightPaletteRows({required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Color'),
        for (final section in folderPaletteSections) ...[
          const SizedBox(height: 12),
          Text(
            section.label,
            style: yMono(
              size: 11,
              weight: FontWeight.w700,
              tracking: 1,
              color: yInk,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in section.colors)
                Semantics(
                  button: true,
                  selected: color.toARGB32() == selected.toARGB32(),
                  label:
                      'Color #${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  child: GestureDetector(
                    onTap: () => onChanged(color),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineThin,
                        ),
                      ),
                      child:
                          color.toARGB32() == selected.toARGB32()
                              ? Icon(
                                YuLiIcons.check,
                                color:
                                    color.computeLuminance() > 0.5
                                        ? yInk
                                        : yCream,
                                size: 20,
                              )
                              : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: yMono(size: 12, weight: FontWeight.w700, tracking: 1.4, color: yInk),
  );
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color? accent;
  final VoidCallback? onTap;
  const _DialogButton({required this.label, this.accent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = accent;
    final foreground =
        color == null || color.computeLuminance() > 0.5 ? yInk : yCream;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: color ?? yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow:
                color == null
                    ? null
                    : const [BoxShadow(color: yInk, offset: Offset(3, 3))],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: yBody(size: 14, weight: FontWeight.w700, color: foreground),
          ),
        ),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: BorderSide(color: color, width: yLineMid),
);

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
          math.min(constraints.maxWidth / 370, constraints.maxHeight / 290),
        );
        final previewLines = noteCount <= 0 ? 0 : math.min(noteCount, 3);
        return SizedBox(
          width: 360 * scale,
          height: 280 * scale,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 280,
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
                      padding: const EdgeInsets.fromLTRB(18, 58, 18, 12),
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
                            height: 64,
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
