import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/note_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/lab_tab_providers.dart';
import '../../widgets/app_column_header.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/note.dart';
import '../../screens/flight/note_cell_model.dart';
import 'kanban_card_tile.dart';
import 'kanban_card_detail.dart';
import 'calendar_tab.dart';
import 'timeline_tab.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Eliminar tarjetas',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text(
          'Se eliminarán ${_selectedCardIds.length} tarjeta(s). Esta acción no se puede deshacer.',
          style: bodyM.copyWith(color: inkColor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
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
      final repo = ref.read(kanbanCardRepositoryProvider);
      await repo.deleteMultiple(_selectedCardIds.toList());
      _clearSelection();
    }
  }

  void _showAddTabSheet() {
    final tabsNotifier = ref.read(labTabsProvider(widget.space.id).notifier);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddTabSheet(
        available: tabsNotifier.available,
        onSelect: (tab) {
          tabsNotifier.addTab(tab);
          setState(() => _tabIndex = tabsNotifier.state.length - 1);
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
          error: (_, __) => const SizedBox.shrink(),
          data: (columns) => _KanbanBoard(
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
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final tabs = ref.watch(labTabsProvider(widget.space.id));

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            _KanbanHeader(
              space: widget.space,
              selectionMode: _selectionMode,
              onToggleSelectionMode: _selectionMode
                  ? _clearSelection
                  : () => setState(() => _selectionActive = true),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ink, width: borderWidth),
                ),
              ),
              child: Row(
                children: [
                  if (_selectionMode)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _clearSelection,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Icon(Icons.clear, size: 16, color: inkGray),
                      ),
                    ),
                  ...tabs.asMap().entries.map((e) => Row(
                        children: [
                          if (e.key > 0)
                            Container(
                                width: 1,
                                height: 28,
                                color: ink.withAlpha(60)),
                          _TabButton(
                            label: e.value,
                            isActive: _tabIndex == e.key,
                            onTap: _selectionMode
                                ? null
                                : () =>
                                    setState(() => _tabIndex = e.key),
                            onClose: e.value == 'Kanban'
                                ? null
                                : () {
                                    final notifier = ref.read(
                                        labTabsProvider(widget.space.id)
                                            .notifier);
                                    final wasActive = _tabIndex == e.key;
                                    notifier.removeTab(e.value);
                                    if (wasActive) {
                                      setState(() => _tabIndex = 0);
                                    } else if (e.key < _tabIndex) {
                                      setState(() => _tabIndex--);
                                    }
                                  },
                          ),
                        ],
                      )),
                  Container(width: 1, height: 28, color: ink.withAlpha(60)),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _selectionMode ? null : _showAddTabSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Icon(Icons.add, size: 18, color: inkGray),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildTabContent(),
            ),
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
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
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
              child: Text('Agregar vista',
                  style: labelBold.copyWith(color: inkGray)),
            ),
            if (available.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text('No hay más vistas disponibles.',
                    style: bodyS.copyWith(color: inkGray)),
              )
            else
              ...available.map((tab) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(tab),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            color: accentLab,
                          ),
                          const SizedBox(width: 12),
                          Text(tab,
                              style: bodyM.copyWith(
                                  color: inkColor(context),
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 8),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: isActive
              ? const Border(
                  bottom: BorderSide(color: inkBlack, width: borderWidthHeavy),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: labelBold.copyWith(
                color: isActive ? inkColor(context) : inkGray,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isActive ? inkColor(context) : inkGray,
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
    final linkedFolderIdsAsync = ref.watch(linkedFolderIdsProvider(space.id));
    final linkedIds = linkedFolderIdsAsync.valueOrNull ?? [];
    final foldersAsync = ref.watch(activeFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    
    final linkedFolders = folders.where((f) => linkedIds.contains(f.id)).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child:
                  Icon(Icons.arrow_back, color: inkColor(context), size: 20),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.name,
                  style: displayL.copyWith(color: space.accentColor),
                ),
                if (linkedFolders.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: linkedFolders.map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: f.color,
                        border: Border.all(color: inkBlack, width: borderWidth),
                        boxShadow: shadowM,
                      ),
                      child: Text(
                        f.name,
                        style: labelBold.copyWith(
                          color: f.color.computeLuminance() > 0.5 ? inkBlack : paperLight,
                          fontSize: 10,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
                if (space.startDate != null || space.dueDate != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: space.accentColor,
                      border: Border.all(color: inkBlack, width: borderWidth),
                      boxShadow: shadowM,
                    ),
                    child: Text(
                      _formatDateRange(space.startDate, space.dueDate),
                      style: labelS.copyWith(
                        color: paperLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    'SIN FECHAS DE PROYECTO',
                    style: bodyS.copyWith(color: inkGray.withAlpha(128)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (linkedFolders.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showLinkedNotes(context),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentFlight,
                  border: Border.all(color: inkBlack, width: borderWidth),
                  boxShadow: shadowM,
                ),
                child: Icon(Icons.description_outlined, size: 16, color: paperLight),
              ),
            ),
          if (linkedFolders.isNotEmpty)
            const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showLinkFolders(context, ref),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accentLab,
                  border: Border.all(color: inkBlack, width: borderWidth),
                  boxShadow: shadowM,
                ),
                child: Icon(Icons.folder_outlined, size: 16, color: paperLight),
              ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDateEditor(context, ref),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: space.accentColor,
                border: Border.all(
                  color: inkBlack,
                  width: borderWidth,
                ),
                boxShadow: shadowM,
              ),
              child: Icon(
                Icons.calendar_today,
                size: 16,
                color: space.accentColor.computeLuminance() > 0.5
                    ? inkBlack
                    : paperColor(context),
              ),
            ),
          ),
          if (onToggleSelectionMode != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleSelectionMode,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selectionMode ? accentFight : Colors.transparent,
                  border: Border.all(
                    color: selectionMode ? accentFight : inkBlack,
                    width: borderWidth,
                  ),
                  boxShadow: selectionMode ? shadowM : null,
                ),
                child: Icon(
                  Icons.checklist,
                  size: 16,
                  color: selectionMode
                      ? paperLight
                      : inkGray,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showLinkedNotes(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => _LinkedNotesSheet(
          space: space,
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _showLinkFolders(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkFoldersSheet(space: space),
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            contentPadding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            content: Container(
              width: 320,
              decoration: BoxDecoration(
                border: Border.all(color: ink, width: borderWidth),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: ink, width: borderWidth),
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
                          child: Icon(Icons.close, size: 18, color: inkGray),
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
                          onClear: () => setDialogState(() => tempStart = null),
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
                          onClear: () => setDialogState(() => tempEnd = null),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: ink, width: borderWidth),
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
                                color: ink,
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
                                .update(space.copyWith(
                                  startDate: tempStart,
                                  clearStartDate: tempStart == null,
                                  dueDate: tempEnd,
                                  clearDueDate: tempEnd == null,
                                ));
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
                border: Border.all(color: ink, width: borderWidth),
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
                      child: Icon(Icons.close, size: 14, color: inkGray),
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

class _KanbanBoard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          itemCount: columns.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            if (i < columns.length) {
              return _KanbanColumn(
                space: space,
                column: columns[i],
                selectedCardIds: selectedCardIds,
                onToggleSelection: onToggleSelection,
                selectionMode: selectionMode,
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
        ],
      );
  }
}

class _KanbanColumn extends ConsumerWidget {
  final LabSpace space;
  final KanbanColumn column;
  final Set<int> selectedCardIds;
  final void Function(int) onToggleSelection;
  final bool selectionMode;

  const _KanbanColumn({
    required this.space,
    required this.column,
    required this.selectedCardIds,
    required this.onToggleSelection,
    required this.selectionMode,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final isProtected = column.name == 'Entregado' || column.name == 'Vencido';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: inkColor(context), width: borderWidth),
        ),
        title: Text('Eliminar columna',
            style: displayM.copyWith(color: inkColor(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se eliminará la columna y todas sus cards.',
                style: bodyM.copyWith(color: inkColor(context))),
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
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
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
      await ref.read(labSpaceRepositoryProvider).deleteColumn(column.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(kanbanCardsByColumnProvider(column.id));
    final cards = cardsAsync.valueOrNull ?? [];

    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppColumnHeader(
            title: column.name,
            accentColor: space.accentColor,
            cardCount: cards.length,
            onDelete: () => _confirmDelete(context, ref),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: DragTarget<_DragData>(
              onAcceptWithDetails: (details) async {
                if (details.data.card.columnId != column.id) {
                  await _moveCardToColumn(ref, details.data, cards.length);
                }
              },
              builder: (context, candidateData, rejectedData) {
                final hasCrossCandidate = candidateData
                    .any((d) => d?.card.columnId != column.id);
                return Container(
                  color: hasCrossCandidate
                      ? space.accentColor.withAlpha(20)
                      : Colors.transparent,
                  child: cards.isEmpty
                      ? const SizedBox.expand()
                      : ListView(
                          children: [
                            for (int i = 0; i < cards.length; i++) ...[
                              _CardDropZone(
                                column: column,
                                accentColor: space.accentColor,
                                position: i,
                                onDrop: (_DragData data) =>
                                    _handleDrop(ref, data, cards, i),
                              ),
                              if (selectionMode)
                                GestureDetector(
                                  key: ValueKey('sel_${cards[i].id}'),
                                  onTap: () =>
                                      onToggleSelection(cards[i].id),
                                  child: KanbanCardTile(
                                    card: cards[i],
                                    accentColor: space.accentColor,
                                    onTap: () =>
                                        onToggleSelection(cards[i].id),
                                    isSelected:
                                        selectedCardIds.contains(cards[i].id),
                                    selectionMode: true,
                                  ),
                                )
                              else
                                LongPressDraggable<_DragData>(
                                  key: ValueKey(cards[i].id),
                                  data: _DragData(cards[i]),
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
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.3,
                                    child: KanbanCardTile(
                                      card: cards[i],
                                      accentColor: space.accentColor,
                                      onTap: () =>
                                          _openCard(context, cards[i]),
                                    ),
                                  ),
                                  child: KanbanCardTile(
                                    card: cards[i],
                                    accentColor: space.accentColor,
                                    onTap: () =>
                                        _openCard(context, cards[i]),
                                  ),
                                ),
                            ],
                            _CardDropZone(
                              column: column,
                              accentColor: space.accentColor,
                              position: cards.length,
                              onDrop: (_DragData data) => _handleDrop(
                                  ref, data, cards, cards.length),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _AddCardButton(
            spaceId: space.id,
            columnId: column.id,
            accentColor: space.accentColor,
          ),
        ],
      ),
    );
  }

  Future<void> _handleDrop(
    WidgetRef ref,
    _DragData data,
    List<KanbanCard> cards,
    int position,
  ) async {
    if (data.card.columnId == column.id) {
      _reorderInColumn(ref, cards, data.card.id, position);
    } else {
      await _moveCardToColumn(ref, data, position);
    }
  }

  Future<void> _moveCardToColumn(WidgetRef ref, _DragData data, int position) async {
    await ref.read(kanbanCardRepositoryProvider).moveToColumn(
          data.card.id,
          column.id,
          position,
        );
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
    await ref.read(kanbanCardRepositoryProvider).reorderInColumn(column.id, ids);
  }

  void _openCard(BuildContext context, KanbanCard card) {
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
  final ValueChanged<_DragData> onDrop;

  const _CardDropZone({
    required this.column,
    required this.accentColor,
    required this.position,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragData>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return Container(
          height: isActive ? 6 : 2,
          margin: EdgeInsets.only(bottom: isActive ? 6 : 0),
          decoration: BoxDecoration(
            color: isActive ? accentColor.withAlpha(40) : Colors.transparent,
            border: isActive
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
      width: 200,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showAddColumn(context, ref),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: inkGray, width: borderWidth),
          ),
          padding: const EdgeInsets.all(16),
          child: Center(
              child: Text(
                '+ Columna',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
          ),
        ),
      );
  }

  void _showAddColumn(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Nueva columna',
            style: displayM.copyWith(color: inkColor(context))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: bodyL.copyWith(color: inkColor(context)),
          decoration: InputDecoration(
            hintText: 'Nombre',
            hintStyle: bodyL.copyWith(color: inkGray),
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
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
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
            child: Text('Crear',
                style: labelBold.copyWith(color: inkColor(context))),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: inkGray, width: borderWidth),
        ),
        child: Text(
          '+ Agregar tarea',
          style: labelBold.copyWith(color: inkGray),
        ),
      ),
    );
  }

  void _showAddCard(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Nueva tarjeta',
            style: displayM.copyWith(color: inkColor(context))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: bodyL.copyWith(color: inkColor(context)),
          decoration: InputDecoration(
            hintText: 'Título',
            hintStyle: bodyL.copyWith(color: inkGray),
          ),
          onSubmitted: (title) async {
            if (title.trim().isNotEmpty) {
              await ref.read(kanbanCardRepositoryProvider).create(
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
            child: Text('Cancelar',
                style: labelBold.copyWith(color: inkGray)),
          ),
          TextButton(
            onPressed: () async {
              final title = ctrl.text.trim();
              if (title.isNotEmpty) {
                await ref.read(kanbanCardRepositoryProvider).create(
                      labSpaceId: spaceId,
                      columnId: columnId,
                      title: title,
                    );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Crear',
                style: labelBold.copyWith(color: inkColor(context))),
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

class _LinkFoldersSheet extends ConsumerWidget {
  final LabSpace space;

  const _LinkFoldersSheet({required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(activeFoldersProvider);
    final folders = foldersAsync.valueOrNull ?? [];
    final linkedFolderIdsAsync = ref.watch(linkedFolderIdsProvider(space.id));
    final linkedIds = linkedFolderIdsAsync.valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
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
                'Vincular carpetas',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text(
                  'No hay carpetas en Flight. Crea una primero.',
                  style: bodyS.copyWith(color: inkGray),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                  itemCount: folders.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: inkGray.withAlpha(40),
                    indent: 24,
                    endIndent: 24,
                  ),
                  itemBuilder: (_, i) {
                    final folder = folders[i];
                    final isLinked = linkedIds.contains(folder.id);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final repo = ref.read(labSpaceRepositoryProvider);
                        if (isLinked) {
                          await repo.unlinkFolder(space.id, folder.id);
                        } else {
                          await repo.linkFolder(space.id, folder.id);
                        }
                        ref.invalidate(linkedFolderIdsProvider(space.id));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: inkColor(context),
                                  width: borderWidth,
                                ),
                              ),
                              child: isLinked
                                  ? Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        color: folder.color,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              folder.name,
                              style: bodyM.copyWith(
                                color: folder.color,
                                fontWeight: isLinked ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LinkedNotesSheet extends ConsumerWidget {
  final LabSpace space;
  final ScrollController scrollController;

  const _LinkedNotesSheet({
    required this.space,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkedFolderIdsAsync = ref.watch(linkedFolderIdsProvider(space.id));
    final linkedIds = linkedFolderIdsAsync.valueOrNull ?? [];
    final foldersAsync = ref.watch(activeFoldersProvider);
    final allFolders = foldersAsync.valueOrNull ?? [];
    final linkedFolders =
        allFolders.where((f) => linkedIds.contains(f.id)).toList();

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: linkedFolders.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Vincula carpetas primero desde el botón de carpetas.',
                style: bodyS.copyWith(color: inkGray),
              ),
            )
          : ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: inkGray.withAlpha(60),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 16),
                  child: Text(
                    'NOTAS VINCULADAS',
                    style: labelBold.copyWith(color: inkGray),
                  ),
                ),
                for (final folder in linkedFolders)
                  _FolderNoteSection(folder: folder, space: space),
              ],
            ),
    );
  }
}

class _FolderNoteSection extends ConsumerWidget {
  final Folder folder;
  final LabSpace space;

  const _FolderNoteSection({required this.folder, required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesByFolderProvider(folder.id));
    final notes = (notesAsync.valueOrNull ?? [])
        .where((n) => n.isActive)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Row(
            children: [
              Container(width: 4, height: 16, color: folder.color),
              const SizedBox(width: 8),
              Text(folder.name,
                  style: labelBold.copyWith(color: folder.color)),
              const Spacer(),
              Text('${notes.length}',
                  style: mono.copyWith(color: inkGray, fontSize: 12)),
            ],
          ),
        ),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 16),
            child: Text('Sin notas',
                style: bodyS.copyWith(color: inkGray)),
          )
        else
          for (final note in notes)
            _NoteRow(note: note, space: space),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NoteRow extends ConsumerWidget {
  final Note note;
  final LabSpace space;

  const _NoteRow({required this.note, required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(kanbanCardsByNoteProvider(note.id));
    final linkedCards = cardsAsync.valueOrNull ?? [];
    final isLinked = linkedCards.any((c) => c.labSpaceId == space.id);

    final snippet = cleanCellContent(note.rawMarkdown)
        .replaceAll(RegExp(r'[#*_`\[\]>\-]'), '')
        .trim();
    final preview = snippet.length > 60 ? snippet.substring(0, 60) : snippet;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(pendingNoteNavigationProvider.notifier).state = note.id;
          Navigator.pop(context);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cardBackground(context),
            border: Border.all(color: inkColor(context), width: borderWidth),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.displayTitle,
                        style: bodyM.copyWith(
                          color: inkColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(preview,
                          style: bodyS.copyWith(color: inkGray),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isLinked)
                Icon(Icons.link, size: 14, color: accentLab)
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showColumnPicker(context, ref),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      border: Border.all(color: accentLab, width: 1),
                    ),
                    child: Icon(Icons.add, size: 14, color: accentLab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showColumnPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColumnPickerSheet(
        space: space,
        note: note,
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
          top: BorderSide(color: ink, width: borderWidthHeavy),
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
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: inkGray, width: borderWidth),
                  ),
                  child: Text(
                    'Cancelar',
                    style: labelBold.copyWith(
                      color: inkGray,
                      fontSize: 12,
                    ),
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
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentFight,
                    border: Border.all(
                      color: accentFight,
                      width: borderWidth,
                    ),
                    boxShadow: shadowM,
                  ),
                  child: Text(
                    'Eliminar',
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
      ),
    );
  }
}

class _ColumnPickerSheet extends ConsumerWidget {
  final LabSpace space;
  final Note note;

  const _ColumnPickerSheet({required this.space, required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnsAsync = ref.watch(kanbanColumnsProvider(space.id));
    final columns = columnsAsync.valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
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
              child: Text('Enviar a columna',
                  style: labelBold.copyWith(color: inkGray)),
            ),
            if (columns.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Text('No hay columnas.',
                    style: bodyS.copyWith(color: inkGray)),
              )
            else
              ...columns.map((col) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final cleaned = cleanCellContent(note.rawMarkdown);
                      final snippet = cleaned.length > 200
                          ? cleaned.substring(0, 200)
                          : cleaned;
                      await ref.read(kanbanCardRepositoryProvider).create(
                            labSpaceId: space.id,
                            columnId: col.id,
                            title: note.displayTitle,
                            description:
                                snippet.isNotEmpty ? snippet : null,
                            sourceNoteId: note.id,
                          );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Card creada en ${col.name}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      child: Text(col.name,
                          style: bodyM.copyWith(color: inkColor(context))),
                    ),
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
