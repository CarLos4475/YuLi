import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../../domain/models/task.dart' as domain_task;
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/schedule_block.dart';
import '../settings/settings_screen.dart';
import '../flight/schedule_screen.dart';

// ─── All-schedule-blocks provider for "próxima clase" aggregation ─────────

final _allScheduleBlocksProvider = StreamProvider<List<ScheduleBlock>>((ref) {
  return ref.watch(scheduleRepositoryProvider).watchAll();
});

// ─── HomeScreen ───────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _taskController = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Folder> _mentionFolders = [];
  int? _mentionStart;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _taskController.addListener(_onTextChanged);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    _clockTimer?.cancel();
    _taskController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static const _maxChars = 280;

  int get _contentLength =>
      _taskController.text.replaceAll(RegExp(r'@\S+'), '').length;

  void _addQuickTask() {
    final raw = _taskController.text.trim();
    if (raw.isEmpty || _contentLength > _maxChars) return;
    final now = DateTime.now();
    final expires = DateTime(now.year, now.month, now.day, 23, 59, 59);

    int? folderId;
    final mentionMatch = RegExp(
      r'@([a-zA-Z0-9_áéíóúÁÉÍÓÚñÑüÜ]+)',
    ).firstMatch(raw);
    if (mentionMatch != null) {
      final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
      final name = mentionMatch.group(1)!;
      final cleanName = removeAccents(name.toLowerCase());
      final match = folders.where(
        (f) => removeAccents(f.name.toLowerCase()) == cleanName,
      );
      if (match.isNotEmpty) folderId = match.first.id;
    }

    ref
        .read(taskRepositoryProvider)
        .save(
          domain_task.Task(
            id: 0,
            content: raw,
            status: domain_task.TaskStatus.pending,
            folderId: folderId,
            createdAt: now,
            expiresAt: expires,
          ),
        );
    _taskController.clear();
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _onTextChanged() {
    final text = _taskController.text;
    final cursor = _taskController.selection.baseOffset;
    if (cursor < 0) return;

    final before = cursor > 0 ? text.substring(0, cursor) : '';
    final atIndex = before.lastIndexOf('@');
    final hasSpaceAfterAt =
        atIndex >= 0 &&
        !before.substring(atIndex).contains(' ') &&
        !before.substring(atIndex).contains('\n');

    if (atIndex >= 0 && hasSpaceAfterAt) {
      final query = before.substring(atIndex + 1).toLowerCase();
      _showMentionPopup(query);
      _mentionStart = atIndex;
    } else {
      _removeOverlay();
      _mentionStart = null;
    }
  }

  void _showMentionPopup(String query) {
    final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
    final cleanQuery = removeAccents(query.toLowerCase());
    final filtered =
        folders
            .where(
              (f) => removeAccents(f.name.toLowerCase()).contains(cleanQuery),
            )
            .toList();

    if (filtered.isEmpty) {
      _removeOverlay();
      return;
    }

    setState(() => _mentionFolders = filtered);

    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder:
          (ctx) => Positioned(
            width: 240,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: _mentionPopupOffset(ctx),
              child: Material(
                color: Colors.transparent,
                child: _MentionPopup(
                  folders: _mentionFolders,
                  onSelect: _onMentionSelect,
                ),
              ),
            ),
          ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Offset _mentionPopupOffset(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (!keyboardVisible) return const Offset(0, 56);

    final visibleItems = _mentionFolders.length.clamp(1, 4);
    final popupHeight = visibleItems * 42.0;
    return Offset(0, -popupHeight - 8);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onMentionSelect(Folder folder) {
    _removeOverlay();
    if (_mentionStart == null) return;

    final text = _taskController.text;
    final cursor = _taskController.selection.baseOffset;
    final replacement = '@${folder.name}';
    final newText =
        text.substring(0, _mentionStart) + replacement + text.substring(cursor);
    _taskController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: _mentionStart! + replacement.length,
      ),
    );
    _mentionStart = null;
    _focusNode.requestFocus();
  }

  void _goTo(AppMode mode) {
    ref.read(currentModeProvider.notifier).state = mode;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = _greeting(now.hour).toUpperCase();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateLong = _formatDateLong(now).toUpperCase();

    return Scaffold(
      backgroundColor: paperColor(context),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _CommandHeader(
              greeting: greeting,
              timeStr: timeStr,
              dateLong: dateLong,
              onSettings:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
            ),
            Expanded(
              child: _DailyHome(
                controller: _taskController,
                focusNode: _focusNode,
                layerLink: _layerLink,
                onSubmit: _addQuickTask,
                onFight: () => _goTo(AppMode.fight),
                onFlight: () => _goTo(AppMode.flight),
                onLab: () => _goTo(AppMode.lab),
                onOpenSchedule:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
                    ),
                onOpenNote: (noteId) {
                  ref.read(pendingNoteNavigationProvider.notifier).state =
                      noteId;
                  _goTo(AppMode.flight);
                },
                onOpenSpace: (spaceId) {
                  ref.read(pendingLabSpaceNavigationProvider.notifier).state =
                      spaceId;
                  _goTo(AppMode.lab);
                },
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

  static const _kWeekdayLong = [
    'LUNES',
    'MARTES',
    'MIÉRCOLES',
    'JUEVES',
    'VIERNES',
    'SÁBADO',
    'DOMINGO',
  ];

  static const _kMonths = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String _formatDateLong(DateTime d) {
    final wd = _kWeekdayLong[d.weekday - 1];
    return '$wd ${d.day} DE ${_kMonths[d.month - 1].toUpperCase()} DE ${d.year}';
  }
}

class _CommandHeader extends StatelessWidget {
  final String greeting;
  final String timeStr;
  final String dateLong;
  final VoidCallback onSettings;

  const _CommandHeader({
    required this.greeting,
    required this.timeStr,
    required this.dateLong,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: ySans(
                    size: 42,
                    weight: FontWeight.w800,
                    color: inkColor(context),
                    height: 0.9,
                  ).copyWith(letterSpacing: -2.5),
                  children: const [
                    TextSpan(text: 'Yu'),
                    TextSpan(text: 'Li', style: TextStyle(color: yAmber2)),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Container(width: 26, height: 3, color: yFight),
                  const SizedBox(width: 7),
                  Container(width: 26, height: 3, color: yFlight),
                  const SizedBox(width: 7),
                  Container(width: 26, height: 3, color: yLab),
                ],
              ),
            ],
          ),
          const SizedBox(width: 30),
          Container(width: yLineThin, height: 56, color: yBorderStrong),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting · Carlos',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.8,
                    color: inkColor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  dateLong,
                  style: yMono(size: 10, tracking: 1.4, color: yMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(width: yLineThin, height: 56, color: yBorderStrong),
          const SizedBox(width: 26),
          Text(
            timeStr,
            style: ySans(
              size: 44,
              weight: FontWeight.w800,
              color: inkColor(context),
              height: 0.9,
            ).copyWith(letterSpacing: -2),
          ),
          const SizedBox(width: 22),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSettings,
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yAmber2,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(YuLiIcons.settings, color: yCream, size: 25),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyHome extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final LayerLink layerLink;
  final VoidCallback onSubmit;
  final VoidCallback onFight;
  final VoidCallback onFlight;
  final VoidCallback onLab;
  final VoidCallback onOpenSchedule;
  final ValueChanged<int> onOpenNote;
  final ValueChanged<int> onOpenSpace;

  const _DailyHome({
    required this.controller,
    required this.focusNode,
    required this.layerLink,
    required this.onSubmit,
    required this.onFight,
    required this.onFlight,
    required this.onLab,
    required this.onOpenSchedule,
    required this.onOpenNote,
    required this.onOpenSpace,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingTasksProvider).valueOrNull ?? [];
    final yesterday = ref.watch(yesterdayTasksProvider).valueOrNull ?? [];
    final expired = ref.watch(vencidasTasksProvider).valueOrNull ?? [];
    final folders = ref.watch(activeFoldersProvider).valueOrNull ?? [];
    final notes = List.of(ref.watch(recentNotesProvider).valueOrNull ?? [])
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final spaces =
        List<LabSpace>.of(ref.watch(activeLabSpacesProvider).valueOrNull ?? [])
          ..removeWhere((space) => space.status != LabSpaceStatus.active)
          ..sort((a, b) {
            final aDue = a.dueDate;
            final bDue = b.dueDate;
            if (aDue == null && bDue == null) {
              return b.createdAt.compareTo(a.createdAt);
            }
            if (aDue == null) return 1;
            if (bDue == null) return -1;
            return aDue.compareTo(bDue);
          });
    final blocks = ref.watch(_allScheduleBlocksProvider).valueOrNull ?? [];
    final urgent = _collectUrgentTasks(pending, yesterday, expired);
    final nextClass = _findNextClass(blocks, DateTime.now());
    final nextFolder =
        nextClass?.block.folderId == null
            ? null
            : _findFolder(folders, nextClass!.block.folderId!);
    final recentNote = notes.isEmpty ? null : notes.first;
    final recentFolder =
        recentNote == null ? null : _findFolder(folders, recentNote.folderId);
    final activeSpace = spaces.isEmpty ? null : spaces.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final nowPanel = _NowPanel(
          controller: controller,
          focusNode: focusNode,
          layerLink: layerLink,
          onSubmit: onSubmit,
          urgent: urgent,
          folders: folders,
          nextClass: nextClass,
          nextClassAccent: nextFolder?.color ?? yFlight,
          recentNote: recentNote,
          recentNoteAccent: recentFolder?.color ?? yFlight,
          activeSpace: activeSpace,
          onFight: onFight,
          onOpenSchedule: onOpenSchedule,
          onOpenNote: onOpenNote,
          onOpenSpace: onOpenSpace,
        );
        final modes = _ModeLaunchStack(
          urgentCount: urgent.length,
          folderCount: folders.length,
          spaceCount: spaces.length,
          onFight: onFight,
          onFlight: onFlight,
          onLab: onLab,
        );

        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(height: 680, child: nowPanel),
                const SizedBox(height: 12),
                SizedBox(height: 390, child: modes),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: nowPanel),
              const SizedBox(width: 12),
              SizedBox(
                width: (constraints.maxWidth * 0.32).clamp(310.0, 500.0),
                child: modes,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NowPanel extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final LayerLink layerLink;
  final VoidCallback onSubmit;
  final List<domain_task.Task> urgent;
  final List<Folder> folders;
  final _NextOccurrence? nextClass;
  final Color nextClassAccent;
  final Note? recentNote;
  final Color recentNoteAccent;
  final LabSpace? activeSpace;
  final VoidCallback onFight;
  final VoidCallback onOpenSchedule;
  final ValueChanged<int> onOpenNote;
  final ValueChanged<int> onOpenSpace;

  const _NowPanel({
    required this.controller,
    required this.focusNode,
    required this.layerLink,
    required this.onSubmit,
    required this.urgent,
    required this.folders,
    required this.nextClass,
    required this.nextClassAccent,
    required this.recentNote,
    required this.recentNoteAccent,
    required this.activeSpace,
    required this.onFight,
    required this.onOpenSchedule,
    required this.onOpenNote,
    required this.onOpenSpace,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AHORA',
          style: ySans(
            size: 54,
            weight: FontWeight.w800,
            color: inkColor(context),
            height: 0.9,
          ).copyWith(letterSpacing: -2.2),
        ),
        const SizedBox(height: 10),
        Expanded(
          flex: 5,
          child: _NextClassSpotlight(
            occurrence: nextClass,
            accent: nextClassAccent,
            onTap: onOpenSchedule,
          ),
        ),
        const SizedBox(height: 10),
        _QuickCaptureBar(
          controller: controller,
          focusNode: focusNode,
          layerLink: layerLink,
          onSubmit: onSubmit,
        ),
        const SizedBox(height: 12),
        _SectionLabel(label: 'TAREAS URGENTES', count: urgent.length),
        const SizedBox(height: 7),
        Expanded(
          flex: 4,
          child: _UrgentTaskList(
            tasks: urgent,
            folders: folders,
            onTap: onFight,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 4,
          child: _RecentActivityStrip(
            note: recentNote,
            noteAccent: recentNoteAccent,
            space: activeSpace,
            onOpenNote: onOpenNote,
            onOpenSpace: onOpenSpace,
          ),
        ),
      ],
    );
  }
}

class _NextClassSpotlight extends StatelessWidget {
  final _NextOccurrence? occurrence;
  final Color accent;
  final VoidCallback onTap;

  const _NextClassSpotlight({
    required this.occurrence,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final block = occurrence?.block;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: paperColor(context),
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 10, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'PRÓXIMA CLASE',
                      style: yMono(
                        size: 11,
                        weight: FontWeight.w700,
                        tracking: 1.8,
                        color: yMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      block?.title ?? 'Sin clases programadas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ySans(
                        size: 38,
                        weight: FontWeight.w800,
                        color: inkColor(context),
                        height: 0.95,
                      ).copyWith(letterSpacing: -1.2),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Icon(YuLiIcons.calendarDays, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          occurrence == null
                              ? 'Abrir horario'
                              : '${occurrence!.label} · ${block!.startTime}',
                          style: yMono(
                            size: 11,
                            weight: FontWeight.w700,
                            tracking: 1.2,
                            color: inkColor(context),
                          ),
                        ),
                        if (block?.location != null &&
                            block!.location!.isNotEmpty) ...[
                          const SizedBox(width: 20),
                          Container(
                            width: yLineThin,
                            height: 18,
                            color: yBorderSoft,
                          ),
                          const SizedBox(width: 20),
                          Icon(YuLiIcons.mapPin, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              block.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: yMono(
                                size: 11,
                                weight: FontWeight.w700,
                                tracking: 1.2,
                                color: inkColor(context),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(YuLiIcons.arrowRight, size: 20, color: accent),
                      ],
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

class _QuickCaptureBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final LayerLink layerLink;
  final VoidCallback onSubmit;

  const _QuickCaptureBar({
    required this.controller,
    required this.focusNode,
    required this.layerLink,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: layerLink,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: yFight,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [BoxShadow(color: yInk, offset: Offset(4, 4))],
        ),
        child: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, _) {
            final contentLength =
                value.text.replaceAll(RegExp(r'@\S+'), '').length;
            final overLimit = contentLength > _HomeScreenState._maxChars;
            final enabled = value.text.trim().isNotEmpty && !overLimit;
            return Row(
              children: [
                const SizedBox(
                  width: 58,
                  child: Icon(YuLiIcons.plus, size: 25, color: yCream),
                ),
                Container(width: yLineThin, color: yCream),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onSubmitted: (_) => onSubmit(),
                    cursorColor: yCream,
                    style: yBody(
                      size: 15,
                      weight: FontWeight.w600,
                      color: yCream,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                      ),
                      hintText: 'Captura una tarea…',
                      hintStyle: yBody(
                        size: 15,
                        weight: FontWeight.w600,
                        color: yCream.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ),
                if (value.text.isNotEmpty)
                  Text(
                    contentLength.toString(),
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      color: overLimit ? yCream : yCream.withValues(alpha: 0.7),
                    ),
                  ),
                const SizedBox(width: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onSubmit : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: enabled ? yAmber2 : yCream.withValues(alpha: 0.2),
                      border: Border.all(color: yCream, width: yLineThin),
                    ),
                    child: const Icon(
                      YuLiIcons.arrowRight,
                      size: 20,
                      color: yCream,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int? count;

  const _SectionLabel({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.7,
            color: inkColor(context),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            '· ${count.toString().padLeft(2, '0')}',
            style: yMono(size: 10, tracking: 1.4, color: yMuted),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: yBorderSoft)),
      ],
    );
  }
}

class _UrgentTaskList extends StatelessWidget {
  final List<domain_task.Task> tasks;
  final List<Folder> folders;
  final VoidCallback onTap;

  const _UrgentTaskList({
    required this.tasks,
    required this.folders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: yCream2,
            border: Border.all(color: yBorderSoft, width: yLineThin),
          ),
          child: Text(
            'SIN URGENCIAS',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.8,
              color: yMuted,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: tasks.length.clamp(0, 3),
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final folder =
            task.folderId == null ? null : _findFolder(folders, task.folderId!);
        final accent = folder?.color ?? yFight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: paperColor(context),
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Row(
              children: [
                Container(width: 7, color: accent),
                const SizedBox(width: 12),
                Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cleanMention(task.content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yBody(
                      size: 13,
                      weight: FontWeight.w600,
                      color: inkColor(context),
                    ),
                  ),
                ),
                Text(
                  _urgentTaskLabel(task),
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.1,
                    color: yFight,
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentActivityStrip extends StatelessWidget {
  final Note? note;
  final Color noteAccent;
  final LabSpace? space;
  final ValueChanged<int> onOpenNote;
  final ValueChanged<int> onOpenSpace;

  const _RecentActivityStrip({
    required this.note,
    required this.noteAccent,
    required this.space,
    required this.onOpenNote,
    required this.onOpenSpace,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: yBorderStrong, width: yLineMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel(label: 'ACTIVIDAD RECIENTE'),
          const SizedBox(height: 9),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _RecentNoteCard(
                    note: note,
                    accent: noteAccent,
                    onTap: note == null ? null : () => onOpenNote(note!.id),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActiveProjectCard(
                    space: space,
                    onTap: space == null ? null : () => onOpenSpace(space!.id),
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

class _RecentNoteCard extends StatelessWidget {
  final Note? note;
  final Color accent;
  final VoidCallback? onTap;

  const _RecentNoteCard({
    required this.note,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: const Icon(YuLiIcons.notebook, size: 20, color: yCream),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'NOTA RECIENTE',
                    style: yMono(
                      size: 8,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    note?.displayTitle ?? 'Sin notas recientes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yBody(
                      size: 12,
                      weight: FontWeight.w700,
                      color: inkColor(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(YuLiIcons.arrowRight, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}

class _ActiveProjectCard extends StatelessWidget {
  final LabSpace? space;
  final VoidCallback? onTap;

  const _ActiveProjectCard({required this.space, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = space?.accentColor ?? yLab;
    final progress = space == null ? null : _projectProgress(space!);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: const Icon(
                YuLiIcons.flaskConical,
                size: 20,
                color: yCream,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PROYECTO ACTIVO',
                    style: yMono(
                      size: 8,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    space?.name ?? 'Sin proyectos activos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yBody(
                      size: 12,
                      weight: FontWeight.w700,
                      color: inkColor(context),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    _MiniProgress(value: progress, accent: accent),
                  ],
                ],
              ),
            ),
            Icon(YuLiIcons.arrowRight, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  final double value;
  final Color accent;

  const _MiniProgress({required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: yBorderStrong, width: 1),
      ),
      child: FractionallySizedBox(
        widthFactor: value,
        alignment: Alignment.centerLeft,
        child: ColoredBox(color: accent),
      ),
    );
  }
}

class _ModeLaunchStack extends StatelessWidget {
  final int urgentCount;
  final int folderCount;
  final int spaceCount;
  final VoidCallback onFight;
  final VoidCallback onFlight;
  final VoidCallback onLab;

  const _ModeLaunchStack({
    required this.urgentCount,
    required this.folderCount,
    required this.spaceCount,
    required this.onFight,
    required this.onFlight,
    required this.onLab,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _ModeLaunchCard(
            mode: 'FIGHT',
            count: urgentCount,
            unit: 'Urgentes',
            color: yFight,
            icon: YuLiIcons.listChecks,
            onTap: onFight,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _ModeLaunchCard(
            mode: 'FLIGHT',
            count: folderCount,
            unit: 'Carpetas',
            color: yFlight,
            icon: YuLiIcons.folder,
            onTap: onFlight,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _ModeLaunchCard(
            mode: 'LAB',
            count: spaceCount,
            unit: 'En proceso',
            color: yLab,
            icon: YuLiIcons.flaskConical,
            onTap: onLab,
          ),
        ),
      ],
    );
  }
}

class _ModeLaunchCard extends StatelessWidget {
  final String mode;
  final int count;
  final String unit;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeLaunchCard({
    required this.mode,
    required this.count,
    required this.unit,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: yBorderStrong, width: yLineHeavy),
          boxShadow: const [BoxShadow(color: yInk, offset: Offset(4, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: Icon(icon, size: 29, color: color),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mode,
                    style: ySans(
                      size: 36,
                      weight: FontWeight.w800,
                      color: yCream,
                      height: 0.9,
                    ).copyWith(letterSpacing: -1.2),
                  ),
                  const SizedBox(height: 12),
                  Container(height: 2, color: yCream.withValues(alpha: 0.72)),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        count.toString(),
                        style: ySans(
                          size: 34,
                          weight: FontWeight.w700,
                          color: yCream,
                          height: 0.9,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          unit.toUpperCase(),
                          style: yMono(
                            size: 9,
                            weight: FontWeight.w700,
                            tracking: 1.3,
                            color: yCream.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(YuLiIcons.arrowRight, size: 22, color: yCream),
          ],
        ),
      ),
    );
  }
}

List<domain_task.Task> _collectUrgentTasks(
  List<domain_task.Task> pending,
  List<domain_task.Task> yesterday,
  List<domain_task.Task> expired,
) {
  final limit = DateTime.now().add(const Duration(hours: 48));
  final tasks = <domain_task.Task>[
    ...expired,
    ...yesterday,
    ...pending.where(
      (task) => task.dueDate != null && !task.dueDate!.isAfter(limit),
    ),
  ];
  tasks.sort((a, b) {
    final aRank = _urgentTaskRank(a);
    final bRank = _urgentTaskRank(b);
    if (aRank != bRank) return aRank.compareTo(bRank);
    final aDate = a.dueDate ?? a.createdAt;
    final bDate = b.dueDate ?? b.createdAt;
    return aDate.compareTo(bDate);
  });
  return tasks;
}

int _urgentTaskRank(domain_task.Task task) => switch (task.status) {
  domain_task.TaskStatus.archivedFailed => 0,
  domain_task.TaskStatus.yesterday => 1,
  _ => 2,
};

String _urgentTaskLabel(domain_task.Task task) {
  if (task.status == domain_task.TaskStatus.archivedFailed) return 'VENCIDA';
  if (task.status == domain_task.TaskStatus.yesterday) return 'AYER';
  final due = task.dueDate;
  if (due == null) return 'PRÓXIMA';
  final now = DateTime.now();
  final isDateOnly = due.hour == 0 && due.minute == 0 && due.second == 0;
  final endOfDueDay = DateTime(due.year, due.month, due.day, 23, 59, 59, 999);
  if ((isDateOnly ? endOfDueDay : due).isBefore(now)) return 'VENCIDA';
  if (due.year == now.year && due.month == now.month && due.day == now.day) {
    return 'HOY';
  }
  final tomorrow = now.add(const Duration(days: 1));
  if (due.year == tomorrow.year &&
      due.month == tomorrow.month &&
      due.day == tomorrow.day) {
    return 'MAÑANA';
  }
  return '${due.day.toString().padLeft(2, '0')}/'
      '${due.month.toString().padLeft(2, '0')}';
}

Folder? _findFolder(List<Folder> folders, int id) {
  for (final folder in folders) {
    if (folder.id == id) return folder;
  }
  return null;
}

double? _projectProgress(LabSpace space) {
  final start = space.startDate;
  final end = space.dueDate;
  if (start == null || end == null || !end.isAfter(start)) return null;
  return (DateTime.now().difference(start).inMinutes /
          end.difference(start).inMinutes)
      .clamp(0.0, 1.0);
}

class _NextOccurrence {
  final ScheduleBlock block;
  final String label;
  const _NextOccurrence(this.block, this.label);
}

const _kBlockDayKeys = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

_NextOccurrence? _findNextClass(List<ScheduleBlock> blocks, DateTime now) {
  if (blocks.isEmpty) return null;

  ScheduleBlock? bestBlock;
  int bestDelta = 1 << 30;
  String bestLabel = '';

  final nowMinutes = now.hour * 60 + now.minute;
  final todayKey = _kBlockDayKeys[now.weekday - 1];

  for (final b in blocks) {
    for (final day in b.days) {
      final dayIdx = _kBlockDayKeys.indexOf(day);
      if (dayIdx < 0) continue;
      int delta;
      String label;
      final todayIdx = now.weekday - 1;
      if (day == todayKey && b.startMinutes > nowMinutes) {
        delta = b.startMinutes - nowMinutes;
        label = 'Hoy';
      } else {
        final dayDiff = (dayIdx - todayIdx + 7) % 7;
        final effectiveDiff = dayDiff == 0 ? 7 : dayDiff;
        delta = effectiveDiff * 24 * 60 + (b.startMinutes - nowMinutes);
        label = effectiveDiff == 1 ? 'Mañana' : day;
      }
      if (delta < bestDelta) {
        bestDelta = delta;
        bestBlock = b;
        bestLabel = label;
      }
    }
  }

  return bestBlock == null ? null : _NextOccurrence(bestBlock, bestLabel);
}

class _MentionPopup extends StatelessWidget {
  final List<Folder> folders;
  final void Function(Folder) onSelect;

  const _MentionPopup({required this.folders, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border.all(color: inkColor(context), width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: inkColor(context),
            offset: shadowOffset,
            blurRadius: shadowBlurRadius,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children:
            folders.map((f) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(f),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, color: f.color),
                      const SizedBox(width: 8),
                      Text(
                        f.name,
                        style: labelBold.copyWith(color: inkColor(context)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
