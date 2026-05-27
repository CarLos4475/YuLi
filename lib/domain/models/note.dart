import 'package:flutter/material.dart';

enum NoteKind {
  block,
  whiteboard,
  notebook;

  String toDbString() => name;

  static NoteKind fromString(String value) => switch (value) {
        'block' => NoteKind.block,
        'whiteboard' => NoteKind.whiteboard,
        'notebook' => NoteKind.notebook,
        _ => NoteKind.block,
      };
}

class Note {
  final int id;
  final int folderId;
  final String? title;
  final String rawMarkdown;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final Color? color;
  final NoteKind kind;

  const Note({
    required this.id,
    required this.folderId,
    this.title,
    required this.rawMarkdown,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.color,
    this.kind = NoteKind.block,
  });

  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final cleaned = rawMarkdown.replaceAll(RegExp(r'[#*_`\[\]]'), '').trim();
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  bool get isActive => deletedAt == null;

  Note copyWith({
    int? id,
    int? folderId,
    String? title,
    bool clearTitle = false,
    String? rawMarkdown,
    int? sizeBytes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    Color? color,
    bool clearColor = false,
    NoteKind? kind,
  }) {
    return Note(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: clearTitle ? null : (title ?? this.title),
      rawMarkdown: rawMarkdown ?? this.rawMarkdown,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      color: clearColor ? null : (color ?? this.color),
      kind: kind ?? this.kind,
    );
  }
}

class NoteImage {
  final int id;
  final int noteId;
  final String filename;
  final String filePath;
  final int sizeBytes;
  final DateTime createdAt;

  const NoteImage({
    required this.id,
    required this.noteId,
    required this.filename,
    required this.filePath,
    required this.sizeBytes,
    required this.createdAt,
  });
}

class NoteVersion {
  final int id;
  final int noteId;
  final String rawMarkdown;
  final DateTime savedAt;

  const NoteVersion({
    required this.id,
    required this.noteId,
    required this.rawMarkdown,
    required this.savedAt,
  });
}
