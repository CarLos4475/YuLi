import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/lab_tab_providers.dart';
import '../../widgets/yuli_design.dart' as y;
import '../../widgets/confetti_burst.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/kanban_card.dart';
import 'kanban_card_tile.dart';
import 'kanban_card_detail.dart';
import 'calendar_tab.dart';
import 'timeline_tab.dart';
import 'schedule_tab.dart';
import 'graph_tab.dart';
import 'lab_space_sources_sheet.dart';

class LabSpaceDetailScreen extends ConsumerStatefulWidget {
  final LabSpace space;

  const LabSpaceDetailScreen({super.key, required this.space});

  @override
  ConsumerState<LabSpaceDetailScreen> createState() =>
      _LabSpaceDetailScreenState();
}

class _LabSpaceDetailScreenState extends ConsumerState<LabSpaceDetailScreen> {
  int _tabIndex = 0;
  final Set<int> _selectedCardIds = {};
  bool _selectionActive = false;

  bool get _selectionMode => _selectionActive || _selectedCardIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingCard());
  }

  Future<void> _openPendingCard() async {
    final cardId = ref.read(pendingKanbanCardNavigationProvider);
    if (cardId == null) return;
    ref.read(pendingKanbanCardNavigationProvider.notifier).state = null;
    final card = await ref.read(kanbanCardRepositoryProvider).getById(cardId);
    if (card == null || card.labSpaceId != widget.space.id || !mounted) return;
    _showCardDetail(card);
  }

  void _showCardDetail(KanbanCard card) {
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

  void _toggleSelection(int cardId) {
    setState(() {
      _selectionActive = true;
      if (_selectedCardIds.contains(cardId)) {
        _selectedCardIds.remove(cardId);
      } else {
        _selectedCardIds.add(cardId);
      }
    });
  }

  void _clearSelection() => setState(() {
    _selectedCardIds.clear();
    _selectionActive = false;
  });

  Future<void> _deleteSelected() async {
    if (_selectedCardIds.isEmpty) return;
    // Capture before any async gap (app-level messenger → survives rebuilds).
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: paperColor(context),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Eliminar tarjetas',
              style: displayM.copyWith(color: inkColor(context)),
            ),
            content: Text(
              'Se eliminarán ${_selectedCardIds.length} tarjeta(s). Esta acción no se puede deshacer.',
              style: bodyM.copyWith(color: inkColor(context)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancelar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      final repo = ref.read(kanbanCardRepositoryProvider);
      final ids = _selectedCardIds.toList();
      // Capture full rows before deleting so undo restores them faithfully.
      final deleted = <KanbanCard>[];
      for (final id in ids) {
        final card = await repo.getById(id);
        if (card != null) deleted.add(card);
      }
      await repo.deleteMultiple(ids);
      _clearSelection();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              deleted.length == 1
                  ? 'Tarjeta eliminada'
                  : '${deleted.length} tarjetas eliminadas',
              style: y.yBody(size: 14, color: y.yCream),
            ),
            action: SnackBarAction(
              label: 'DESHACER',
              textColor: y.yCream,
              onPressed: () async {
                for (final card in deleted) {
                  await repo.restore(card);
                }
              },
            ),
          ),
        );
    }
  }

  void _showAddTabSheet() {
    final tabsNotifier = ref.read(labTabsProvider(widget.space.id).notifier);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _AddTabSheet(
            available: tabsNotifier.available,
            onSelect: (tab) {
              tabsNotifier.addTab(tab);
              setState(
                () =>
                    _tabIndex =
                        ref.read(labTabsProvider(widget.space.id)).length - 1,
              );
              Navigator.pop(context);
            },
          ),
    );
  }

  Widget _buildTabContent() {
    final tabs = ref.watch(labTabsProvider(widget.space.id));
    if (tabs.isEmpty) return const SizedBox.shrink();
    switch (tabs[_tabIndex.clamp(0, tabs.length - 1)]) {
      case 'Kanban':
        final columnsAsync = ref.watch(kanbanColumnsProvider(widget.space.id));
        return columnsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data:
              (columns) => _KanbanBoard(
                space: widget.space,
                columns: columns,
                selectedCardIds: _selectedCardIds,
                onToggleSelection: _toggleSelection,
                selectionMode: _selectionMode,
              ),
        );
      case 'Calendario':
        return CalendarTab(
          space: widget.space,
          selectedCardIds: _selectedCardIds,
          onToggleSelection: _toggleSelection,
          selectionMode: _selectionMode,
        );
      case 'Timeline':
        return TimelineTab(
          space: widget.space,
          selectedCardIds: _selectedCardIds,
          onToggleSelection: _toggleSelection,
          selectionMode: _selectionMode,
        );
      case 'Horario':
        return ScheduleTab(space: widget.space);
      case 'Grafo':
        return GraphTab(
          space: widget.space,
          onOpenCard: (cardId) async {
            final card =
                await ref.read(kanbanCardRepositoryProvider).getById(cardId);
            if (card != null && mounted) _showCardDetail(card);
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(labTabsProvider(widget.space.id));

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            _KanbanHeader(
              space: widget.space,
              selectionMode: _selectionMode,
              onToggleSelectionMode:
                  _selectionMode
                      ? _clearSelection
                      : () => setState(() => _selectionActive = true),
            ),
            Container(
              decoration: const BoxDecoration(
                color: y.yCream,
                border: Border(
                  bottom: BorderSide(color: y.yBorderStrong, width: 2),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  if (_selectionMode)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _clearSelection,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: const Icon(
                          YuLiIcons.close,
                          size: 16,
                          color: y.yMuted,
                        ),
                      ),
                    ),
                  ...tabs.asMap().entries.map(
                    (e) => _TabButton(
                      label: e.value,
                      isActive: _tabIndex == e.key,
                      onTap:
                          _selectionMode
                              ? null
                              : () => setState(() => _tabIndex = e.key),
                      onClose:
                          (e.value == 'Kanban' || e.value == 'Grafo')
                              ? null
                              : () {
                                final notifier = ref.read(
                                  labTabsProvider(widget.space.id).notifier,
                                );
                                final wasActive = _tabIndex == e.key;
                                notifier.removeTab(e.value);
                                if (wasActive) {
                                  setState(() => _tabIndex = 0);
                                } else if (e.key < _tabIndex) {
                                  setState(() => _tabIndex--);
                                }
                              },
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _selectionMode ? null : _showAddTabSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 20,
                          color: y.yMuted,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildTabContent()),
            if (_selectedCardIds.isNotEmpty)
              _SelectionBar(
                count: _selectedCardIds.length,
                onDelete: _deleteSelected,
                onCancel: _clearSelection,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTabSheet extends StatelessWidget {
  final List<String> available;
  final void Function(String) onSelect;

  const _AddTabSheet({required this.available, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: y.yBorderStrong, width: borderWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Agregar vista',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
            if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  'No hay más vistas disponibles.',
                  style: bodyS.copyWith(color: inkGray),
                ),
              )
            else
              ...available.map(
                (tab) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(tab),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: Row(
                      children: [
                        Container(width: 10, height: 10, color: accentLab),
                        const SizedBox(width: 12),
                        Text(
                          tab,
                          style: bodyM.copyWith(
                            color: inkColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final bool fill;
  final VoidCallback onTap;

  const _HeaderIcon({
    required this.icon,
    required this.bg,
    this.fg = y.yCream,
    this.fill = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ? bg : y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Icon(icon, size: 17, color: fg),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const _TabButton({
    required this.label,
    required this.isActive,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? y.yBorderStrong : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        transform: Matrix4.translationValues(0, 2, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: y.ySans(
                size: 16,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: isActive ? y.yInk : y.yMuted,
                height: 1.0,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                                YuLiIcons.close,
                    size: 12,
                    color: isActive ? y.yInk : y.yMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KanbanHeader extends ConsumerWidget {
  final LabSpace space;
  final bool selectionMode;
  final void Function()? onToggleSelectionMode;

  const _KanbanHeader({
    required this.space,
    this.selectionMode = false,
    this.onToggleSelectionMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: y.yCream,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: y.yCream,
                border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
              ),
              child: const Icon(YuLiIcons.arrowLeft, color: y.yInk, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        space.name,
                        style: y.ySans(
                          size: 32,
                          weight: FontWeight.w700,
                          letterSpacing: -1.2,
                          color: space.accentColor,
                          height: 0.95,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (space.startDate != null || space.dueDate != null) ...[
                  const SizedBox(height: 6),
                  y.YBadge(
                    label: _formatDateRange(space.startDate, space.dueDate),
                    bg: space.accentColor,
                    fg: y.yCream,
                    fontSize: 10,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeaderIcon(
            icon: YuLiIcons.link,
            bg: space.accentColor,
            onTap: () => showSpaceSourcesSheet(context, space),
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            icon: YuLiIcons.calendar,
            bg: space.accentColor,
            onTap: () => _showDateEditor(context, ref),
          ),
          if (onToggleSelectionMode != null) ...[
            const SizedBox(width: 6),
            _HeaderIcon(
              icon: YuLiIcons.listChecks,
              bg: selectionMode ? y.yFight : space.accentColor,
              fg: y.yCream,
              fill: true,
              onTap: onToggleSelectionMode!,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start != null && end != null) {
      return '${_formatDate(start)} – ${_formatDate(end)}';
    } else if (start != null) {
      return 'INICIO: ${_formatDate(start)}';
    } else if (end != null) {
      return 'FIN: ${_formatDate(end)}';
    }
    return '';
  }

  void _showDateEditor(BuildContext context, WidgetRef ref) {
    final ink = inkColor(context);
    DateTime? tempStart = space.startDate;
    DateTime? tempEnd = space.dueDate;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                contentPadding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                content: Container(
                  width: 320,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: y.yBorderStrong,
                      width: borderWidth,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: y.yBorderStrong,
                              width: borderWidth,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'FECHAS DEL PROYECTO',
                                style: labelBold.copyWith(color: ink),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Icon(
                    YuLiIcons.close,
                                size: 18,
                                color: inkGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DateRow(
                              label: 'INICIO',
                              date: tempStart,
                              ink: ink,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: tempStart ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        dialogTheme: const DialogThemeData(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.zero,
                                          ),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setDialogState(() => tempStart = picked);
                                }
                              },
                              onClear:
                                  () => setDialogState(() => tempStart = null),
                            ),
                            const SizedBox(height: 12),
                            _DateRow(
                              label: 'FIN',
                              date: tempEnd,
                              ink: ink,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: tempEnd ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        dialogTheme: const DialogThemeData(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.zero,
                                          ),
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setDialogState(() => tempEnd = picked);
                                }
                              },
                              onClear:
                                  () => setDialogState(() => tempEnd = null),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: y.yBorderStrong,
                              width: borderWidth,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: y.yBorderStrong,
                                    width: borderWidth,
                                  ),
                                ),
                                child: Text(
                                  'CANCELAR',
                                  style: labelBold.copyWith(
                                    color: inkGray,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                await ref
                                    .read(labSpaceRepositoryProvider)
                                    .update(
                                      space.copyWith(
                                        startDate: tempStart,
                                        clearStartDate: tempStart == null,
                                        dueDate: tempEnd,
                                        clearDueDate: tempEnd == null,
                                      ),
                                    );
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: space.accentColor,
                                  border: Border.all(
                                    color: space.accentColor,
                                    width: borderWidth,
                                  ),
                                  boxShadow: shadowM,
                                ),
                                child: Text(
                                  'GUARDAR',
                                  style: labelBold.copyWith(
                                    color: paperLight,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final DateTime? date;
  final Color ink;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateRow({
    required this.label,
    required this.date,
    required this.ink,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: labelBold.copyWith(color: ink, fontSize: 12),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: y.yBorderStrong, width: borderWidth),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      date != null
                          ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}'
                          : 'SELECCIONAR...',
                      style: bodyS.copyWith(
                        color: date != null ? ink : inkGray,
                      ),
                    ),
                  ),
                  if (date != null)
                    GestureDetector(
                      onTap: onClear,
                      child: Icon(YuLiIcons.close, size: 14, color: inkGray),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KanbanBoard extends ConsumerStatefulWidget {
  final LabSpace space;
  final List<KanbanColumn> columns;
  final Set<int> selectedCardIds;
  final void Function(int) onToggleSelection;
  final bool selectionMode;

  const _KanbanBoard({
    required this.space,
    required this.columns,
    required this.selectedCardIds,
    required this.onToggleSelection,
    required this.selectionMode,
  });

  @override
  ConsumerState<_KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends ConsumerState<_KanbanBoard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ValueNotifier<bool> _dragging = ValueNotifier(false);

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  AudioPlayer? _dicePlayer;
  bool _foreground = true;
  bool _rolling = false;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  int? _luckyCardId;
  final GlobalKey _luckyKey = GlobalKey();
  Timer? _luckyClear;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accelSub = userAccelerometerEventStream().listen((e) {
      if (!_foreground || _rolling) return;
      final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (magnitude < 16) return;
      final now = DateTime.now();
      if (now.difference(_lastShake) < const Duration(milliseconds: 1200)) {
        return;
      }
      _lastShake = now;
      _rollDice();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _luckyClear?.cancel();
    _shake.dispose();
    _dicePlayer?.dispose();
    _dragging.dispose();
    super.dispose();
  }

  void _rollDice() async {
    if (_rolling) return;
    final eligibleColumns =
        widget.columns
            .where((c) => !c.isTerminal && !c.isExpired)
            .map((c) => c.id)
            .toSet();
    final allCards =
        ref.read(kanbanCardsBySpaceProvider(widget.space.id)).valueOrNull ?? [];
    final pool =
        allCards
            .where((c) => eligibleColumns.contains(c.columnId) && !c.isDone)
            .toList();
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              'Nada para sortear',
              style: y.yBody(size: 14, color: y.yCream),
            ),
          ),
        );
      return;
    }

    setState(() {
      _rolling = true;
      _luckyCardId = null;
    });
    _luckyClear?.cancel();
    HapticFeedback.mediumImpact();
    (_dicePlayer ??= AudioPlayer()).play(AssetSource('sounds/dice.wav'));
    _shake.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final picked = pool[Random().nextInt(pool.length)];
    setState(() {
      _rolling = false;
      _luckyCardId = picked.id;
    });
    HapticFeedback.heavyImpact();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _luckyKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.5,
          curve: Curves.easeOut,
        );
      }
    });

    _luckyClear = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _luckyCardId = null);
    });
  }

  void _deleteCard(KanbanCard card) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(kanbanCardRepositoryProvider);
    await repo.delete(card.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            'Tarjeta eliminada',
            style: y.yBody(size: 14, color: y.yCream),
          ),
          action: SnackBarAction(
            label: 'DESHACER',
            textColor: y.yCream,
            onPressed: () => repo.restore(card),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final space = widget.space;
    final columns = widget.columns;
    final allCards =
        ref.watch(kanbanCardsBySpaceProvider(space.id)).valueOrNull ?? [];
    return Column(
      children: [
        y.ViewHead(
          title: 'Kanban',
          titleColor: space.accentColor,
          kicker: '${allCards.length} tareas . ${columns.length} columnas',
          right: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _rolling ? null : _rollDice,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: y.yCream,
                  border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
                ),
                child: Icon(YuLiIcons.dice5, size: 16, color: y.yInk),
              ),
            ),
            const SizedBox(width: 8),
            y.HeadBtn(
              label: '+ TAREA',
              primary: true,
              color: space.accentColor,
              onTap: () => _showQuickAdd(context, ref),
            ),
          ],
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final v = _shake.value;
              final dx = v == 0 ? 0.0 : sin(v * pi * 9) * 11 * (1 - v);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Stack(
            children: [
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
                itemCount: columns.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  if (i < columns.length) {
                    return _KanbanColumn(
                      space: space,
                      column: columns[i],
                      selectedCardIds: widget.selectedCardIds,
                      onToggleSelection: widget.onToggleSelection,
                      selectionMode: widget.selectionMode,
                      onDragStart: () => _dragging.value = true,
                      onDragEnd: () => _dragging.value = false,
                      luckyCardId: _luckyCardId,
                      luckyKey: _luckyKey,
                    );
                  }
                  return _AddColumnButton(spaceId: space.id);
                },
              ),
              // Tablet: show overflow indicator when more columns exist
              if (columns.length > 3)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            paperColor(context).withAlpha(0),
                            paperColor(context),
                          ],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'más →',
                            style: labelBold.copyWith(color: inkGray),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Drag-to-delete: physical trash bin, only while dragging a card
              Positioned(
                right: 24,
                bottom: 24,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _dragging,
                  builder:
                      (_, dragging, _) => _TrashBin(
                        visible: dragging,
                        onDelete: _deleteCard,
                      ),
                ),
              ),
            ],
            ),
          ),
        ),
      ],
    );
  }

  void _showQuickAdd(BuildContext context, WidgetRef ref) {
    final columns = widget.columns;
    final space = widget.space;
    if (columns.isEmpty) return;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: y.yCream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: y.yBorderStrong, width: y.yLineMid),
            ),
            title: Text(
              'Nueva tarea',
              style: y.ySans(size: 18, weight: FontWeight.w700, color: y.yInk),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Titulo',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineThin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineMid,
                  ),
                ),
              ),
              onSubmitted: (t) async {
                if (t.trim().isNotEmpty) {
                  await ref
                      .read(kanbanCardRepositoryProvider)
                      .create(
                        labSpaceId: space.id,
                        columnId: columns.first.id,
                        title: t.trim(),
                      );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () async {
                  final t = ctrl.text.trim();
                  if (t.isNotEmpty) {
                    await ref
                        .read(kanbanCardRepositoryProvider)
                        .create(
                          labSpaceId: space.id,
                          columnId: columns.first.id,
                          title: t,
                        );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Crear'),
              ),
            ],
          ),
    );
  }
}

class _KanbanColumn extends ConsumerWidget {
  final LabSpace space;
  final KanbanColumn column;
  final Set<int> selectedCardIds;
  final void Function(int) onToggleSelection;
  final bool selectionMode;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final int? luckyCardId;
  final GlobalKey luckyKey;

  const _KanbanColumn({
    required this.space,
    required this.column,
    required this.selectedCardIds,
    required this.onToggleSelection,
    required this.selectionMode,
    required this.onDragStart,
    required this.onDragEnd,
    required this.luckyCardId,
    required this.luckyKey,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final isProtected =
        column.isTerminal || column.isExpired || column.isInProgress;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: paperColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: y.yBorderStrong, width: borderWidth),
            ),
            title: Text(
              'Eliminar columna',
              style: displayM.copyWith(color: inkColor(context)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se eliminará la columna y todas sus cards.',
                  style: bodyM.copyWith(color: inkColor(context)),
                ),
                if (isProtected) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${column.name} es una columna automática del sistema. '
                    'Si la eliminas, las cards no se moverán automáticamente.',
                    style: bodyS.copyWith(color: accentFight),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancelar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Eliminar',
                  style: labelBold.copyWith(color: accentFight),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(labSpaceRepositoryProvider).deleteColumn(column.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(kanbanCardsByColumnProvider(column.id));
    final cards = cardsAsync.valueOrNull ?? [];

    final colColor = _columnColor(column, space.accentColor);
    return SizedBox(
      width: 268,
      child: Container(
        decoration: BoxDecoration(
          color: y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color stripe
            Container(height: 6, color: colColor),
            Container(height: 2, color: y.yBorderStrong),
            // Column header
            _ColumnHead(
              column: column,
              count: cards.length,
              onMenu: () => _showManagePopover(context, ref, colColor),
            ),
            Expanded(
              child: DragTarget<_DragData>(
                onAcceptWithDetails: (details) async {
                  if (details.data.card.columnId != column.id) {
                    await _handleDrop(
                      context,
                      ref,
                      details.data,
                      cards,
                      cards.length,
                      details.offset,
                    );
                  }
                },
                builder: (context, candidateData, rejectedData) {
                  final hasCrossCandidate = candidateData.any(
                    (d) => d?.card.columnId != column.id,
                  );
                  return Container(
                    color:
                        hasCrossCandidate
                            ? space.accentColor.withAlpha(20)
                            : Colors.transparent,
                    child:
                        cards.isEmpty
                            ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: y.yMuted,
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 20,
                                ),
                                child: Center(
                                  child: Text(
                                    'vacio',
                                    style: y.yMono(
                                      size: 10,
                                      tracking: 1.2,
                                      color: y.yMuted,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            : ListView(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                              children: [
                                for (int i = 0; i < cards.length; i++) ...[
                                  _CardDropZone(
                                    column: column,
                                    accentColor: space.accentColor,
                                    position: i,
                                    onDrop:
                                        (data, at) => _handleDrop(
                                          context,
                                          ref,
                                          data,
                                          cards,
                                          i,
                                          at,
                                        ),
                                  ),
                                  if (selectionMode)
                                    GestureDetector(
                                      key: ValueKey('sel_${cards[i].id}'),
                                      onTap:
                                          () => onToggleSelection(cards[i].id),
                                      child: KanbanCardTile(
                                        card: cards[i],
                                        accentColor: space.accentColor,
                                        onTap:
                                            () =>
                                                onToggleSelection(cards[i].id),
                                        isSelected: selectedCardIds.contains(
                                          cards[i].id,
                                        ),
                                        selectionMode: true,
                                        inExpiredColumn: column.isExpired,
                                      ),
                                    )
                                  else
                                    LongPressDraggable<_DragData>(
                                      key: ValueKey(cards[i].id),
                                      data: _DragData(cards[i]),
                                      onDragStarted: onDragStart,
                                      onDragEnd: (_) => onDragEnd(),
                                      feedback: Material(
                                        elevation: 4,
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.zero,
                                        child: SizedBox(
                                          width: 260,
                                          child: KanbanCardTile(
                                            card: cards[i],
                                            accentColor: space.accentColor,
                                            onTap: () {},
                                            inExpiredColumn: column.isExpired,
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.3,
                                        child: KanbanCardTile(
                                          card: cards[i],
                                          accentColor: space.accentColor,
                                          onTap:
                                              () =>
                                                  _openCard(context, cards[i]),
                                          inExpiredColumn: column.isExpired,
                                        ),
                                      ),
                                      child: _LuckyWrap(
                                        isLucky: cards[i].id == luckyCardId,
                                        luckyKey: luckyKey,
                                        accent: space.accentColor,
                                        child: KanbanCardTile(
                                          card: cards[i],
                                          accentColor: space.accentColor,
                                          onTap:
                                              () => _openCard(context, cards[i]),
                                          inExpiredColumn: column.isExpired,
                                        ),
                                      ),
                                    ),
                                ],
                                _CardDropZone(
                                  column: column,
                                  accentColor: space.accentColor,
                                  position: cards.length,
                                  onDrop:
                                      (data, at) => _handleDrop(
                                        context,
                                        ref,
                                        data,
                                        cards,
                                        cards.length,
                                        at,
                                      ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                  );
                },
              ),
            ),
            Container(height: 1, color: y.yBorderStrong),
            _AddCardButton(
              spaceId: space.id,
              columnId: column.id,
              accentColor: space.accentColor,
            ),
          ],
        ),
      ),
    );
  }

  Color _columnColor(KanbanColumn col, Color spaceAccent) {
    if (col.isExpired) return y.yFight;
    if (col.isTerminal) return y.yLab;
    if (col.isInProgress) return y.yAmber;
    if (col.name == 'Backlog') return y.yMuted;
    return spaceAccent;
  }

  void _showManagePopover(BuildContext context, WidgetRef ref, Color colColor) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder:
          (ctx) => _ColumnManagePopover(
            column: column,
            spaceId: space.id,
            currentColor: colColor,
            onRename: () {
              Navigator.pop(ctx);
              _showRenameDialog(context, ref);
            },
            onColorChange: (c) async {
              await ref
                  .read(labSpaceRepositoryProvider)
                  .updateColumn(column.copyWith());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            onMoveLeft: () async {
              Navigator.pop(ctx);
              await _moveColumn(ref, -1);
            },
            onMoveRight: () async {
              Navigator.pop(ctx);
              await _moveColumn(ref, 1);
            },
            onToggleDone: () async {
              final repo = ref.read(labSpaceRepositoryProvider);
              final willBeTerminal = !column.isTerminal;
              if (willBeTerminal) {
                final all = await repo.getColumns(space.id);
                for (final c in all) {
                  if (c.id != column.id && c.isTerminal) {
                    await repo.updateColumn(c.copyWith(isTerminal: false));
                  }
                }
              }
              await repo.updateColumn(
                column.copyWith(
                  isTerminal: willBeTerminal,
                  isExpired: false,
                  isInProgress: false,
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            onToggleExpired: () async {
              final repo = ref.read(labSpaceRepositoryProvider);
              final willBeExpired = !column.isExpired;
              if (willBeExpired) {
                final all = await repo.getColumns(space.id);
                for (final c in all) {
                  if (c.id != column.id && c.isExpired) {
                    await repo.updateColumn(c.copyWith(isExpired: false));
                  }
                }
              }
              await repo.updateColumn(
                column.copyWith(
                  isExpired: willBeExpired,
                  isTerminal: false,
                  isInProgress: false,
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            onToggleInProgress: () async {
              final repo = ref.read(labSpaceRepositoryProvider);
              final willBeInProgress = !column.isInProgress;
              if (willBeInProgress) {
                final all = await repo.getColumns(space.id);
                for (final c in all) {
                  if (c.id != column.id && c.isInProgress) {
                    await repo.updateColumn(c.copyWith(isInProgress: false));
                  }
                }
              }
              await repo.updateColumn(
                column.copyWith(
                  isInProgress: willBeInProgress,
                  isTerminal: false,
                  isExpired: false,
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            onDelete: () {
              Navigator.pop(ctx);
              _confirmDelete(context, ref);
            },
          ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: column.name);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: y.yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Renombrar columna',
              style: y.ySans(size: 18, weight: FontWeight.w700),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Nombre'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    if (newName != null && newName.isNotEmpty && newName != column.name) {
      await ref
          .read(labSpaceRepositoryProvider)
          .updateColumn(column.copyWith(name: newName));
    }
  }

  Future<void> _moveColumn(WidgetRef ref, int dir) async {
    final all = await ref.read(labSpaceRepositoryProvider).getColumns(space.id);
    final ids = all.map((c) => c.id).toList();
    final idx = ids.indexOf(column.id);
    final target = idx + dir;
    if (idx < 0 || target < 0 || target >= ids.length) return;
    ids.removeAt(idx);
    ids.insert(target, column.id);
    await ref.read(labSpaceRepositoryProvider).reorderColumns(space.id, ids);
  }

  Future<void> _handleDrop(
    BuildContext ctx,
    WidgetRef ref,
    _DragData data,
    List<KanbanCard> cards,
    int position,
    Offset at,
  ) async {
    final celebrate = column.isTerminal && data.card.columnId != column.id;
    if (data.card.columnId == column.id) {
      _reorderInColumn(ref, cards, data.card.id, position);
    } else {
      await _moveCardToColumn(ref, data, position);
    }
    if (celebrate && ctx.mounted) {
      burstConfetti(
        ctx,
        at + const Offset(130, 18),
        accent: space.accentColor,
      );
    }
  }

  Future<void> _moveCardToColumn(
    WidgetRef ref,
    _DragData data,
    int position,
  ) async {
    await ref
        .read(kanbanCardRepositoryProvider)
        .moveToColumn(data.card.id, column.id, position);
  }

  Future<void> _reorderInColumn(
    WidgetRef ref,
    List<KanbanCard> cards,
    int cardId,
    int newPosition,
  ) async {
    final ids = cards.map((c) => c.id).toList();
    final oldIndex = ids.indexOf(cardId);
    if (oldIndex == -1 || oldIndex == newPosition) return;
    ids.removeAt(oldIndex);
    if (newPosition > oldIndex) newPosition--;
    ids.insert(newPosition, cardId);
    await ref
        .read(kanbanCardRepositoryProvider)
        .reorderInColumn(column.id, ids);
  }

  void _openCard(BuildContext context, KanbanCard card) {
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
                  space: space,
                  scrollController: sc,
                ),
          ),
    );
  }
}

class _CardDropZone extends StatelessWidget {
  final KanbanColumn column;
  final Color accentColor;
  final int position;
  final void Function(_DragData, Offset) onDrop;

  const _CardDropZone({
    required this.column,
    required this.accentColor,
    required this.position,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragData>(
      onAcceptWithDetails: (details) => onDrop(details.data, details.offset),
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return Container(
          height: isActive ? 6 : 2,
          margin: EdgeInsets.only(bottom: isActive ? 6 : 0),
          decoration: BoxDecoration(
            color: isActive ? accentColor.withAlpha(40) : Colors.transparent,
            border:
                isActive
                    ? Border(
                      top: BorderSide(color: accentColor, width: 2),
                      bottom: BorderSide(color: accentColor, width: 2),
                    )
                    : null,
          ),
        );
      },
    );
  }
}

class _AddColumnButton extends ConsumerWidget {
  final int spaceId;

  const _AddColumnButton({required this.spaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 180,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showAddColumn(context, ref),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: y.yMuted,
              width: 3,
              style: BorderStyle.solid,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: y.yCream,
                  border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
                ),
                child: const Text(
                  '+',
                  style: TextStyle(
                    fontSize: 28,
                    color: y.yInk,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Columna',
                style: y.ySans(
                  size: 14,
                  weight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: y.yInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'NOMBRE + COLOR',
                textAlign: TextAlign.center,
                style: y.yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.2,
                  color: y.yMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddColumn(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: paperColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: y.yBorderStrong, width: y.yLineMid),
            ),
            title: Text(
              'Nueva columna',
              style: displayM.copyWith(color: inkColor(context)),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: bodyL.copyWith(color: inkColor(context)),
              decoration: InputDecoration(
                hintText: 'Nombre',
                hintStyle: bodyL.copyWith(color: inkGray),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineThin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineMid,
                  ),
                ),
              ),
              onSubmitted: (name) async {
                if (name.trim().isNotEmpty) {
                  await ref
                      .read(labSpaceRepositoryProvider)
                      .createColumn(spaceId, name.trim());
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancelar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final name = ctrl.text.trim();
                  if (name.isNotEmpty) {
                    await ref
                        .read(labSpaceRepositoryProvider)
                        .createColumn(spaceId, name);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'Crear',
                  style: labelBold.copyWith(color: inkColor(context)),
                ),
              ),
            ],
          ),
    );
  }
}

class _AddCardButton extends ConsumerWidget {
  final int spaceId;
  final int columnId;
  final Color accentColor;

  const _AddCardButton({
    required this.spaceId,
    required this.columnId,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAddCard(context, ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Text(
              '+',
              style: TextStyle(fontSize: 14, color: y.yMuted, height: 1.0),
            ),
            const SizedBox(width: 8),
            Text(
              'AÑADIR TAREA',
              style: y.yMono(
                size: 11,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: y.yMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCard(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: paperColor(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: y.yBorderStrong, width: y.yLineMid),
            ),
            title: Text(
              'Nueva tarjeta',
              style: displayM.copyWith(color: inkColor(context)),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: bodyL.copyWith(color: inkColor(context)),
              decoration: InputDecoration(
                hintText: 'Título',
                hintStyle: bodyL.copyWith(color: inkGray),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineThin,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(
                    color: y.yBorderStrong,
                    width: y.yLineMid,
                  ),
                ),
              ),
              onSubmitted: (title) async {
                if (title.trim().isNotEmpty) {
                  await ref
                      .read(kanbanCardRepositoryProvider)
                      .create(
                        labSpaceId: spaceId,
                        columnId: columnId,
                        title: title.trim(),
                      );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancelar',
                  style: labelBold.copyWith(color: inkGray),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final title = ctrl.text.trim();
                  if (title.isNotEmpty) {
                    await ref
                        .read(kanbanCardRepositoryProvider)
                        .create(
                          labSpaceId: spaceId,
                          columnId: columnId,
                          title: title,
                        );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  'Crear',
                  style: labelBold.copyWith(color: inkColor(context)),
                ),
              ),
            ],
          ),
    );
  }
}

// Drag payload
class _DragData {
  final KanbanCard card;
  const _DragData(this.card);
}

/// Applies the dice-winner highlight to a single card. Only the lucky card
/// carries [luckyKey] (so Scrollable.ensureVisible can reach it); others pass
/// through untouched.
class _LuckyWrap extends StatelessWidget {
  final bool isLucky;
  final GlobalKey luckyKey;
  final Color accent;
  final Widget child;

  const _LuckyWrap({
    required this.isLucky,
    required this.luckyKey,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLucky) return child;
    return _DiceHighlight(key: luckyKey, accent: accent, child: child);
  }
}

/// The "you got picked" treatment: a one-shot bounce + a blinking accent halo.
class _DiceHighlight extends StatefulWidget {
  final Color accent;
  final Widget child;

  const _DiceHighlight({super.key, required this.accent, required this.child});

  @override
  State<_DiceHighlight> createState() => _DiceHighlightState();
}

class _DiceHighlightState extends State<_DiceHighlight>
    with TickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  )..repeat(reverse: true);

  late final AnimationController _jump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  )..forward();

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_jump);

  @override
  void dispose() {
    _blink.dispose();
    _jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_blink, _jump]),
      child: widget.child,
      builder: (context, child) {
        final t = _blink.value;
        return Transform.scale(
          scale: _scale.value,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Color.lerp(widget.accent.withAlpha(60), widget.accent, t)!,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withAlpha((140 * t).round()),
                  blurRadius: 0,
                  spreadRadius: 2 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Drag-to-delete target. Slides up from the corner only while a card is being
/// dragged; grows + flips color + haptics when a card hovers over it, and
/// "chomps" (heavy haptic) when one is dropped in.
class _TrashBin extends StatefulWidget {
  final bool visible;
  final void Function(KanbanCard) onDelete;

  const _TrashBin({required this.visible, required this.onDelete});

  @override
  State<_TrashBin> createState() => _TrashBinState();
}

class _TrashBinState extends State<_TrashBin> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: widget.visible ? Curves.easeOutBack : Curves.easeIn,
        offset: widget.visible ? Offset.zero : const Offset(0, 1.8),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: widget.visible ? 1 : 0,
          child: DragTarget<_DragData>(
            onMove: (_) {
              if (!_hovering) {
                setState(() => _hovering = true);
                HapticFeedback.mediumImpact();
              }
            },
            onLeave: (_) {
              if (_hovering) setState(() => _hovering = false);
            },
            onAcceptWithDetails: (details) {
              setState(() => _hovering = false);
              HapticFeedback.heavyImpact();
              widget.onDelete(details.data.card);
            },
            builder: (context, candidate, rejected) {
              final active = _hovering;
              return AnimatedScale(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                scale: active ? 1.3 : 1.0,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: active ? accentFight : y.yCream,
                    border: Border.all(
                      color: y.yBorderStrong,
                      width: active ? 3 : 2,
                    ),
                    boxShadow:
                        active
                            ? [
                              BoxShadow(
                                color: y.yBorderStrong,
                                offset: const Offset(4, 4),
                              ),
                            ]
                            : null,
                  ),
                  child: Icon(
                    YuLiIcons.trash,
                    size: 26,
                    color: active ? y.yCream : y.yInk,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: y.yBorderStrong, width: borderWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: inkGray, width: borderWidth),
                  ),
                  child: Text(
                    'Cancelar',
                    style: labelBold.copyWith(color: inkGray, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count seleccionada(s)',
                  style: labelBold.copyWith(color: ink),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accentFight,
                    border: Border.all(color: accentFight, width: borderWidth),
                    boxShadow: shadowM,
                  ),
                  child: Text(
                    'Eliminar',
                    style: labelBold.copyWith(color: paperLight, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColumnHead extends StatelessWidget {
  final KanbanColumn column;
  final int count;
  final VoidCallback onMenu;

  const _ColumnHead({
    required this.column,
    required this.count,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: y.yBorderStrong, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Flexible(
            child: Text(
              column.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: y.ySans(
                size: 16,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: y.yInk,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count.toString().padLeft(2, '0'),
            style: y.yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 0.5,
              color: y.yMuted,
            ),
          ),
          if (column.isTerminal) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
              decoration: BoxDecoration(
                color: y.yCream2,
                border: Border.all(color: y.yLab, width: 1.5),
              ),
              child: Text(
                'DONE',
                style: y.yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yLab,
                ),
              ),
            ),
          ],
          if (column.isExpired) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
              decoration: BoxDecoration(
                color: y.yCream2,
                border: Border.all(color: y.yFight, width: 1.5),
              ),
              child: Text(
                'EXPIRED',
                style: y.yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yFight,
                ),
              ),
            ),
          ],
          if (column.isInProgress) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
              decoration: BoxDecoration(
                color: y.yCream2,
                border: Border.all(color: y.yFlight, width: 1.5),
              ),
              child: Text(
                'INICIO',
                style: y.yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yFlight,
                ),
              ),
            ),
          ],
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMenu,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                '⋯',
                style: TextStyle(fontSize: 16, color: y.yMuted, height: 1.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnManagePopover extends StatelessWidget {
  final KanbanColumn column;
  final int spaceId;
  final Color currentColor;
  final VoidCallback onRename;
  final ValueChanged<Color> onColorChange;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleExpired;
  final VoidCallback onToggleInProgress;
  final VoidCallback onDelete;

  const _ColumnManagePopover({
    required this.column,
    required this.spaceId,
    required this.currentColor,
    required this.onRename,
    required this.onColorChange,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onToggleDone,
    required this.onToggleExpired,
    required this.onToggleInProgress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: y.yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
          boxShadow: [BoxShadow(color: y.yInk, offset: const Offset(4, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: y.yInk,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                '> COLUMNA · ${column.name.toUpperCase()}',
                style: y.yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: y.yCream,
                ),
              ),
            ),
            Container(height: 2, color: y.yBorderStrong),
            _PopRow(
              icon: YuLiIcons.pen,
              label: 'Renombrar',
              onTap: onRename,
            ),
            _PopRow(
              icon: YuLiIcons.chevronLeft,
              label: 'Mover a la izquierda',
              onTap: onMoveLeft,
            ),
            _PopRow(
              icon: YuLiIcons.chevronRight,
              label: 'Mover a la derecha',
              onTap: onMoveRight,
            ),
            _PopRow(
              icon:
                  column.isTerminal
                      ? YuLiIcons.squareCheck
                      : YuLiIcons.square,
              label: column.isTerminal ? 'Quitar DONE' : 'Marcar como DONE',
              onTap: onToggleDone,
            ),
            _PopRow(
              icon:
                  column.isExpired
                      ? YuLiIcons.triangleAlert
                      : YuLiIcons.triangleAlert,
              label:
                  column.isExpired ? 'Quitar EXPIRED' : 'Marcar como EXPIRED',
              onTap: onToggleExpired,
            ),
            _PopRow(
              icon:
                  column.isInProgress
                      ? YuLiIcons.circlePlay
                      : YuLiIcons.circlePlay,
              label:
                  column.isInProgress
                      ? 'Quitar EN PROCESO'
                      : 'Marcar como EN PROCESO',
              onTap: onToggleInProgress,
            ),
            Container(height: 2, color: y.yBorderSoft),
            _PopRow(
              icon: YuLiIcons.close,
              label: 'Eliminar columna',
              danger: true,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PopRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _PopRow({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: danger ? y.yFight : y.yMuted),
            const SizedBox(width: 10),
            Text(
              label,
              style: y.yBody(
                size: 13,
                weight: FontWeight.w500,
                color: danger ? y.yFight : y.yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
