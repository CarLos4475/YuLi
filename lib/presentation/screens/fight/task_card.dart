import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart' show cleanMention;
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';

class TaskCard extends ConsumerStatefulWidget {
  final Task task;
  final bool isYesterday;
  final bool isDone;

  const TaskCard({
    super.key,
    required this.task,
    required this.isYesterday,
    this.isDone = false,
  });

  @override
  ConsumerState<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<TaskCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_completing) return;
    setState(() => _completing = true);

    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    if (!reducedMotion) {
      HapticFeedback.mediumImpact();
      await ref.read(taskRepositoryProvider).markDone(widget.task.id);
      await syncTaskCompletionToKanban(ref, widget.task.id);
      if (mounted) await _fadeController.forward();
    } else {
      await ref.read(taskRepositoryProvider).markDone(widget.task.id);
      await syncTaskCompletionToKanban(ref, widget.task.id);
    }
  }

  Future<void> _delete() async {
    await ref.read(taskRepositoryProvider).moveToTrash(widget.task.id);
  }

  void _showSendToKanban(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SendToKanbanSheet(task: widget.task),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final folderAsync = task.folderId != null
        ? ref.watch(folderByIdProvider(task.folderId!))
        : null;
    final folder = folderAsync?.valueOrNull;

    final borderCol = inkColor(context);

    Widget card = AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) => Opacity(
        opacity: _fadeAnimation.value,
        child: child,
      ),
      child: _CardContent(
        task: task,
        folder: folder,
        borderColor: borderCol,
        isDone: widget.isDone || _completing,
      ),
    );

    if (widget.isDone) {
      return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('done_${task.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          await _delete();
          return false;
        },
        background: const SizedBox.shrink(),
        secondaryBackground: _SwipeBackground(
          color: accentFight,
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
        ),
        child: card,
      ),
    );
    }

    // Long-press to send to Kanban
    card = GestureDetector(
      onLongPress: () => _showSendToKanban(context),
      child: card,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(task.id),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _complete();
          } else {
            await _delete();
          }
          return false;
        },
        background: _SwipeBackground(
          color: Colors.green,
          alignment: Alignment.centerLeft,
          icon: Icons.check,
        ),
        secondaryBackground: _SwipeBackground(
          color: accentFight,
          alignment: Alignment.centerRight,
          icon: Icons.delete_outline,
        ),
        child: card,
      ),
    );
  }
}

class _CardContent extends ConsumerWidget {
  final Task task;
  final Folder? folder;
  final Color borderColor;
  final bool isDone;

  const _CardContent({
    required this.task,
    required this.folder,
    required this.borderColor,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doneBackground = desaturate(accentFight, amount: 0.85)
        .withAlpha(60);

    final defaultStyle = bodyL.copyWith(
      color: inkColor(context),
      decoration: isDone ? TextDecoration.lineThrough : null,
      decorationThickness: 3.0,
      decorationColor: inkColor(context),
    );

    final contentText = cleanMention(task.content);

    Widget? dateChip;
    if (task.dueDate != null) {
      final color = _dueDateColor(task.dueDate!);
      dateChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: const [
            BoxShadow(
              color: inkBlack,
              offset: shadowOffset,
              blurRadius: shadowBlurRadius,
            ),
          ],
        ),
        child: Text(
          _formatDueDate(task.dueDate!),
          style: labelBold.copyWith(color: paperLight, fontSize: 10),
        ),
      );
    }

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDone ? doneBackground : cardBackground(context),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contentText, style: defaultStyle),
                    if (dateChip != null) ...[
                      const SizedBox(height: 6),
                      dateChip,
                    ],
                  ],
                ),
              ),
              if (folder != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: folder!.color,
                    border: Border.all(color: inkBlack, width: borderWidth),
                    boxShadow: const [
                      BoxShadow(
                        color: inkBlack,
                        offset: shadowOffset,
                        blurRadius: shadowBlurRadius,
                      ),
                    ],
                  ),
                  child: Text(
                    folder!.name,
                    style: labelBold.copyWith(
                      color: folder!.color.computeLuminance() > 0.4
                          ? inkBlack
                          : inkLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => _pickDueDate(context, ref),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: task.dueDate != null ? accentFight : paperColor(context),
                border: Border.all(color: inkBlack, width: borderWidth),
                boxShadow: const [
                  BoxShadow(
                    color: inkBlack,
                    offset: shadowOffset,
                    blurRadius: shadowBlurRadius,
                  ),
                ],
              ),
              child: Icon(
                task.dueDate != null
                    ? Icons.access_time_filled
                    : Icons.access_time,
                size: 12,
                color: task.dueDate != null ? paperLight : inkBlack,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _dueDateColor(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = due.difference(today).inDays;

    if (diff < 0) return accentFight;
    if (diff <= 1) return folderPalette[3];
    return inkGray;
  }

  String _formatDueDate(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = dueDay.difference(today).inDays;
    final time =
        '${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';

    if (diff == 0) return 'Hoy $time';
    if (diff == 1) return 'Mañana $time';
    return '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')} $time';
  }

  Future<void> _pickDueDate(BuildContext context, WidgetRef ref) async {
    if (task.dueDate != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: paperColor(ctx),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          title: Text(
            'Fecha límite',
            style: displayM.copyWith(color: inkColor(ctx)),
          ),
          content: Text(
            'Actual: ${task.dueDate!.day.toString().padLeft(2, '0')}/${task.dueDate!.month.toString().padLeft(2, '0')}/${task.dueDate!.year} ${task.dueDate!.hour.toString().padLeft(2, '0')}:${task.dueDate!.minute.toString().padLeft(2, '0')}',
            style: bodyM.copyWith(color: inkColor(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: Text(
                'BORRAR',
                style: labelBold.copyWith(color: accentFight),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: Text(
                'CAMBIAR',
                style: labelBold.copyWith(color: inkColor(ctx)),
              ),
            ),
          ],
        ),
      );

      if (action == 'clear') {
        await ref.read(taskRepositoryProvider).updateDueDate(task.id, null);
        return;
      }
      if (action != 'change') return;
    }

    if (!context.mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          datePickerTheme: const DatePickerThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: task.dueDate != null
          ? TimeOfDay.fromDateTime(task.dueDate!)
          : const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          timePickerTheme: const TimePickerThemeData(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    final dt = DateTime(
      picked.year, picked.month, picked.day, time.hour, time.minute,
    );
    await ref.read(taskRepositoryProvider).updateDueDate(task.id, dt);
  }
}

class _SwipeBackground extends StatelessWidget {
  final Color color;
  final Alignment alignment;
  final IconData icon;

  const _SwipeBackground({
    required this.color,
    required this.alignment,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(icon, color: inkColor(context), size: 24),
    );
  }
}

/// Bottom sheet to send a Fight task to a Kanban column.
class _SendToKanbanSheet extends ConsumerWidget {
  final Task task;
  const _SendToKanbanSheet({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final spaces = spacesAsync.valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Enviar a Lab',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
            if (spaces.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  'No hay Lab Spaces. Crea uno primero.',
                  style: bodyS.copyWith(color: inkGray),
                ),
              )
            else
              ...spaces.map((space) => _SpaceRow(task: task, space: space)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SpaceRow extends ConsumerWidget {
  final Task task;
  final LabSpace space;
  const _SpaceRow({required this.task, required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnsAsync = ref.watch(kanbanColumnsProvider(space.id));
    final columns = columnsAsync.valueOrNull ?? [];

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(space.name,
          style: bodyM.copyWith(color: space.accentColor, fontWeight: FontWeight.w700)),
      children: columns.map((col) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            int? folderColor;
            if (task.folderId != null) {
              final folder =
                  await ref.read(folderRepositoryProvider).getById(task.folderId!);
              folderColor = folder?.color.toARGB32();
            }
            await ref.read(kanbanCardRepositoryProvider).create(
                  labSpaceId: space.id,
                  columnId: col.id,
                  title: task.content,
                  originTaskId: task.id,
                  originFolderColor: folderColor,
                  dueDate: task.dueDate,
                );
            if (context.mounted) Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 10, 24, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(col.name,
                  style: bodyM.copyWith(color: inkColor(context))),
            ),
          ),
        );
      }).toList(),
    );
  }
}
