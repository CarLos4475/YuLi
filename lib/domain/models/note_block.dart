import 'dart:convert';

enum NoteBlockType {
  text,
  math,
  heading,
  bullets,
  tareas,
  drawing;

  String toDbString() => name;

  static NoteBlockType fromString(String value) =>
      NoteBlockType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => NoteBlockType.text,
      );
}

/// Sealed-like NoteBlock with type-discriminated payload.
/// The block's identity is `id` (DB row id); position drives ordering.
sealed class NoteBlock {
  final int id;
  final int noteId;
  final int position;
  final NoteBlockType type;

  const NoteBlock({
    required this.id,
    required this.noteId,
    required this.position,
    required this.type,
  });

  Map<String, dynamic> payloadJson();
  String get payloadString => jsonEncode(payloadJson());

  static NoteBlock fromPayload({
    required int id,
    required int noteId,
    required int position,
    required NoteBlockType type,
    required String payload,
  }) {
    final json = payload.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(payload) as Map<String, dynamic>);
    switch (type) {
      case NoteBlockType.text:
        return TextBlock(
          id: id,
          noteId: noteId,
          position: position,
          markdown: (json['md'] as String?) ?? '',
        );
      case NoteBlockType.math:
        return MathBlock(
          id: id,
          noteId: noteId,
          position: position,
          latex: (json['latex'] as String?) ?? '',
        );
      case NoteBlockType.heading:
        return HeadingBlock(
          id: id,
          noteId: noteId,
          position: position,
          level: (json['level'] as int?) ?? 2,
          text: (json['text'] as String?) ?? '',
        );
      case NoteBlockType.bullets:
        return BulletsBlock(
          id: id,
          noteId: noteId,
          position: position,
          items: ((json['items'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
        );
      case NoteBlockType.tareas:
        return TareasBlock(
          id: id,
          noteId: noteId,
          position: position,
          taskIds: ((json['taskIds'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toList(),
        );
      case NoteBlockType.drawing:
        return DrawingBlock(
          id: id,
          noteId: noteId,
          position: position,
          height: ((json['h'] as num?) ?? 300).toDouble(),
          strokesJson: jsonEncode(json['s'] ?? const []),
        );
    }
  }
}

class TextBlock extends NoteBlock {
  final String markdown;
  const TextBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.markdown,
  }) : super(type: NoteBlockType.text);

  TextBlock copyWith({String? markdown}) => TextBlock(
        id: id,
        noteId: noteId,
        position: position,
        markdown: markdown ?? this.markdown,
      );

  @override
  Map<String, dynamic> payloadJson() => {'md': markdown};
}

class MathBlock extends NoteBlock {
  final String latex;
  const MathBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.latex,
  }) : super(type: NoteBlockType.math);

  MathBlock copyWith({String? latex}) => MathBlock(
        id: id,
        noteId: noteId,
        position: position,
        latex: latex ?? this.latex,
      );

  @override
  Map<String, dynamic> payloadJson() => {'latex': latex};
}

class HeadingBlock extends NoteBlock {
  final int level;
  final String text;
  const HeadingBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.level,
    required this.text,
  }) : super(type: NoteBlockType.heading);

  HeadingBlock copyWith({int? level, String? text}) => HeadingBlock(
        id: id,
        noteId: noteId,
        position: position,
        level: level ?? this.level,
        text: text ?? this.text,
      );

  @override
  Map<String, dynamic> payloadJson() => {'level': level, 'text': text};
}

class BulletsBlock extends NoteBlock {
  final List<String> items;
  const BulletsBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.items,
  }) : super(type: NoteBlockType.bullets);

  BulletsBlock copyWith({List<String>? items}) => BulletsBlock(
        id: id,
        noteId: noteId,
        position: position,
        items: items ?? this.items,
      );

  @override
  Map<String, dynamic> payloadJson() => {'items': items};
}

class TareasBlock extends NoteBlock {
  final List<int> taskIds;
  const TareasBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.taskIds,
  }) : super(type: NoteBlockType.tareas);

  TareasBlock copyWith({List<int>? taskIds}) => TareasBlock(
        id: id,
        noteId: noteId,
        position: position,
        taskIds: taskIds ?? this.taskIds,
      );

  @override
  Map<String, dynamic> payloadJson() => {'taskIds': taskIds};
}

class DrawingBlock extends NoteBlock {
  final double height;
  final String strokesJson;
  const DrawingBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.height,
    required this.strokesJson,
  }) : super(type: NoteBlockType.drawing);

  DrawingBlock copyWith({double? height, String? strokesJson}) => DrawingBlock(
        id: id,
        noteId: noteId,
        position: position,
        height: height ?? this.height,
        strokesJson: strokesJson ?? this.strokesJson,
      );

  @override
  Map<String, dynamic> payloadJson() => {
        'h': height,
        's': jsonDecode(strokesJson),
      };
}
