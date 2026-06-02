import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/app_tokens.dart';
import '../../../domain/models/note.dart';

Future<NoteKind?> showNewNotePicker(BuildContext context) {
  return showDialog<NoteKind>(
    context: context,
    builder: (_) => const _NewNotePickerDialog(),
  );
}

class _NewNotePickerDialog extends StatelessWidget {
  const _NewNotePickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.fromLTRB(10, 18, 10, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nueva nota',
              style: ySans(
                size: 22,
                weight: FontWeight.w700,
                letterSpacing: -0.5,
                color: yInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elige el tipo',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _KindOption(
                    label: 'NOTA',
                    sublabel: 'BLOQUES',
                    description:
                        'Texto, math, listas, dibujos. Bloque a bloque.',
                    icon: 'Tt',
                    accent: yFlight,
                    onTap: () => Navigator.pop(context, NoteKind.block),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _KindOption(
                    label: 'CUADERNO',
                    sublabel: 'PÁGINAS',
                    description: 'Páginas A4 apiladas. Dibujo con stylus.',
                    icon: '\u25A4',
                    accent: yAmber,
                    onTap: () => Navigator.pop(context, NoteKind.notebook),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _KindOption(
                    label: 'PIZARRA',
                    sublabel: 'INFINITA',
                    description: 'Canvas infinito. Solo dibujo. Pan + zoom.',
                    icon: '\u270E',
                    accent: yLab,
                    onTap: () => Navigator.pop(context, NoteKind.whiteboard),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final String description;
  final String icon;
  final Color accent;
  final VoidCallback onTap;

  const _KindOption({
    required this.label,
    required this.sublabel,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 80,
              alignment: Alignment.center,
              color: accent,
              child: Text(
                icon,
                style: ySans(
                  size: 38,
                  weight: FontWeight.w700,
                  color: yCream,
                  height: 1.0,
                ),
              ),
            ),
            Container(height: 2, color: yBorderStrong),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: ySans(
                            size: 24,
                            weight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: yInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sublabel,
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 3,
                    style: yBody(size: 12, color: yInk2, height: 1.4),
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

class _NewNoteDetails extends StatefulWidget {
  final NoteKind kind;

  const _NewNoteDetails({required this.kind});

  @override
  State<_NewNoteDetails> createState() => _NewNoteDetailsState();
}

class _NewNoteDetailsState extends State<_NewNoteDetails> {
  final _nameCtrl = TextEditingController();
  Color _selectedColor = folderPalette[1];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kindLabel = switch (widget.kind) {
      NoteKind.block => 'NOTA',
      NoteKind.notebook => 'CUADERNO',
      NoteKind.whiteboard => 'PIZARRA',
    };
    final kindColor = switch (widget.kind) {
      NoteKind.block => yFlight,
      NoteKind.notebook => yAmber,
      NoteKind.whiteboard => yLab,
    };

    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: kindColor,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: Text(
                    kindLabel,
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yCream,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: ySans(size: 18, weight: FontWeight.w600, color: yInk),
              decoration: InputDecoration(
                hintText: 'Nombre',
                hintStyle: ySans(
                  size: 18,
                  weight: FontWeight.w600,
                  color: yInk.withValues(alpha: 0.3),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: yLineThin,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: yBorderStrong,
                    width: yLineThin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _doCreate(),
            ),
            const SizedBox(height: 14),
            Text(
              'Color',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  folderPalette.map((c) {
                    final sel = c == _selectedColor;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c,
                          border: Border.all(
                            color: sel ? yBorderStrong : Colors.transparent,
                            width: yLineHeavy,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Text(
                      'Cancelar',
                      style: yMono(
                        size: 11,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _doCreate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: kindColor,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: Text(
                      'Crear',
                      style: yBody(
                        size: 13,
                        weight: FontWeight.w700,
                        color: yCream,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _doCreate() {
    Navigator.pop(
      context,
      NewNoteDetails(title: _nameCtrl.text.trim(), color: _selectedColor),
    );
  }
}

Future<NewNoteDetails?> showNewNoteDetailsDialog(
  BuildContext context,
  NoteKind kind,
) {
  return showDialog<NewNoteDetails>(
    context: context,
    builder: (_) => _NewNoteDetails(kind: kind),
  );
}

class NewNoteDetails {
  final String? title;
  final Color color;
  const NewNoteDetails({this.title, required this.color});
}
