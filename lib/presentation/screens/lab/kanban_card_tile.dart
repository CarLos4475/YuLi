import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/kanban_card.dart';

class KanbanCardTile extends StatelessWidget {
  final KanbanCard card;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isSelected;
  final bool selectionMode;
  final bool inExpiredColumn;

  const KanbanCardTile({
    super.key,
    required this.card,
    required this.accentColor,
    required this.onTap,
    this.isSelected = false,
    this.selectionMode = false,
    this.inExpiredColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEndState = card.isDone;
    final folderColor =
        card.originFolderColor != null ? Color(card.originFolderColor!) : null;
    final overdue = card.isOverdue(inExpiredColumn: inExpiredColumn);
    final pColor = _priorityColor();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isEndState ? yCream2 : yCream,
          border: Border.all(
            color: isSelected ? accentColor : yBorderStrong,
            width: isSelected ? yLineHeavy : 2,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pColor != null) Container(width: 5, color: pColor),
              Expanded(
                child: Opacity(
                  opacity: isEndState ? 0.85 : 1.0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pColor != null ? 8 : 12,
                      10,
                      12,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                cleanMention(card.title),
                                style: ySans(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                  color: isEndState ? yMuted : yInk,
                                  height: 1.3,
                                ).copyWith(
                                  decoration:
                                      isEndState
                                          ? TextDecoration.lineThrough
                                          : null,
                                ),
                              ),
                            ),
                            if (selectionMode)
                              Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? accentColor : yCream,
                                  border: Border.all(
                                    color: yBorderStrong,
                                    width: 1.5,
                                  ),
                                ),
                                child:
                                    isSelected
                                        ? const Center(
                                          child: Text(
                                            'v',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: yCream,
                                              fontWeight: FontWeight.w700,
                                              height: 1.0,
                                            ),
                                          ),
                                        )
                                        : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  if (folderColor != null &&
                                      _folderName().isNotEmpty)
                                    Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 5),
                                        padding: const EdgeInsets.fromLTRB(
                                          6,
                                          1,
                                          6,
                                          2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: folderColor,
                                          border: Border.all(
                                            color: yBorderStrong,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Text(
                                          '@${_folderName()}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: yMono(
                                            size: 9,
                                            weight: FontWeight.w700,
                                            color: yCream,
                                            tracking: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (card.originTaskId != null)
                                    _originBadge(isEndState, overdue),
                                  if (card.sourceNoteId != null)
                                    Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      padding: const EdgeInsets.fromLTRB(
                                        6,
                                        1,
                                        6,
                                        2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: yFlight,
                                        border: Border.all(
                                          color: yBorderStrong,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        'NOTA',
                                        style: yMono(
                                          size: 9,
                                          weight: FontWeight.w700,
                                          color: yCream,
                                          tracking: 0.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (card.remindAt != null && !isEndState)
                              const Padding(
                                padding: EdgeInsets.only(right: 5),
                                child: Icon(
                                  Icons.notifications_active,
                                  size: 12,
                                  color: yInk,
                                ),
                              ),
                            if (card.dueDate != null)
                              Text(
                                '${overdue ? "v " : ""}${_formatDue()}',
                                style: yMono(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  tracking: 1,
                                  color: overdue ? yFight : yMuted,
                                ),
                              ),
                          ],
                        ),
                        if (card.description != null &&
                            card.description!.isNotEmpty &&
                            !isEndState) ...[
                          const SizedBox(height: 5),
                          Text(
                            card.description!
                                .replaceAll(RegExp(r'[#*_`\[\]>\-]'), '')
                                .trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: yBody(size: 11, color: yMuted, height: 1.3),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _originBadge(bool isEndState, bool overdue) {
    final String label;
    final Color bg;

    if (isEndState) {
      label = 'HECHO';
      bg = yLab;
    } else if (overdue) {
      label = 'VENCIDO';
      bg = yFight;
    } else {
      label = 'TAREA';
      bg = yAmber;
    }

    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.fromLTRB(6, 1, 6, 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yBorderStrong, width: 1.5),
      ),
      child: Text(
        label,
        style: yMono(
          size: 9,
          weight: FontWeight.w700,
          color: yCream,
          tracking: 0.5,
        ),
      ),
    );
  }

  String _formatDue() {
    final d = card.dueDate!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  String _folderName() {
    final match = RegExp(r'@([a-zA-Z0-9_áéíóúñ]+)').firstMatch(card.title);
    if (match != null) return match.group(1)!;
    return '';
  }

  Color? _priorityColor() {
    switch (card.priority) {
      case CardPriority.high:
        return yFight;
      case CardPriority.medium:
        return yAmber;
      case CardPriority.low:
        return yLab;
      case CardPriority.none:
        return null;
    }
  }
}
