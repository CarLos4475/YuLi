import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart' as y;
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import 'kanban_card_detail.dart';

class TimelineTab extends ConsumerStatefulWidget {
  final LabSpace space;
  final Set<int> selectedCardIds;
  final void Function(int) onToggleSelection;
  final bool selectionMode;

  const TimelineTab({
    super.key,
    required this.space,
    required this.selectedCardIds,
    required this.onToggleSelection,
    required this.selectionMode,
  });

  @override
  ConsumerState<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends ConsumerState<TimelineTab>
    with AutomaticKeepAliveClientMixin {
  final TransformationController _transformationController =
      TransformationController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final columnsAsync = ref.watch(kanbanColumnsProvider(widget.space.id));
    final cardsAsync = ref.watch(kanbanCardsBySpaceProvider(widget.space.id));
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final ink = inkColor(context);

    final reactiveSpace = spacesAsync.valueOrNull?.firstWhere(
          (s) => s.id == widget.space.id,
          orElse: () => widget.space,
        ) ??
        widget.space;
    if (reactiveSpace.startDate == null || reactiveSpace.dueDate == null) {
      return _NoDatesMessage(ink: ink, accentColor: reactiveSpace.accentColor);
    }

    return columnsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (columns) {
        return cardsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (cards) {
            final withDate = cards.where((c) => c.dueDate != null).toList();
            final noDate = cards.where((c) => c.dueDate == null).toList();

            const tH = 40.0;
            const lH = 100.0;
            final totalH = tH + (columns.length * lH);
            final availH = MediaQuery.of(context).size.height * 0.5;
            final zoom = (availH / totalH).clamp(1.2, 2.0);
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _transformationController.value = Matrix4.diagonal3Values(zoom, zoom, 1);
            });

                return Column(
                  children: [
                    y.ViewHead(
                      title: 'Timeline',
                      kicker:
                          '${withDate.length} CON FECHA · ${columns.length} COLUMNAS',
                    ),
                    Expanded(
                      child: _TimelineViewer(
                        key: ValueKey('${reactiveSpace.id}_${columns.length}_${withDate.length}'),
                        space: reactiveSpace,
                        columns: columns,
                        cards: withDate,
                        ink: ink,
                        transformationController: _transformationController,
                        onCardTap: (card) => widget.selectionMode
                            ? widget.onToggleSelection(card.id)
                            : _openCardDetail(context, card),
                        onCardLongPress: (card) =>
                            widget.onToggleSelection(card.id),
                        selectedCardIds: widget.selectedCardIds,
                        selectionMode: widget.selectionMode,
                        accentColor: widget.space.accentColor,
                      ),
                    ),
                    if (noDate.isNotEmpty)
                      _SinFechaSection(
                        cards: noDate,
                        ink: ink,
                        accentColor: widget.space.accentColor,
                        onCardTap: (card) => widget.selectionMode
                            ? widget.onToggleSelection(card.id)
                            : _openCardDetail(context, card),
                        onCardLongPress: (card) =>
                            widget.onToggleSelection(card.id),
                        selectedCardIds: widget.selectedCardIds,
                        selectionMode: widget.selectionMode,
                      ),
                  ],
                );
          },
        );
      },
    );
  }

  void _openCardDetail(BuildContext context, KanbanCard card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, sc) => KanbanCardDetail(
          card: card,
          space: widget.space,
          scrollController: sc,
        ),
      ),
    );
  }
}

// ─── No Dates Message ────────────────────────────────────────────────────

class _NoDatesMessage extends StatelessWidget {
  final Color ink;
  final Color accentColor;
  const _NoDatesMessage({required this.ink, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final fg = accentColor.computeLuminance() > 0.5 ? inkBlack : paperColor(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: accentColor,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: shadowM,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 32, color: fg),
            const SizedBox(height: 12),
            Text(
              'ESTABLECER FECHAS DEL PROYECTO',
              style: labelM.copyWith(color: fg, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Configura la fecha de inicio y de entrega para usar el timeline.',
              style: bodyS.copyWith(color: fg.withAlpha(180)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Timeline Viewer ─────────────────────────────────────────────────────

class _TimelineViewer extends StatelessWidget {
  final LabSpace space;
  final List<KanbanColumn> columns;
  final List<KanbanCard> cards;
  final Color ink;
  final TransformationController transformationController;
  final void Function(KanbanCard) onCardTap;
  final void Function(KanbanCard) onCardLongPress;
  final Set<int> selectedCardIds;
  final bool selectionMode;
  final Color accentColor;

  const _TimelineViewer({
    super.key,
    required this.space,
    required this.columns,
    required this.cards,
    required this.ink,
    required this.transformationController,
    required this.onCardTap,
    this.onCardLongPress = _noop,
    this.selectedCardIds = const {},
    this.selectionMode = false,
    required this.accentColor,
  });

  static void _noop(KanbanCard _) {}

  @override
  Widget build(BuildContext context) {
    final totalDays = space.dueDate!.difference(space.startDate!).inDays + 1;
    const baseLaneHeight = 100.0;
    const headerHeight = 40.0;
    final availWidth = MediaQuery.of(context).size.width;

    // Count cards per day and per lane for dynamic sizing
    final cardsPerDay = <int, int>{};
    final cardsPerLane = <int, int>{};
    final startDay = DateTime(space.startDate!.year, space.startDate!.month, space.startDate!.day);

    for (final card in cards) {
      if (card.dueDate == null) continue;
      final cardDay = DateTime(card.dueDate!.year, card.dueDate!.month, card.dueDate!.day);
      final dayIndex = cardDay.difference(startDay).inDays;
      if (dayIndex < 0 || dayIndex >= totalDays) continue;
      final laneIndex = columns.indexWhere((c) => c.id == card.columnId);
      if (laneIndex < 0) continue;
      cardsPerDay[dayIndex] = (cardsPerDay[dayIndex] ?? 0) + 1;
      cardsPerLane[laneIndex] = (cardsPerLane[laneIndex] ?? 0) + 1;
    }

    // Day widths: empty days keep original width, days with cards get extra space
    final baseW = availWidth / totalDays;
    final dayWidths = List.generate(totalDays, (d) =>
        (cardsPerDay[d] ?? 0) > 0 ? baseW * 2.5 : baseW);
    final dayPositions = List.filled(totalDays, 0.0);
    for (int d = 0; d < totalDays; d++) {
      dayPositions[d] = d == 0 ? 0 : dayPositions[d - 1] + dayWidths[d - 1];
    }
    final totalWidth = dayPositions.last + dayWidths.last;

    // Calculate per-lane Y positions with dynamic heights
    final laneTopPositions = List.filled(columns.length, 0.0);
    double currentY = headerHeight;
    for (int i = 0; i < columns.length; i++) {
      laneTopPositions[i] = currentY;
      final count = cardsPerLane[i] ?? 0;
      currentY += baseLaneHeight + (count > 4 ? (count - 4) * 26.0 : 0);
    }
    final totalHeight = currentY;

    // Group cards by (dayIndex, laneIndex) for vertical stacking
    final groups = <String, List<KanbanCard>>{};
    for (final card in cards) {
      if (card.dueDate == null) continue;
      final cardDay = DateTime(card.dueDate!.year, card.dueDate!.month, card.dueDate!.day);
      final dayIndex = cardDay.difference(startDay).inDays;
      if (dayIndex < 0 || dayIndex >= totalDays) continue;
      final laneIndex = columns.indexWhere((c) => c.id == card.columnId);
      if (laneIndex < 0) continue;
      final key = '$dayIndex|$laneIndex';
      groups.putIfAbsent(key, () => []).add(card);
    }

    // Build positioned card widgets with vertical stacking
    final cardWidgets = <Widget>[];
    for (final group in groups.entries) {
      final parts = group.key.split('|');
      final dayIndex = int.parse(parts[0]);
      final laneIndex = int.parse(parts[1]);
      final groupCards = group.value;

      groupCards.sort((a, b) => a.position.compareTo(b.position));

      for (int gi = 0; gi < groupCards.length; gi++) {
        final card = groupCards[gi];
        final dayW = dayWidths[dayIndex];
        final x = dayPositions[dayIndex] + 2;
        final top = laneTopPositions[laneIndex] + 4 + gi * 24;
        final cardWidth = dayW - 4;
        final cardHeight = 20.0;
        final isSelected = selectedCardIds.contains(card.id);
        final bg = card.originFolderColor != null
            ? Color(card.originFolderColor!)
            : (card.originTaskDoneAt != null
                ? accentSuccess
                : _cardColor(card));

        cardWidgets.add(
          Positioned(
            left: x,
            top: top,
            width: cardWidth,
            height: cardHeight,
            child: GestureDetector(
              onTap: () => onCardTap(card),
              onLongPress: () => onCardLongPress(card),
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : bg,
                  border: Border.all(
                    color: inkBlack,
                    width: isSelected ? borderWidthHeavy : borderWidth,
                  ),
                  boxShadow: shadowM,
                ),
                padding: const EdgeInsets.fromLTRB(5, 2, 4, 2),
                child: Text(
                  card.title,
                  style: TextStyle(
                    color: isSelected
                        ? paperLight
                        : bg.computeLuminance() > 0.5
                            ? inkBlack
                            : paperLight,
                    fontSize: 9,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      }
    }

    return InteractiveViewer(
      transformationController: transformationController,
      boundaryMargin: const EdgeInsets.all(0),
      minScale: 0.5,
      maxScale: 5.0,
      constrained: false,
      child: SizedBox(
        width: totalWidth,
        height: totalHeight,
        child: Stack(
          children: [
            CustomPaint(
              painter: _TimelineGridPainter(
                startDate: space.startDate!,
                dueDate: space.dueDate!,
                columns: columns,
                ink: ink,
                headerHeight: headerHeight,
                laneTopPositions: laneTopPositions,
                dayPositions: dayPositions,
                dayWidths: dayWidths,
              ),
              size: Size(totalWidth, totalHeight),
            ),
            ...cardWidgets,
          ],
        ),
      ),
    );
  }

  Color _cardColor(KanbanCard card) {
    if (card.originTaskDoneAt != null) return accentSuccess;
    if (card.originFolderColor != null) return Color(card.originFolderColor!);
    return switch (card.priority) {
      CardPriority.high => accentError,
      CardPriority.medium => const Color(0xFFF5A623),
      CardPriority.low => accentSuccess,
      CardPriority.none => inkGray,
    };
  }
}

// ─── Timeline Grid Painter ───────────────────────────────────────────────

class _TimelineGridPainter extends CustomPainter {
  final DateTime startDate;
  final DateTime dueDate;
  final List<KanbanColumn> columns;
  final Color ink;
  final double headerHeight;
  final List<double> laneTopPositions;
  final List<double> dayPositions;
  final List<double> dayWidths;

  _TimelineGridPainter({
    required this.startDate,
    required this.dueDate,
    required this.columns,
    required this.ink,
    required this.headerHeight,
    required this.laneTopPositions,
    required this.dayPositions,
    required this.dayWidths,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalDays = dueDate.difference(startDate).inDays + 1;
    final today = DateTime.now();

    final gridPaint = Paint()
      ..color = ink.withAlpha(30)
      ..strokeWidth = 0.5;

    final laneBorderPaint = Paint()
      ..color = ink.withAlpha(60)
      ..strokeWidth = borderWidth;

    final wine = const Color(0xFF800020);
    final todayPaint = Paint()
      ..color = wine
      ..strokeWidth = 1.5;

    const textStyle = TextStyle(
      color: inkGray,
      fontSize: 10,
      fontFamily: 'monospace',
    );

    // Draw vertical grid lines and date labels
    for (int i = 0; i < totalDays; i++) {
      final x = dayPositions[i];
      final dw = dayWidths[i];

      // Grid line at start of day
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Grid line at end of day
      canvas.drawLine(
        Offset(x + dw, 0),
        Offset(x + dw, size.height),
        gridPaint,
      );

      // Date label centered in day width
      final day = DateTime(startDate.year, startDate.month, startDate.day + i);
      final dayStr = '${day.day}';
      final textSpan = TextSpan(text: dayStr, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final labelX = x + 2;
      textPainter.paint(
        canvas,
        Offset(labelX, 2),
      );

      // Month label on first day or when month changes
      if (i == 0 || day.day == 1) {
        final monthStr = _monthShort(day.month);
        final monthSpan = TextSpan(
          text: monthStr,
          style: textStyle.copyWith(fontWeight: FontWeight.w600),
        );
        final monthPainter = TextPainter(
          text: monthSpan,
          textDirection: TextDirection.ltr,
        );
        monthPainter.layout();
        monthPainter.paint(
          canvas,
          Offset(labelX, 14),
        );
      }
    }

    // Rightmost border
    canvas.drawLine(
      Offset(dayPositions.last + dayWidths.last, 0),
      Offset(dayPositions.last + dayWidths.last, size.height),
      gridPaint,
    );

    // Horizontal lane lines and column labels
    for (int i = 0; i < columns.length; i++) {
      final y = laneTopPositions[i];

      // Lane top border
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        laneBorderPaint,
      );

      // Column label
      final labelSpan = TextSpan(
        text: columns[i].name.toUpperCase(),
        style: const TextStyle(
          color: inkGray,
          fontSize: 11,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
        ),
      );
      final labelPainter = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(4, y + 4),
      );
    }

    // Bottom border
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      laneBorderPaint,
    );

    // Today vertical line
    final todayDiff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(startDate.year, startDate.month, startDate.day))
        .inDays;
    if (todayDiff >= 0 && todayDiff < totalDays) {
      final todayX = dayPositions[todayDiff] + (dayWidths[todayDiff] / 2);
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        todayPaint,
      );

      // "HOY" label
      final hoySpan = TextSpan(
        text: 'HOY',
        style: textStyle.copyWith(
          color: const Color(0xFF800020),
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      );
      final hoyPainter = TextPainter(
        text: hoySpan,
        textDirection: TextDirection.ltr,
      );
      hoyPainter.layout();
      hoyPainter.paint(
        canvas,
        Offset(todayX + 2, size.height - 14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  String _monthShort(int m) => [
        'ENE',
        'FEB',
        'MAR',
        'ABR',
        'MAY',
        'JUN',
        'JUL',
        'AGO',
        'SEP',
        'OCT',
        'NOV',
        'DIC',
      ][m - 1];
}

// ─── Sin Fecha Section ───────────────────────────────────────────────────

class _SinFechaSection extends StatelessWidget {
  final List<KanbanCard> cards;
  final Color ink;
  final Color accentColor;
  final void Function(KanbanCard)? onCardTap;
  final void Function(KanbanCard)? onCardLongPress;
  final Set<int> selectedCardIds;
  final bool selectionMode;

  const _SinFechaSection({
    required this.cards,
    required this.ink,
    required this.accentColor,
    this.onCardTap,
    this.onCardLongPress,
    this.selectedCardIds = const {},
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ink, width: borderWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ink.withAlpha(10),
              border: Border(
                bottom: BorderSide(
                  color: ink.withAlpha(40),
                  width: borderWidth,
                ),
              ),
            ),
            child: Text(
              'SIN FECHA (${cards.length})',
              style: labelS.copyWith(
                color: inkGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              itemCount: cards.length,
              itemBuilder: (context, i) {
                final bg = cards[i].originTaskDoneAt != null
                    ? accentSuccess
                    : (cards[i].originFolderColor != null
                        ? Color(cards[i].originFolderColor!)
                        : _priorityColor(cards[i].priority));
                final isSelected = selectedCardIds.contains(cards[i].id);
                return GestureDetector(
                  onTap: onCardTap != null ? () => onCardTap!(cards[i]) : null,
                  onLongPress: onCardLongPress != null
                      ? () => onCardLongPress!(cards[i])
                      : null,
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border.all(
                        color: isSelected ? accentColor : inkBlack,
                        width: isSelected ? borderWidthHeavy : borderWidth,
                      ),
                      boxShadow: isSelected ? null : shadowM,
                    ),
                    child: Text(
                      cards[i].title,
                      style: bodyS.copyWith(
                        color: bg.computeLuminance() > 0.5
                            ? inkBlack
                            : paperColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _priorityColor(CardPriority p) => switch (p) {
        CardPriority.high => accentError,
        CardPriority.medium => const Color(0xFFF5A623),
        CardPriority.low => accentSuccess,
        CardPriority.none => inkGray,
      };
}
