import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/kanban_card.dart';

/// Priority → Lab brutalist palette. Single source of truth shared by the
/// board tile, timeline and calendar so a given priority looks identical
/// everywhere. "none" falls back to the muted token.
Color labPriorityColor(CardPriority p) => switch (p) {
      CardPriority.high => yFight,
      CardPriority.medium => yAmber,
      CardPriority.low => yLab,
      CardPriority.none => yMuted,
    };

/// Status accent for bar/dot surfaces (timeline bars, month event-bars, week
/// stripes, "sin fecha" list). Mirrors the resolution order used across the
/// Lab: overdue → done → folder → priority.
Color labCardAccent(KanbanCard c, {bool inExpiredColumn = false}) {
  if (c.isOverdue(inExpiredColumn: inExpiredColumn)) return yFight;
  if (c.isDone) return yCream2;
  if (c.originFolderColor != null) return Color(c.originFolderColor!);
  return labPriorityColor(c.priority);
}
