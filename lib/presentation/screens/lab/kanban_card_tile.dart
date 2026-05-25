import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';
import '../../../domain/models/kanban_card.dart';

class KanbanCardTile extends StatelessWidget {
  final KanbanCard card;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isSelected;
  final bool selectionMode;

  const KanbanCardTile({
    super.key,
    required this.card,
    required this.accentColor,
    required this.onTap,
    this.isSelected = false,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final priorityColor = _priorityColor(card.priority);
    final ink = inkColor(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withAlpha(30)
                : cardBackground(context),
            border: Border.all(
              color: isSelected ? accentColor : ink,
              width: isSelected ? borderWidthHeavy : borderWidth,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Priority indicator bar
                Container(
                  width: 4,
                  color: isSelected ? accentColor : priorityColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (card.originFolderColor != null)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                color: Color(card.originFolderColor!),
                              ),
                            Expanded(
                              child: Text(
                                card.title,
                                style: bodyM.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: card.originTaskDoneAt != null
                                    ? accentLab
                                    : (card.originFolderColor != null
                                        ? Color(card.originFolderColor!)
                                        : accentFight),
                                border: Border.all(color: inkBlack, width: borderWidth),
                                boxShadow: const [
                                  BoxShadow(
                                    color: inkBlack,
                                    offset: shadowOffset,
                                    blurRadius: shadowBlurRadius,
                                  ),
                                ],
                              ),
                              child: Text(
                                  card.originTaskDoneAt != null ? 'Hecho' : 'Tarea',
                                  style: labelBold.copyWith(
                                      color: paperLight, fontSize: 9)),
                            ),
                          ),
                        if (card.dueDate != null && card.originTaskDoneAt == null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: card.dueDate!.isBefore(DateTime.now())
                                  ? accentFight
                                  : folderPalette[3],
                              border: Border.all(color: inkBlack, width: borderWidth),
                              boxShadow: const [
                                BoxShadow(
                                  color: inkBlack,
                                  offset: shadowOffset,
                                  blurRadius: shadowBlurRadius,
                                ),
                              ],
                            ),
                            child: Text(
                              _formatDate(card.dueDate!),
                              style: labelBold.copyWith(
                                color: paperLight,
                                fontSize: 9,
                              ),
                            ),
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
                if (selectionMode)
                  Container(
                    width: 32,
                    color: isSelected ? accentColor : Colors.transparent,
                    child: Center(
                      child: Icon(
                        isSelected ? Icons.check : Icons.check_box_outline_blank,
                        size: 14,
                        color: isSelected ? paperLight : inkGray,
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
