import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../../theme/app_tokens.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/repositories/kanban_card_repository.dart';

class KanbanCardDetail extends ConsumerStatefulWidget {
  final KanbanCard card;
  final LabSpace space;
  final ScrollController scrollController;

  const KanbanCardDetail({
    super.key,
    required this.card,
    required this.space,
    required this.scrollController,
  });

  @override
  ConsumerState<KanbanCardDetail> createState() => _KanbanCardDetailState();
}

class _KanbanCardDetailState extends ConsumerState<KanbanCardDetail> {
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final KanbanCardRepository _repository;
  late KanbanCard _card;
  bool _isDirty = false;
  bool _isPreview = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(kanbanCardRepositoryProvider);
    _card = widget.card;
    _titleController =
        TextEditingController(text: widget.card.title);
    _descController =
        TextEditingController(text: widget.card.description ?? '');
    _titleController.addListener(_markDirty);
    _descController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _onCardChanged(KanbanCard updated) {
    setState(() => _card = updated);
  }

  @override
  void dispose() {
    _save();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isDirty) return;
    await _repository.update(
      _card.copyWith(
        title: _titleController.text.trim().isEmpty
            ? _card.title
            : _titleController.text.trim(),
        description: _descController.text.isEmpty
            ? null
            : _descController.text,
        clearDescription: _descController.text.isEmpty,
      ),
    );
    _isDirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final columnsAsync =
        ref.watch(kanbanColumnsProvider(widget.space.id));
    final columns = columnsAsync.valueOrNull ?? [];
    final currentColumn = columns
        .where((c) => c.id == widget.card.columnId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(
              color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              color: inkGray,
              margin: const EdgeInsets.only(bottom: 16),
            ),
          ),
          // Title + save + preview
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  style: displayM.copyWith(color: inkColor(context)),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Título',
                    hintStyle: displayM.copyWith(color: inkGray),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await _save();
                  if (context.mounted) Navigator.pop(context);
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isDirty ? accentFlight : Colors.transparent,
                    border: Border.all(
                      color: _isDirty ? accentFlight : inkGray.withAlpha(80),
                      width: 1,
                    ),
                  ),
                  child: Icon(Icons.check, size: 16,
                    color: _isDirty ? paperLight : inkGray.withAlpha(80)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _isPreview = !_isPreview),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _isPreview ? accentLab : Colors.transparent,
                    border: Border.all(
                      color: _isPreview ? accentLab : inkGray.withAlpha(80),
                      width: 1,
                    ),
                  ),
                  child: Icon(_isPreview ? Icons.edit_outlined : Icons.visibility_outlined,
                    size: 16,
                    color: _isPreview ? paperLight : inkGray.withAlpha(80)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Column selector
          if (currentColumn != null)
            _ColumnSelector(
              card: _card,
              currentColumn: currentColumn,
              columns: columns,
              repo: _repository,
              onChanged: (c) => _onCardChanged(c),
            ),
          const SizedBox(height: 16),
          // Priority
          _PrioritySelector(
            card: _card,
            repo: _repository,
            onChanged: (c) => _onCardChanged(c),
          ),
          const SizedBox(height: 16),
          // Due date
          _DueDateRow(
            card: _card,
            repo: _repository,
            onChanged: (c) => _onCardChanged(c),
          ),
          const SizedBox(height: 20),
          // Description
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: inkColor(context), width: borderWidth),
            ),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minHeight: 120),
            child: _isPreview && _descController.text.isNotEmpty
                ? MarkdownWidget(
                    data: _descController.text,
                    shrinkWrap: true,
                    config: MarkdownConfig(configs: [
                      PConfig(textStyle: bodyM.copyWith(color: inkColor(context))),
                    ]),
                  )
                : TextField(
                    controller: _descController,
                    style: bodyM.copyWith(color: inkColor(context)),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText:
                          'Descripción (Markdown, LaTeX inline, código)',
                      hintStyle: bodyM.copyWith(color: inkGray),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
          ),
          // Origin note link
          if (widget.card.sourceNoteId != null) ...[
            const SizedBox(height: 20),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ref.read(pendingNoteNavigationProvider.notifier).state =
                    widget.card.sourceNoteId;
                Navigator.pop(context); // close card detail
                Navigator.pop(context); // close kanban board → AppShell handles mode switch
              },
              child: Text(
                'Ver nota de origen →',
                style: bodyS.copyWith(color: accentFlight),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Delete
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmDelete(context),
            child: Text(
              'Eliminar tarjeta',
              style: bodyS.copyWith(color: accentFight.withAlpha(180)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: paperColor(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Eliminar tarjeta',
            style: displayM.copyWith(color: inkColor(context))),
        content: Text('Esta acción no se puede deshacer.',
            style: bodyM.copyWith(color: inkColor(context))),
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
      await _repository.delete(widget.card.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _ColumnSelector extends StatelessWidget {
  final KanbanCard card;
  final KanbanColumn currentColumn;
  final List<KanbanColumn> columns;
  final KanbanCardRepository repo;
  final ValueChanged<KanbanCard> onChanged;

  const _ColumnSelector({
    required this.card,
    required this.currentColumn,
    required this.columns,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPicker(context),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '[${currentColumn.name.toUpperCase()} ▾]',
              style: labelBold.copyWith(color: inkColor(context)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: paperColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...columns.map((col) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await repo.moveToColumn(
                        card.id,
                        col.id,
                        0,
                      );
                  onChanged(card.copyWith(columnId: col.id));
                  if (context.mounted) Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  width: double.infinity,
                  child: Text(
                    col.name,
                    style: bodyM.copyWith(
                      color: col.id == currentColumn.id
                          ? inkColor(context)
                          : inkGray,
                      fontWeight: col.id == currentColumn.id
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  final KanbanCard card;
  final KanbanCardRepository repo;
  final ValueChanged<KanbanCard> onChanged;

  const _PrioritySelector({
    required this.card,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: CardPriority.values.map((p) {
        final isSelected = card.priority == p;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final updated = card.copyWith(priority: p);
            repo.update(updated);
            onChanged(updated);
          },
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? inkColor(context) : Colors.transparent,
              border: Border.all(
                color: isSelected ? inkColor(context) : inkGray,
                width: borderWidth,
              ),
            ),
            child: Text(
              _label(p),
              style: labelBold.copyWith(
                color: isSelected ? paperColor(context) : inkGray,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _label(CardPriority p) => switch (p) {
        CardPriority.none => 'Sin prioridad',
        CardPriority.low => 'Baja',
        CardPriority.medium => 'Media',
        CardPriority.high => 'Alta',
      };
}

class _DueDateRow extends StatelessWidget {
  final KanbanCard card;
  final KanbanCardRepository repo;
  final ValueChanged<KanbanCard> onChanged;

  const _DueDateRow({
    required this.card,
    required this.repo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickDate(context),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 14, color: inkGray),
          const SizedBox(width: 8),
          Text(
            card.dueDate != null
                ? _formatDate(card.dueDate!)
                : 'Agregar fecha límite',
            style: bodyS.copyWith(color: inkGray),
          ),
          if (card.dueDate != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final updated = card.copyWith(clearDueDate: true);
                repo.update(updated);
                onChanged(updated);
              },
              child: const Icon(Icons.close, size: 14, color: inkGray),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: card.dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          dialogTheme: DialogThemeData(backgroundColor: paperColor(ctx)),
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: inkColor(ctx),
                onPrimary: paperColor(ctx),
              ),
          inputDecorationTheme: const InputDecorationTheme(
            border:
                OutlineInputBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: card.dueDate != null
          ? TimeOfDay.fromDateTime(card.dueDate!)
          : const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          dialogTheme: DialogThemeData(backgroundColor: paperColor(ctx)),
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: inkColor(ctx),
                onPrimary: paperColor(ctx),
              ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final updated = card.copyWith(dueDate: dt);
    await repo.update(updated);
    onChanged(updated);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
