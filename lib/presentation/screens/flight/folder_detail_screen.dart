import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../../domain/repositories/schedule_repository.dart';
import '../../../domain/models/schedule_block.dart';
import '../../widgets/app_banner.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../widgets/fight_panel.dart';
import 'note_editor_screen.dart';
import '../../widgets/edit_item_dialog.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  final Folder folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  ConsumerState<FolderDetailScreen> createState() =>
      _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  bool _isGrid = true;

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
    final noteFolder = await ref.read(folderRepositoryProvider).getById(note.folderId);
    if (noteFolder == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, folder: noteFolder),
      ),
    );
  }

  void _showFightPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.2,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => FightPanel(
          folderId: widget.folder.id,
          scrollController: scrollController,
          onTapTask: (task) async {
            await ref.read(taskRepositoryProvider).markDone(task.id);
            await syncTaskCompletionToKanban(ref, task.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tarea completada'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesByFolderProvider(widget.folder.id));
    final pendingTasksAsync =
        ref.watch(pendingTasksForFolderProvider(widget.folder.id));
    final pendingCount = pendingTasksAsync.valueOrNull?.length ?? 0;
    final notes = notesAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            _FolderDetailHeader(
              folder: widget.folder,
              noteCount: notes.length,
              isGrid: _isGrid,
              onToggleLayout: () => setState(() => _isGrid = !_isGrid),
            ),
            if (pendingCount > 0)
              AppBanner(
                message: '${pendingCount} Tarea${pendingCount == 1 ? '' : 's'} Pendiente${pendingCount == 1 ? '' : 's'}',
                accentColor: widget.folder.color,
                actionLabel: 'Ver en Fight',
                onAction: () {
                  Navigator.pop(context);
                  ref.read(currentModeProvider.notifier).state = AppMode.fight;
                },
              ),
            _NextClassBanner(folderId: widget.folder.id),
            Expanded(
              child: _NoteGrid(
                notes: notes,
                folder: widget.folder,
                isGrid: _isGrid,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: paperColor(context),
          border: Border(
            top: BorderSide(color: inkColor(context), width: borderWidth),
          ),
        ),
        child: SafeArea(
          top: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showFightPanel(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                pendingCount > 0
                    ? 'Tareas pendientes ($pendingCount)'
                    : 'Tareas pendientes',
                style: labelBold.copyWith(color: widget.folder.color),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _NewNoteButton(folder: widget.folder),
    );
  }
}

class _FolderDetailHeader extends StatelessWidget {
  final Folder folder;
  final int noteCount;
  final bool isGrid;
  final VoidCallback onToggleLayout;

  const _FolderDetailHeader({
    required this.folder,
    required this.noteCount,
    required this.isGrid,
    required this.onToggleLayout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.arrow_back, color: inkColor(context), size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: displayL.copyWith(color: folder.color),
                ),
                Text(
                   '$noteCount Nota${noteCount == 1 ? '' : 's'}',
                  style: bodyS.copyWith(color: inkGray),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleLayout,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                isGrid ? 'Lista' : 'Grid',
                style: labelBold.copyWith(color: inkColor(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteGrid extends StatelessWidget {
  final List<Note> notes;
  final Folder folder;
  final bool isGrid;

  const _NoteGrid({
    required this.notes,
    required this.folder,
    required this.isGrid,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Text(
          'Sin notas todavía',
          style: bodyS.copyWith(color: inkGray),
        ),
      );
    }

    if (!isGrid) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _NoteListItem(note: notes[i], folder: folder),
      );
    }

    final crossCount = _crossAxisCount(context);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: notes.length,
      itemBuilder: (_, i) {
        // Slight asymmetric rotation for editorial feel
        final rotation = (i % 2 == 0 ? 1.0 : -1.0) *
            (1.0 + (i % 3) * 0.5) *
            (math.pi / 180);
        return Transform.rotate(
          angle: rotation,
          child: _NoteGridItem(note: notes[i], folder: folder),
        );
      },
    );
  }

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }
}

class _NoteGridItem extends ConsumerWidget {
  final Note note;
  final Folder folder;

  const _NoteGridItem({required this.note, required this.folder});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: inkColor(context), width: borderWidth),
        ),
        title: Text('Eliminar nota',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Se moverá la nota a la papelera.',
            style: bodyM.copyWith(color: inkColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: labelBold.copyWith(color: accentFight)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteRepositoryProvider).softDelete(note.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nota "${note.displayTitle}" movida a la papelera'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => EditItemDialog(
        title: 'Nota',
        initialName: note.displayTitle,
        initialColor: note.color ?? folder.color,
        onSave: (name, color) async {
          await ref.read(noteRepositoryProvider).update(note.copyWith(
                title: name,
                color: color,
              ));
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
    final bgColor = note.color ?? folder.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openNote(context),
      onLongPress: () => _showOptions(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: inkColor(context), width: borderWidthHeavy),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              note.displayTitle,
              style: displayM.copyWith(color: inkLight),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _openNote(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, folder: folder),
      ),
    );
  }

}

class _NoteListItem extends ConsumerWidget {
  final Note note;
  final Folder folder;

  const _NoteListItem({required this.note, required this.folder});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: inkColor(context), width: borderWidth),
        ),
        title: Text('Eliminar nota',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Se moverá la nota a la papelera.',
            style: bodyM.copyWith(color: inkColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: labelBold.copyWith(color: accentFight)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteRepositoryProvider).softDelete(note.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nota "${note.displayTitle}" movida a la papelera'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => EditItemDialog(
        title: 'Nota',
        initialName: note.displayTitle,
        initialColor: note.color ?? folder.color,
        onSave: (name, color) async {
          await ref.read(noteRepositoryProvider).update(note.copyWith(
                title: name,
                color: color,
              ));
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
    final bgColor = note.color ?? folder.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoteEditorScreen(note: note, folder: folder),
        ),
      ),
      onLongPress: () => _showOptions(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: inkColor(context), width: borderWidthHeavy),
        ),
        padding: const EdgeInsets.all(12),
        child: Text(
          note.displayTitle,
          style: displayM.copyWith(color: inkLight),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _NewNoteButton extends ConsumerWidget {
  final Folder folder;

  const _NewNoteButton({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final note = await ref
            .read(noteRepositoryProvider)
            .create(folder.id, rawMarkdown: '');
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NoteEditorScreen(note: note, folder: folder),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: inkColor(context),
          border: Border.all(color: inkColor(context), width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: folder.color,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Text(
          '+ Nota',
          style: labelBold.copyWith(color: paperColor(context)),
        ),
      ),
    );
  }
}

// ─── Next Class Banner (Flight integration) ─────────────────────────────────

class _NextClassBanner extends ConsumerWidget {
  final int folderId;
  const _NextClassBanner({required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(scheduleRepositoryProvider);

    return FutureBuilder<List<ScheduleBlock>>(
      future: repo.getByFolderId(folderId),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();

        final now = DateTime.now();
        final todayDay = _dayNameFromIndex(now.weekday - 1);
        final nowMinutes = now.hour * 60 + now.minute;

        final upcoming = _nextClass(snap.data!, todayDay, nowMinutes, now.weekday);
        if (upcoming == null) return const SizedBox.shrink();

        final text = upcoming.location != null && upcoming.location!.isNotEmpty
            ? '${upcoming.title} — ${upcoming.startTime}  ${upcoming.location}'
            : '${upcoming.title} — ${upcoming.startTime}';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accentLab.withAlpha(15),
            border: Border(
              bottom: BorderSide(color: accentLab, width: borderWidth),
            ),
          ),
          child: Text(
            text,
            style: bodyS.copyWith(color: accentLab),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  ScheduleBlock? _nextClass(
      List<ScheduleBlock> blocks, String todayDay, int nowMinutes, int weekday) {
    for (final b in blocks) {
      if (b.days.contains(todayDay) && b.startMinutes > nowMinutes) {
        return b;
      }
    }
    // If none today, find the next day
    final dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // Map schedule day keys to day order
    const dayMap = {
      'Lun': 'Mon', 'Mar': 'Tue', 'Mié': 'Wed', 'Jue': 'Thu',
      'Vie': 'Fri', 'Sáb': 'Sat', 'Dom': 'Sun',
    };
    int todayIdx = dayOrder.indexOf(_dayNameFromIndex(weekday - 1));
    if (todayIdx == -1) todayIdx = 0;

    for (int offset = 1; offset <= 7; offset++) {
      final idx = (todayIdx + offset) % 7;
      final engDay = dayOrder[idx];
      final espDay = dayMap.entries
          .firstWhere((e) => e.value == engDay, orElse: () => const MapEntry('', ''))
          .key;
      if (espDay.isEmpty) continue;
      for (final b in blocks) {
        if (b.days.contains(espDay)) return b;
      }
    }
    return null;
  }

  String _dayNameFromIndex(int idx) {
    const names = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return names[idx >= 0 && idx < 7 ? idx : 0];
  }
}
