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
        // Legacy: transparently convert to TextBlock with markdown heading
        final level = ((json['level'] as int?) ?? 2).clamp(1, 6);
        final text = (json['text'] as String?) ?? '';
        return TextBlock(
          id: id,
          noteId: noteId,
          position: position,
          markdown: '${'#' * level} $text',
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
          imagesJson: jsonEncode(json['i'] ?? const []),
          taskBlocksJson: jsonEncode(json['t'] ?? const []),
          textBlocksJson: jsonEncode(json['tx'] ?? const []),
          background: json['bg'] as String?,
          bgColor: (json['bgc'] as num?)?.toInt(),
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
  final String imagesJson;
  final String taskBlocksJson;
  final String textBlocksJson;
  final String? background;
  final int? bgColor;
  const DrawingBlock({
    required super.id,
    required super.noteId,
    required super.position,
    required this.height,
    required this.strokesJson,
    this.imagesJson = '[]',
    this.taskBlocksJson = '[]',
    this.textBlocksJson = '[]',
    this.background,
    this.bgColor,
  }) : super(type: NoteBlockType.drawing);

  DrawingBlock copyWith({
    double? height,
    String? strokesJson,
    String? imagesJson,
    String? taskBlocksJson,
    String? textBlocksJson,
    String? background,
    int? bgColor,
  }) =>
      DrawingBlock(
        id: id,
        noteId: noteId,
        position: position,
        height: height ?? this.height,
        strokesJson: strokesJson ?? this.strokesJson,
        imagesJson: imagesJson ?? this.imagesJson,
        taskBlocksJson: taskBlocksJson ?? this.taskBlocksJson,
        textBlocksJson: textBlocksJson ?? this.textBlocksJson,
        background: background ?? this.background,
        bgColor: bgColor ?? this.bgColor,
      );

  @override
  Map<String, dynamic> payloadJson() => {
        'h': height,
        's': jsonDecode(strokesJson),
        'i': jsonDecode(imagesJson),
        't': jsonDecode(taskBlocksJson),
        'tx': jsonDecode(textBlocksJson),
        if (background != null) 'bg': background,
        if (bgColor != null) 'bgc': bgColor,
      };
}
