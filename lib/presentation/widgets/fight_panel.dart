import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_tokens.dart';
import '../providers/database_providers.dart';
import '../providers/task_providers.dart';
import '../providers/folder_providers.dart';
import 'app_card.dart';
import '../../domain/models/task.dart';
import '../../domain/models/folder.dart';

class FightPanel extends ConsumerWidget {
  final int folderId;
  final ScrollController scrollController;
  final void Function(Task) onTapTask;

  const FightPanel({
    super.key,
    required this.folderId,
    required this.scrollController,
    required this.onTapTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(pendingTasksForFolderProvider(folderId));
    final tasks = tasksAsync.valueOrNull ?? [];
    final folderAsync = ref.watch(folderByIdProvider(folderId));
    final folder = folderAsync.valueOrNull;

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            width: 40,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: inkGray,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'FIGHT — tareas de esta carpeta (toca para seleccionar)',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      'Sin tareas pendientes',
                      style: bodyS.copyWith(color: inkGray),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => PanelTaskTile(
                      task: tasks[i],
                      folder: folder,
                      onTapText: () => onTapTask(tasks[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class PanelTaskTile extends ConsumerWidget {
  final Task task;
  final Folder? folder;
  final VoidCallback onTapText;

  const PanelTaskTile({
    super.key,
    required this.task,
    required this.folder,
    required this.onTapText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = this.folder;
    final defaultStyle = bodyM.copyWith(color: inkColor(context));

    InlineSpan contentSpan;

    if (folder != null) {
      final text = task.content;
      final regex = RegExp(r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)');
      final matches = regex.allMatches(text).toList();
      final targetClean = removeAccents(folder.name.toLowerCase());
      
      final validMatches = matches.where((m) {
        final matchedName = m.group(1)!;
        return removeAccents(matchedName.toLowerCase()) == targetClean;
      }).toList();

      if (validMatches.isEmpty) {
        contentSpan = TextSpan(text: text, style: defaultStyle);
      } else {
        final folderColor = folder.color;
        final spans = <InlineSpan>[];
        int lastIndex = 0;

        final mentionStyle = defaultStyle.copyWith(
          color: folderColor,
          fontWeight: FontWeight.bold,
        );

        for (final match in validMatches) {
          if (match.start > lastIndex) {
            spans.add(TextSpan(
              text: text.substring(lastIndex, match.start),
              style: defaultStyle,
            ));
          }
          final matchedText = match.group(0)!;
          final folderPart = matchedText.substring(1);
          spans.add(TextSpan(
            text: folderPart,
            style: mentionStyle,
          ));
          lastIndex = match.end;
        }

        if (lastIndex < text.length) {
          spans.add(TextSpan(
            text: text.substring(lastIndex),
            style: defaultStyle,
          ));
        }

        contentSpan = TextSpan(children: spans);
      }
    } else {
      contentSpan = TextSpan(text: task.content, style: defaultStyle);
    }

    Widget? dateChip;
    if (task.dueDate != null) {
      final color = _dueDateColor(task.dueDate!);
      dateChip = Container(
        margin: const EdgeInsets.only(top: 4),
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

    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapText,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(contentSpan),
                  if (dateChip != null) dateChip,
                ],
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(taskRepositoryProvider).markDone(task.id),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.check, color: accentFight, size: 18),
            ),
          ),
        ],
      ),
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
}
