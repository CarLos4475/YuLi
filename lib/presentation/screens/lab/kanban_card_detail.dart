import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart' as y;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/navigation_provider.dart';
import '../../widgets/reminder_picker.dart';
import '../../widgets/confetti_burst.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/repositories/kanban_card_repository.dart';
import 'lab_card_colors.dart';

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
  late bool _isPreview;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(kanbanCardRepositoryProvider);
    _card = widget.card;
    _isPreview =
        widget.card.sourceNoteId != null &&
        (widget.card.description?.isNotEmpty ?? false);
    _titleController = TextEditingController(
      text: y.cleanMention(widget.card.title),
    );
    _descController = TextEditingController(
      text: widget.card.description ?? '',
    );
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
    final editedTitle = _titleController.text.trim();
    final originalClean = y.cleanMention(widget.card.title).trim();
    final titleChanged = editedTitle.isNotEmpty && editedTitle != originalClean;
    String? newTitle;
    if (titleChanged) {
      // The title field shows the cleaned text (sin @folder). Re-attach the
      // original mention(s) so editing the text doesn't drop the folder tag,
      // unless the user typed their own mention.
      final mentions = y.extractMentions(widget.card.title);
      final editedHasMention = y.extractMentions(editedTitle).isNotEmpty;
      newTitle =
          (mentions.isEmpty || editedHasMention)
              ? editedTitle
              : '$mentions $editedTitle';
    }
    await _repository.update(
      _card.copyWith(
        title: newTitle,
        description: _descController.text.isEmpty ? null : _descController.text,
        clearDescription: _descController.text.isEmpty,
      ),
    );
    _isDirty = false;
  }

  @override
  Widget build(BuildContext context) {
    final columnsAsync = ref.watch(kanbanColumnsProvider(widget.space.id));
    final columns = columnsAsync.valueOrNull ?? [];
    final currentColumn =
        columns.where((c) => c.id == _card.columnId).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: y.yCream,
        border: Border(
          top: BorderSide(color: y.yBorderStrong, width: y.yLineMid),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle (ink bar w/ cream nub)
          Container(
            color: y.yInk,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            child: Container(width: 56, height: 4, color: y.yCream),
          ),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              children: [
                // Kicker + title row + 3 icon btns
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '> TAREA · ID #${widget.card.id} · DESDE KANBAN',
                            style: y.yMono(
                              size: 9,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: y.yMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _titleController,
                            style: y.ySans(
                              size: 26,
                              weight: FontWeight.w700,
                              letterSpacing: -0.8,
                              color: y.yInk,
                              height: 1.15,
                            ),
                            maxLines: null,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Título',
                              hintStyle: y.ySans(
                                size: 26,
                                weight: FontWeight.w700,
                                letterSpacing: -0.8,
                                color: y.yMuted,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SheetIcon(
                      icon: YuLiIcons.check,
                      active: !_isDirty,
                      color: y.yLab,
                      onTap: () async {
                        await _save();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 6),
                    _SheetIcon(
                      icon:
                          _isPreview
                              ? YuLiIcons.pen
                              : YuLiIcons.eye,
                      active: _isPreview,
                      color: y.yFlight,
                      onTap: () => setState(() => _isPreview = !_isPreview),
                    ),
                    const SizedBox(width: 6),
                    _SheetIcon(
                      icon: YuLiIcons.close,
                      active: false,
                      color: y.yCream,
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Column selector
                if (columns.isNotEmpty)
                  _ColumnSelector(
                    card: _card,
                    currentColumn:
                        columns
                            .where((c) => c.id == _card.columnId)
                            .firstOrNull ??
                        columns.first,
                    columns: columns,
                    repo: _repository,
                    accent: widget.space.accentColor,
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
                  ref: ref,
                  card: _card,
                  repo: _repository,
                  space: widget.space,
                  onChanged: (c) => _onCardChanged(c),
                ),
                const SizedBox(height: 20),
                // Description
                Text(
                  '> DESCRIPCION . MARKDOWN . LATEX . CODIGO',
                  style: y.yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: y.yMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: y.yCream2,
                    border: Border.all(
                      color: y.yBorderStrong,
                      width: y.yLineMid,
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(minHeight: 160),
                  child:
                      _isPreview && _descController.text.isNotEmpty
                          ? MarkdownWidget(
                            data: _descController.text,
                            shrinkWrap: true,
                            config: MarkdownConfig(
                              configs: [
                                PConfig(
                                  textStyle: y.yBody(
                                    size: 13,
                                    color: y.yInk,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : TextField(
                            controller: _descController,
                            style: y.yBody(
                              size: 13,
                              color: y.yInk,
                              height: 1.55,
                            ),
                            maxLines: null,
                            decoration: InputDecoration(
                              hintText: '',
                              filled: true,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                ),
                if (widget.card.sourceNoteId != null) ...[
                  const SizedBox(height: 20),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ref.read(pendingNoteNavigationProvider.notifier).state =
                          widget.card.sourceNoteId;
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: y.yFlight.withAlpha(20),
                        border: Border.all(color: y.yFlight, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            YuLiIcons.fileText,
                            size: 16,
                            color: y.yFlight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ver nota de origen',
                              style: y.ySans(
                                size: 13,
                                weight: FontWeight.w700,
                                color: y.yFlight,
                              ),
                            ),
                          ),
                          Icon(YuLiIcons.arrowRight, size: 14, color: y.yFlight),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Aparece en
                Text(
                  '> ESTA TAREA APARECE EN',
                  style: y.yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: y.yMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _AppearChips(card: _card, currentColumn: currentColumn),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: y.yCream2,
              border: Border(top: BorderSide(color: y.yBorderStrong, width: 2)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDelete(context),
                  child: Text(
                    '✕ Eliminar tarjeta',
                    style: y
                        .yBody(
                          size: 13,
                          weight: FontWeight.w700,
                          color: y.yFight,
                        )
                        .copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: y.yFight,
                        ),
                  ),
                ),
                Text(
                  _isDirty ? 'editando · sin guardar' : 'autoguardado',
                  style: y.yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: y.yMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: y.yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            title: Text(
              'Eliminar tarjeta',
              style: y.ySans(size: 18, weight: FontWeight.w700, color: y.yInk),
            ),
            content: Text(
              'Esta accion no se puede deshacer.',
              style: y.yBody(size: 14, color: y.yInk),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Eliminar',
                  style: TextStyle(
                    color: y.yFight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      // Capture before the pop: the messenger (app-level → survives this screen
      // closing) and the full card (to restore it faithfully on undo).
      final messenger = ScaffoldMessenger.of(context);
      final deleted = widget.card;
      await _repository.delete(deleted.id);
      if (context.mounted) Navigator.pop(context);
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
              onPressed: () => _repository.restore(deleted),
            ),
          ),
        );
    }
  }
}

class _ColumnSelector extends StatelessWidget {
  final KanbanCard card;
  final KanbanColumn currentColumn;
  final List<KanbanColumn> columns;
  final KanbanCardRepository repo;
  final Color accent;
  final ValueChanged<KanbanCard> onChanged;

  const _ColumnSelector({
    required this.card,
    required this.currentColumn,
    required this.columns,
    required this.repo,
    required this.accent,
    required this.onChanged,
  });

  Color _colColor(KanbanColumn col) {
    if (col.isExpired) return y.yFight;
    if (col.isTerminal) return y.yLab;
    if (col.isInProgress) return y.yAmber;
    return y.yMuted;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: y.yCream2,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _colColor(currentColumn),
                border: Border.all(color: y.yBorderStrong, width: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                currentColumn.name,
                style: y.ySans(
                  size: 14,
                  weight: FontWeight.w700,
                  color: y.yInk,
                ),
              ),
            ),
            Text('v', style: y.yBody(size: 12, color: y.yMuted)),
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
      builder:
          (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...columns.map(
                (col) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) async {
                    final celebrate =
                        col.isTerminal && col.id != card.columnId;
                    await repo.moveToColumn(card.id, col.id, 0);
                    onChanged(card.copyWith(columnId: col.id));
                    if (context.mounted) Navigator.pop(context);
                    if (celebrate && context.mounted) {
                      burstConfetti(context, d.globalPosition, accent: accent);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    width: double.infinity,
                    child: Text(
                      col.name,
                      style: bodyM.copyWith(
                        color:
                            col.id == currentColumn.id
                                ? inkColor(context)
                                : inkGray,
                        fontWeight:
                            col.id == currentColumn.id
                                ? FontWeight.w700
                                : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
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
      children:
          CardPriority.values.map((p) {
            final isSelected = card.priority == p;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final updated = card.copyWith(priority: p);
                  repo.update(updated);
                  onChanged(updated);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? labPriorityColor(p) : y.yCream,
                    border: Border.all(
                      color: y.yBorderStrong,
                      width: y.yLineMid,
                    ),
                  ),
                  child: Text(
                    _label(p),
                    style: y.yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: isSelected ? y.yCream : y.yInk,
                    ),
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
  final WidgetRef ref;
  final KanbanCard card;
  final KanbanCardRepository repo;
  final LabSpace space;
  final ValueChanged<KanbanCard> onChanged;

  const _DueDateRow({
    required this.ref,
    required this.card,
    required this.repo,
    required this.space,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final overdue = card.isOverdue();
    // Etiqueta contextual del campo de fecha de fin según el estado de la card.
    final finLabel =
        card.isDone ? 'ENTREGADO EL' : (overdue ? 'VENCIÓ EL' : 'VENCIMIENTO');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '> FECHAS',
          style: y.yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.4,
            color: y.yMuted,
          ),
        ),
        const SizedBox(height: 10),
        // INICIO (fecha de inicio real / agregado como fallback)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                'INICIO',
                style: y.yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yInk,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pickStartDate(context),
                    child: _dateChip(
                      card.startDate != null
                          ? _formatDate(card.startDate!)
                          : 'agregado · ${_formatDate(card.createdAt)}',
                      card.startDate != null ? y.yLab : y.yCream,
                    ),
                  ),
                  _startToggleChip('AUTO', card.startDate == null, () {
                    if (card.startDate != null) {
                      final u = card.copyWith(clearStartDate: true);
                      repo.update(u);
                      onChanged(u);
                    }
                  }),
                  _startToggleChip(
                    'FIJA',
                    card.startDate != null,
                    () => _pickStartDate(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // FIN (due date / fecha de acabado al entregar)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                finLabel,
                style: y.yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yInk,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickDate(context),
                child: _dateChip(
                  card.dueDate != null
                      ? _formatDate(card.dueDate!)
                      : 'sin fecha',
                  card.dueDate != null
                      ? (overdue ? y.yFight : y.yFlight)
                      : y.yCream,
                ),
              ),
            ),
          ],
        ),
        if (card.dueDate != null) ...[
          const SizedBox(height: 8),
          Text(
            'rango timeline:  ${_short(card.startDate ?? card.createdAt)} → ${_short(card.dueDate!)}',
            style: y.yMono(size: 10, tracking: 0.5, color: y.yMuted),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                'RECORDAR',
                style: y.yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: y.yInk,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickReminder(context),
                child: _dateChip(
                  card.remindAt != null
                      ? formatReminderTime(card.remindAt!)
                      : 'SIN RECORDATORIO',
                  card.remindAt != null ? space.accentColor : y.yCream,
                ),
              ),
            ),
          ],
        ),
        if (card.originFolderColor != null &&
            RegExp(r'@([a-zA-Z0-9_áéíóúñ]+)').hasMatch(card.title)) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Color(card.originFolderColor!),
              border: Border.all(color: y.yBorderStrong, width: 1.5),
            ),
            child: Text(
              '@${RegExp(r'@([a-zA-Z0-9_áéíóúñ]+)').firstMatch(card.title)!.group(1)!}',
              style: y.yMono(
                size: 10,
                weight: FontWeight.w700,
                color: y.yCream,
                tracking: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateChip(String label, Color bg) {
    final dark = bg.computeLuminance() < 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: y.yBorderStrong, width: 1.5),
      ),
      child: Text(
        label,
        style: y.yMono(
          size: 12,
          weight: FontWeight.w700,
          color: dark ? y.yCream : y.yInk,
          tracking: 0.3,
        ),
      ),
    );
  }

  Future<void> _pickReminder(BuildContext context) async {
    final selected = await showReminderPicker(
      context,
      accent: y.yLab,
      dueDate: card.dueDate,
      currentRemindAt: card.remindAt,
    );
    if (selected == null) return;
    final coordinator = ref.read(reminderCoordinatorProvider);
    if (selected.remindAt != null) {
      await coordinator.requestNotificationPermission();
    }
    await repo.updateReminder(card.id, selected.remindAt, selected.preset);
    onChanged(
      card.copyWith(
        remindAt: selected.remindAt,
        reminderPreset: selected.preset,
        clearRemindAt: selected.remindAt == null,
        clearReminderPreset: selected.preset == null,
      ),
    );
    if (selected.remindAt != null && context.mounted) {
      final enabled = await coordinator.areNotificationsEnabled();
      if (!enabled && context.mounted) {
        showNotificationsDisabledSnack(
          context,
          onOpenSettings: coordinator.openNotificationSettings,
        );
      }
    }
  }

  String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Widget _startToggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? space.accentColor : y.yCream,
          border: Border.all(color: y.yBorderStrong, width: 2),
        ),
        child: Text(
          label,
          style: y.yMono(
            size: 10,
            weight: FontWeight.w700,
            tracking: 1.2,
            color: active ? y.yCream : y.yInk,
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: card.startDate ?? card.createdAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder:
          (ctx, child) => Theme(
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
    if (date == null) return;
    final dt = DateTime(date.year, date.month, date.day);
    final updated = card.copyWith(startDate: dt);
    await repo.update(updated);
    onChanged(updated);
  }

  Future<void> _pickDate(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: card.dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder:
          (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              dialogTheme: DialogThemeData(backgroundColor: paperColor(ctx)),
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: inkColor(ctx),
                onPrimary: paperColor(ctx),
              ),
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            child: child!,
          ),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          card.dueDate != null
              ? TimeOfDay.fromDateTime(card.dueDate!)
              : const TimeOfDay(hour: 12, minute: 0),
      builder:
          (ctx, child) => Theme(
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
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final updated = card.copyWith(dueDate: dt);
    await repo.update(updated);
    onChanged(updated);
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _SheetIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _SheetIcon({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color : y.yCream,
          border: Border.all(color: y.yBorderStrong, width: y.yLineMid),
        ),
        child: Icon(icon, size: 16, color: active ? y.yCream : y.yInk),
      ),
    );
  }
}

class _AppearChips extends StatelessWidget {
  final KanbanCard card;
  final KanbanColumn? currentColumn;

  const _AppearChips({required this.card, required this.currentColumn});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (currentColumn != null) {
      chips.add(
        _AppearChip(icon: YuLiIcons.kanban, label: 'Kanban / ${currentColumn!.name}'),
      );
    }
    if (card.dueDate != null) {
      chips.add(
        _AppearChip(
          icon: YuLiIcons.calendar,
          label: 'Calendario / ${_fmtShort(card.dueDate!)}',
        ),
      );
      chips.add(
        _AppearChip(
          icon: YuLiIcons.timeline,
          label: 'Timeline · ${_fmtShort(card.dueDate!)}',
        ),
      );
    }
    if (card.originTaskId != null) {
      chips.add(const _AppearChip(icon: YuLiIcons.xSquare, label: 'FIGHT / origen task'));
    }
    if (card.sourceNoteId != null) {
      chips.add(const _AppearChip(icon: YuLiIcons.fileText, label: 'FLIGHT / nota'));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _AppearChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AppearChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 5),
      decoration: BoxDecoration(
        color: y.yCream2,
        border: Border.all(color: y.yBorderStrong, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: y.yInk),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: y.yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: y.yInk,
            ),
          ),
        ],
      ),
    );
  }
}
