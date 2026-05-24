import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';
import '../../../domain/models/kanban_card.dart';

class KanbanCardTile extends StatelessWidget {
  final KanbanCard card;
  final Color accentColor;
  final VoidCallback onTap;

  const KanbanCardTile({
    super.key,
    required this.card,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priorityColor = _priorityColor(card.priority);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: cardBackground(context),
            border: Border.all(color: inkColor(context), width: borderWidth),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority indicator bar
                Container(
                  width: 4,
                  color: priorityColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.title,
                          style: bodyM.copyWith(
                            color: inkColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (card.sourceNoteId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.description_outlined,
                                    size: 12, color: accentFlight),
                                const SizedBox(width: 4),
                                Text('Nota',
                                    style: bodyS.copyWith(
                                        color: accentFlight, fontSize: 10)),
                              ],
                            ),
                          ),
                        if (card.originTaskId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.flash_on,
                                    size: 12, color: accentFight),
                                const SizedBox(width: 4),
                                Text('Tarea',
                                    style: bodyS.copyWith(
                                        color: accentFight, fontSize: 10)),
                              ],
                            ),
                          ),
                        if (card.dueDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(card.dueDate!),
                            style: bodyS.copyWith(color: inkGray),
                          ),
                        ],
                        if (card.description != null &&
                            card.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            card.description!
                                .replaceAll(RegExp(r'[#*_`\[\]>\-]'), '')
                                .trim(),
                            style: bodyS.copyWith(color: inkGray.withAlpha(180)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityColor(CardPriority p) => switch (p) {
        CardPriority.none => Colors.transparent,
        CardPriority.low => folderPalette[2], // verde musgo
        CardPriority.medium => folderPalette[3], // ocre
        CardPriority.high => accentFight,
      };

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
