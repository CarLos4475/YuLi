enum CanvasSourceKind {
  note,
  folder,
  url;

  String toDbString() => name;

  static CanvasSourceKind fromString(String v) => switch (v) {
    'url' => CanvasSourceKind.url,
    'folder' => CanvasSourceKind.folder,
    _ => CanvasSourceKind.note,
  };
}

/// A single unified context source, owned by EITHER a canvas note
/// ([canvasNoteId]) or a lab space ([labSpaceId]) — exactly one is set. Kinds:
/// internal `note`, a `folder` (expands to its notes) or an external `url`.
class CanvasContextSource {
  final int id;
  final int? canvasNoteId;
  final int? labSpaceId;
  final CanvasSourceKind kind;

  /// Note id / folder id (as text) or the URL, per [kind].
  final String ref;

  /// Display title (note/folder/page title). May be null.
  final String? label;

  /// When a url's content was last fetched. Null for notes/folders.
  final DateTime? fetchedAt;

  final DateTime createdAt;

  const CanvasContextSource({
    required this.id,
    this.canvasNoteId,
    this.labSpaceId,
    required this.kind,
    required this.ref,
    this.label,
    this.fetchedAt,
    required this.createdAt,
  });

  bool get isNote => kind == CanvasSourceKind.note;
  bool get isFolder => kind == CanvasSourceKind.folder;
  bool get isUrl => kind == CanvasSourceKind.url;

  /// Note id when [isNote], else null.
  int? get noteId => isNote ? int.tryParse(ref) : null;

  /// Folder id when [isFolder], else null.
  int? get folderId => isFolder ? int.tryParse(ref) : null;
}
