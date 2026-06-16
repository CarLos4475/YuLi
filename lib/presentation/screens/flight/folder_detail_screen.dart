import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/flight_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_propagation_provider.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/status_bar_flood.dart';
import '../../widgets/edit_item_dialog.dart';
import '../../widgets/yuli_action_sheet.dart';
import '../../theme/lab_icons.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/page_background.dart';
import '../../../domain/models/task.dart' as domain_task;
import 'note_editor_screen.dart';
import 'new_note_picker.dart';
import 'notebook_editor_screen.dart';
import 'whiteboard_editor_screen.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  final Folder folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  ConsumerState<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  bool _grid = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingNoteId = ref.read(pendingNoteNavigationProvider);
      if (pendingNoteId != null) {
        ref.read(pendingNoteNavigationProvider.notifier).state = null;
        _navigateToPendingNote(pendingNoteId);
      }
    });
  }

  Future<void> _navigateToPendingNote(int noteId) async {
    final note = await ref.read(noteRepositoryProvider).getById(noteId);
    if (note == null || !mounted) return;
    final folder = await ref
        .read(folderRepositoryProvider)
        .getById(note.folderId);
    if (folder == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => switch (note.kind) {
              NoteKind.whiteboard => WhiteboardEditorScreen(
                note: note,
                folder: folder,
              ),
              NoteKind.notebook => NotebookEditorScreen(
                note: note,
                folder: folder,
              ),
              _ => NoteEditorScreen(note: note, folder: folder),
            },
      ),
    );
  }

  List<Note> _sortNotes(List<Note> notes, Set<int> pinned) {
    final indexed = notes.indexed.toList();
    indexed.sort((a, b) {
      final pa = pinned.contains(a.$2.id) ? 0 : 1;
      final pb = pinned.contains(b.$2.id) ? 0 : 1;
      if (pa != pb) return pa - pb;
      return a.$1.compareTo(b.$1);
    });
    return [for (final item in indexed) item.$2];
  }

  Future<void> _createNote() async {
    final details = await showNewNoteDialog(
      context,
      folderAccent: widget.folder.color,
    );
    if (details == null || !mounted) return;
    final note = await ref
        .read(noteRepositoryProvider)
        .create(
          widget.folder.id,
          rawMarkdown: '',
          kind: details.kind,
          title: details.title,
          color: details.color,
        );
    if (!mounted) return;
    _openNote(note);
  }

  void _openNote(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => switch (note.kind) {
              NoteKind.whiteboard => WhiteboardEditorScreen(
                note: note,
                folder: widget.folder,
              ),
              NoteKind.notebook => NotebookEditorScreen(
                note: note,
                folder: widget.folder,
              ),
              _ => NoteEditorScreen(note: note, folder: widget.folder),
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes =
        ref.watch(notesByFolderProvider(widget.folder.id)).valueOrNull ?? [];
    final pinned = ref.watch(pinnedNotesProvider);
    final sortedNotes = _sortNotes(notes, pinned);
    final pending =
        ref
            .watch(pendingTasksForFolderProvider(widget.folder.id))
            .valueOrNull ??
        [];
    final enrichment =
        ref.watch(folderEnrichmentProvider(widget.folder.id)).valueOrNull;
    final linkedSpaces = enrichment?.linkedSpaces ?? [];

    return Scaffold(
      backgroundColor: yCream,
      body: StatusBarFlood(
        color: yCream2, // matches the _FolderHero header
        leadingColor: widget.folder.color, // continue its left accent stripe
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _FolderHero(
                folder: widget.folder,
                onBack: () => Navigator.pop(context),
                noteCount: notes.length,
                lastEdit: enrichment?.lastEditedAt,
                linkedSpaces: linkedSpaces.map((s) => s.name).toList(),
                grid: _grid,
                onToggleView: () => setState(() => _grid = !_grid),
                onCreateNote: _createNote,
              ),
              Expanded(
                child: Container(
                  color: yCream,
                  child:
                      sortedNotes.isEmpty
                          ? Center(
                            child: Text(
                              'SIN NOTAS — toca + NOTA',
                              style: yMono(
                                size: 11,
                                color: yMuted,
                                tracking: 1.4,
                              ),
                            ),
                          )
                          : _grid
                          ? _NoteGrid(notes: sortedNotes, folder: widget.folder)
                          : _NoteList(
                            notes: sortedNotes,
                            folder: widget.folder,
                          ),
                ),
              ),
              if (pending.isNotEmpty)
                _TareasStrip(
                  folder: widget.folder,
                  tasks: pending,
                  onOpen: () {
                    Navigator.pop(context);
                    ref.read(currentModeProvider.notifier).state =
                        AppMode.fight;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Folder hero header ───────────────────────────────────────────────────

class _FolderHero extends StatelessWidget {
  final Folder folder;
  final int noteCount;
  final DateTime? lastEdit;
  final List<String> linkedSpaces;
  final bool grid;
  final VoidCallback onToggleView;
  final VoidCallback onCreateNote;
  final VoidCallback onBack;

  const _FolderHero({
    required this.folder,
    required this.noteCount,
    required this.lastEdit,
    required this.linkedSpaces,
    required this.grid,
    required this.onToggleView,
    required this.onCreateNote,
    required this.onBack,
  });

  String _lastEditLabel(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} sem';
    return '${(diff.inDays / 30).floor()} m';
  }

  @override
  Widget build(BuildContext context) {
    final scope = linkedSpaces.isEmpty ? null : linkedSpaces.join(' · ');
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      child: Stack(
        children: [
          // Color stripe on the left
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            child: Container(width: 8, color: folder.color),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 28, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: const Icon(
                      YuLiIcons.arrowLeft,
                      color: yInk,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scope == null
                            ? '> CARPETA'
                            : '> CARPETA · ${scope.toUpperCase()}',
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              folder.name,
                              style: ySans(
                                size: 44,
                                weight: FontWeight.w700,
                                letterSpacing: -1.5,
                                color: folder.color,
                                height: 0.95,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              '${noteCount.toString().padLeft(2, '0')} NOTAS'
                              '${lastEdit != null ? ' · ED. HACE ${_lastEditLabel(lastEdit).toUpperCase()}' : ''}',
                              style: yMono(
                                size: 11,
                                weight: FontWeight.w700,
                                tracking: 1.4,
                                color: yMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ViewToggleBtn(
                  icon: YuLiIcons.layoutGrid,
                  active: grid,
                  accentColor: folder.color,
                  onTap: grid ? () {} : onToggleView,
                ),
                const SizedBox(width: 4),
                ViewToggleBtn(
                  icon: YuLiIcons.menu,
                  active: !grid,
                  accentColor: folder.color,
                  onTap: !grid ? () {} : onToggleView,
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCreateNote,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: folder.color,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '+',
                          style: TextStyle(
                            fontSize: 16,
                            color: yCream,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'NOTA',
                          style: yBody(
                            size: 13,
                            weight: FontWeight.w700,
                            color: yCream,
                          ).copyWith(letterSpacing: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notes grid ───────────────────────────────────────────────────────────

class _NoteGrid extends ConsumerWidget {
  final List<Note> notes;
  final Folder folder;

  const _NoteGrid({required this.notes, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final cols =
            c.maxWidth >= 1000
                ? 3
                : c.maxWidth >= 650
                ? 2
                : 1;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 206,
          ),
          itemCount: notes.length,
          itemBuilder: (_, i) => _NoteCard(note: notes[i], folder: folder),
        );
      },
    );
  }
}

class _NoteList extends ConsumerWidget {
  final List<Note> notes;
  final Folder folder;

  const _NoteList({required this.notes, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
      itemBuilder: (_, i) => _NoteRow(note: notes[i], folder: folder),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemCount: notes.length,
    );
  }
}

// ─── Note card (saturated) ────────────────────────────────────────────────

class _NotebookCardPreview {
  final int pageCount;
  final PageBackground pattern;
  final Color paperColor;

  const _NotebookCardPreview({
    required this.pageCount,
    required this.pattern,
    required this.paperColor,
  });

  List<String> get lines {
    final pageLabel = pageCount == 1 ? 'Pagina' : 'Paginas';
    return [
      '$pageLabel ${pageCount.toString().padLeft(2, '0')}',
      'Color ${_colorHex(paperColor)}',
      'Patron ${_patternLabel(pattern)}',
    ];
  }

  static String _colorHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  static String _patternLabel(PageBackground pattern) => switch (pattern) {
    PageBackground.blank => 'Blanco',
    PageBackground.lined => 'Lineas',
    PageBackground.grid => 'Cuadricula',
    PageBackground.gridSmall => 'Cuadricula chica',
    PageBackground.dotted => 'Puntos',
  };
}

final _notebookCardPreviewProvider =
    StreamProvider.family<_NotebookCardPreview, int>((ref, noteId) {
      return ref.watch(noteBlockRepositoryProvider).watchByNote(noteId).map((
        blocks,
      ) {
        final pages =
            blocks.whereType<DrawingBlock>().toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        final last = pages.isEmpty ? null : pages.last;
        return _NotebookCardPreview(
          pageCount: pages.isEmpty ? 1 : pages.length,
          pattern: PageBackground.fromString(last?.background ?? ''),
          paperColor: Color(last?.bgColor ?? 0xFFFFFFFF),
        );
      });
    });

class _TextNoteCardPreview {
  final String excerpt;
  final int wordCount;

  const _TextNoteCardPreview({required this.excerpt, required this.wordCount});
}

final _textNoteCardPreviewProvider = StreamProvider.family<
  _TextNoteCardPreview,
  int
>((ref, noteId) {
  return ref.watch(noteBlockRepositoryProvider).watchByNote(noteId).map((
    blocks,
  ) {
    final ordered = List<NoteBlock>.from(blocks)
      ..sort((a, b) => a.position.compareTo(b.position));
    final pieces = <String>[];
    for (final block in ordered) {
      final text = switch (block) {
        TextBlock b => _cleanBlockText(b.markdown),
        BulletsBlock b => b.items
            .map(_cleanBlockText)
            .where((item) => item.isNotEmpty)
            .join(' / '),
        MathBlock b =>
          b.latex.trim().isEmpty ? '' : 'Formula ${b.latex.trim()}',
        TareasBlock b => b.taskIds.isEmpty ? '' : 'Tareas ${b.taskIds.length}',
        DrawingBlock _ => '',
      };
      if (text.isNotEmpty) pieces.add(text);
      if (pieces.join(' ').length >= 220) break;
    }
    final body = pieces.join(' ').trim();
    final excerpt =
        body.isEmpty
            ? 'Sin contenido todavia'
            : body.length > 220
            ? '${body.substring(0, 220)}...'
            : body;
    return _TextNoteCardPreview(excerpt: excerpt, wordCount: _wordCount(body));
  });
});

String _cleanBlockText(String value) {
  return value
      .replaceAll(RegExp(r'#{1,6}\s+'), '')
      .replaceAll(RegExp(r'[*_`~>\[\]()]'), '')
      .replaceAll(RegExp(r'!\S+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _wordCount(String value) {
  if (value.trim().isEmpty) return 0;
  return RegExp(r'\S+').allMatches(value.trim()).length;
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final Folder folder;

  const _NoteCard({required this.note, required this.folder});

  String _lastEditLabel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return 'hace ${(diff.inDays / 7).floor()} sem';
  }

  String _previewOf(Note n) {
    if (n.kind == NoteKind.whiteboard) return 'Pizarra infinita / pan + zoom';
    final clean = n.rawMarkdown
        .replaceAll(RegExp(r'#{1,6}\s+'), '')
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\n+'), ' ');
    return clean.length > 220 ? '${clean.substring(0, 220)}...' : clean;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Eliminar nota',
              style: ySans(size: 20, weight: FontWeight.w700),
            ),
            content: Text(
              'Se moverá la nota a la papelera.',
              style: yBody(size: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await ref.read(noteRepositoryProvider).softDelete(note.id);
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final pinned = ref.read(pinnedNotesProvider).contains(note.id);
    _showNoteActions(
      context,
      ref,
      note,
      folder,
      pinned,
      onDelete: () => _confirmDelete(context, ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedNotesProvider).contains(note.id);
    final bg = note.color ?? folder.color;
    final notebookPreview =
        note.kind == NoteKind.notebook
            ? ref.watch(_notebookCardPreviewProvider(note.id)).valueOrNull
            : null;
    final textPreview =
        note.kind == NoteKind.block
            ? ref.watch(_textNoteCardPreviewProvider(note.id)).valueOrNull
            : null;
    final preview = switch (note.kind) {
      NoteKind.notebook => '',
      NoteKind.block =>
        textPreview?.excerpt ??
            (note.rawMarkdown.trim().isEmpty
                ? 'Sin contenido todavia'
                : _previewOf(note)),
      NoteKind.whiteboard => _previewOf(note),
    };
    final footerMetric =
        note.kind == NoteKind.block
            ? '${textPreview?.wordCount ?? 0} PALABRAS'
            : '${note.sizeBytes}B';
    final notebookLines =
        notebookPreview?.lines ??
        const ['Paginas 01', 'Color #FFFFFF', 'Patron Blanco'];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => switch (note.kind) {
                    NoteKind.whiteboard => WhiteboardEditorScreen(
                      note: note,
                      folder: folder,
                    ),
                    NoteKind.notebook => NotebookEditorScreen(
                      note: note,
                      folder: folder,
                    ),
                    _ => NoteEditorScreen(note: note, folder: folder),
                  },
            ),
          ),
      onLongPress: () => _showOptions(context, ref),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: 8,
            top: 8,
            right: -8,
            bottom: -8,
            child: CustomPaint(
              painter: _NoteCardBackgroundPainter(kind: note.kind, color: yInk),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _NoteCardBackgroundPainter(
                kind: note.kind,
                color: bg,
                border: true,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _NoteCardPainter(kind: note.kind)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                note.kind == NoteKind.notebook ? 64 : 16,
                14,
                note.kind == NoteKind.block ? 54 : 16,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NoteKindBadge(kind: note.kind),
                  const SizedBox(height: 6),
                  Text(
                    note.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ySans(
                      size: 20,
                      weight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: yCream,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child:
                        note.kind == NoteKind.notebook
                            ? _NotebookPreviewLines(lines: notebookLines)
                            : Text(
                              preview,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: yBody(
                                size: 12,
                                color: yCream.withValues(alpha: 0.85),
                                height: 1.4,
                              ),
                            ),
                  ),
                  const SizedBox(height: 8),
                  Container(height: 1.5, color: yCream.withValues(alpha: 0.3)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _lastEditLabel(note.updatedAt).toUpperCase(),
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yCream.withValues(alpha: 0.85),
                        ),
                      ),
                      Text(
                        footerMetric,
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 1.2,
                          color: yCream.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (pinned)
            Positioned(
              top: -2,
              right: note.kind == NoteKind.block ? 68 : 12,
              child: Transform.rotate(
                angle: 0.035,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
                  decoration: BoxDecoration(
                    color: yAmber2,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(YuLiIcons.star, size: 10, color: yInk),
                      const SizedBox(width: 4),
                      Text(
                        'FIJADA',
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showNoteActions(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Folder folder,
  bool pinned, {
  VoidCallback? onDelete,
}) {
  final accent = note.color ?? folder.color;
  final meta = _kindMeta(note.kind);
  showModalBottomSheet(
    context: context,
    backgroundColor: yCream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder:
        (ctx) => YuLiActionSheet(
          title: note.displayTitle,
          badge: meta.label,
          badgeIcon: meta.icon,
          accent: accent,
          children: [
            YuLiActionTile(
              icon: YuLiIcons.star,
              label: pinned ? 'Desfijar' : 'Fijar',
              accent: accent,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(pinnedNotesProvider.notifier).toggle(note.id);
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.pen,
              label: 'Editar',
              accent: accent,
              onTap: () {
                Navigator.pop(ctx);
                _showEditNoteDialog(context, ref, note, folder);
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.palette,
              label: 'Cambiar color',
              accent: accent,
              onTap: () {
                Navigator.pop(ctx);
                _showNoteColorDialog(context, ref, note, folder);
              },
            ),
            YuLiActionTile(
              icon: YuLiIcons.trash,
              label: 'Eliminar',
              accent: accent,
              destructive: true,
              onTap: () {
                Navigator.pop(ctx);
                if (onDelete != null) {
                  onDelete();
                } else {
                  _confirmDeleteNote(context, ref, note);
                }
              },
            ),
          ],
        ),
  );
}

void _showNoteColorDialog(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Folder folder,
) {
  showDialog(
    context: context,
    builder:
        (dCtx) => AlertDialog(
          backgroundColor: yCream,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'Color de nota',
            style: ySans(size: 18, weight: FontWeight.w700),
          ),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                folderPalette
                    .map(
                      (c) => GestureDetector(
                        onTap: () async {
                          await ref
                              .read(noteRepositoryProvider)
                              .update(note.copyWith(color: c));
                          if (dCtx.mounted) Navigator.pop(dCtx);
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c,
                            border: Border.all(
                              color: yBorderStrong,
                              width:
                                  (note.color ?? folder.color) == c
                                      ? yLineMid
                                      : yLineThin,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
  );
}

void _showEditNoteDialog(
  BuildContext context,
  WidgetRef ref,
  Note note,
  Folder folder,
) {
  showDialog(
    context: context,
    builder:
        (ctx) => EditItemDialog(
          title: 'Nota',
          initialName: note.displayTitle,
          initialColor: note.color ?? folder.color,
          onSave: (name, color) async {
            await ref
                .read(noteRepositoryProvider)
                .update(note.copyWith(title: name, color: color));
          },
          onDelete: () async {
            Navigator.pop(ctx);
            await _confirmDeleteNote(context, ref, note);
          },
        ),
  );
}

Future<void> _confirmDeleteNote(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: yCream,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'Eliminar nota',
            style: ySans(size: 20, weight: FontWeight.w700),
          ),
          content: Text(
            'Se movera la nota a la papelera.',
            style: yBody(size: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
  );
  if (confirmed == true) {
    await ref.read(noteRepositoryProvider).softDelete(note.id);
  }
}

class _NotebookPreviewLines extends StatelessWidget {
  final List<String> lines;

  const _NotebookPreviewLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final line in lines.take(3))
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1.1,
                  color: yCream.withValues(alpha: 0.86),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NoteCardBackgroundPainter extends CustomPainter {
  final NoteKind kind;
  final Color color;
  final bool border;

  const _NoteCardBackgroundPainter({
    required this.kind,
    required this.color,
    this.border = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        kind == NoteKind.block
            ? (Path()
              ..moveTo(0, 0)
              ..lineTo(size.width - 58, 0)
              ..lineTo(size.width, 58)
              ..lineTo(size.width, size.height)
              ..lineTo(0, size.height)
              ..close())
            : (Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(path, Paint()..color = color);
    if (border) {
      canvas.drawPath(
        path,
        Paint()
          ..color = yBorderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineMid
          ..strokeJoin = StrokeJoin.miter,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NoteCardBackgroundPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.border != border;
}

class _NoteCardPainter extends CustomPainter {
  final NoteKind kind;

  const _NoteCardPainter({required this.kind});

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case NoteKind.whiteboard:
        _paintWhiteboard(canvas, size);
      case NoteKind.notebook:
        _paintNotebook(canvas, size);
      case NoteKind.block:
        _paintTextNote(canvas, size);
    }
  }

  void _paintWhiteboard(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = yCream.withValues(alpha: 0.12);
    for (double x = 24; x < size.width - 24; x += 18) {
      for (double y = 34; y < size.height - 46; y += 18) {
        canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
      }
    }
    final line =
        Paint()
          ..color = yCream.withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.16, size.height * 0.48, 50, 36),
      line,
    );
    canvas.drawLine(
      Offset(size.width * 0.36, size.height * 0.57),
      Offset(size.width * 0.46, size.height * 0.57),
      line,
    );
    final circle = Rect.fromCircle(
      center: Offset(size.width * 0.56, size.height * 0.56),
      radius: 28,
    );
    canvas.drawOval(circle, line);
    canvas.drawLine(
      Offset(circle.center.dx - 8, circle.center.dy - 10),
      Offset(circle.center.dx + 8, circle.center.dy + 12),
      line,
    );
    canvas.drawLine(
      Offset(circle.center.dx + 8, circle.center.dy - 10),
      Offset(circle.center.dx - 8, circle.center.dy + 12),
      line,
    );
    final graph =
        Path()
          ..moveTo(size.width * 0.75, size.height * 0.42)
          ..lineTo(size.width * 0.75, size.height * 0.25)
          ..moveTo(size.width * 0.75, size.height * 0.42)
          ..lineTo(size.width * 0.92, size.height * 0.42)
          ..moveTo(size.width * 0.79, size.height * 0.39)
          ..cubicTo(
            size.width * 0.82,
            size.height * 0.28,
            size.width * 0.86,
            size.height * 0.43,
            size.width * 0.90,
            size.height * 0.29,
          );
    canvas.drawPath(graph, line);
    final hatchRect = Rect.fromLTWH(size.width - 64, size.height - 44, 64, 44);
    canvas.drawRect(
      hatchRect,
      Paint()..color = yBorderStrong.withValues(alpha: 0.12),
    );
    canvas.save();
    canvas.clipRect(hatchRect);
    final hatch =
        Paint()
          ..color = yBorderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    for (double x = hatchRect.left - 36; x < hatchRect.right; x += 10) {
      canvas.drawLine(
        Offset(x, hatchRect.bottom + 2),
        Offset(x + 42, hatchRect.top - 2),
        hatch,
      );
    }
    canvas.restore();
    canvas.drawRect(
      hatchRect,
      Paint()
        ..color = yBorderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = yLineMid,
    );
  }

  void _paintNotebook(Canvas canvas, Size size) {
    final ringPaint = Paint()..color = yInk;
    for (double y = 28; y < size.height - 26; y += 25) {
      canvas.drawRect(Rect.fromLTWH(-3, y, 24, 9), ringPaint);
      canvas.drawRect(
        Rect.fromLTWH(18, y + 2, 12, 5),
        Paint()..color = yCream.withValues(alpha: 0.32),
      );
    }
    final line =
        Paint()
          ..color = yCream.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
    for (double y = size.height * 0.42; y < size.height - 52; y += 18) {
      canvas.drawLine(Offset(60, y), Offset(size.width - 18, y), line);
    }
    canvas.drawLine(
      const Offset(54, 40),
      Offset(54, size.height - 48),
      Paint()
        ..color = yCream.withValues(alpha: 0.16)
        ..strokeWidth = 1.2,
    );
  }

  void _paintTextNote(Canvas canvas, Size size) {
    final fold =
        Path()
          ..moveTo(size.width - 58, 0)
          ..lineTo(size.width, 58)
          ..lineTo(size.width - 58, 58)
          ..close();
    canvas.drawPath(fold, Paint()..color = yCream.withValues(alpha: 0.9));
    final foldBorder =
        Paint()
          ..color = yBorderStrong
          ..strokeWidth = yLineMid
          ..strokeJoin = StrokeJoin.miter;
    canvas.drawLine(
      Offset(size.width - 58, 0),
      Offset(size.width, 58),
      foldBorder,
    );
    canvas.drawLine(
      Offset(size.width - 58, 58),
      Offset(size.width, 58),
      foldBorder,
    );
    canvas.drawLine(
      Offset(size.width - 58, 0),
      Offset(size.width - 58, 58),
      foldBorder,
    );
  }

  @override
  bool shouldRepaint(covariant _NoteCardPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

class _NoteRow extends ConsumerWidget {
  final Note note;
  final Folder folder;

  const _NoteRow({required this.note, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedNotesProvider).contains(note.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => switch (note.kind) {
                    NoteKind.whiteboard => WhiteboardEditorScreen(
                      note: note,
                      folder: folder,
                    ),
                    NoteKind.notebook => NotebookEditorScreen(
                      note: note,
                      folder: folder,
                    ),
                    _ => NoteEditorScreen(note: note, folder: folder),
                  },
            ),
          ),
      onLongPress: () => _showNoteActions(context, ref, note, folder, pinned),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: note.color ?? folder.color,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          children: [
            _NoteKindGlyph(kind: note.kind, color: yCream),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ySans(size: 16, weight: FontWeight.w700, color: yCream),
              ),
            ),
            if (pinned) ...[
              const SizedBox(width: 8),
              Icon(YuLiIcons.star, size: 14, color: yAmber2),
            ],
            const SizedBox(width: 8),
            Text(
              '→',
              style: TextStyle(fontSize: 14, color: yCream, height: 1.0),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Note kind indicators ────────────────────────────────────────────────────

({IconData icon, String label}) _kindMeta(NoteKind k) => switch (k) {
  NoteKind.notebook => (icon: YuLiIcons.notebook, label: 'CUADERNO'),
  NoteKind.whiteboard => (icon: YuLiIcons.pencil, label: 'PIZARRA'),
  NoteKind.block => (icon: YuLiIcons.textInitial, label: 'NOTA'),
};

class _NoteKindBadge extends StatelessWidget {
  final NoteKind kind;
  const _NoteKindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(kind);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 3),
      decoration: BoxDecoration(
        color: yCream.withValues(alpha: 0.18),
        border: Border.all(color: yCream, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 11, color: yCream),
          const SizedBox(width: 5),
          Text(
            meta.label,
            style: yMono(
              size: 9,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yCream,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteKindGlyph extends StatelessWidget {
  final NoteKind kind;
  final Color color;
  const _NoteKindGlyph({required this.kind, required this.color});

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(kind);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: color, width: 1.5)),
      child: Icon(meta.icon, size: 14, color: color),
    );
  }
}

// ─── Tareas pendientes strip ──────────────────────────────────────────────

class _TareasStrip extends StatelessWidget {
  final Folder folder;
  final List<domain_task.Task> tasks;
  final VoidCallback onOpen;

  const _TareasStrip({
    required this.folder,
    required this.tasks,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'TAREAS PENDIENTES',
                style: yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.6,
                  color: yInk,
                ),
              ),
              const SizedBox(width: 10),
              YBadge(
                label: '@${folder.name} · ${tasks.length}',
                bg: folder.color,
                fg: yCream,
                fontSize: 10,
              ),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Text(
                  'ABRIR EN FIGHT →',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: yInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              final cols = (tasks.length).clamp(1, 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: c.maxWidth >= 900 ? cols : 1,
                  mainAxisExtent: 48,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 8,
                ),
                itemCount: tasks.length,
                itemBuilder: (_, i) => _TareaStripRow(task: tasks[i]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TareaStripRow extends ConsumerWidget {
  final domain_task.Task task;
  const _TareaStripRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prop =
        ref.watch(taskPropagationProvider(task.id)).valueOrNull ??
        TaskPropagation.empty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              // This row disappears the instant the task is completed (it's no
              // longer pending), disposing its `ref`/`context`. Capture the
              // messenger + repos NOW (while alive) so both the snackbar and the
              // undo survive the disposal.
              final messenger = ScaffoldMessenger.of(context);
              final taskRepo = ref.read(taskRepositoryProvider);
              final kanbanRepo = ref.read(kanbanCardRepositoryProvider);
              final labRepo = ref.read(labSpaceRepositoryProvider);
              await setTaskDoneWith(
                taskRepo: taskRepo,
                kanbanRepo: kanbanRepo,
                labRepo: labRepo,
                taskId: task.id,
                done: true,
              );
              messenger.showSnackBar(
                SnackBar(
                  content: const Text('Tarea completada'),
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: 'Deshacer',
                    onPressed: () {
                      setTaskDoneWith(
                        taskRepo: taskRepo,
                        kanbanRepo: kanbanRepo,
                        labRepo: labRepo,
                        taskId: task.id,
                        done: false,
                      );
                    },
                  ),
                ),
              );
            },
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cleanMention(task.content),
                  style: ySans(
                    size: 13,
                    weight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: yInk,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'PENDIENTE',
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: yMuted,
                  ),
                ),
              ],
            ),
          ),
          if (prop.hasNoteLinks) ...[
            const SizedBox(width: 6),
            _StripChip(
              text: prop.noteCount > 1 ? '↳ ${prop.noteCount}' : '↳ NOTA',
              bg: yFlight,
            ),
          ],
          if (prop.spaceName != null) ...[
            const SizedBox(width: 4),
            _StripChip(text: '→ ${prop.spaceName!.toUpperCase()}', bg: yLab),
          ],
        ],
      ),
    );
  }
}

class _StripChip extends StatelessWidget {
  final String text;
  final Color bg;

  const _StripChip({required this.text, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yBorderStrong, width: 1.5),
      ),
      child: Text(
        text,
        style: yMono(
          size: 8,
          weight: FontWeight.w700,
          tracking: 1,
          color: yCream,
        ),
      ),
    );
  }
}
