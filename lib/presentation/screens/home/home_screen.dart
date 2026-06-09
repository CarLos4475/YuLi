import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/yuli_splash_screen.dart';
import '../../providers/database_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_providers.dart';
import '../../../domain/models/task.dart' as domain_task;
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/schedule_block.dart';
import '../settings/settings_screen.dart';

// ─── Design tokens (V1 Command Triptych) ──────────────────────────────────

const Color _yCream = Color(0xFFF2EFE6);
const Color _yInk = Color(0xFF0A0A0A);
const Color _yMuted = Color(0xFF7A6F60);
const Color _yFight = Color(0xFFC8332C);
const Color _yFlight = Color(0xFF2D3F8C);
const Color _yLab = Color(0xFF3F6E3E);
const Color _yAmber = Color(0xFFE29A3A);
const Color _ySoftBorder = Color(0xCC0A0A0A);

const double _hLine = 3.0;
const double _mLine = 2.5;

TextStyle _mono({
  double size = 11,
  Color color = _yMuted,
  double tracking = 1.4,
}) => TextStyle(
  fontFamily: 'monospace',
  fontSize: size,
  letterSpacing: tracking,
  color: color,
  fontWeight: FontWeight.w500,
  height: 1.2,
);

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

  @override
  void initState() {
    super.initState();
    _taskController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
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
      backgroundColor: _yCream,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: _HeaderStrip(
                    greeting: greeting,
                    timeStr: timeStr,
                    dateLong: dateLong,
                    onSettings:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child:
                        constraints.maxWidth >= 900
                            ? _ThreePillarsRow(
                              fight: _buildFightPillar(),
                              flight: _buildFlightPillar(),
                              lab: _buildLabPillar(),
                            )
                            : SingleChildScrollView(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 560,
                                    child: _buildFightPillar(),
                                  ),
                                  SizedBox(
                                    height: 560,
                                    child: _buildFlightPillar(),
                                  ),
                                  SizedBox(
                                    height: 700,
                                    child: _buildLabPillar(),
                                  ),
                                ],
                              ),
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

  Widget _buildFightPillar() {
    return _FightPillar(
      controller: _taskController,
      focusNode: _focusNode,
      layerLink: _layerLink,
      onSubmit: _addQuickTask,
      onEnter: () => _goTo(AppMode.fight),
    );
  }

  Widget _buildFlightPillar() {
    return _FlightPillar(onEnter: () => _goTo(AppMode.flight));
  }

  Widget _buildLabPillar() {
    return _LabPillar(onEnter: () => _goTo(AppMode.lab));
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

// ─── Header strip ─────────────────────────────────────────────────────────

class _HeaderStrip extends StatelessWidget {
  final String greeting;
  final String timeStr;
  final String dateLong;
  final VoidCallback onSettings;

  const _HeaderStrip({
    required this.greeting,
    required this.timeStr,
    required this.dateLong,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        color: _yCream,
        border: Border.fromBorderSide(
          BorderSide(color: _ySoftBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x660A0A0A),
            offset: Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(width: 12, color: _yAmber),
          Expanded(
            flex: 8,
            child: Container(
              padding: const EdgeInsets.fromLTRB(44, 22, 34, 18),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: _ySoftBorder, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$greeting · Carlos',
                    style: _mono(size: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -2.2,
                          height: 1.0,
                          color: _yInk,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Container(width: 2, height: 44, color: _ySoftBorder),
                      const SizedBox(width: 24),
                      Flexible(
                        child: Text(
                          dateLong,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.0,
                            color: _yMuted,
                            height: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.fromLTRB(34, 12, 32, 12),
              child: Stack(
                children: [
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const YuliAnimatedCube(
                          accent: _yFight,
                          accents: [_yFight, _yFlight, _yLab],
                          size: 54,
                        ),
                        const SizedBox(width: 18),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 74,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -4.2,
                                  height: 0.92,
                                  color: _yInk,
                                ),
                                children: [
                                  TextSpan(text: 'Yu'),
                                  TextSpan(
                                    text: 'Li',
                                    style: TextStyle(color: _yAmber),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 34, height: 4, color: _yFight),
                                const SizedBox(width: 10),
                                Container(
                                  width: 34,
                                  height: 4,
                                  color: _yFlight,
                                ),
                                const SizedBox(width: 10),
                                Container(width: 34, height: 4, color: _yLab),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onSettings,
                      child: Container(
                        width: 68,
                        height: 68,
                        alignment: Alignment.center,
                        child: const Icon(
                          YuLiIcons.settings,
                          color: _yInk,
                          size: 38,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Three pillars row ────────────────────────────────────────────────────

class _ThreePillarsRow extends StatelessWidget {
  final Widget fight;
  final Widget flight;
  final Widget lab;

  const _ThreePillarsRow({
    required this.fight,
    required this.flight,
    required this.lab,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: fight),
        const SizedBox(width: 8),
        Expanded(child: flight),
        const SizedBox(width: 8),
        Expanded(child: lab),
      ],
    );
  }
}

// ─── Pillar shell ─────────────────────────────────────────────────────────

class _PillarShell extends StatelessWidget {
  final String mode;
  final String subtitle;
  final Color color;
  final Widget child;
  final String footerLabel;
  final VoidCallback onEnter;
  final String? bigNumber;
  final String? bigNumberUnit;

  const _PillarShell({
    required this.mode,
    required this.subtitle,
    required this.color,
    required this.child,
    required this.footerLabel,
    required this.onEnter,
    this.bigNumber,
    this.bigNumberUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: _ySoftBorder, width: _mLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode,
                  style: const TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 62,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.8,
                    height: 0.92,
                    color: _yCream,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: _mono(
                    size: 11,
                    color: _yCream.withValues(alpha: 0.7),
                    tracking: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(height: 2, color: _yCream.withValues(alpha: 0.42)),
                if (bigNumber != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        bigNumber!,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 96,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -2.0,
                          height: 0.9,
                          color: _yCream,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          bigNumberUnit ?? '',
                          style: _mono(
                            size: 11,
                            color: _yCream.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 0),
              child: child,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEnter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _yCream, width: _hLine)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    footerLabel,
                    style: const TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: _yCream,
                    ),
                  ),
                  const Text(
                    '→',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 22,
                      color: _yCream,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FIGHT pillar ─────────────────────────────────────────────────────────

class _FightPillar extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final LayerLink layerLink;
  final VoidCallback onSubmit;
  final VoidCallback onEnter;

  const _FightPillar({
    required this.controller,
    required this.focusNode,
    required this.layerLink,
    required this.onSubmit,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTasksProvider);
    final doneAsync = ref.watch(doneTodayTasksProvider);
    final folders = ref.watch(activeFoldersProvider).valueOrNull ?? [];

    final pending = pendingAsync.valueOrNull ?? [];
    final done = doneAsync.valueOrNull ?? [];

    return _PillarShell(
      mode: 'FIGHT',
      subtitle: 'MODO CAPTURA',
      color: _yFight,
      footerLabel: 'ENTRAR EN FIGHT',
      onEnter: onEnter,
      bigNumber: '${pending.length}',
      bigNumberUnit: 'Pendientes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Captura input
          CompositedTransformTarget(
            link: layerLink,
            child: _BrutalSlab(
              bg: _yCream,
              child: ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) {
                  final contentLen =
                      value.text.replaceAll(RegExp(r'@\S+'), '').length;
                  final overLimit = contentLen > _HomeScreenState._maxChars;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: _yInk,
                            ),
                            cursorColor: _yInk,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              hintText: 'Captura una tarea…',
                              hintStyle: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: _yMuted,
                              ),
                            ),
                            onSubmitted: (_) => onSubmit(),
                          ),
                        ),
                        if (value.text.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$contentLen',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color:
                                  overLimit
                                      ? _yFight
                                      : contentLen > 260
                                      ? const Color(0xFFC7822F)
                                      : _yMuted,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap:
                              (value.text.trim().isEmpty || overLimit)
                                  ? null
                                  : onSubmit,
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  (value.text.trim().isEmpty || overLimit)
                                      ? _yMuted.withValues(alpha: 0.3)
                                      : _yFight,
                              border: Border.all(color: _ySoftBorder, width: 2),
                            ),
                            child: const Text(
                              '+',
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                color: _yCream,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '── Completadas hoy ──',
            style: _mono(color: _yCream.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child:
                done.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _PillarEmpty(text: 'NADA TODAVÍA'),
                    )
                    : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, i) {
                        final t = done[i];
                        final folder =
                            t.folderId == null
                                ? null
                                : folders.firstWhere(
                                  (f) => f.id == t.folderId,
                                  orElse:
                                      () =>
                                          folders.isEmpty
                                              ? Folder(
                                                id: -1,
                                                name: '',
                                                color: _yMuted,
                                                createdAt: DateTime.now(),
                                              )
                                              : folders.first,
                                );
                        return _DoneTaskRow(task: t, folder: folder);
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemCount: done.length,
                    ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _DoneTaskRow extends StatelessWidget {
  final domain_task.Task task;
  final Folder? folder;

  const _DoneTaskRow({required this.task, this.folder});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _yCream,
        border: Border.all(color: _ySoftBorder, width: 2),
      ),
      child: Row(
        children: [
          if (folder != null && folder!.id != -1)
            Container(
              width: 4,
              height: 16,
              margin: const EdgeInsets.only(right: 8),
              color: folder!.color,
            ),
          Expanded(
            child: Text(
              cleanMention(task.content),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: yInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FLIGHT pillar ────────────────────────────────────────────────────────

class _FlightPillar extends ConsumerWidget {
  final VoidCallback onEnter;

  const _FlightPillar({required this.onEnter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(activeFoldersProvider).valueOrNull ?? [];
    final allNotes = ref.watch(recentNotesProvider).valueOrNull ?? [];

    // count notes per folder
    final counts = <int, int>{};
    for (final n in allNotes) {
      counts[n.folderId] = (counts[n.folderId] ?? 0) + 1;
    }

    return _PillarShell(
      mode: 'FLIGHT',
      subtitle: 'MODO NOTAS',
      color: _yFlight,
      footerLabel: 'ENTRAR EN FLIGHT',
      onEnter: onEnter,
      bigNumber: '${folders.length}',
      bigNumberUnit: 'Carpetas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '── Carpetas ──',
            style: _mono(color: _yCream.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child:
                folders.isEmpty
                    ? _PillarEmpty(text: 'SIN CARPETAS')
                    : GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            mainAxisExtent: 60,
                          ),
                      itemBuilder: (ctx, i) {
                        final f = folders[i];
                        return _FolderCard(folder: f, count: counts[f.id] ?? 0);
                      },
                      itemCount: folders.length,
                    ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final Folder folder;
  final int count;

  const _FolderCard({required this.folder, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: folder.color,
        border: Border.all(color: _ySoftBorder, width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: _yCream,
            ),
          ),
          Text(
            '$count notas',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: _yCream.withValues(alpha: 0.85),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LAB pillar ───────────────────────────────────────────────────────────

class _LabPillar extends ConsumerWidget {
  final VoidCallback onEnter;

  const _LabPillar({required this.onEnter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final blocksAsync = ref.watch(_allScheduleBlocksProvider);

    final spaces =
        (spacesAsync.valueOrNull ?? [])
            .where((s) => s.status == LabSpaceStatus.active)
            .toList();
    final allBlocks = blocksAsync.valueOrNull ?? [];

    final activeSpaceIds = spaces.map((s) => s.id).toSet();
    final relevantBlocks =
        allBlocks.where((b) => activeSpaceIds.contains(b.labSpaceId)).toList();

    final nextClass = _findNextClass(relevantBlocks, DateTime.now());

    return _PillarShell(
      mode: 'LAB',
      subtitle: 'MODO PROYECTOS',
      color: _yLab,
      footerLabel: 'ENTRAR EN LAB',
      onEnter: onEnter,
      bigNumber: '${spaces.length}',
      bigNumberUnit: 'En proceso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nextClass != null) ...[
            Text(
              '── Próxima clase ──',
              style: _mono(color: _yCream.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 8),
            _NextClassCard(block: nextClass.block, when: nextClass.label),
            const SizedBox(height: 18),
          ],
          Text(
            '── Spaces activos ──',
            style: _mono(color: _yCream.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child:
                spaces.isEmpty
                    ? _PillarEmpty(text: 'SIN SPACES ACTIVOS')
                    : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, i) => _SpaceCard(space: spaces[i]),
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemCount: spaces.length,
                    ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
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

class _NextClassCard extends StatelessWidget {
  final ScheduleBlock block;
  final String when;

  const _NextClassCard({required this.block, required this.when});

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(block.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _yCream,
        border: Border.all(color: _ySoftBorder, width: _hLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _yInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when · ${block.startTime}'
                  '${block.location != null && block.location!.isNotEmpty ? ' · ${block.location}' : ''}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: _yMuted,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Badge(
            label:
                block.title.length > 12
                    ? block.title.substring(0, 12)
                    : block.title,
            bg: color,
            fg: _yCream,
          ),
        ],
      ),
    );
  }
}

Color _parseHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return _yMuted;
}

class _SpaceCard extends StatelessWidget {
  final LabSpace space;

  const _SpaceCard({required this.space});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stage = _stageLabel(space, now);
    final progress = _timeProgress(space, now);
    final dueText = space.dueDate != null ? _fmtDate(space.dueDate!) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _yCream,
        border: Border.all(color: _ySoftBorder, width: _hLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            space.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.0,
              color: _yInk,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Badge(label: stage, bg: space.accentColor, fg: _yCream),
              if (dueText != null)
                _Badge(label: dueText, bg: _yFlight, fg: _yCream),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            Text(
              'Progreso · ${(progress * 100).round()}%',
              style: _mono(size: 10, color: _yMuted, tracking: 1.2),
            ),
            const SizedBox(height: 4),
            _ProgressBar(value: progress, color: space.accentColor),
          ],
        ],
      ),
    );
  }

  String _stageLabel(LabSpace s, DateTime now) {
    if (s.status == LabSpaceStatus.completed) return 'Completado';
    if (s.status == LabSpaceStatus.archived) return 'Archivado';
    if (s.dueDate != null && now.isAfter(s.dueDate!)) return 'Vencido';
    if (s.startDate != null && now.isBefore(s.startDate!)) return 'Por iniciar';
    if (s.startDate == null && s.dueDate == null) return 'Sin fechas';
    return 'En proceso';
  }

  double? _timeProgress(LabSpace s, DateTime now) {
    final start = s.startDate;
    final end = s.dueDate;
    if (start == null || end == null) return null;
    if (!end.isAfter(start)) return null;
    final total = end.difference(start).inMinutes;
    final elapsed = now.difference(start).inMinutes;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFFEBE6D9),
        border: Border.all(color: _ySoftBorder, width: 2),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value,
              heightFactor: 1.0,
              child: ClipRect(
                child: CustomPaint(painter: _HatchedFillPainter(color: color)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HatchedFillPainter extends CustomPainter {
  final Color color;
  _HatchedFillPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final bgPaint = Paint()..color = color;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final hatchPaint =
        Paint()
          ..color = const Color(0x2E000000)
          ..strokeWidth = 1.2;
    const step = 7.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        hatchPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchedFillPainter old) => old.color != color;
}

// ─── Shared visual atoms ──────────────────────────────────────────────────

class _BrutalSlab extends StatelessWidget {
  final Color bg;
  final Widget child;

  const _BrutalSlab({required this.bg, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: _ySoftBorder, width: _hLine),
      ),
      child: child,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: _ySoftBorder, width: 2.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.2,
          height: 1.1,
          color: fg,
        ),
      ),
    );
  }
}

class _PillarEmpty extends StatelessWidget {
  final String text;
  const _PillarEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: _mono(
          size: 11,
          color: _yCream.withValues(alpha: 0.5),
          tracking: 1.4,
        ),
      ),
    );
  }
}

// ─── Mention popup (reused from prior home) ───────────────────────────────

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
