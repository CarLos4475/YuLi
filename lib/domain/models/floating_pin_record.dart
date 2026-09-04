import 'dart:ui' show Rect;

/// Drift-free view of a persisted floating pin, used by the presentation layer
/// (Riverpod never imports Drift). [metadata] is the decoded per-kind blob:
/// image → {filename, aspect, title}.
class FloatingPinRecord {
  final int id;
  final int noteId;
  final String kind;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool collapsed;
  final int sortOrder;
  final Map<String, dynamic> metadata;

  const FloatingPinRecord({
    required this.id,
    required this.noteId,
    required this.kind,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.collapsed,
    required this.sortOrder,
    required this.metadata,
  });

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  int? get canvasBlockId {
    final value = metadata['canvasBlockId'];
    return value is num ? value.toInt() : null;
  }

  FloatingPinRecord copyWith({
    Rect? rect,
    bool? collapsed,
    int? sortOrder,
    Map<String, dynamic>? metadata,
  }) => FloatingPinRecord(
    id: id,
    noteId: noteId,
    kind: kind,
    left: rect?.left ?? left,
    top: rect?.top ?? top,
    width: rect?.width ?? width,
    height: rect?.height ?? height,
    collapsed: collapsed ?? this.collapsed,
    sortOrder: sortOrder ?? this.sortOrder,
    metadata: metadata ?? this.metadata,
  );
}
