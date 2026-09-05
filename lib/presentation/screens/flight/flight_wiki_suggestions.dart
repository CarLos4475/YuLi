import 'package:flutter/material.dart';

import '../../../domain/models/note.dart';
import '../../providers/flight_workspace_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

class FlightWikiLinkSuggestions extends StatelessWidget {
  final String query;
  final Future<List<FlightWorkspaceTarget>> matches;
  final Color accent;
  final ValueChanged<FlightWorkspaceTarget> onSelect;
  final ValueChanged<NoteKind> onCreate;

  const FlightWikiLinkSuggestions({
    super.key,
    required this.query,
    required this.matches,
    required this.accent,
    required this.onSelect,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, right: 20),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 250),
        child: FutureBuilder<List<FlightWorkspaceTarget>>(
          future: matches,
          builder: (context, snapshot) {
            final targets = snapshot.data ?? const <FlightWorkspaceTarget>[];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final target in targets)
                    _FlightWikiSuggestionRow(
                      icon: flightWikiKindIcon(target.kind),
                      title: target.label,
                      subtitle: target.folderLabel,
                      accent: target.folderColor ?? accent,
                      onTap: () => onSelect(target),
                    ),
                  if (query.trim().isNotEmpty) ...[
                    _FlightWikiSuggestionRow(
                      icon: YuLiIcons.fileText,
                      title: 'Crear nota “${query.trim()}”',
                      subtitle: 'NOTA EN ESTA CARPETA',
                      accent: accent,
                      onTap: () => onCreate(NoteKind.block),
                    ),
                    _FlightWikiSuggestionRow(
                      icon: YuLiIcons.layoutGrid,
                      title: 'Crear pizarra “${query.trim()}”',
                      subtitle: 'PIZARRA EN ESTA CARPETA',
                      accent: accent,
                      onTap: () => onCreate(NoteKind.whiteboard),
                    ),
                    _FlightWikiSuggestionRow(
                      icon: YuLiIcons.notebook,
                      title: 'Crear cuaderno “${query.trim()}”',
                      subtitle: 'CUADERNO EN ESTA CARPETA',
                      accent: accent,
                      onTap: () => onCreate(NoteKind.notebook),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FlightWikiSuggestionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _FlightWikiSuggestionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          border: const Border(
            bottom: BorderSide(color: yBorderSoft, width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(width: 4, height: 28, color: accent),
            const SizedBox(width: 8),
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: yInk,
                    ),
                  ),
                  Text(subtitle, style: yMono(size: 8, color: yMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData flightWikiKindIcon(NoteKind kind) => switch (kind) {
  NoteKind.block => YuLiIcons.fileText,
  NoteKind.whiteboard => YuLiIcons.layoutGrid,
  NoteKind.notebook => YuLiIcons.notebook,
};
