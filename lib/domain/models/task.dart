enum TaskStatus {
  pending,
  yesterday,
  archivedFailed,
  done,
  trash;

  static TaskStatus fromString(String value) => switch (value) {
        'pending' => pending,
        'yesterday' => yesterday,
        'archived_failed' => archivedFailed,
        'done' => done,
        'trash' => trash,
        _ => throw ArgumentError('Unknown TaskStatus: $value'),
      };

  String toDbString() => switch (this) {
        pending => 'pending',
        yesterday => 'yesterday',
        archivedFailed => 'archived_failed',
        done => 'done',
        trash => 'trash',
      };
}

class Task {
  final int id;
  final String content;
  final TaskStatus status;
  final int? folderId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? trashedAt;
  final DateTime? dueDate;

  const Task({
    required this.id,
    required this.content,
    required this.status,
    this.folderId,
    required this.createdAt,
    required this.expiresAt,
    this.trashedAt,
    this.dueDate,
  });

  Task copyWith({
    int? id,
    String? content,
    TaskStatus? status,
    int? folderId,
    bool clearFolderId = false,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) {
    return Task(
      id: id ?? this.id,
      content: content ?? this.content,
      status: status ?? this.status,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    );
  }
}
