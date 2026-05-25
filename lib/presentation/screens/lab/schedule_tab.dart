import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart' as y;
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../../domain/models/schedule_block.dart';
import '../../../domain/models/schedule_settings.dart';
import '../../../domain/models/schedule_week_note.dart';
import '../../../domain/models/lab_space.dart';

// ─── Constants ─────────────────────────────────────────────────────────────

const _hoursWidth = 52.0;
const _hourHeight = 48.0;
const _dayHeaderHeight = 56.0;
const _dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

List<String> _weekDays(bool showSat, bool showSun) {
  if (!showSat && !showSun) return _dayNames.sublist(0, 5);
  if (showSat && !showSun) return _dayNames.sublist(0, 6);
  return _dayNames;
}

String _minutesToTime(int m) {
  final h = m ~/ 60;
  final min = m % 60;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

int _roundToHour(int minutes) =>
    (minutes / 60).round() * 60;

DateTime _mondayOfWeek(DateTime date) {
  final wd = date.weekday;
  return DateTime(date.year, date.month, date.day - (wd - 1));
}

Color _parseHex(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  return Color(int.parse(h, radix: 16));
}

// ─── Lane Assignment (overlap resolver) ────────────────────────────────────

class _LaneInfo {
  final ScheduleBlock block;
  final int lane;
  final int totalLanes;
  final int colSpan;
  const _LaneInfo(this.block, this.lane, this.totalLanes, this.colSpan);
}

List<_LaneInfo> _assignLanes(List<ScheduleBlock> blocks) {
  if (blocks.isEmpty) return [];
  final sorted = List<ScheduleBlock>.from(blocks)
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  final result = <_LaneInfo>[];
  var cluster = <ScheduleBlock>[];
  var maxEnd = 0;

  for (final block in sorted) {
    if (cluster.isEmpty) {
      cluster.add(block);
      maxEnd = block.endMinutes;
    } else if (block.startMinutes < maxEnd) {
      cluster.add(block);
      if (block.endMinutes > maxEnd) {
        maxEnd = block.endMinutes;
      }
    } else {
      result.addAll(_assignLanesForCluster(cluster));
      cluster = [block];
      maxEnd = block.endMinutes;
    }
  }
  if (cluster.isNotEmpty) {
    result.addAll(_assignLanesForCluster(cluster));
  }
  return result;
}

List<_LaneInfo> _assignLanesForCluster(List<ScheduleBlock> cluster) {
  final lanes = <List<ScheduleBlock>>[];
  final tempResult = <(ScheduleBlock, int)>[];

  for (final block in cluster) {
    int idx = -1;
    for (int i = 0; i < lanes.length; i++) {
      if (lanes[i].last.endMinutes <= block.startMinutes) {
        idx = i;
        break;
      }
    }
    if (idx == -1) {
      idx = lanes.length;
      lanes.add([]);
    }
    lanes[idx].add(block);
    tempResult.add((block, idx));
  }

  final N = lanes.length;
  final result = <_LaneInfo>[];

  for (final (block, c) in tempResult) {
    int colSpan = 1;
    for (int j = c + 1; j < N; j++) {
      final hasOverlap = lanes[j].any((otherBlock) =>
          otherBlock.startMinutes < block.endMinutes &&
          otherBlock.endMinutes > block.startMinutes);
      if (hasOverlap) {
        break;
      }
      colSpan++;
    }
    result.add(_LaneInfo(block, c, N, colSpan));
  }

  return result;
}

// ─── Providers ────────────────────────────────────────────────────────────

final _scheduleSettingsProvider =
    FutureProvider.family<ScheduleSettings, int>((ref, spaceId) async {
  final repo = ref.watch(scheduleRepositoryProvider);
  return repo.getOrCreateSettings(spaceId);
});

final _scheduleBlocksProvider =
    StreamProvider.family<List<ScheduleBlock>, int>((ref, spaceId) {
  final repo = ref.watch(scheduleRepositoryProvider);
  return repo.watchBySpace(spaceId);
});

final _weekNoteProvider =
    StreamProvider.family<ScheduleWeekNote?, (int, String)>((ref, key) {
  final (spaceId, weekStart) = key;
  final date = DateTime.parse(weekStart);
  final repo = ref.watch(scheduleRepositoryProvider);
  return repo.watchWeekNote(spaceId, date);
});

// ─── Main Widget ───────────────────────────────────────────────────────────

class ScheduleTab extends ConsumerStatefulWidget {
  final LabSpace space;
  const ScheduleTab({super.key, required this.space});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  late DateTime _currentWeekStart;
  bool _creatingMode = false;
  double? _dragStartY;
  double? _dragCurrentY;
  int? _dragDayIndex;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _mondayOfWeek(DateTime.now());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _prev() => setState(
      () => _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7)));

  void _next() => setState(
      () => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7)));

  void _today() => setState(() => _currentWeekStart = _mondayOfWeek(DateTime.now()));

  String _weekLabel() {
    final end = _currentWeekStart.add(const Duration(days: 6));
    return '${_currentWeekStart.day}/${_currentWeekStart.month} – ${end.day}/${end.month}';
  }

  String _weekStartStr() =>
      '${_currentWeekStart.year}-${_currentWeekStart.month.toString().padLeft(2, '0')}-${_currentWeekStart.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final settingsAsync = ref.watch(_scheduleSettingsProvider(widget.space.id));
    final blocksAsync = ref.watch(_scheduleBlocksProvider(widget.space.id));
    final weekNoteAsync = ref.watch(_weekNoteProvider((widget.space.id, _weekStartStr())));

    final settings = settingsAsync.valueOrNull;
    final blocks = blocksAsync.valueOrNull ?? [];
    final weekNote = weekNoteAsync.valueOrNull;

    if (settings == null) return const SizedBox.shrink();

    return _buildWithBlocks(settings, blocks, weekNote, ink);
  }

  Widget _buildWithBlocks(ScheduleSettings settings, List<ScheduleBlock> blocks,
      ScheduleWeekNote? weekNote, Color ink) {
    final days = _weekDays(settings.showSaturday, settings.showSunday);
    final sMin = settings.startMinutes;
    final eMin = settings.endMinutes;
    final totalMins = eMin - sMin;
    final totalHeight = (totalMins / 60) * _hourHeight;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = (screenWidth * 0.04).clamp(16.0, 80.0);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
        child: Column(
          children: [
            _ScheduleHeader(
              weekLabel: _weekLabel(),
              onPrev: _prev,
              onNext: _next,
              onToday: _today,
              onSettings: () => _showSettings(context, settings),
              creatingMode: _creatingMode,
              onToggleCreate: () =>
                  setState(() => _creatingMode = !_creatingMode),
            ),
            if (weekNote != null)
              _WeekNoteBanner(
                note: weekNote.note,
                onEdit: () => _editWeekNote(context, weekNote),
                onDismiss: () async {
                  await ref
                      .read(scheduleRepositoryProvider)
                      .deleteWeekNote(weekNote.id);
                },
              ),
            // Grid
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dayWidth =
                      (constraints.maxWidth - _hoursWidth) / days.length;
                  return Column(
                    children: [
                      // Day headers (fixed)
                      _DayHeaderRow(
                        days: days,
                        dayWidth: dayWidth,
                        weekStart: _currentWeekStart,
                        accentColor: widget.space.accentColor,
                      ),
                      // Scrollable grid
                      Expanded(
                        child: SingleChildScrollView(
                          child: SizedBox(
                            height: totalHeight + _hourHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Hours column
                                SizedBox(
                                  width: _hoursWidth,
                                  child: Column(
                                    children: [
                                      for (int m = sMin;
                                          m <= eMin;
                                          m += 60)
                                        SizedBox(
                                          height: _hourHeight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 6, top: 2),
                                            child: Text(
                                              _minutesToTime(m),
                                              style: bodyS.copyWith(
                                                  color: inkGray, fontSize: 10),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Days area
                                Expanded(
                                  child: SizedBox(
                                    height: totalHeight + _hourHeight,
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          size: Size(
                                              constraints.maxWidth - _hoursWidth,
                                              totalHeight + _hourHeight),
                                          painter: _GridPainter(
                                            ink: ink,
                                            totalMinutes: totalMins,
                                            numDays: days.length,
                                            dayWidth: dayWidth,
                                          hourHeight: _hourHeight,
                                          ),
                                        ),
                                        // Blocks per day
                                        for (int di = 0; di < days.length; di++)
                                          ..._buildDayBlocks(
                                            blocks,
                                            di,
                                            days[di],
                                            dayWidth,
                                            sMin,
                                            totalHeight,
                                          ),
                                        // Drag overlay (only in creating mode)
                                        if (_creatingMode &&
                                            _dragStartY != null &&
                                            _dragCurrentY != null &&
                                            _dragDayIndex != null)
                                          _DragOverlay(
                                            startY: _dragStartY!,
                                            currentY: _dragCurrentY!,
                                            dayIndex: _dragDayIndex!,
                                            dayWidth: dayWidth,
                                            hoursWidth: _hoursWidth,
                                          ),
                                        // Current time line (on top of blocks)
                                        _TimeLineWidget(
                                          startMinutes: sMin,
                                          totalMinutes: totalMins,
                                            hourHeight: _hourHeight,
                                          totalWidth:
                                              constraints.maxWidth - _hoursWidth,
                                        ),
                                        // Drag gesture detector for each day
                                        for (int di = 0; di < days.length; di++)
                                          Positioned(
                                            left: di * dayWidth,
                                            top: 0,
                                            width: dayWidth,
                                            height:
                                                totalHeight + _hourHeight,
                                            child: IgnorePointer(
                                              ignoring: !_creatingMode,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onVerticalDragStart: (d) =>
                                                    setState(() {
                                                  _dragStartY =
                                                      d.localPosition.dy;
                                                  _dragCurrentY =
                                                      d.localPosition.dy;
                                                  _dragDayIndex = di;
                                                }),
                                                onVerticalDragUpdate: (d) =>
                                                    setState(() =>
                                                        _dragCurrentY =
                                                            d.localPosition.dy),
                                                onVerticalDragEnd: (d) {
                                                  _finishDrag(
                                                      blocks, days, sMin,
                                                      totalHeight);
                                                },
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
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
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDayBlocks(
    List<ScheduleBlock> blocks,
    int dayIndex,
    String dayKey,
    double dayWidth,
    int startMinutes,
    double totalHeight,
  ) {
    final dayBlocks = blocks
        .where((b) => b.days.contains(dayKey))
        .toList();
    if (dayBlocks.isEmpty) return [];

    final lanes = _assignLanes(dayBlocks);
    final result = <Widget>[];

    for (final li in lanes) {
      final b = li.block;
      final laneWidth = dayWidth / li.totalLanes;
      final top = ((b.startMinutes - startMinutes) / 60) * _hourHeight;
      final height = ((b.endMinutes - b.startMinutes) / 60) * _hourHeight;

      final remainingDayWidth = dayWidth - (li.lane * laneWidth);
      double blockWidth = li.colSpan * laneWidth;
      if (li.lane + li.colSpan < li.totalLanes) {
        blockWidth += 0.5 * laneWidth;
      }
      if (blockWidth > remainingDayWidth) {
        blockWidth = remainingDayWidth;
      }

      result.add(
        Positioned(
          left: dayIndex * dayWidth + li.lane * laneWidth + 2.0,
          top: top + 2.0,
          width: (blockWidth - 4.0).clamp(4.0, double.infinity),
          height: (height - 4.0).clamp(4.0, double.infinity),
          child: _ScheduleBlockWidget(
            block: b,
            onTap: () => _showBlockDetail(context, b),
          ),
        ),
      );
    }
    return result;
  }

  void _finishDrag(
    List<ScheduleBlock> blocks,
    List<String> days,
    int startMinutes,
    double totalHeight,
  ) {
    if (_dragStartY == null || _dragCurrentY == null || _dragDayIndex == null) {
      _dragStartY = null;
      _dragCurrentY = null;
      _dragDayIndex = null;
      return;
    }

    final yStart = _dragStartY!;
    final yEnd = _dragCurrentY!;
    final top = yStart < yEnd ? yStart : yEnd;
    final bottom = yStart < yEnd ? yEnd : yStart;

    final minPerPixel = 60.0 / _hourHeight;
    final startMins =
        _roundToHour(startMinutes + (top * minPerPixel).round());
    final endMins =
        _roundToHour(startMinutes + (bottom * minPerPixel).round());

    final dayIndex = _dragDayIndex!;

    setState(() {
      _dragStartY = null;
      _dragCurrentY = null;
      _dragDayIndex = null;
    });

    if (endMins - startMins < 60) return;

    final dayKey = days[dayIndex];
    _showCreateBlock(context, startMins, endMins, dayKey);
  }

  // ─── Sheets ──────────────────────────────────────────────────────────────

  void _showCreateBlock(
      BuildContext context, int startMins, int endMins, String dayKey) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, sc) => _BlockFormSheet(
          space: widget.space,
          scrollController: sc,
          initialStartTime: _minutesToTime(startMins),
          initialEndTime: _minutesToTime(endMins),
          initialDays: [dayKey],
        ),
      ),
    );
  }

  void _showBlockDetail(BuildContext context, ScheduleBlock block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        builder: (ctx, sc) => _BlockDetailSheet(
          block: block,
          space: widget.space,
          scrollController: sc,
          onEdit: () {
            Navigator.pop(ctx);
            _showEditBlock(context, block);
          },
          onDelete: () => _confirmDelete(context, block),
        ),
      ),
    );
  }

  void _showEditBlock(BuildContext context, ScheduleBlock block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, sc) => _BlockFormSheet(
          space: widget.space,
          scrollController: sc,
          existingBlock: block,
          initialStartTime: block.startTime,
          initialEndTime: block.endTime,
          initialDays: List.from(block.days),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, ScheduleBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Eliminar este bloque?',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Afecta todos los dias en que se repite.',
            style: bodyM.copyWith(color: inkColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancelar', style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: labelBold.copyWith(color: accentFight)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(scheduleRepositoryProvider).deleteBlock(block.id);
    }
  }

  void _showSettings(BuildContext context, ScheduleSettings settings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        builder: (ctx, sc) => _SettingsSheet(
          settings: settings,
          scrollController: sc,
          onChanged: (s) {
            ref.read(scheduleRepositoryProvider).updateSettings(s);
            ref.invalidate(_scheduleSettingsProvider(widget.space.id));
          },
        ),
      ),
    );
  }

  void _editWeekNote(BuildContext context, ScheduleWeekNote? note) {
    final ctrl = TextEditingController(text: note?.note ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Nota de la semana',
            style: displayM.copyWith(color: inkColor(context))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: bodyM.copyWith(color: inkColor(context)),
          decoration: InputDecoration(
            hintText: 'Ej: Semana de examenes',
            hintStyle: bodyM.copyWith(color: inkGray),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancelar', style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await ref
                    .read(scheduleRepositoryProvider)
                    .setWeekNote(widget.space.id, _currentWeekStart, ctrl.text.trim());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child:
                Text('Guardar', style: labelBold.copyWith(color: inkColor(context))),
          ),
        ],
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────

class _ScheduleHeader extends StatelessWidget {
  final String weekLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onSettings;
  final bool creatingMode;
  final VoidCallback onToggleCreate;

  const _ScheduleHeader({
    required this.weekLabel,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onSettings,
    this.creatingMode = false,
    required this.onToggleCreate,
  });

  @override
  Widget build(BuildContext context) {
    return y.ViewHead(
      title: 'Horario',
      kicker: weekLabel.toUpperCase(),
      right: [
        y.NavBtn(glyph: '‹', onTap: onPrev),
        const SizedBox(width: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToday,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('HOY',
                style: y.yMono(
                  size: 11,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: y.yInk,
                )),
          ),
        ),
        const SizedBox(width: 4),
        y.NavBtn(glyph: '›', onTap: onNext),
        const SizedBox(width: 8),
        y.HeadBtn(
          label: creatingMode ? '✕ SALIR' : '+ CREAR',
          primary: !creatingMode,
          onTap: onToggleCreate,
        ),
        const SizedBox(width: 6),
        y.HeadBtn(
          label: '⚙ AJUSTAR',
          leadingIcon: null,
          onTap: onSettings,
        ),
      ],
    );
  }
}

// ─── Week Note Banner ──────────────────────────────────────────────────────

class _WeekNoteBanner extends StatelessWidget {
  final String note;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;

  const _WeekNoteBanner({
    required this.note,
    required this.onEdit,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: accentLab.withAlpha(20),
        border: Border(
          bottom: BorderSide(color: accentLab, width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              note,
              style: bodyS.copyWith(color: accentLab),
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: accentLab, width: borderWidth),
              ),
              child: Text('[Editar]',
                  style: labelBold.copyWith(color: accentLab, fontSize: 10)),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 14, color: accentLab),
          ),
        ],
      ),
    );
  }
}

// ─── Day Header Row ────────────────────────────────────────────────────────

class _DayHeaderRow extends StatelessWidget {
  final List<String> days;
  final double dayWidth;
  final DateTime weekStart;
  final Color accentColor;

  const _DayHeaderRow({
    required this.days,
    required this.dayWidth,
    required this.weekStart,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final today = DateTime.now();
    return Container(
      height: _dayHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ink.withAlpha(40), width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _hoursWidth),
          for (int i = 0; i < days.length; i++) ...[
            if (i > 0)
              Container(width: borderWidth, color: ink.withAlpha(40)),
            Expanded(
              child: _buildDayCell(days[i], i, today, ink),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayCell(String dayName, int offset, DateTime today, Color ink) {
    final date = weekStart.add(Duration(days: offset));
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final dayIndex = _dayNames.indexOf(dayName);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            _dayNames[dayIndex],
            style: labelBold.copyWith(
              color: isToday ? accentColor : ink,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${date.day}',
            style: bodyS.copyWith(
              color: isToday ? accentColor : inkGray,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid Painter ──────────────────────────────────────────────────────────

// ─── Current Time Line ─────────────────────────────────────────────────────

class _TimeLineWidget extends StatelessWidget {
  final int startMinutes;
  final int totalMinutes;
  final double hourHeight;
  final double totalWidth;

  const _TimeLineWidget({
    required this.startMinutes,
    required this.totalMinutes,
    required this.hourHeight,
    required this.totalWidth,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    if (nowMinutes < startMinutes ||
        nowMinutes > startMinutes + totalMinutes) {
      return const SizedBox.shrink();
    }

    final nowY = ((nowMinutes - startMinutes) / 60.0) * hourHeight;

    return Positioned(
      left: 0,
      top: nowY - 4,
      width: totalWidth,
      height: 10,
      child: CustomPaint(
        size: Size(totalWidth, 10),
        painter: _TimeLinePainter(),
      ),
    );
  }
}

class _TimeLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF800020)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(0, 4), Offset(size.width, 4), paint);
    final triangle = Path()
      ..moveTo(0, 0)
      ..lineTo(8, 4)
      ..lineTo(0, 8)
      ..close();
    canvas.drawPath(triangle, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Grid Painter ──────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color ink;
  final int totalMinutes;
  final int numDays;
  final double dayWidth;
  final double hourHeight;

  _GridPainter({
    required this.ink,
    required this.totalMinutes,
    required this.numDays,
    required this.dayWidth,
    required this.hourHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ink.withAlpha(20)
      ..strokeWidth = 0.5;

    final borderPaint = Paint()
      ..color = ink.withAlpha(40)
      ..strokeWidth = borderWidth;

    final hours = totalMinutes ~/ 60;

    for (int i = 0; i <= hours; i++) {
      final y = i * hourHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i == 0 || i == hours ? borderPaint : gridPaint,
      );
    }

    for (int i = 1; i < numDays; i++) {
      final x = i * dayWidth;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Drag Overlay ──────────────────────────────────────────────────────────

class _DragOverlay extends StatelessWidget {
  final double startY;
  final double currentY;
  final int dayIndex;
  final double dayWidth;
  final double hoursWidth;

  const _DragOverlay({
    required this.startY,
    required this.currentY,
    required this.dayIndex,
    required this.dayWidth,
    required this.hoursWidth,
  });

  @override
  Widget build(BuildContext context) {
    final top = startY < currentY ? startY : currentY;
    final height = (startY - currentY).abs();
    return Positioned(
      left: dayIndex * dayWidth,
      top: top,
      width: dayWidth,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: accentLab.withAlpha(30),
          border: Border.all(color: accentLab, width: borderWidth),
        ),
      ),
    );
  }
}

// ─── Schedule Block Widget ─────────────────────────────────────────────────

class _ScheduleBlockWidget extends StatelessWidget {
  final ScheduleBlock block;
  final VoidCallback onTap;

  const _ScheduleBlockWidget({
    required this.block,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = _parseHex(block.color);
    final showLocation = block.location != null && block.location!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: shadowM,
        ),
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.title,
              style: labelBold.copyWith(
                color: paperLight,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showLocation && block.durationMinutes >= 60)
              Text(
                block.location!,
                style: bodyS.copyWith(
                  color: paperLight.withAlpha(180),
                  fontSize: 8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Block Detail Sheet ────────────────────────────────────────────────────

class _BlockDetailSheet extends ConsumerWidget {
  final ScheduleBlock block;
  final LabSpace space;
  final ScrollController scrollController;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BlockDetailSheet({
    required this.block,
    required this.space,
    required this.scrollController,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayLabels = block.days
        .map((d) => _dayNames[_dayNames.indexOf(d)])
        .join(', ');
    final ink = inkColor(context);

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: ink, width: borderWidthHeavy),
        ),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              color: inkGray,
              margin: const EdgeInsets.only(bottom: 16),
            ),
          ),
          Row(
            children: [
              Container(
                width: 4,
                height: 32,
                color: _parseHex(block.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(block.title,
                    style: displayM.copyWith(color: ink)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _InfoRow(label: 'Horario', value: '${block.startTime} – ${block.endTime}'),
          const SizedBox(height: 8),
          _InfoRow(label: 'Dias', value: dayLabels),
          if (block.location != null && block.location!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(label: 'Salon', value: block.location!),
          ],
          if (block.folderId != null) ...[
            const SizedBox(height: 20),
            _FolderLinkButton(folderId: block.folderId!),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: accentLab,
                      border: Border.all(color: inkBlack, width: borderWidth),
                      boxShadow: shadowM,
                    ),
                    child: Center(
                      child: Text('Editar',
                          style: labelBold.copyWith(color: paperLight)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: accentFight,
                      border: Border.all(color: inkBlack, width: borderWidth),
                      boxShadow: shadowM,
                    ),
                    child: Center(
                      child: Text('Eliminar',
                          style: labelBold.copyWith(color: paperLight)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: labelBold.copyWith(color: inkGray, fontSize: 12)),
        ),
        Expanded(
          child: Text(value, style: bodyM.copyWith(color: ink)),
        ),
      ],
    );
  }
}

class _FolderLinkButton extends ConsumerWidget {
  final int folderId;
  const _FolderLinkButton({required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folderAsync = ref.watch(folderByIdProvider(folderId));
    final folder = folderAsync.valueOrNull;
    if (folder == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        ref.read(pendingFolderNavigationProvider.notifier).state = folderId;
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: folder.color.withAlpha(20),
          border: Border.all(color: folder.color, width: borderWidth),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: folder.color),
            const SizedBox(width: 8),
              Text('Ir a carpeta $_arrow',
                style: labelBold.copyWith(color: folder.color)),
          ],
        ),
      ),
    );
  }
}

const _arrow = '\u2192';

// ─── Block Form Sheet (Create / Edit) ──────────────────────────────────────

class _BlockFormSheet extends ConsumerStatefulWidget {
  final LabSpace space;
  final ScrollController scrollController;
  final String initialStartTime;
  final String initialEndTime;
  final List<String> initialDays;
  final ScheduleBlock? existingBlock;

  const _BlockFormSheet({
    required this.space,
    required this.scrollController,
    required this.initialStartTime,
    required this.initialEndTime,
    required this.initialDays,
    this.existingBlock,
  });

  @override
  ConsumerState<_BlockFormSheet> createState() => _BlockFormSheetState();
}

class _BlockFormSheetState extends ConsumerState<_BlockFormSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _locationCtrl;
  late String _startTime;
  late String _endTime;
  late List<String> _selectedDays;
  int? _selectedFolderId;
  late String _selectedColor;
  bool _useFolderColor = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existingBlock;
    _titleCtrl = TextEditingController(text: b?.title ?? '');
    _locationCtrl = TextEditingController(text: b?.location ?? '');
    _startTime = widget.initialStartTime;
    _endTime = widget.initialEndTime;
    _selectedDays = List.from(widget.initialDays);
    _selectedFolderId = b?.folderId;
    _selectedColor = b?.color ?? '#3D6B4F';
    _useFolderColor = b?.useFolderColor ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    String title = _titleCtrl.text.trim();
    if (_selectedFolderId != null) {
      final folders = ref.read(activeFoldersProvider).valueOrNull ?? [];
      final folder = folders.where((f) => f.id == _selectedFolderId).firstOrNull;
      if (folder != null) {
        title = folder.name;
      }
    }
    if (title.isEmpty || _selectedDays.isEmpty) return;

    final color = _useFolderColor && _selectedFolderId != null
        ? _colorToHex(_folderColor(_selectedFolderId!))
        : _selectedColor;

    final repo = ref.read(scheduleRepositoryProvider);
    if (widget.existingBlock != null) {
      await repo.updateBlock(widget.existingBlock!.copyWith(
        title: title,
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        startTime: _startTime,
        endTime: _endTime,
        days: List.from(_selectedDays),
        color: color,
        folderId: _selectedFolderId,
        useFolderColor: _useFolderColor,
      ));
    } else {
      await repo.createBlock(
        labSpaceId: widget.space.id,
        folderId: _selectedFolderId,
        title: title,
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        startTime: _startTime,
        endTime: _endTime,
        days: List.from(_selectedDays),
        color: color,
        useFolderColor: _useFolderColor,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Color _folderColor(int folderId) {
    final foldersAsync = ref.read(activeFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    final folder = folders.where((f) => f.id == folderId).firstOrNull;
    return folder?.color ?? const Color(0xFF3D6B4F);
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(activeFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    final ink = inkColor(context);

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: ink, width: borderWidthHeavy),
        ),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              color: inkGray,
              margin: const EdgeInsets.only(bottom: 16),
            ),
          ),
          Text(
            widget.existingBlock != null ? 'Editar bloque' : 'Nuevo bloque',
            style: displayM.copyWith(color: ink),
          ),
          const SizedBox(height: 20),
          // Folder selector
          Text('Materia', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...folders.map((f) {
                final isSelected = _selectedFolderId == f.id;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedFolderId = isSelected ? null : f.id;
                    if (_selectedFolderId != null) {
                      _useFolderColor = true;
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: f.color,
                      border: Border.all(
                        color: inkBlack,
                        width: isSelected ? borderWidthHeavy : borderWidth,
                      ),
                      boxShadow: shadowM,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f.name,
                          style: labelBold.copyWith(
                            color: f.color.computeLuminance() > 0.5
                                ? inkBlack
                                : paperLight,
                            fontSize: 11,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check, size: 10,
                              color: f.color.computeLuminance() > 0.5
                                  ? inkBlack
                                  : paperLight),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              if (_selectedFolderId != null)
                GestureDetector(
                  onTap: () =>
                      setState(() => _selectedFolderId = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: accentFight, width: borderWidth),
                    ),
                    child: Text('Sin carpeta',
                        style: labelBold.copyWith(
                            color: accentFight, fontSize: 11)),
                  ),
                ),
            ],
          ),
          if (_selectedFolderId == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              style: bodyM.copyWith(color: ink),
              decoration: InputDecoration(
                hintText: 'Nombre de la materia',
                hintStyle: bodyM.copyWith(color: inkGray),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: ink, width: borderWidth),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: ink, width: borderWidth),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Days selector
          Text('Dias', style: labelBold.copyWith(color: inkGray)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _dayNames.map((d) {
              final isSelected = _selectedDays.contains(d);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) {
                    _selectedDays.remove(d);
                  } else {
                    _selectedDays.add(d);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _parseHex(_selectedColor)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? _parseHex(_selectedColor)
                          : inkGray,
                      width: borderWidth,
                    ),
                  ),
                  child: Text(
                    d,
                    style: labelBold.copyWith(
                      color: isSelected ? paperLight : inkGray,
                      fontSize: 11,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          // Time pickers
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Inicio',
                  value: _startTime,
                  onChanged: (t) => setState(() => _startTime = t),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimePickerField(
                  label: 'Fin',
                  value: _endTime,
                  onChanged: (t) => setState(() => _endTime = t),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Location
          TextField(
            controller: _locationCtrl,
            style: bodyM.copyWith(color: ink),
            decoration: InputDecoration(
              hintText: 'Salon (opcional)',
              hintStyle: bodyM.copyWith(color: inkGray),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: ink, width: borderWidth),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: ink, width: borderWidth),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (_selectedFolderId == null) ...[
            const SizedBox(height: 16),
            Text('Color', style: labelBold.copyWith(color: inkGray)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                '#3D6B4F', '#2D4B8E', '#E02B2B', '#C17F3A',
                '#4A7C59', '#5B6ABF', '#D9805A', '#7B4B8A',
                '#3A7F7F', '#8F6B3A',
              ].map((hex) {
                final c = _parseHex(hex);
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      border: Border.all(
                        color: isSelected ? inkBlack : Colors.transparent,
                        width: borderWidthHeavy,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 14, color: paperLight)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
          if (_selectedFolderId != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: () =>
                      setState(() => _useFolderColor = !_useFolderColor),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _useFolderColor
                          ? _folderColor(_selectedFolderId!)
                          : Colors.transparent,
                      border: Border.all(color: ink, width: borderWidth),
                    ),
                    child: _useFolderColor
                        ? const Icon(Icons.check, size: 10, color: paperLight)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Usar color de carpeta',
                    style: bodyS.copyWith(color: ink)),
              ],
            ),
          ],
          const SizedBox(height: 24),
          // Save button
          GestureDetector(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: accentLab,
                border: Border.all(color: inkBlack, width: borderWidth),
                boxShadow: shadowM,
              ),
              child: Center(
                child: Text(
                  widget.existingBlock != null ? 'Guardar cambios' : 'Crear bloque',
                  style: labelBold.copyWith(color: paperLight),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Toggle Row ─────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: labelBold.copyWith(color: ink)),
          ),
          Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color: value ? accentLab : inkGray,
              border: Border.all(color: inkBlack, width: borderWidth),
            ),
            child: Align(
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                color: paperLight,
                margin: const EdgeInsets.all(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Time Picker Field ─────────────────────────────────────────────────────

class _TimePickerField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TimePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return GestureDetector(
      onTap: () async {
        final p = value.split(':');
        final initial = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              dialogTheme: const DialogThemeData(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null && context.mounted) {
          onChanged(
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelBold.copyWith(color: inkGray, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: ink, width: borderWidth),
            ),
            child: Row(
              children: [
                Text(value, style: bodyM.copyWith(color: ink)),
                const Spacer(),
                const Icon(Icons.access_time, size: 14, color: inkGray),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Sheet ────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final ScheduleSettings settings;
  final ScrollController scrollController;
  final ValueChanged<ScheduleSettings> onChanged;

  const _SettingsSheet({
    required this.settings,
    required this.scrollController,
    required this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _showSaturday;
  late bool _showSunday;
  late String _dayStart;
  late String _dayEnd;

  @override
  void initState() {
    super.initState();
    _showSaturday = widget.settings.showSaturday;
    _showSunday = widget.settings.showSunday;
    _dayStart = widget.settings.dayStartTime;
    _dayEnd = widget.settings.dayEndTime;
  }

  void _emit() {
    widget.onChanged(widget.settings.copyWith(
      showSaturday: _showSaturday,
      showSunday: _showSunday,
      dayStartTime: _dayStart,
      dayEndTime: _dayEnd,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: ink, width: borderWidthHeavy),
        ),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              color: inkGray,
              margin: const EdgeInsets.only(bottom: 16),
            ),
          ),
          Text('Ajustes del horario',
              style: displayM.copyWith(color: ink)),
          const SizedBox(height: 24),
          _ToggleRow(
            label: 'Mostrar sabado',
            value: _showSaturday,
            onChanged: (v) {
              setState(() => _showSaturday = v);
              _emit();
            },
          ),
          const SizedBox(height: 12),
          _ToggleRow(
            label: 'Mostrar domingo',
            value: _showSunday,
            onChanged: (v) {
              setState(() => _showSunday = v);
              _emit();
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Hora de inicio',
                  value: _dayStart,
                  onChanged: (t) {
                    setState(() => _dayStart = t);
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimePickerField(
                  label: 'Hora de fin',
                  value: _dayEnd,
                  onChanged: (t) {
                    setState(() => _dayEnd = t);
                    _emit();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
