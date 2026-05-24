import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/task.dart' as domain_task;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Timer _timer;
  final _taskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    _taskController.dispose();
    super.dispose();
  }

  void _addQuickTask() {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final expires = DateTime(now.year, now.month, now.day, 23, 59, 59);
    ref.read(taskRepositoryProvider).save(
          domain_task.Task(
            id: 0,
            content: text,
            status: domain_task.TaskStatus.pending,
            folderId: null,
            createdAt: now,
            expiresAt: expires,
          ),
        );
    _taskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = _greeting(now.hour);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final dateStr = _formatDate(now);

    final pendingAsync = ref.watch(pendingTasksProvider);
    final foldersAsync = ref.watch(activeFoldersProvider);
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final doneAsync = ref.watch(doneTodayTasksProvider);

    final pendingTasks = pendingAsync.valueOrNull ?? [];
    final folders = foldersAsync.valueOrNull ?? [];
    final spaceCount = spacesAsync.valueOrNull?.length ?? 0;
    final doneCount = doneAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            // Greeting
            Center(
              child: Text(
                greeting,
                style: displayL.copyWith(color: inkGray.withAlpha(120)),
              ),
            ),
            const SizedBox(height: 4),
            // Clock
            Center(
              child: Text(
                timeStr,
                style: displayXL.copyWith(color: inkColor(context)),
              ),
            ),
            const SizedBox(height: 4),
            // Date
            Center(
              child: Text(
                dateStr,
                style: bodyL.copyWith(color: inkGray),
              ),
            ),
            const SizedBox(height: 32),
            // Stats row
            Row(
              children: [
                _StatCard(
                  label: 'Pendientes',
                  value: '${pendingTasks.length}',
                  color: accentFight,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Notas',
                  value: '${folders.length}',
                  color: accentFlight,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Labs',
                  value: '$spaceCount',
                  color: accentLab,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  label: 'Hechas',
                  value: '$doneCount',
                  color: accentJournal,
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Quick task input
            Text(
              'Tarea rápida',
              style: labelBold.copyWith(color: inkGray),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: inkGray.withAlpha(80), width: 1),
                    ),
                    child: TextField(
                      controller: _taskController,
                      style: bodyM.copyWith(color: inkColor(context)),
                      decoration: const InputDecoration(
                        hintText: 'Escribe una tarea...',
                        hintStyle: TextStyle(color: inkGray),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => _addQuickTask(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addQuickTask,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accentFight,
                      border: Border.all(color: accentFight, width: 1),
                    ),
                    child: const Icon(Icons.add, size: 18, color: paperLight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Next tasks
            Text(
              'Próximas tareas',
              style: labelBold.copyWith(color: inkGray),
            ),
            const SizedBox(height: 8),
            if (pendingTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Sin tareas pendientes',
                  style: bodyS.copyWith(color: inkGray.withAlpha(120)),
                ),
              )
            else
              ...pendingTasks.take(5).map((task) => _TaskRow(task: task)),
            const SizedBox(height: 24),
            // Folders quick links
            Text(
              'Tus notas',
              style: labelBold.copyWith(color: inkGray),
            ),
            const SizedBox(height: 8),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Sin carpetas',
                  style: bodyS.copyWith(color: inkGray.withAlpha(120)),
                ),
              )
            else
              ...folders.take(4).map((f) => _FolderRow(
                    folder: f,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                  )),
            const SizedBox(height: 32),
            // Go to board
            Center(
              child: GestureDetector(
                onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: inkColor(context),
                    border: Border.all(color: inkColor(context), width: borderWidth),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward, size: 18, color: paperColor(context)),
                      const SizedBox(width: 8),
                      Text(
                        'Ir al tablero',
                        style: labelBold.copyWith(color: paperColor(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting(int hour) {
    if (hour < 6) return 'Buenas noches';
    if (hour < 12) return 'Buenos días';
    if (hour < 18) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _formatDate(DateTime d) {
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return '${d.day} de ${months[d.month - 1]} de ${d.year}';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: borderWidth),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: displayM.copyWith(color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: bodyS.copyWith(color: inkGray),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final domain_task.Task task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(taskRepositoryProvider).markDone(task.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: inkGray.withAlpha(30), width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: accentFight, width: borderWidth),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.content,
                style: bodyM.copyWith(color: inkColor(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final dynamic folder;
  final VoidCallback onTap;

  const _FolderRow({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: inkGray.withAlpha(30), width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              color: folder.color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                style: bodyM.copyWith(color: inkColor(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
