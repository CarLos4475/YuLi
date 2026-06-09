// Interactive task block placed on a drawing canvas (whiteboard / notebook).
// Mirrors the note editor's TareasBlock UI, but its tasks are stored as ids on
// a [CanvasTaskBlock] inside the canvas DrawingData (not a note_block row). The
// FIGHT/LAB wiring is delegated to [NoteBlockActions] so linking/done/trash
// behave identically to a note's task block.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/task.dart';
import 'note_block_actions.dart';
import 'note_cell_model.dart';

/// Default box width for a freshly inserted block (scale 1.0). The card content
/// is laid out at `w / scale` and uniformly scaled by [CanvasTaskBlock.scale]
/// via a `FittedBox`, so corner-resize grows the whole block (text included)
/// while side-resize reflows the text at the same font size.
const double kCanvasTaskBlockDefaultW = 320.0;

// Reactive: refreshes when the linked card is created/moved/deleted (was a
// one-shot read, so the badge could go stale).
final _kanbanByTaskProvider =
    StreamProvider.family<String?, int>((ref, taskId) {
  final labRepo = ref.watch(labSpaceRepositoryProvider);
  return ref
      .watch(kanbanCardRepositoryProvider)
      .watchByOriginTaskId(taskId)
      .asyncMap((card) async {
    if (card == null) return null;
    final space = await labRepo.getById(card.labSpaceId);
    return space?.name;
  });
});

enum _DeleteChoice { unlink, hard }

class CanvasTaskBlockOverlay extends ConsumerStatefulWidget {
  final CanvasTaskBlock block;
  final int noteId;
  final int? folderId;
  final String folderName;
  final Color accent;

  /// True when the user can tap tasks / use the block's buttons. False while a
  /// drawing tool without palm-rejection is active, or the block is lasso-
  /// selected / mid-gesture (then the box is for transform).
  final bool interactive;

  /// Persist the canvas DrawingData after a task mutation changed [block.taskIds].
  final Future<void> Function() onPersist;

  /// Rebuild the editor after a task was added/removed, so the card reflects
  /// the in-memory [block.taskIds] change immediately (the canvas block's ids
  /// aren't a watched provider — only the note's linked tasks are).
  final VoidCallback onTasksChanged;

  /// Reports the block's natural height (in world px, after scaling) so the
  /// editor can keep [CanvasTaskBlock.h] in sync for the lasso bounding box.
  final ValueChanged<double> onHeightMeasured;

  const CanvasTaskBlockOverlay({
    super.key,
    required this.block,
    required this.noteId,
    required this.folderId,
    required this.folderName,
    required this.accent,
    required this.interactive,
    required this.onPersist,
    required this.onTasksChanged,
    required this.onHeightMeasured,
  });

  @override
  ConsumerState<CanvasTaskBlockOverlay> createState() =>
      _CanvasTaskBlockOverlayState();
}

class _CanvasTaskBlockOverlayState
    extends ConsumerState<CanvasTaskBlockOverlay> {
  final _newTaskCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _contentKey = GlobalKey();
  bool _showInput = false;
  OverlayEntry? _inputEntry;

  NoteBlockActions get _actions => NoteBlockActions(
        ref: ref,
        noteId: widget.noteId,
        folderId: widget.folderId,
      );

  @override
  void dispose() {
    _removeInputBar();
    _inputFocus.dispose();
    _newTaskCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CanvasTaskBlockOverlay old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
  }

  /// Reports the block's rendered footprint height: the content's natural
  /// height at the current layout width, times [CanvasTaskBlock.scale].
  void _reportHeight() {
    final ctx = _contentKey.currentContext;
    if (ctx == null || !mounted) return;
    final hb = ctx.size?.height;
    if (hb == null || hb <= 0) return;
    final target = hb * widget.block.scale;
    if ((target - widget.block.h).abs() > 0.5) {
      widget.onHeightMeasured(target);
    }
  }

  // ─── Task mutations (taskIds live on the canvas block, not a DB row) ──────

  Future<void> _submitNew() async {
    final content = _newTaskCtrl.text.trim();
    if (content.isEmpty) return;
    final now = DateTime.now();
    final task = await ref.read(taskRepositoryProvider).save(
          Task(
            id: 0,
            content: content,
            status: TaskStatus.pending,
            folderId: widget.folderId,
            createdAt: now,
            expiresAt: DateTime(now.year, now.month, now.day, 23, 59, 59),
          ),
        );
    await ref.read(noteRepositoryProvider).linkTask(widget.noteId, task.id);
    widget.block.taskIds.add(task.id);
    await widget.onPersist();
    widget.onTasksChanged();
    _newTaskCtrl.clear();
    // Stay open for rapid entry; keep the keyboard up.
    _inputFocus.requestFocus();
    if (mounted) setState(() {});
  }

  // ─── Add-task input, docked above the keyboard ────────────────────────────

  void _toggleInput() => _showInput ? _closeInput() : _openInput();

  void _openInput() {
    setState(() => _showInput = true);
    _inputEntry = OverlayEntry(builder: _buildInputBar);
    Overlay.of(context, rootOverlay: true).insert(_inputEntry!);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  void _closeInput() {
    _removeInputBar();
    _newTaskCtrl.clear();
    if (mounted) setState(() => _showInput = false);
  }

  void _removeInputBar() {
    _inputEntry?.remove();
    _inputEntry = null;
  }

  Widget _buildInputBar(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      children: [
        // Tap anywhere outside the bar discards the add-task edit.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeInput,
          ),
        ),
        Positioned(
      left: 0,
      right: 0,
      bottom: insets,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(top: BorderSide(color: yBorderStrong, width: yLineHeavy)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10),
                  color: widget.accent,
                ),
                Expanded(
                  child: TextField(
                    controller: _newTaskCtrl,
                    focusNode: _inputFocus,
                    onSubmitted: (_) => _submitNew(),
                    textInputAction: TextInputAction.done,
                    style: yBody(size: 15, color: yInk),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                      filled: false,
                      hintText: 'nueva tarea en @${widget.folderName.toLowerCase()}…',
                      hintStyle: yBody(size: 15, color: yMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _submitNew,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yFight,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: const Text('+',
                        style: TextStyle(
                            fontSize: 20, color: yCream, height: 1.0)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeInput,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yCream,
                      border: Border.all(color: yBorderStrong, width: yLineMid),
                    ),
                    child: const Icon(YuLiIcons.chevronDown,
                        color: yInk, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
        ),
      ],
    );
  }

  Future<void> _onCheck(Task t) => _actions.toggleDone(t);

  Future<void> _onLongPress(Task t) async {
    final spaces = ref.read(activeLabSpacesProvider).valueOrNull ?? [];
    if (spaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay spaces activos'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final picked = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => _SpacePickerDialog(spaces: spaces),
    );
    if (picked == null) return;
    await _actions.linkTaskToSpace(t, picked.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Linkeada a ${picked.name}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _onDelete(Task t) async {
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title:
            Text('Borrar tarea', style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text(
          '¿Solo desenlazar de la nota (sigue viva en FIGHT) o borrar de todos los lugares?',
          style: yBody(size: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, _DeleteChoice.unlink),
              child: const Text('Solo desenlazar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _DeleteChoice.hard),
              child: const Text('Borrar de todos lados')),
        ],
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case _DeleteChoice.unlink:
        await ref
            .read(noteRepositoryProvider)
            .unlinkTask(widget.noteId, t.id);
      case _DeleteChoice.hard:
        await ref.read(taskRepositoryProvider).moveToTrash(t.id);
    }
    widget.block.taskIds.remove(t.id);
    await widget.onPersist();
    widget.onTasksChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Keep the block's stored height in sync with its content after each build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());

    final scale = widget.block.scale;
    // Content lays out (text reflow) at this width; FittedBox.fitWidth then
    // scales it uniformly up to the rendered footprint width [block.w]. The
    // scale factor it applies is block.w / contentWidth == scale.
    final contentWidth =
        scale > 0 ? widget.block.w / scale : widget.block.w;

    final Widget box = SizedBox(
      width: widget.block.w,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: contentWidth,
          child: KeyedSubtree(key: _contentKey, child: _buildCard()),
        ),
      ),
    );

    final angle = widget.block.rotation;
    if (angle == 0.0) return box;
    return Transform.rotate(
        angle: angle, alignment: Alignment.center, child: box);
  }

  Widget _buildCard() {
    final tasksAsync = ref.watch(noteLinkedTasksProvider(widget.noteId));
    final allTasks = tasksAsync.valueOrNull ?? [];
    final blockTasks = allTasks
        .where((t) =>
            widget.block.taskIds.contains(t.id) &&
            t.status != TaskStatus.trash)
        .toList()
      ..sort((a, b) {
        final aDone = a.status == TaskStatus.done;
        final bDone = b.status == TaskStatus.done;
        if (aDone != bDone) return aDone ? 1 : -1;
        return a.createdAt.compareTo(b.createdAt);
      });

    final card = Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        borderRadius: BorderRadius.zero,
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: widget.accent, width: 6)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('> TAREAS',
                    style: yMono(
                        size: 10,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yInk)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'se enlazan a fight con @${widget.folderName.toLowerCase()}',
                    overflow: TextOverflow.ellipsis,
                    style: yMono(size: 10, color: yMuted, tracking: 1),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleInput,
                  child: Text(_showInput ? 'CERRAR' : '+ TAREA',
                      style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (blockTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('sin tareas',
                    style: yMono(
                        size: 10,
                        color: yMuted.withValues(alpha: 0.6),
                        tracking: 1.2)),
              ),
            for (final t in blockTasks)
              _CanvasTaskRow(
                task: t,
                onCheck: () => _onCheck(t),
                onLongPress: () => _onLongPress(t),
                onDelete: () => _onDelete(t),
              ),
          ],
        ),
      ),
    );

    return widget.interactive ? card : IgnorePointer(child: card);
  }
}

class _CanvasTaskRow extends ConsumerWidget {
  final Task task;
  final VoidCallback onCheck;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _CanvasTaskRow({
    required this.task,
    required this.onCheck,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.status == TaskStatus.done;
    final linkedSpaceName = ref.watch(_kanbanByTaskProvider(task.id)).valueOrNull;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Container(
        color: done ? yCream2 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCheck,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? yInk : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: done
                    ? const Text('✓',
                        style: TextStyle(
                            fontSize: 12,
                            color: yCream,
                            height: 1.0,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            if (task.folderId != null) ...[
              Builder(builder: (context) {
                final fColor = ref
                    .watch(folderByIdProvider(task.folderId!))
                    .valueOrNull
                    ?.color;
                if (fColor == null) return const SizedBox.shrink();
                return Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsets.only(right: 6),
                  color: fColor,
                );
              }),
            ],
            Expanded(
              child: Text(
                cleanMention(task.content),
                style: yBody(
                  size: 14,
                  weight: FontWeight.w500,
                  color: done ? yMuted : yInk,
                  height: 1.3,
                ).copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            _LinkChip(text: '→ FIGHT', bg: yFight),
            if (linkedSpaceName != null) ...[
              const SizedBox(width: 4),
              _LinkChip(text: '→ ${linkedSpaceName.toUpperCase()}', bg: yLab),
            ],
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(YuLiIcons.close,
                    size: 14, color: yMuted.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String text;
  final Color bg;

  const _LinkChip({required this.text, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yBorderStrong, width: 1.5),
      ),
      child: Text(text,
          style: yMono(
              size: 8, weight: FontWeight.w700, tracking: 1, color: yCream)),
    );
  }
}

class _SpacePickerDialog extends StatelessWidget {
  final List<LabSpace> spaces;
  const _SpacePickerDialog({required this.spaces});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(border: Border.all(color: yBorderStrong, width: yLineHeavy)),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Linkear a space',
                style: ySans(size: 20, weight: FontWeight.w700, color: yInk)),
            const SizedBox(height: 12),
            for (final s in spaces)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, color: s.accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child:
                            Text(s.name, style: ySans(size: 16, color: yInk)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
