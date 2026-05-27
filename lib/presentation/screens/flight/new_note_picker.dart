import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
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
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nueva nota',
                style: ySans(
                  size: 22,
                  weight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: yInk,
                )),
            const SizedBox(height: 4),
            Text('Elige el tipo',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted,
                )),
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
                    onTap: () =>
                        Navigator.pop(context, NoteKind.block),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _KindOption(
                    label: 'CUADERNO',
                    sublabel: 'PÁGINAS',
                    description:
                        'Páginas A4 apiladas. Dibujo con stylus.',
                    icon: '▤',
                    accent: yAmber,
                    onTap: () =>
                        Navigator.pop(context, NoteKind.notebook),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _KindOption(
                    label: 'PIZARRA',
                    sublabel: 'INFINITA',
                    description:
                        'Canvas infinito. Solo dibujo. Pan + zoom.',
                    icon: '✎',
                    accent: yLab,
                    onTap: () =>
                        Navigator.pop(context, NoteKind.whiteboard),
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
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 80,
              alignment: Alignment.center,
              color: accent,
              child: Text(icon,
                  style: ySans(
                    size: 44,
                    weight: FontWeight.w700,
                    color: yCream,
                    height: 1.0,
                  )),
            ),
            Container(height: 2, color: yInk),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(label,
                          style: ySans(
                            size: 24,
                            weight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: yInk,
                          )),
                      const SizedBox(width: 6),
                      Text(sublabel,
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w700,
                            tracking: 1.4,
                            color: yMuted,
                          )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description,
                      style: yBody(
                        size: 12,
                        color: yInk2,
                        height: 1.4,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
