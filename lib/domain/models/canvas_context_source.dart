enum CanvasSourceKind {
  note,
  url;

  String toDbString() => name;

  static CanvasSourceKind fromString(String v) =>
      v == 'url' ? CanvasSourceKind.url : CanvasSourceKind.note;
}

/// A single context source feeding a canvas's AI chat: an internal note or an
/// external URL (fetched via Jina Reader).
class CanvasContextSource {
  final int id;
  final int canvasNoteId;
  final CanvasSourceKind kind;

  /// Note id (as text) for [CanvasSourceKind.note], or the URL for
  /// [CanvasSourceKind.url].
  final String ref;

  /// Display title (note title / fetched page title). May be null.
  final String? label;

  /// When a url's content was last fetched. Null for notes.
  final DateTime? fetchedAt;

  final DateTime createdAt;

  const CanvasContextSource({
    required this.id,
    required this.canvasNoteId,
    required this.kind,
    required this.ref,
    this.label,
    this.fetchedAt,
    required this.createdAt,
  });

  bool get isNote => kind == CanvasSourceKind.note;
  bool get isUrl => kind == CanvasSourceKind.url;

  /// Note id when [isNote], else null.
  int? get noteId => isNote ? int.tryParse(ref) : null;
}
