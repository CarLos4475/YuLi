import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart' as y;
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/repositories/kanban_card_repository.dart';
import '../../../domain/repositories/task_repository.dart';
import 'kanban_card_detail.dart';
import 'kanban_card_tile.dart';
import 'lab_card_colors.dart';

class CalendarTab extends ConsumerStatefulWidget {
  final LabSpace space;
  final Set<int> selectedCardIds;
  final void Function(int) onToggleSelection;
  final bool selectionMode;

  const CalendarTab({
    super.key,
    required this.space,
    required this.selectedCardIds,
    required this.onToggleSelection,
    required this.selectionMode,
  });

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<CalendarTab>
    with AutomaticKeepAliveClientMixin {
  bool _isWeekView = true;
  DateTime _currentWeekStart = DateTime.now();
  DateTime _currentMonth = DateTime.now();

  @override
  bool get wantKeepAlive => true;

  void _prev() {
    setState(() {
      if (_isWeekView) {
        _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
      } else {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      }
    });
  }

  void _next() {
    setState(() {
      if (_isWeekView) {
        _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
      } else {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      }
    });
  }

  void _onCardDropped(
    KanbanCard card,
    DateTime targetDate,
    KanbanCardRepository repo,
    TaskRepository taskRepo,
  ) async {
    final oldDue = card.dueDate;
    final newDue =
        oldDue != null
            ? DateTime(
              targetDate.year,
              targetDate.month,
              targetDate.day,
              oldDue.hour,
              oldDue.minute,
              oldDue.second,
            )
            : targetDate;
    final updated = card.copyWith(dueDate: newDue);
    await repo.update(updated);
    if (card.originTaskId != null) {
      await taskRepo.updateDueDate(card.originTaskId!, newDue);
    }
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

  void _showDayCardsDialog(
    BuildContext context,
    DateTime day,
    List<KanbanCard> dayCards,
  ) {
    if (dayCards.isEmpty) return;
    final count = dayCards.length;
    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 40,
            ),
            child: Container(
              width: 360,
              decoration: BoxDecoration(
                color: y.yCream,
                border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
                boxShadow: [
                  BoxShadow(color: y.yBorderStrong, offset: const Offset(4, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: y.yInk,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '> ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year} · ${count.toString().padLeft(2, '0')} ${count == 1 ? 'TAREA' : 'TAREAS'}',
                            style: y.yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: y.yCream,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Icon(Icons.close, size: 16, color: y.yCream),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 2, color: y.yBorderStrong),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final card in dayCards)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: KanbanCardTile(
                                card: card,
                                accentColor: widget.space.accentColor,
                                selectionMode: widget.selectionMode,
                                isSelected: widget.selectedCardIds.contains(
                                  card.id,
                                ),
                                onTap: () {
                                  if (widget.selectionMode) {
                                    widget.onToggleSelection(card.id);
                                  } else {
                                    Navigator.pop(ctx);
                                    _openCardDetail(context, card);
                                  }
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
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cardsAsync = ref.watch(kanbanCardsBySpaceProvider(widget.space.id));
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final repo = ref.read(kanbanCardRepositoryProvider);
    final taskRepo = ref.read(taskRepositoryProvider);
    final ink = inkColor(context);

    final reactiveSpace =
        spacesAsync.valueOrNull?.firstWhere(
          (s) => s.id == widget.space.id,
          orElse: () => widget.space,
        ) ??
        widget.space;
    if (reactiveSpace.startDate == null) {
      return _NoDatesMessage(ink: ink, accentColor: reactiveSpace.accentColor);
    }

    return cardsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (cards) {
        final withDate = cards.where((c) => c.dueDate != null).toList();
        final noDate = cards.where((c) => c.dueDate == null).toList();

        return Column(
          children: [
            _buildHeader(ink),
            Expanded(
              child:
                  _isWeekView
                      ? _WeekView(
                        weekStart: _currentWeekStart,
                        cards: withDate,
                        ink: ink,
                        accentColor: widget.space.accentColor,
                        onCardDropped:
                            (card, date) =>
                                _onCardDropped(card, date, repo, taskRepo),
                        onCardTap:
                            (card) =>
                                widget.selectionMode
                                    ? widget.onToggleSelection(card.id)
                                    : _openCardDetail(context, card),
                        onCardLongPress:
                            (card) => widget.onToggleSelection(card.id),
                        selectedCardIds: widget.selectedCardIds,
                        selectionMode: widget.selectionMode,
                      )
                      : _MonthView(
                        month: _currentMonth,
                        cards: withDate,
                        ink: ink,
                        accentColor: widget.space.accentColor,
                        onDayTap:
                            (day, dayCards) =>
                                _showDayCardsDialog(context, day, dayCards),
                        onCardDropped:
                            (card, date) =>
                                _onCardDropped(card, date, repo, taskRepo),
                        onCardTap: (card) => _openCardDetail(context, card),
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
                onCardLongPress: (card) => widget.onToggleSelection(card.id),
                selectedCardIds: widget.selectedCardIds,
                selectionMode: widget.selectionMode,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(Color ink) {
    final dateText =
        _isWeekView
            ? '${_currentWeekStart.day}/${_currentWeekStart.month} – ${_currentWeekStart.add(const Duration(days: 6)).day}/${_currentWeekStart.add(const Duration(days: 6)).month}'
            : '${_monthName(_currentMonth.month)} ${_currentMonth.year}';

    return y.ViewHead(
      title: 'Calendario',
      titleColor: widget.space.accentColor,
      kicker: dateText.toUpperCase(),
      right: [
        y.NavBtn(glyph: '‹', onTap: _prev),
        const SizedBox(width: 4),
        y.NavBtn(glyph: '›', onTap: _next),
        const SizedBox(width: 8),
        _ViewToggleButton(
          label: 'SEMANA',
          isActive: _isWeekView,
          onTap: () => setState(() => _isWeekView = true),
          accentColor: widget.space.accentColor,
          ink: ink,
        ),
        _ViewToggleButton(
          label: 'MES',
          isActive: !_isWeekView,
          onTap: () => setState(() => _isWeekView = false),
          accentColor: widget.space.accentColor,
          ink: ink,
        ),
      ],
    );
  }

  String _monthName(int m) =>
      [
        'Enero',
        'Febrero',
        'Marzo',
        'Abril',
        'Mayo',
        'Junio',
        'Julio',
        'Agosto',
        'Septiembre',
        'Octubre',
        'Noviembre',
        'Diciembre',
      ][m - 1];
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
            Icon(Icons.date_range, size: 32, color: fg),
            const SizedBox(height: 12),
            Text(
              'ESTABLECER FECHAS DEL PROYECTO',
              style: labelM.copyWith(color: fg, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Configura la fecha de inicio para usar el calendario.',
              style: bodyS.copyWith(color: fg.withAlpha(180)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── View Toggle Button ──────────────────────────────────────────────────

class _ViewToggleButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color accentColor;
  final Color ink;

  const _ViewToggleButton({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.accentColor,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        decoration: BoxDecoration(
          color: isActive ? accentColor : y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Text(
          label,
          style: y.yMono(
            size: 12,
            weight: FontWeight.w700,
            tracking: 1.2,
            color: isActive ? y.yCream : y.yInk,
          ),
        ),
      ),
    );
  }
}

// ─── Week View ───────────────────────────────────────────────────────────

class _WeekView extends StatelessWidget {
  final DateTime weekStart;
  final List<KanbanCard> cards;
  final Color ink;
  final void Function(KanbanCard, DateTime) onCardDropped;
  final void Function(KanbanCard) onCardTap;
  final void Function(KanbanCard) onCardLongPress;
  final Set<int> selectedCardIds;
  final bool selectionMode;
  final Color accentColor;

  const _WeekView({
    required this.weekStart,
    required this.cards,
    required this.ink,
    required this.accentColor,
    required this.onCardDropped,
    required this.onCardTap,
    this.onCardLongPress = _noop,
    this.selectedCardIds = const {},
    this.selectionMode = false,
  });

  static void _noop(KanbanCard _) {}

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<KanbanCard> _cardsForDay(DateTime day) {
    final target = _dateOnly(day);
    return cards.where((c) {
      final cd = _dateOnly(c.dueDate!);
      return cd.year == target.year &&
          cd.month == target.month &&
          cd.day == target.day;
    }).toList();
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          days.map((day) {
            final dayCards = _cardsForDay(day);
            final isToday = _isToday(day);

            return Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: day.weekday >= 6 ? y.yCream2 : y.yCream,
                  border: Border(
                    right: BorderSide(color: y.yInk.withAlpha(45), width: 2),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      decoration: BoxDecoration(
                        color:
                            isToday
                                ? accentColor
                                : (day.weekday >= 6 ? y.yCream2 : y.yCream),
                        border: const Border(
                          bottom: BorderSide(color: y.yBorderStrong, width: 2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_dayLabel(day.weekday).toUpperCase()}${isToday ? ' . HOY' : ''}',
                            style: y.yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color:
                                  isToday
                                      ? y.yCream.withAlpha(230)
                                      : (day.weekday >= 6
                                          ? y.yMuted.withAlpha(140)
                                          : y.yMuted),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.day}',
                            style: y.ySans(
                              size: 30,
                              weight: FontWeight.w700,
                              letterSpacing: -1,
                              color: isToday ? y.yCream : y.yInk,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: DragTarget<KanbanCard>(
                        onWillAcceptWithDetails: (_) => true,
                        onAcceptWithDetails: (details) {
                          onCardDropped(details.data, day);
                        },
                        builder: (context, candidateData, rejectedData) {
                          return Container(
                            color:
                                candidateData.isNotEmpty
                                    ? ink.withAlpha(20)
                                    : Colors.transparent,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(4),
                              itemCount: dayCards.length,
                              itemBuilder: (context, i) {
                                return _DraggableCard(
                                  card: dayCards[i],
                                  ink: ink,
                                  accentColor: accentColor,
                                  onTap: () => onCardTap(dayCards[i]),
                                  onLongPress:
                                      () => onCardLongPress(dayCards[i]),
                                  isSelected: selectedCardIds.contains(
                                    dayCards[i].id,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  String _dayLabel(int weekday) {
    const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return labels[weekday - 1];
  }
}

// ─── Draggable Card ──────────────────────────────────────────────────────

class _DraggableCard extends StatelessWidget {
  final KanbanCard card;
  final Color ink;
  final Color accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;

  const _DraggableCard({
    required this.card,
    required this.ink,
    required this.accentColor,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<KanbanCard>(
      data: card,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: paperColor(context),
            border: Border.all(color: ink, width: borderWidth),
            boxShadow: shadowM,
          ),
          child: Text(
            y.cleanMention(card.title),
            style: bodyS.copyWith(color: ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _cardContent(context)),
      child: _cardContent(context),
    );
  }

  Widget _cardContent(BuildContext context) {
    final accent = labCardAccent(card);
    final done = card.isDone;
    final cardWidget = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      decoration: BoxDecoration(
        color: isSelected ? accentColor : (done ? y.yCream2 : y.yCream),
        border:
            !isSelected
                ? Border(
                  left: BorderSide(color: accent, width: 6),
                  top: BorderSide(color: y.yBorderStrong, width: 2),
                  bottom: BorderSide(color: y.yBorderStrong, width: 2),
                  right: BorderSide(color: y.yBorderStrong, width: 2),
                )
                : Border.all(color: y.yBorderStrong, width: y.yLineMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.dueDate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'TAREA . DUE',
                style: y.yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: isSelected ? y.yCream : y.yMuted,
                ),
              ),
            ),
          Text(
            y.cleanMention(card.title),
            style: y
                .ySans(
                  size: 12,
                  weight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isSelected ? y.yCream : (done ? y.yMuted : y.yInk),
                  height: 1.2,
                )
                .copyWith(decoration: done ? TextDecoration.lineThrough : null),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return cardWidget;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: cardWidget,
    );
  }
}

// ─── Month View ──────────────────────────────────────────────────────────

class _MonthView extends StatelessWidget {
  final DateTime month;
  final List<KanbanCard> cards;
  final Color ink;
  final Color accentColor;
  final void Function(DateTime, List<KanbanCard>) onDayTap;
  final void Function(KanbanCard, DateTime) onCardDropped;
  final void Function(KanbanCard) onCardTap;

  const _MonthView({
    required this.month,
    required this.cards,
    required this.ink,
    required this.accentColor,
    required this.onDayTap,
    required this.onCardDropped,
    required this.onCardTap,
  });

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<KanbanCard> _cardsForDay(DateTime day) {
    final target = _dateOnly(day);
    return cards.where((c) {
      final cd = _dateOnly(c.dueDate!);
      return cd.year == target.year &&
          cd.month == target.month &&
          cd.day == target.day;
    }).toList();
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = firstDay.weekday;

    final totalCells = (startWeekday - 1) + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final totalGrid = rows * 7;

    return Column(
      children: [
        // Day-of-week header
        Container(
          decoration: const BoxDecoration(
            color: y.yInk,
            border: Border(
              bottom: BorderSide(color: y.yBorderStrong, width: 2),
            ),
          ),
          child: Row(
            children:
                [
                  'LUN',
                  'MAR',
                  'MIE',
                  'JUE',
                  'VIE',
                  'SAB',
                  'DOM',
                ].asMap().entries.map((e) {
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border:
                            e.key < 6
                                ? Border(
                                  right: BorderSide(
                                    color: y.yCream.withAlpha(64),
                                    width: 1,
                                  ),
                                )
                                : null,
                      ),
                      child: Text(
                        e.value,
                        style: y.yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color:
                              e.key >= 5 ? y.yCream.withAlpha(178) : y.yCream,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        // Grid
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final aspectRatio =
                  (constraints.maxWidth / 7) / ((constraints.maxHeight) / rows);
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: totalGrid,
                itemBuilder: (context, index) {
                  final cellIndex = index - (startWeekday - 1);
                  if (cellIndex < 0 || cellIndex >= daysInMonth) {
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: ink.withAlpha(20),
                          width: borderWidth,
                        ),
                      ),
                    );
                  }

                  final day = DateTime(month.year, month.month, cellIndex + 1);
                  final dayCards = _cardsForDay(day);
                  final isToday = _isToday(day);
                  final dow = index % 7;
                  final isWeekend = dow >= 5;

                  return DragTarget<KanbanCard>(
                    onWillAcceptWithDetails: (_) => true,
                    onAcceptWithDetails: (details) {
                      onCardDropped(details.data, day);
                    },
                    builder: (context, candidateData, rejectedData) {
                      return GestureDetector(
                        onTap: () => onDayTap(day, dayCards),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                isToday
                                    ? y.yFlight
                                    : candidateData.isNotEmpty
                                    ? y.yInk.withAlpha(20)
                                    : (isWeekend ? y.yCream2 : y.yCream),
                            border: Border.all(
                              color: y.yInk.withAlpha(46),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: y.ySans(
                                      size: isToday ? 22 : 18,
                                      weight: FontWeight.w700,
                                      letterSpacing: -0.6,
                                      color: isToday ? y.yCream : y.yInk,
                                      height: 1.0,
                                    ),
                                  ),
                                  if (isToday)
                                    Text(
                                      'HOY',
                                      style: y.yMono(
                                        size: 9,
                                        weight: FontWeight.w700,
                                        tracking: 1.2,
                                        color: y.yCream.withAlpha(216),
                                      ),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              if (dayCards.isNotEmpty)
                                for (final c in dayCards.take(2))
                                  Container(
                                    margin: const EdgeInsets.only(top: 3),
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: labCardAccent(c),
                                      border: Border.all(
                                        color: isToday ? y.yCream : y.yBorderStrong,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                              if (dayCards.length > 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '+${dayCards.length - 2} más',
                                    style: y.yMono(
                                      size: 8,
                                      weight: FontWeight.w700,
                                      color: isToday ? y.yCream : y.yMuted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
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
        border: Border(top: BorderSide(color: ink, width: borderWidth)),
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
                final bg = labCardAccent(cards[i]);
                final isSelected = selectedCardIds.contains(cards[i].id);
                return GestureDetector(
                  onTap: onCardTap != null ? () => onCardTap!(cards[i]) : null,
                  onLongPress:
                      onCardLongPress != null
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cards[i].title,
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
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.check,
                              size: 10,
                              color: accentColor,
                            ),
                          ),
                      ],
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
