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
    this.sourceNoteId,
    this.sourceAnchor,
    this.originTaskId,
    this.originFolderColor,
    this.originTaskDoneAt,
    required this.createdAt,
  });

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
