import 'package:flutter/material.dart';

import '../../../domain/models/page_background.dart';
import '../../widgets/yuli_design.dart';
import 'drawing_engine.dart';
import 'note_cell_model.dart';
import 'notebook_constants.dart';

class NotebookPageDrawer extends StatelessWidget {
  final List<int> pageBlockIds;
  final Map<int, DrawingData> pageData;
  final Set<int> starredBlockIds;
  final PageBackground background;
  final Color accentColor;
  final int currentPageIndex;
  final void Function(int pageIndex) onNavigate;
  final void Function(int blockId) onToggleStar;
  final void Function(int pageIndex) onDelete;
  final void Function(int oldUnstarredIdx, int newUnstarredIdx) onReorder;
  final VoidCallback onClose;
  final VoidCallback onAddPage;

  const NotebookPageDrawer({
    super.key,
    required this.pageBlockIds,
    required this.pageData,
    required this.starredBlockIds,
    required this.background,
    required this.accentColor,
    required this.currentPageIndex,
    required this.onNavigate,
    required this.onToggleStar,
    required this.onDelete,
    required this.onReorder,
    required this.onClose,
    required this.onAddPage,
  });

  @override
  Widget build(BuildContext context) {
    final starred = <_PageRef>[];
    final unstarred = <_PageRef>[];
    for (int i = 0; i < pageBlockIds.length; i++) {
      final id = pageBlockIds[i];
      final ref = _PageRef(pageIndex: i, blockId: id);
      if (starredBlockIds.contains(id)) {
        starred.add(ref);
      } else {
        unstarred.add(ref);
      }
    }

    final canDelete = pageBlockIds.length > 1;

    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(left: BorderSide(color: yBorderStrong, width: yLineHeavy)),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(
              pageCount: pageBlockIds.length,
              accentColor: accentColor,
              onClose: onClose,
              onAddPage: onAddPage,
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (starred.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        label: 'GUARDADAS',
                        count: starred.length,
                        icon: Icons.bookmark,
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final ref = starred[i];
                          return _PageTile(
                            key: ValueKey('s-${ref.blockId}'),
                            pageIndex: ref.pageIndex,
                            blockId: ref.blockId,
                            data: pageData[ref.blockId],
                            background: background,
                            accentColor: accentColor,
                            isStarred: true,
                            isCurrent: ref.pageIndex == currentPageIndex,
                            canDelete: canDelete,
                            showDragHandle: false,
                            onTap: () => onNavigate(ref.pageIndex),
                            onToggleStar: () => onToggleStar(ref.blockId),
                            onDelete: () => onDelete(ref.pageIndex),
                          );
                        },
                        childCount: starred.length,
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      label: 'PÁGINAS',
                      count: unstarred.length,
                      icon: Icons.auto_stories,
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: unstarred.length,
                    onReorder: onReorder,
                    itemBuilder: (ctx, i) {
                      final ref = unstarred[i];
                      return _PageTile(
                        key: ValueKey('u-${ref.blockId}'),
                        pageIndex: ref.pageIndex,
                        blockId: ref.blockId,
                        data: pageData[ref.blockId],
                        background: background,
                        accentColor: accentColor,
                        isStarred: false,
                        isCurrent: ref.pageIndex == currentPageIndex,
                        canDelete: canDelete,
                        showDragHandle: true,
                        dragIndex: i,
                        onTap: () => onNavigate(ref.pageIndex),
                        onToggleStar: () => onToggleStar(ref.blockId),
                        onDelete: () => onDelete(ref.pageIndex),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageRef {
  final int pageIndex;
  final int blockId;
  const _PageRef({required this.pageIndex, required this.blockId});
}

class _DrawerHeader extends StatelessWidget {
  final int pageCount;
  final Color accentColor;
  final VoidCallback onClose;
  final VoidCallback onAddPage;

  const _DrawerHeader({
    required this.pageCount,
    required this.accentColor,
    required this.onClose,
    required this.onAddPage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yBorderStrong, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Container(width: 4, height: 28, color: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PÁGINAS',
                  style: ySans(
                    size: 16,
                    weight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: yInk,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$pageCount EN TOTAL',
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddPage,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accentColor,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 14, color: yCream),
                  const SizedBox(width: 4),
                  Text(
                    'NUEVA',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: yCream,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(Icons.close, color: yInk, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: const BoxDecoration(
        color: yCream,
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: yMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.6,
              color: yMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.2,
              color: yMuted.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          Container(
            height: 1,
            width: 40,
            color: yInk.withValues(alpha: 0.15),
          ),
        ],
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  final int pageIndex;
  final int blockId;
  final DrawingData? data;
  final PageBackground background;
  final Color accentColor;
  final bool isStarred;
  final bool isCurrent;
  final bool canDelete;
  final bool showDragHandle;
  final int? dragIndex;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;
  final VoidCallback onDelete;

  const _PageTile({
    super.key,
    required this.pageIndex,
    required this.blockId,
    required this.data,
    required this.background,
    required this.accentColor,
    required this.isStarred,
    required this.isCurrent,
    required this.canDelete,
    required this.showDragHandle,
    this.dragIndex,
    required this.onTap,
    required this.onToggleStar,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const thumbW = 72.0;
    const thumbH = thumbW * kNotebookPageHeight / kNotebookPageWidth;

    final strokeCount = data?.strokes.length ?? 0;

    final tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent ? accentColor.withValues(alpha: 0.1) : yCream,
          border: const Border(
            bottom: BorderSide(color: yBorderStrong, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isCurrent)
              Container(width: 3, height: thumbH, color: accentColor)
            else
              const SizedBox(width: 3),
            const SizedBox(width: 8),
            Container(
              width: thumbW,
              height: thumbH,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF8),
                border: Border.all(
                  color: isCurrent ? accentColor : yBorderStrong,
                  width: isCurrent ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: yInk.withValues(alpha: 0.12),
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
              child: ClipRect(
                child: data == null
                    ? const SizedBox()
                    : CustomPaint(
                        painter: _PageThumbnailPainter(
                          data: data!,
                          background: background,
                          accentColor: accentColor,
                          scale: thumbW / kNotebookPageWidth,
                        ),
                        size: const Size(thumbW, thumbH),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PG ${pageIndex + 1}',
                    style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strokeCount == 0
                        ? 'VACÍA'
                        : '$strokeCount TRAZO${strokeCount == 1 ? '' : 'S'}',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.2,
                      color: yMuted,
                    ),
                  ),
                ],
              ),
            ),
            _IconBtn(
              icon: isStarred ? Icons.bookmark : Icons.bookmark_border,
              color: isStarred ? accentColor : yMuted,
              onTap: onToggleStar,
            ),
            const SizedBox(width: 6),
            _IconBtn(
              icon: Icons.delete_outline,
              color: canDelete ? yInk : yMuted.withValues(alpha: 0.3),
              onTap: canDelete ? () => _confirmDelete(context) : null,
            ),
            if (showDragHandle && dragIndex != null) ...[
              const SizedBox(width: 6),
              ReorderableDragStartListener(
                index: dragIndex!,
                child: Container(
                  width: 28,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: yCream2,
                    border: Border.all(color: yBorderStrong, width: 1.2),
                  ),
                  child: const Icon(Icons.drag_handle,
                      size: 16, color: yInk),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return tile;
  }

  void _confirmDelete(BuildContext context) {
    final strokeCount = data?.strokes.length ?? 0;
    if (strokeCount == 0) {
      onDelete();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ELIMINAR PÁGINA ${pageIndex + 1}',
                style: ySans(
                    size: 16, weight: FontWeight.w700, color: yInk),
              ),
              const SizedBox(height: 8),
              Text(
                'Esta página tiene $strokeCount trazo${strokeCount == 1 ? '' : 's'}. Esta acción no se puede deshacer.',
                style: yBody(size: 13, color: yInk),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(color: yBorderStrong, width: yLineThin),
                      ),
                      child: Text('CANCELAR',
                          style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: yInk)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(ctx);
                      onDelete();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: yFight,
                        border: Border.all(color: yBorderStrong, width: yLineMid),
                      ),
                      child: Text('ELIMINAR',
                          style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: yCream)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _PageThumbnailPainter extends CustomPainter {
  final DrawingData data;
  final PageBackground background;
  final Color accentColor;
  final double scale;

  _PageThumbnailPainter({
    required this.data,
    required this.background,
    required this.accentColor,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final pageRect =
        Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight);

    canvas.drawRect(pageRect, Paint()..color = const Color(0xFFFFFDF8));
    _drawBackground(canvas, pageRect);

    canvas.clipRect(pageRect);
    for (final stroke in data.strokes) {
      drawStroke(canvas, stroke);
    }

    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Rect page) {
    switch (background) {
      case PageBackground.blank:
        break;
      case PageBackground.lined:
        final paint = Paint()
          ..color = const Color(0xFFD6D1C8)
          ..strokeWidth = 0.5;
        const step = 28.0;
        for (double y = page.top + 60; y < page.bottom - 20; y += step) {
          canvas.drawLine(
            Offset(page.left + 40, y),
            Offset(page.right - 20, y),
            paint,
          );
        }
        canvas.drawLine(
          Offset(page.left + 36, page.top + 40),
          Offset(page.left + 36, page.bottom - 20),
          Paint()
            ..color = accentColor.withValues(alpha: 0.45)
            ..strokeWidth = 0.8,
        );
      case PageBackground.grid:
      case PageBackground.gridSmall:
        final paint = Paint()
          ..color = const Color(0xFFDAD6CE)
          ..strokeWidth = 0.4;
        final step = background == PageBackground.gridSmall ? 14.0 : 28.0;
        for (double y = page.top + step; y < page.bottom; y += step) {
          canvas.drawLine(
              Offset(page.left, y), Offset(page.right, y), paint);
        }
        for (double x = page.left + step; x < page.right; x += step) {
          canvas.drawLine(
              Offset(x, page.top), Offset(x, page.bottom), paint);
        }
      case PageBackground.dotted:
        final dot = Paint()..color = yMuted.withValues(alpha: 0.2);
        const step = 28.0;
        for (double x = page.left + step; x < page.right; x += step) {
          for (double y = page.top + step; y < page.bottom; y += step) {
            canvas.drawCircle(Offset(x, y), 1.0, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_PageThumbnailPainter old) =>
      old.data != data ||
      old.background != background ||
      old.accentColor != accentColor ||
      old.scale != scale;
}
