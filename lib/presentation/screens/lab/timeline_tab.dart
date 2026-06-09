import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart' as y;
import '../../providers/lab_space_providers.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import 'kanban_card_detail.dart';
import 'lab_card_colors.dart';

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

    final reactiveSpace =
        spacesAsync.valueOrNull?.firstWhere(
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

            // No forced zoom: the viewer starts at natural 1:1 (the day width
            // already fits the viewport, see `_TimelineViewer.dayW`) and the
            // controller keeps whatever the user pinches to. The old per-build
            // auto-zoom slammed everything to ≥1.2× and reset the user's zoom on
            // every rebuild — hence "se reajusta solo / todo muy grande".

            return Column(
              children: [
                y.ViewHead(
                  title: 'Timeline',
                  titleColor: reactiveSpace.accentColor,
                  kicker:
                      '${withDate.length} CON FECHA · ${columns.length} COLUMNAS',
                ),
                Expanded(
                  child: _TimelineViewer(
                    key: ValueKey(
                      '${reactiveSpace.id}_${columns.length}_${withDate.length}',
                    ),
                    space: reactiveSpace,
                    columns: columns,
                    cards: withDate,
                    ink: ink,
                    transformationController: _transformationController,
                    onCardTap:
                        (card) =>
                            widget.selectionMode
                                ? widget.onToggleSelection(card.id)
                                : _openCardDetail(context, card),
                    onCardLongPress:
                        (card) => widget.onToggleSelection(card.id),
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
                    onCardTap:
                        (card) =>
                            widget.selectionMode
                                ? widget.onToggleSelection(card.id)
                                : _openCardDetail(context, card),
                    onCardLongPress:
                        (card) => widget.onToggleSelection(card.id),
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
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder:
                (ctx, sc) => KanbanCardDetail(
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
    final fg =
        accentColor.computeLuminance() > 0.5 ? inkBlack : paperColor(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: accentColor,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
          boxShadow: shadowM,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(YuLiIcons.timeline, size: 32, color: fg),
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
    final startDay = DateTime(
      space.startDate!.year,
      space.startDate!.month,
      space.startDate!.day,
    );
    final endDay = DateTime(
      space.dueDate!.year,
      space.dueDate!.month,
      space.dueDate!.day,
    );
    final totalDays = endDay.difference(startDay).inDays + 1;
    const headerHeight = 40.0;
    const rowH = 32.0; // height of one stacked bar row
    const laneVPad = 8.0;
    final availWidth = MediaQuery.of(context).size.width;

    // Uniform day width (so a bar's length reads as its duration). Min keeps it
    // legible; InteractiveViewer scrolls when there are many days.
    final dayW = math.max(availWidth / totalDays, 26.0);
    final dayPositions = List.generate(totalDays, (d) => d * dayW);
    final dayWidths = List.filled(totalDays, dayW);
    final totalWidth = totalDays * dayW;

    int clampDay(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return day.difference(startDay).inDays.clamp(0, totalDays - 1);
    }

    // Per-lane interval packing: a card spans (startDate ?? createdAt) → dueDate;
    // overlapping spans get stacked into separate rows. dueDate keeps its
    // existing cross-mode behavior — we only READ it here.
    final placed = <_BarPlacement>[];
    final laneRowCount = List.filled(columns.length, 1);
    for (int li = 0; li < columns.length; li++) {
      final spans =
          cards
              .where((c) => c.dueDate != null && c.columnId == columns[li].id)
              .map((c) {
                final s = clampDay(c.startDate ?? c.createdAt);
                var e = clampDay(c.dueDate!);
                if (e < s) e = s;
                return (card: c, s: s, e: e);
              })
              .toList()
            ..sort((a, b) => a.s.compareTo(b.s));
      final rowEnds = <int>[]; // last end-day index per row
      for (final sp in spans) {
        int row = -1;
        for (int r = 0; r < rowEnds.length; r++) {
          if (rowEnds[r] < sp.s) {
            row = r;
            break;
          }
        }
        if (row < 0) {
          row = rowEnds.length;
          rowEnds.add(sp.e);
        } else {
          rowEnds[row] = sp.e;
        }
        placed.add(
          _BarPlacement(
            card: sp.card,
            lane: li,
            row: row,
            startIdx: sp.s,
            endIdx: sp.e,
          ),
        );
      }
      laneRowCount[li] = math.max(1, rowEnds.length);
    }

    // Per-lane Y positions (height grows with stacked rows).
    final laneTopPositions = List.filled(columns.length, 0.0);
    double currentY = headerHeight;
    for (int i = 0; i < columns.length; i++) {
      laneTopPositions[i] = currentY;
      currentY += laneVPad + laneRowCount[i] * rowH + laneVPad;
    }
    final totalHeight = currentY;

    // Build positioned bar widgets.
    final cardWidgets = <Widget>[];
    {
      for (final p in placed) {
        final card = p.card;
        final x = dayPositions[p.startIdx] + 2;
        final top = laneTopPositions[p.lane] + laneVPad + p.row * rowH;
        final cardWidth = (p.endIdx - p.startIdx + 1) * dayW - 4;
        final cardHeight = 28.0;
        final isSelected = selectedCardIds.contains(card.id);
        final bg = labCardAccent(
          card,
          inExpiredColumn: columns.any(
            (c) => c.id == card.columnId && c.isExpired,
          ),
        );

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
                    color: y.yBorderStrong,
                    width: isSelected ? y.yLineHeavy : 2,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        y.cleanMention(card.title),
                        style: y
                            .ySans(
                              size: 11,
                              weight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color:
                                  isSelected
                                      ? y.yCream
                                      : bg.computeLuminance() > 0.5
                                      ? y.yInk
                                      : y.yCream,
                              height: 1.1,
                            )
                            .copyWith(
                              decoration:
                                  card.originTaskDoneAt != null
                                      ? TextDecoration.lineThrough
                                      : null,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Only show the date chip when the bar is wide enough for
                    // it alongside the (Expanded) title — otherwise it has no
                    // flex and overflows narrow 1-day bars.
                    if (card.dueDate != null && cardWidth > 80)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '${card.dueDate!.day.toString().padLeft(2, '0')}/${card.dueDate!.month.toString().padLeft(2, '0')}',
                          style: y.yMono(
                            size: 9,
                            color:
                                (isSelected || bg.computeLuminance() <= 0.5)
                                    ? y.yCream.withAlpha(216)
                                    : y.yMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Pad the canvas to AT LEAST the viewport height so the child always
        // covers the viewport. That lets boundaryMargin be zero (content can't
        // be flung into the void) WHILE avoiding the "child smaller than
        // viewport" snap-zoom on the first pinch. minScale 1.0 forbids shrinking
        // below the natural 1:1 fit (which would re-open the void).
        final canvasH = math.max(totalHeight, constraints.maxHeight);
        return InteractiveViewer(
          transformationController: transformationController,
          boundaryMargin: EdgeInsets.zero,
          minScale: 1.0,
          maxScale: 5.0,
          constrained: false,
          child: SizedBox(
            width: totalWidth,
            height: canvasH,
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
      },
    );
  }
}

/// A card's placement on the timeline: its lane (column), the stacked row it
/// got packed into, and the day-index span [startIdx]..[endIdx] of its bar.
class _BarPlacement {
  final KanbanCard card;
  final int lane;
  final int row;
  final int startIdx;
  final int endIdx;
  const _BarPlacement({
    required this.card,
    required this.lane,
    required this.row,
    required this.startIdx,
    required this.endIdx,
  });
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

    final gridPaint =
        Paint()
          ..color = ink.withAlpha(30)
          ..strokeWidth = 0.5;

    final laneBorderPaint =
        Paint()
          ..color = ink.withAlpha(60)
          ..strokeWidth = borderWidth;

    final todayPaint =
        Paint()
          ..color = y.yFight
          ..strokeWidth = 2.0;

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
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

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
      textPainter.paint(canvas, Offset(labelX, 2));

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
        monthPainter.paint(canvas, Offset(labelX, 14));
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
      canvas.drawLine(Offset(0, y), Offset(size.width, y), laneBorderPaint);

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
      labelPainter.paint(canvas, Offset(4, y + 4));
    }

    // Bottom border
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      laneBorderPaint,
    );

    // Today vertical line
    final todayDiff =
        DateTime(today.year, today.month, today.day)
            .difference(
              DateTime(startDate.year, startDate.month, startDate.day),
            )
            .inDays;
    if (todayDiff >= 0 && todayDiff < totalDays) {
      final todayX = dayPositions[todayDiff] + (dayWidths[todayDiff] / 2);
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        todayPaint,
      );

      // "HOY" label chip
      final hoySpan = TextSpan(
        text: 'HOY',
        style: const TextStyle(
          color: y.yCream,
          fontWeight: FontWeight.w700,
          fontSize: 8,
          fontFamily: 'monospace',
          letterSpacing: 1.2,
        ),
      );
      final hoyPainter = TextPainter(
        text: hoySpan,
        textDirection: TextDirection.ltr,
      );
      hoyPainter.layout();
      final chipW = hoyPainter.width + 12;
      final chipH = hoyPainter.height + 6;
      canvas.drawRect(
        Rect.fromLTWH(todayX - chipW / 2, -2, chipW, chipH),
        Paint()..color = y.yFight,
      );
      canvas.drawRect(
        Rect.fromLTWH(todayX - chipW / 2, -2, chipW, chipH),
        Paint()
          ..color = y.yInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      hoyPainter.paint(canvas, Offset(todayX - hoyPainter.width / 2, 1));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  String _monthShort(int m) =>
      [
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

class _SinFechaSection extends StatefulWidget {
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
  State<_SinFechaSection> createState() => _SinFechaSectionState();
}

class _SinFechaSectionState extends State<_SinFechaSection> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: widget.ink, width: borderWidth)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.accentColor,
                border: Border(
                  bottom: BorderSide(
                    color: widget.ink,
                    width: borderWidth,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _collapsed ? YuLiIcons.chevronRight : YuLiIcons.chevronDown,
                    size: 14,
                    color: y.yCream,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SIN FECHA (${widget.cards.length})',
                    style: labelS.copyWith(
                      color: y.yCream,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: widget.cards.length,
                itemBuilder: (context, i) {
                  final bg = labCardAccent(widget.cards[i]);
                  final isSelected =
                      widget.selectedCardIds.contains(widget.cards[i].id);
                  return GestureDetector(
                    onTap:
                        widget.onCardTap != null
                            ? () => widget.onCardTap!(widget.cards[i])
                            : null,
                    onLongPress:
                        widget.onCardLongPress != null
                            ? () => widget.onCardLongPress!(widget.cards[i])
                            : null,
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(
                          color:
                              isSelected ? widget.accentColor : inkBlack,
                          width:
                              isSelected ? borderWidthHeavy : borderWidth,
                        ),
                        boxShadow: isSelected ? null : shadowM,
                      ),
                      child: Text(
                        widget.cards[i].title,
                        style: bodyS.copyWith(
                          color:
                              bg.computeLuminance() > 0.5
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
}
