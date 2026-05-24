import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/task.dart' as domain_task;
import '../../widgets/app_card.dart';
import '../../widgets/app_section_divider.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _taskController = TextEditingController();

  @override
  void dispose() {
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
    final dateStr = _formatDate(now);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final pendingAsync = ref.watch(pendingTasksProvider);
    final foldersAsync = ref.watch(activeFoldersProvider);
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final doneAsync = ref.watch(doneTodayTasksProvider);

    final pendingTasks = pendingAsync.valueOrNull ?? [];
    final folders = foldersAsync.valueOrNull ?? [];
    final spaces = spacesAsync.valueOrNull ?? [];
    final doneCount = doneAsync.valueOrNull?.length ?? 0;

    final nextTask = pendingTasks.isNotEmpty ? pendingTasks.first : null;
    final latestFolder = folders.isNotEmpty ? folders.first : null;

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── HEADER MONOLITO ──
            Container(
              width: double.infinity,
              color: inkColor(context),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            greeting.toUpperCase(),
                            style: labelBold.copyWith(
                              color: paperColor(context),
                              letterSpacing: 2,
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.settings,
                                size: 20,
                                color: paperColor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 48,
                        height: borderWidthHeavy,
                        color: paperColor(context).withAlpha(80),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeStr,
                        style: displayXL.copyWith(color: paperColor(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr.toUpperCase(),
                        style: bodyS.copyWith(color: inkGray),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 32,
                    bottom: -20,
                    child: Text(
                      'YuLi',
                      textAlign: TextAlign.right,
                      style: displayL.copyWith(
                        color: paperColor(context).withAlpha(20),
                        fontSize: 144,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: borderWidthHeavy,
              color: inkColor(context),
            ),

            // ── STATS BLOQUES ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatBlock(
                    label: 'PENDIENTES',
                    value: '${pendingTasks.length}',
                    color: accentFight,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                  ),
                  _StatBlock(
                    label: 'NOTAS',
                    value: '${folders.length}',
                    color: accentFlight,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                  ),
                  _StatBlock(
                    label: 'LABS',
                    value: '${spaces.length}',
                    color: accentLab,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.lab,
                  ),
                  _StatBlock(
                    label: 'HECHAS',
                    value: '$doneCount',
                    color: accentJournal,
                    onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'CAPTURAR'),
            ),
            const SizedBox(height: 12),

            // ── INPUT RÁPIDO ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _taskController,
                      style: bodyM.copyWith(color: inkColor(context)),
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Escribe una tarea...',
                        hintStyle: bodyM.copyWith(color: inkGray),
                        filled: true,
                        fillColor: cardBackground(context),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: inkBlack, width: borderWidthHeavy),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addQuickTask(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _addQuickTask,
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentFight,
                        border: Border.all(color: inkBlack, width: borderWidth),
                        boxShadow: const [
                          BoxShadow(
                            color: inkBlack,
                            offset: shadowOffset,
                            blurRadius: shadowBlurRadius,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 24,
                        color: paperLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'PENDIENTES'),
            ),
            const SizedBox(height: 12),

            // ── LISTA PENDIENTES ──
            if (pendingTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: AppCard(
                  borderColor: inkGray.withAlpha(80),
                  backgroundColor: paperColor(context),
                  child: Center(
                    child: Text(
                      'NADA PENDIENTE',
                      style: labelBold.copyWith(color: inkGray.withAlpha(120)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: pendingTasks.take(5).map((task) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TaskBlock(
                        task: task,
                        onToggle: () => ref.read(taskRepositoryProvider).markDone(task.id),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AppSectionDivider(label: 'NOTAS'),
            ),
            const SizedBox(height: 12),

            // ── LISTA CARPETAS ──
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: AppCard(
                  borderColor: inkGray.withAlpha(80),
                  backgroundColor: paperColor(context),
                  child: Center(
                    child: Text(
                      'SIN CARPETAS',
                      style: labelBold.copyWith(color: inkGray.withAlpha(120)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: folders.take(4).map((folder) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FolderBlock(
                        folder: folder,
                        onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 24),

            // ── DOS CARDS DESTACADAS ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _HighlightCard(
                      label: 'PRÓXIMA TAREA',
                      value: nextTask?.content ?? 'NADA',
                      color: accentFight,
                      onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HighlightCard(
                      label: 'CARPETA',
                      value: latestFolder?.name ?? 'SIN CARPETAS',
                      color: accentFlight,
                      onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.flight,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── BOTÓN IR AL TABLERO ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => ref.read(currentModeProvider.notifier).state = AppMode.fight,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: accentFight,
                    border: Border.all(color: inkBlack, width: borderWidth),
                    boxShadow: const [
                      BoxShadow(
                        color: inkBlack,
                        offset: shadowOffset,
                        blurRadius: shadowBlurRadius,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'IR AL TABLERO',
                        style: labelBold.copyWith(
                          color: paperLight,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: paperLight.withAlpha(220),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
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

// ── WIDGETS PRIVADOS ──

class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 40) / 2,
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: displayL.copyWith(color: paperLight, height: 1.0),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: labelBold.copyWith(
                color: paperLight.withAlpha(220),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskBlock extends StatelessWidget {
  final domain_task.Task task;
  final VoidCallback onToggle;

  const _TaskBlock({required this.task, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onToggle,
      borderColor: inkColor(context),
      backgroundColor: cardBackground(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border.all(color: accentFight, width: borderWidth),
            ),
          ),
          const SizedBox(width: 12),
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
    );
  }
}

class _FolderBlock extends StatelessWidget {
  final dynamic folder;
  final VoidCallback onTap;

  const _FolderBlock({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderColor: inkColor(context),
      backgroundColor: cardBackground(context),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            color: folder.color as Color? ?? inkGray,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder.name as String? ?? '',
              style: bodyM.copyWith(color: inkColor(context)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_forward, size: 16, color: inkGray),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _HighlightCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: labelBold.copyWith(
                color: paperLight.withAlpha(220),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: bodyM.copyWith(
                color: paperLight,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
