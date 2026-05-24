import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_tokens.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../widgets/app_column_header.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/kanban_card.dart';
import 'kanban_card_tile.dart';
import 'kanban_card_detail.dart';

class LabSpaceDetailScreen extends ConsumerWidget {
  final LabSpace space;

  const LabSpaceDetailScreen({super.key, required this.space});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnsAsync = ref.watch(kanbanColumnsProvider(space.id));

    return Scaffold(
      backgroundColor: paperColor(context),
      body: SafeArea(
        child: Column(
          children: [
            _KanbanHeader(space: space),
            Expanded(
              child: columnsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (columns) => _KanbanBoard(
                  space: space,
                  columns: columns,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KanbanHeader extends ConsumerWidget {
  final LabSpace space;

  const _KanbanHeader({required this.space});

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        space.name,
                        style: displayL.copyWith(color: space.accentColor),
                      ),
                    ),
                  ],
                ),
                if (linkedFolders.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: linkedFolders.map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: f.color.withAlpha(30),
                        border: Border.all(color: f.color, width: 1),
                      ),
                      child: Text(
                        f.name,
                        style: labelBold.copyWith(color: f.color, fontSize: 10),
                      ),
                    )).toList(),
                  ),
                ],
                if (space.dueDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(space.dueDate!),
                    style: bodyS.copyWith(color: inkGray),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showLinkFolders(context, ref),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentFlight,
                border: Border.all(color: accentFlight, width: 1),
              ),
              child: Icon(Icons.folder_outlined, size: 16, color: paperLight),
            ),
          ),
        ],
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
}

class _KanbanBoard extends ConsumerWidget {
  final LabSpace space;
  final List<KanbanColumn> columns;

  const _KanbanBoard({required this.space, required this.columns});

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
                  space: space, column: columns[i]);
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

  const _KanbanColumn({required this.space, required this.column});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
        content: Text('Se eliminará la columna y todas sus cards.',
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
              onAcceptWithDetails: (details) {
                if (details.data.card.columnId != column.id) {
                  _moveCardToColumn(ref, details.data, cards.length);
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

  void _handleDrop(
    WidgetRef ref,
    _DragData data,
    List<KanbanCard> cards,
    int position,
  ) {
    if (data.card.columnId == column.id) {
      _reorderInColumn(ref, cards, data.card.id, position);
    } else {
      _moveCardToColumn(ref, data, position);
    }
  }

  void _moveCardToColumn(WidgetRef ref, _DragData data, int position) {
    ref.read(kanbanCardRepositoryProvider).moveToColumn(
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
