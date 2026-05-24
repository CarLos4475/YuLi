import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/repositories/kanban_card_repository.dart';
import '../../../domain/repositories/task_repository.dart';
import 'kanban_card_detail.dart';

class CalendarTab extends ConsumerStatefulWidget {
  final LabSpace space;
  const CalendarTab({super.key, required this.space});

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

  @override
  void initState() {
    super.initState();
    if (widget.space.startDate != null) {
      _currentWeekStart = _startOfWeek(widget.space.startDate!);
      _currentMonth = DateTime(
        widget.space.startDate!.year,
        widget.space.startDate!.month,
      );
    }
  }

  DateTime _startOfWeek(DateTime date) {
    final wd = date.weekday;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: wd - 1));
  }

  void _prev() {
    setState(() {
      if (_isWeekView) {
        _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
      } else {
        _currentMonth = DateTime(
          _currentMonth.year,
          _currentMonth.month - 1,
        );
      }
    });
  }

  void _next() {
    setState(() {
      if (_isWeekView) {
        _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
      } else {
        _currentMonth = DateTime(
          _currentMonth.year,
          _currentMonth.month + 1,
        );
      }
    });
  }

  void _onCardDropped(
    KanbanCard card,
    DateTime targetDate,
    KanbanCardRepository repo,
    TaskRepository taskRepo,
  ) async {
    final updated = card.copyWith(dueDate: targetDate);
    await repo.update(updated);
    if (card.originTaskId != null) {
      await taskRepo.updateDueDate(card.originTaskId!, targetDate);
    }
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

  void _showDayCardsDialog(BuildContext context, DateTime day, List<KanbanCard> dayCards) {
    if (dayCards.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(ctx),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        contentPadding: EdgeInsets.zero,
        content: Container(
          width: 360,
          decoration: BoxDecoration(
            border: Border.all(color: inkBlack, width: borderWidth),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: inkBlack, width: borderWidth),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${day.day}/${day.month}/${day.year}',
                      style: labelBold.copyWith(color: inkColor(context)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(Icons.close, size: 16, color: inkGray),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: dayCards.map((card) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () => _openCardDetail(context, card),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: inkBlack, width: borderWidth),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: 4,
                                color: _cardPriorityColor(card.priority),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        card.title,
                                        style: bodyM.copyWith(color: inkColor(context)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (card.dueDate != null) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: card.dueDate!.isBefore(DateTime.now())
                                                ? accentFight
                                                : folderPalette[3],
                                            border: Border.all(color: inkBlack, width: borderWidth),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: inkBlack,
                                                offset: shadowOffset,
                                                blurRadius: shadowBlurRadius,
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            _dialogFormatDate(card.dueDate!),
                                            style: labelBold.copyWith(
                                              color: paperLight,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dialogFormatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Color _cardPriorityColor(CardPriority p) => switch (p) {
        CardPriority.high => accentError,
        CardPriority.medium => const Color(0xFFF5A623),
        CardPriority.low => accentSuccess,
        CardPriority.none => inkGray,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cardsAsync = ref.watch(kanbanCardsBySpaceProvider(widget.space.id));
    final spacesAsync = ref.watch(activeLabSpacesProvider);
    final repo = ref.read(kanbanCardRepositoryProvider);
    final taskRepo = ref.read(taskRepositoryProvider);
    final ink = inkColor(context);

    final reactiveSpace = spacesAsync.valueOrNull?.firstWhere(
          (s) => s.id == widget.space.id,
          orElse: () => widget.space,
        ) ??
        widget.space;
    if (reactiveSpace.startDate == null) {
      return _NoDatesMessage(ink: ink, accentColor: reactiveSpace.accentColor);
    }

    return cardsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (cards) {
        final withDate = cards.where((c) => c.dueDate != null).toList();
        final noDate = cards.where((c) => c.dueDate == null).toList();

        return Column(
          children: [
            _buildHeader(ink),
            Expanded(
              child: _isWeekView
                  ? _WeekView(
                      weekStart: _currentWeekStart,
                      cards: withDate,
                      ink: ink,
                      onCardDropped: (card, date) =>
                          _onCardDropped(card, date, repo, taskRepo),
                      onCardTap: (card) => _openCardDetail(context, card),
                    )
                  : _MonthView(
                      month: _currentMonth,
                      cards: withDate,
                      ink: ink,
                      onDayTap: (day, dayCards) => _showDayCardsDialog(context, day, dayCards),
                      onCardDropped: (card, date) =>
                          _onCardDropped(card, date, repo, taskRepo),
                      onCardTap: (card) => _openCardDetail(context, card),
                    ),
            ),
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
  }

  Widget _buildHeader(Color ink) {
    final dateText = _isWeekView
        ? '${_currentWeekStart.day}/${_currentWeekStart.month} – ${_currentWeekStart.add(const Duration(days: 6)).day}/${_currentWeekStart.add(const Duration(days: 6)).month}'
        : '${_monthName(_currentMonth.month)} ${_currentMonth.year}';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ink, width: borderWidth)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
        children: [
          GestureDetector(
            onTap: _prev,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.space.accentColor,
                border: Border.all(color: inkBlack, width: borderWidth),
                boxShadow: shadowM,
              ),
              child: Icon(Icons.chevron_left, size: 18,
                color: widget.space.accentColor.computeLuminance() > 0.5
                    ? inkBlack
                    : paperColor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dateText.toUpperCase(),
              textAlign: TextAlign.center,
              style: labelS.copyWith(color: ink, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _next,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.space.accentColor,
                border: Border.all(color: inkBlack, width: borderWidth),
                boxShadow: shadowM,
              ),
              child: Icon(Icons.chevron_right, size: 18,
                color: widget.space.accentColor.computeLuminance() > 0.5
                    ? inkBlack
                    : paperColor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
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
          ),
        ],
      ),
    );
  }

  String _monthName(int m) => [
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? accentColor : Colors.transparent,
          border: Border.all(color: inkBlack, width: borderWidth),
          boxShadow: isActive ? shadowM : null,
        ),
        child: Text(
          label,
          style: labelXS.copyWith(
            color: isActive
                ? (accentColor.computeLuminance() > 0.5
                    ? inkBlack
                    : paperColor(context))
                : ink,
            fontWeight: FontWeight.w600,
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

  const _WeekView({
    required this.weekStart,
    required this.cards,
    required this.ink,
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
    final days = List.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: days.map((day) {
        final dayCards = _cardsForDay(day);
        final isToday = _isToday(day);

        return Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: ink.withAlpha(40),
                  width: borderWidth,
                ),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isToday ? ink.withAlpha(20) : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: ink.withAlpha(40),
                        width: borderWidth,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _dayLabel(day.weekday),
                        style: labelXS.copyWith(color: inkGray),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: labelM.copyWith(
                          color: isToday ? accentError : ink,
                          fontWeight: FontWeight.w700,
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
                        color: candidateData.isNotEmpty
                            ? ink.withAlpha(20)
                            : Colors.transparent,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(4),
                          itemCount: dayCards.length,
                          itemBuilder: (context, i) {
                            return _DraggableCard(
                              card: dayCards[i],
                              ink: ink,
                              onTap: () => onCardTap(dayCards[i]),
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
  final VoidCallback? onTap;
  const _DraggableCard({required this.card, required this.ink, this.onTap});

  Color _priorityColor() {
    if (card.originTaskDoneAt != null) return accentSuccess;
    return switch (card.priority) {
      CardPriority.high => accentError,
      CardPriority.medium => const Color(0xFFF5A623),
      CardPriority.low => accentSuccess,
      CardPriority.none => inkGray,
    };
  }

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
            card.title,
            style: bodyS.copyWith(color: ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _cardContent(context),
      ),
      child: _cardContent(context),
    );
  }

  Widget _cardContent(BuildContext context) {
    final cardWidget = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: ink.withAlpha(60), width: borderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _priorityColor(),
              shape: BoxShape.rectangle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              card.title,
              style: bodyXS.copyWith(color: ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return cardWidget;
    return GestureDetector(
      onTap: onTap,
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
  final void Function(DateTime, List<KanbanCard>) onDayTap;
  final void Function(KanbanCard, DateTime) onCardDropped;
  final void Function(KanbanCard) onCardTap;

  const _MonthView({
    required this.month,
    required this.cards,
    required this.ink,
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
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: ink.withAlpha(40), width: borderWidth),
            ),
          ),
          child: Row(
            children: ['L', 'M', 'X', 'J', 'V', 'S', 'D'].map((l) {
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  child: Text(l, style: labelXS.copyWith(color: inkGray)),
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
                        color: candidateData.isNotEmpty
                            ? ink.withAlpha(20)
                            : isToday
                                ? ink.withAlpha(15)
                                : Colors.transparent,
                        border: Border.all(
                          color: ink.withAlpha(40),
                          width: borderWidth,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        children: [
                          Text(
                            '${day.day}',
                            style: labelS.copyWith(
                              color: isToday ? accentError : ink,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          const Spacer(),
                          if (dayCards.isNotEmpty)
                            Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              alignment: WrapAlignment.center,
                              children: dayCards.take(4).map((c) {
                                return Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: _dotColor(c.priority),
                                    shape: BoxShape.rectangle,
                                  ),
                                );
                              }).toList(),
                            ),
                          if (dayCards.length > 4)
                            Text(
                              '+${dayCards.length - 4}',
                              style: labelXXS.copyWith(color: inkGray),
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

  Color _dotColor(CardPriority p) => switch (p) {
        CardPriority.high => accentError,
        CardPriority.medium => const Color(0xFFF5A623),
        CardPriority.low => accentSuccess,
        CardPriority.none => inkGray,
      };
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
                bottom: BorderSide(color: ink.withAlpha(40), width: borderWidth),
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
