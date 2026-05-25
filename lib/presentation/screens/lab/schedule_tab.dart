import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../../domain/models/schedule_block.dart';
import '../../../domain/models/schedule_settings.dart';
import '../../../domain/models/schedule_week_note.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/repositories/schedule_repository.dart';

// ─── Constants ─────────────────────────────────────────────────────────────

const _hoursWidth = 52.0;
const _halfHourHeight = 40.0;
const _dayHeaderHeight = 56.0;
const _dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

List<String> _weekDays(bool showWeekends) =>
    showWeekends ? _dayNames : _dayNames.sublist(0, 5);

int _timeToMinutes(String time) {
  final p = time.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _minutesToTime(int m) {
  final h = m ~/ 60;
  final min = m % 60;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

int _roundToHalfHour(int minutes) =>
    (minutes / 30).round() * 30;

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
  const _LaneInfo(this.block, this.lane, this.totalLanes);
}

List<_LaneInfo> _assignLanes(List<ScheduleBlock> blocks) {
  if (blocks.isEmpty) return [];
  final sorted = List<ScheduleBlock>.from(blocks)
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final lanes = <List<ScheduleBlock>>[];
  final result = <_LaneInfo>[];
  for (final block in sorted) {
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
    result.add(_LaneInfo(block, idx, lanes.length));
  }
  return result;
}

// ─── Settings provider per space ──────────────────────────────────────────

final _scheduleSettingsProvider =
    FutureProvider.family<ScheduleSettings, int>((ref, spaceId) async {
  return ref.read(scheduleRepositoryProvider).getOrCreateSettings(spaceId);
});

// ─── Main Widget ───────────────────────────────────────────────────────────

class ScheduleTab extends ConsumerStatefulWidget {
  final LabSpace space;
  const ScheduleTab({super.key, required this.space});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab>
    with AutomaticKeepAliveClientMixin {
  late DateTime _currentWeekStart;

  double? _dragStartY;
  double? _dragCurrentY;
  int? _dragDayIndex;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _mondayOfWeek(DateTime.now());
  }

  void _prevWeek() => setState(
      () => _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7)));

  void _nextWeek() => setState(
      () => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7)));

  void _goToday() => setState(() => _currentWeekStart = _mondayOfWeek(DateTime.now()));

  String _weekLabel() {
    final end = _currentWeekStart.add(const Duration(days: 6));
    return '${_currentWeekStart.day}/${_currentWeekStart.month} – ${end.day}/${end.month}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ink = inkColor(context);

    return ref.watch(_scheduleSettingsProvider(widget.space.id)).when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (settings) {
        return StreamBuilder<List<ScheduleBlock>>(
          stream: ref.read(scheduleRepositoryProvider).watchBySpace(widget.space.id),
          builder: (ctx, snap) {
            final blocks = snap.data ?? [];
            return _buildWithBlocks(ctx, blocks, settings, ink);
          },
        );
      },
    );
  }

  Widget _buildWithBlocks(BuildContext outerCtx, List<ScheduleBlock> blocks,
      ScheduleSettings settings, Color ink) {
    final days = _weekDays(settings.showWeekends);
    final sMin = settings.startMinutes;
    final eMin = settings.endMinutes;
    final totalMins = eMin - sMin;
    final totalHeight = (totalMins / 30) * _halfHourHeight;

    return StreamBuilder<ScheduleWeekNote?>(
      stream: ref.read(scheduleRepositoryProvider).watchWeekNote(
        widget.space.id, _currentWeekStart),
      builder: (context, noteSnap) {
        final weekNote = noteSnap.data;
        return Column(
          children: [
            _ScheduleHeader(
              weekLabel: _weekLabel(),
              onPrev: _prevWeek,
              onNext: _nextWeek,
              onToday: _goToday,
              onSettings: () => _showSettings(context, settings),
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
                            height: totalHeight + _halfHourHeight,
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
                                          m += 30)
                                        SizedBox(
                                          height: _halfHourHeight,
                                          child: Align(
                                            alignment: Alignment.topRight,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.only(right: 6, top: -6),
                                              child: Text(
                                                _minutesToTime(m),
                                                style: bodyS.copyWith(
                                                    color: inkGray, fontSize: 10),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Days area
                                Expanded(
                                  child: SizedBox(
                                    height: totalHeight + _halfHourHeight,
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          size: Size(
                                              constraints.maxWidth - _hoursWidth,
                                              totalHeight + _halfHourHeight),
                                          painter: _GridPainter(
                                            ink: ink,
                                            totalMinutes: totalMins,
                                            numDays: days.length,
                                            dayWidth: dayWidth,
                                            halfHourHeight: _halfHourHeight,
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
                                        // Drag overlay
                                        if (_dragStartY != null &&
                                            _dragCurrentY != null &&
                                            _dragDayIndex != null)
                                          _DragOverlay(
                                            startY: _dragStartY!,
                                            currentY: _dragCurrentY!,
                                            dayIndex: _dragDayIndex!,
                                            dayWidth: dayWidth,
                                            hoursWidth: _hoursWidth,
                                          ),
                                        // Drag gesture detector for each day
                                        for (int di = 0; di < days.length; di++)
                                          Positioned(
                                            left: di * dayWidth,
                                            top: 0,
                                            width: dayWidth,
                                            height:
                                                totalHeight + _halfHourHeight,
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onVerticalDragStart: (d) =>
                                                  setState(() {
                                                _dragStartY = d.localPosition.dy;
                                                _dragCurrentY =
                                                    d.localPosition.dy;
                                                _dragDayIndex = di;
                                              }),
                                              onVerticalDragUpdate: (d) =>
                                                  setState(() =>
                                                      _dragCurrentY =
                                                          d.localPosition.dy),
                                              onVerticalDragEnd: (d) {
                                                _finishDrag(blocks, days, sMin,
                                                    totalHeight);
                                              },
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
        );
      },
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
      final topRatio =
          (b.startMinutes - startMinutes) / (totalHeight / _halfHourHeight * 30);
      final heightRatio =
          (b.endMinutes - b.startMinutes) / (_halfHourHeight * 2) * _halfHourHeight;
      final top = topRatio * _halfHourHeight;

      result.add(
        Positioned(
          left: dayIndex * dayWidth + li.lane * laneWidth,
          top: top,
          width: laneWidth - 2,
          height: heightRatio - 2,
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

    final minPerPixel = 30.0 / _halfHourHeight;
    final startMins =
        _roundToHalfHour(startMinutes + (top * minPerPixel).round());
    final endMins =
        _roundToHalfHour(startMinutes + (bottom * minPerPixel).round());

    setState(() {
      _dragStartY = null;
      _dragCurrentY = null;
      _dragDayIndex = null;
    });

    if (endMins - startMins < 30) return;

    final dayKey = days[_dragDayIndex!];
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

  const _ScheduleHeader({
    required this.weekLabel,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ink, width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          Text('Horario', style: displayM.copyWith(color: accentLab)),
          const Spacer(),
          GestureDetector(
            onTap: onPrev,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border.all(color: inkGray, width: borderWidth),
              ),
              child: const Icon(Icons.chevron_left, size: 16, color: inkGray),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onToday,
            child: Text(
              weekLabel,
              style: labelBold.copyWith(color: ink),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onNext,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border.all(color: inkGray, width: borderWidth),
              ),
              child: const Icon(Icons.chevron_right, size: 16, color: inkGray),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: inkGray, width: borderWidth),
              ),
              child: Text('Ajustar',
                  style: labelBold.copyWith(color: inkGray, fontSize: 11)),
            ),
          ),
        ],
      ),
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

class _GridPainter extends CustomPainter {
  final Color ink;
  final int totalMinutes;
  final int numDays;
  final double dayWidth;
  final double halfHourHeight;

  _GridPainter({
    required this.ink,
    required this.totalMinutes,
    required this.numDays,
    required this.dayWidth,
    required this.halfHourHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ink.withAlpha(20)
      ..strokeWidth = 0.5;

    final borderPaint = Paint()
      ..color = ink.withAlpha(40)
      ..strokeWidth = borderWidth;

    final slots = totalMinutes ~/ 30;

    // Horizontal lines
    for (int i = 0; i <= slots; i++) {
      final y = i * halfHourHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % 2 == 0 ? borderPaint : gridPaint,
      );
    }

    // Vertical lines (day separators)
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
    final title = _titleCtrl.text.trim();
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
    if (context.mounted) Navigator.pop(context);
  }

  String _colorToHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

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
              ...folders.map((f) => GestureDetector(
                    onTap: () => setState(() {
                      _selectedFolderId =
                          _selectedFolderId == f.id ? null : f.id;
                      if (_selectedFolderId != null) {
                        _useFolderColor = true;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedFolderId == f.id
                            ? f.color
                            : Colors.transparent,
                        border: Border.all(
                          color: _selectedFolderId == f.id
                              ? f.color
                              : inkGray,
                          width: borderWidth,
                        ),
                      ),
                      child: Text(
                        f.name,
                        style: labelBold.copyWith(
                          color: _selectedFolderId == f.id
                              ? paperLight
                              : f.color,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )),
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
  late bool _showWeekends;
  late String _dayStart;
  late String _dayEnd;

  @override
  void initState() {
    super.initState();
    _showWeekends = widget.settings.showWeekends;
    _dayStart = widget.settings.dayStartTime;
    _dayEnd = widget.settings.dayEndTime;
  }

  void _emit() {
    widget.onChanged(widget.settings.copyWith(
      showWeekends: _showWeekends,
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
          Row(
            children: [
              Expanded(
                child: Text('Mostrar sabado y domingo',
                    style: bodyM.copyWith(color: ink)),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _showWeekends = !_showWeekends);
                  _emit();
                },
                child: Container(
                  width: 40,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _showWeekends ? accentLab : inkGray,
                    border: Border.all(color: inkBlack, width: borderWidth),
                  ),
                  child: Align(
                    alignment:
                        _showWeekends ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 18,
                      height: 18,
                      color: paperLight,
                      margin: const EdgeInsets.all(1),
                    ),
                  ),
                ),
              ),
            ],
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
