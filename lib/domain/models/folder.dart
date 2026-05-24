import 'package:flutter/material.dart';

class Folder {
  final int id;
  final String name;
  final Color color;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const Folder({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    this.deletedAt,
  });

  bool get isActive => deletedAt == null;

  Folder copyWith({
    int? id,
    String? name,
    Color? color,
    DateTime? createdAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
