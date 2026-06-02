import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/flight_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_propagation_provider.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/edit_item_dialog.dart';

import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
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

  Future<void> _createNote() async {
    final kind = await showNewNotePicker(context);
    if (kind == null || !mounted) return;
    final details = await showNewNoteDetailsDialog(context, kind);
    if (details == null || !mounted) return;
    final note = await ref
        .read(noteRepositoryProvider)
        .create(
          widget.folder.id,
          rawMarkdown: '',
          kind: kind,
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
      body: SafeArea(
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
                    notes.isEmpty
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
                        ? _NoteGrid(notes: notes, folder: widget.folder)
                        : _NoteList(notes: notes, folder: widget.folder),
              ),
            ),
            if (pending.isNotEmpty)
              _TareasStrip(
                folder: widget.folder,
                tasks: pending,
                onOpen: () {
                  Navigator.pop(context);
                  ref.read(currentModeProvider.notifier).state = AppMode.fight;
                },
              ),
          ],
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
            padding: const EdgeInsets.fromLTRB(20, 14, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                    child: const Icon(Icons.arrow_back, color: yInk, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scope == null
                                ? '// CARPETA'
                                : '// CARPETA · ${scope.toUpperCase()}',
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
                      glyph: '▣',
                      active: grid,
                      onTap: grid ? () {} : onToggleView,
                    ),
                    const SizedBox(width: 4),
                    ViewToggleBtn(
                      glyph: '≡',
                      active: !grid,
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
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
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
            mainAxisExtent: 168,
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
    if (n.kind == NoteKind.notebook) return _notebookPreview(n);
    if (n.kind == NoteKind.whiteboard) return 'Pizarra infinita · pan + zoom';
    final clean = n.rawMarkdown
        .replaceAll(RegExp(r'#{1,6}\s+'), '')
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\n+'), ' ');
    return clean.length > 220 ? '${clean.substring(0, 220)}…' : clean;
  }

  String _notebookPreview(Note n) {
    final bg = _readNotebookBackground(n.rawMarkdown);
    return switch (bg) {
      'lined' => 'Cuaderno A4 · líneas',
      'grid' => 'Cuaderno A4 · cuadrícula',
      'dotted' => 'Cuaderno A4 · puntos',
      _ => 'Cuaderno A4 · blanco',
    };
  }

  String _readNotebookBackground(String raw) {
    if (raw.isEmpty) return 'blank';
    try {
      final meta = jsonDecode(raw);
      if (meta is Map && meta['pageBackground'] is String) {
        return meta['pageBackground'] as String;
      }
    } catch (_) {}
    return 'blank';
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
              await _confirmDelete(context, ref);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedNotesProvider).contains(note.id);
    final bg = note.color ?? folder.color;
    final preview = _previewOf(note);
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
          Container(
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                  child: Text(
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
                      '${note.sizeBytes}B',
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
          if (pinned)
            Positioned(
              top: -2,
              right: 12,
              child: Transform.rotate(
                angle: 0.035,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
                  decoration: BoxDecoration(
                    color: yAmber2,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: Text(
                    '★ FIJADA',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteRow extends ConsumerWidget {
  final Note note;
  final Folder folder;

  const _NoteRow({required this.note, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
  NoteKind.notebook => (icon: Icons.menu_book_outlined, label: 'CUADERNO'),
  NoteKind.whiteboard => (icon: Icons.gesture, label: 'PIZARRA'),
  NoteKind.block => (icon: Icons.notes_outlined, label: 'NOTA'),
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
                '── TAREAS PENDIENTES',
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
                bg: yFight,
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
              await setTaskDone(ref, task.id, done: true);
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
