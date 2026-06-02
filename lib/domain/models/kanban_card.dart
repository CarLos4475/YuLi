enum CardPriority {
  none,
  low,
  medium,
  high;

  static CardPriority fromString(String value) => switch (value) {
        'none' => none,
        'low' => low,
        'medium' => medium,
        'high' => high,
        _ => throw ArgumentError('Unknown CardPriority: $value'),
      };

  String toDbString() => switch (this) {
        none => 'none',
        low => 'low',
        medium => 'medium',
        high => 'high',
      };
}

class KanbanCard {
  final int id;
  final int labSpaceId;
  final int columnId;
  final String title;
  final String? description;
  final CardPriority priority;
  final int position;
  final DateTime? dueDate;

  /// Lab-only optional planned start. Null → auto (timeline uses [createdAt]).
  final DateTime? startDate;
  final int? sourceNoteId;
  final String? sourceAnchor;
  final int? originTaskId;
  final int? originFolderColor;
  final DateTime? originTaskDoneAt;
  final DateTime createdAt;

  const KanbanCard({
    required this.id,
    required this.labSpaceId,
    required this.columnId,
    required this.title,
    this.description,
    required this.priority,
    required this.position,
    this.dueDate,
    this.startDate,
    this.sourceNoteId,
    this.sourceAnchor,
    this.originTaskId,
    this.originFolderColor,
    this.originTaskDoneAt,
    required this.createdAt,
  });

  /// A card is "done" once it has entered a terminal column (stamped even when
  /// there is no linked task).
  bool get isDone => originTaskDoneAt != null;

  /// Single source of truth for the "vencida" state across the whole Lab UI
  /// (board tile, timeline, calendar, card detail) and mirrored by the expiry
  /// sweep in the DB. A card is overdue when it is NOT done and either sits in
  /// the expired column or its deadline has passed.
  ///
  /// Deadline granularity is UX-driven: a [dueDate] with a real time is honored
  /// exactly, while a date-only deadline (local midnight) means "by the end of
  /// that day" — it only turns overdue once the next day starts, so a card due
  /// "today" is not nagged during its own day.
  bool isOverdue({bool inExpiredColumn = false}) {
    if (isDone) return false;
    if (inExpiredColumn) return true;
    final due = dueDate;
    if (due == null) return false;
    final isMidnight = due.hour == 0 && due.minute == 0 && due.second == 0;
    final deadline =
        isMidnight ? DateTime(due.year, due.month, due.day + 1) : due;
    return DateTime.now().isAfter(deadline);
  }

  KanbanCard copyWith({
    int? id,
    int? labSpaceId,
    int? columnId,
    String? title,
    String? description,
    bool clearDescription = false,
    CardPriority? priority,
    int? position,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? startDate,
    bool clearStartDate = false,
    int? sourceNoteId,
    bool clearSourceNoteId = false,
    String? sourceAnchor,
    bool clearSourceAnchor = false,
    int? originTaskId,
    bool clearOriginTaskId = false,
    int? originFolderColor,
    bool clearOriginFolderColor = false,
    DateTime? originTaskDoneAt,
    bool clearOriginTaskDoneAt = false,
    DateTime? createdAt,
  }) {
    return KanbanCard(
      id: id ?? this.id,
      labSpaceId: labSpaceId ?? this.labSpaceId,
      columnId: columnId ?? this.columnId,
      title: title ?? this.title,
      description:
          clearDescription ? null : (description ?? this.description),
      priority: priority ?? this.priority,
      position: position ?? this.position,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      sourceNoteId:
          clearSourceNoteId ? null : (sourceNoteId ?? this.sourceNoteId),
      sourceAnchor:
          clearSourceAnchor ? null : (sourceAnchor ?? this.sourceAnchor),
      originTaskId:
          clearOriginTaskId ? null : (originTaskId ?? this.originTaskId),
      originFolderColor: clearOriginFolderColor
          ? null
          : (originFolderColor ?? this.originFolderColor),
      originTaskDoneAt: clearOriginTaskDoneAt
          ? null
          : (originTaskDoneAt ?? this.originTaskDoneAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
