import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import 'kanban_card_detail.dart';

class TimelineTab extends ConsumerStatefulWidget {
  final LabSpace space;
  const TimelineTab({super.key, required this.space});

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
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _fitTimeline());
  }

  void _fitTimeline() {
    if (!mounted) return;
    if (widget.space.startDate == null || widget.space.dueDate == null) return;
    final totalDays = widget.space.dueDate!.difference(widget.space.startDate!).inDays + 1;
    if (totalDays <= 0) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final totalWidth = screenWidth + (totalDays * 4.0);
    final scale = screenWidth / totalWidth;
    _transformationController.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

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
      error: (_, __) => const SizedBox.shrink(),
      data: (columns) {
        return cardsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (cards) {
            final withDate = cards.where((c) => c.dueDate != null).toList();
            final noDate = cards.where((c) => c.dueDate == null).toList();

            return Column(
              children: [
                // Timeline zoom area
                Expanded(
                  child: _TimelineViewer(
                    space: reactiveSpace,
                    columns: columns,
                    cards: withDate,
                    ink: ink,
                    transformationController: _transformationController,
                    onCardTap: (card) => _openCardDetail(context, card),
                  ),
                ),
                // SIN FECHA section
                if (noDate.isNotEmpty)
                  _SinFechaSection(
                    cards: noDate,
                    ink: ink,
                    onCardTap: (card) => _openCardDetail(context, card),
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

  const _TimelineViewer({
    required this.space,
    required this.columns,
    required this.cards,
    required this.ink,
    required this.transformationController,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalDays = space.dueDate!.difference(space.startDate!).inDays + 1;
    const laneHeight = 80.0;
    const headerHeight = 40.0;
    final totalHeight = headerHeight + (columns.length * laneHeight);
    final minWidth = MediaQuery.of(context).size.width;
    final totalWidth = minWidth + (totalDays * 4.0);
    final dayWidth = totalWidth / totalDays;
    final paper = paperColor(context);

    // Build positioned card widgets
    final cardWidgets = <Widget>[];
    for (final card in cards) {
      if (card.dueDate == null) continue;

      final cardDay = DateTime(card.dueDate!.year, card.dueDate!.month, card.dueDate!.day);
      final startDay = DateTime(space.startDate!.year, space.startDate!.month, space.startDate!.day);
      final dayIndex = cardDay.difference(startDay).inDays;

      if (dayIndex < 0 || dayIndex >= totalDays) continue;

      final laneIndex = columns.indexWhere((c) => c.id == card.columnId);
      if (laneIndex < 0) continue;

      final x = dayIndex * dayWidth + 2;
      final y = headerHeight + (laneIndex * laneHeight) + 24;
      final cardWidth = dayWidth - 4;
      final cardHeight = laneHeight - 28;

      cardWidgets.add(
        Positioned(
          left: x,
          top: y,
          width: cardWidth,
          height: cardHeight,
          child: GestureDetector(
            onTap: () => onCardTap(card),
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                color: paper,
                border: Border.all(color: ink.withAlpha(80), width: borderWidth),
              ),
              padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: double.infinity,
                    color: _cardColor(card),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      card.title,
                      style: TextStyle(
                        color: ink,
                        fontSize: 9,
                        fontFamily: 'Inter',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
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
                laneHeight: laneHeight,
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
  final double laneHeight;

  _TimelineGridPainter({
    required this.startDate,
    required this.dueDate,
    required this.columns,
    required this.ink,
    required this.headerHeight,
    required this.laneHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalDays = dueDate.difference(startDate).inDays + 1;
    final dayWidth = size.width / totalDays;
    final today = DateTime.now();

    final gridPaint = Paint()
      ..color = ink.withAlpha(30)
      ..strokeWidth = 0.5;

    final laneBorderPaint = Paint()
      ..color = ink.withAlpha(60)
      ..strokeWidth = borderWidth;

    final todayPaint = Paint()
      ..color = accentError
      ..strokeWidth = 1.5;

    const textStyle = TextStyle(
      color: inkGray,
      fontSize: 10,
      fontFamily: 'monospace',
    );

    // Draw vertical grid lines and date labels
    for (int i = 0; i <= totalDays; i++) {
      final x = i * dayWidth;

      // Grid line
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Date label
      if (i < totalDays) {
        final day = DateTime(startDate.year, startDate.month, startDate.day + i);
        final dayStr = '${day.day}';
        final textSpan = TextSpan(text: dayStr, style: textStyle);
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x + 2, 2),
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
            Offset(x + 2, 14),
          );
        }
      }
    }

    // Horizontal lane lines and column labels
    for (int i = 0; i < columns.length; i++) {
      final y = headerHeight + (i * laneHeight);

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
      final todayX = todayDiff * dayWidth + (dayWidth / 2);
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        todayPaint,
      );

      // "HOY" label
      final hoySpan = TextSpan(
        text: 'HOY',
        style: textStyle.copyWith(
          color: accentError,
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
  final void Function(KanbanCard)? onCardTap;

  const _SinFechaSection({
    required this.cards,
    required this.ink,
    this.onCardTap,
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
                    : _priorityColor(cards[i].priority);
                return GestureDetector(
                  onTap: onCardTap != null ? () => onCardTap!(cards[i]) : null,
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bg,
                      border: Border.all(
                        color: inkBlack,
                        width: borderWidth,
                      ),
                      boxShadow: shadowM,
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
