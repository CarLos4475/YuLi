import 'package:flutter/material.dart';

enum LabSpaceStatus {
  active,
  paused,
  completed,
  archived;

  static LabSpaceStatus fromString(String value) => switch (value) {
        'active' => active,
        'paused' => paused,
        'completed' => completed,
        'archived' => archived,
        // Unknown values default to active to keep the app usable across
        // schema additions without crashing.
        _ => active,
      };

  String toDbString() => switch (this) {
        active => 'active',
        paused => 'paused',
        completed => 'completed',
        archived => 'archived',
      };
}

class LabSpace {
  final int id;
  final String name;
  final Color accentColor;
  final LabSpaceStatus status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const LabSpace({
    required this.id,
    required this.name,
    required this.accentColor,
    required this.status,
    this.startDate,
    this.dueDate,
    required this.createdAt,
    this.deletedAt,
  });

  bool get isActive => deletedAt == null;

  LabSpace copyWith({
    int? id,
    String? name,
    Color? accentColor,
    LabSpaceStatus? status,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? createdAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return LabSpace(
      id: id ?? this.id,
      name: name ?? this.name,
      accentColor: accentColor ?? this.accentColor,
      status: status ?? this.status,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      createdAt: createdAt ?? this.createdAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
