import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import 'background_paint.dart';
import 'canvas_image_cache.dart';
import 'drawing_engine.dart';
import 'note_cell_model.dart';
import 'notebook_constants.dart';

class NotebookPageDrawer extends StatefulWidget {
  final List<int> pageBlockIds;
  final Map<int, DrawingData> pageData;
  final Set<int> starredBlockIds;
  final Color accentColor;
  final CanvasImageCache? imageCache;
  final int currentPageIndex;
  final void Function(int pageIndex) onNavigate;
  final void Function(int blockId) onToggleStar;
  final void Function(int pageIndex) onDelete;
  final void Function(int oldUnstarredIdx, int newUnstarredIdx) onReorder;
  final VoidCallback onClose;
  final VoidCallback onAddPage;

  /// Export the chosen page indices (0-based, sorted ascending). The editor
  /// closes the drawer and runs the format sheet + render.
  final void Function(List<int> pageIndices) onExport;

  const NotebookPageDrawer({
    super.key,
    required this.pageBlockIds,
    required this.pageData,
    required this.starredBlockIds,
    required this.accentColor,
    this.imageCache,
    required this.currentPageIndex,
    required this.onNavigate,
    required this.onToggleStar,
    required this.onDelete,
    required this.onReorder,
    required this.onClose,
    required this.onAddPage,
    required this.onExport,
  });

  @override
  State<NotebookPageDrawer> createState() => _NotebookPageDrawerState();
}

class _NotebookPageDrawerState extends State<NotebookPageDrawer> {
  bool _exportMode = false;
  final Set<int> _selected = {};

  void _enterExport() {
    setState(() {
      _exportMode = true;
      _selected
        ..clear()
        ..add(widget.currentPageIndex);
    });
  }

  void _exitExport() {
    setState(() {
      _exportMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(int pageIndex) {
    setState(() {
      if (!_selected.remove(pageIndex)) _selected.add(pageIndex);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == widget.pageBlockIds.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll([for (int i = 0; i < widget.pageBlockIds.length; i++) i]);
      }
    });
  }

  void _confirmExport() {
    if (_selected.isEmpty) return;
    final indices = _selected.toList()..sort();
    _exitExport();
    widget.onExport(indices);
  }

  @override
  Widget build(BuildContext context) {
    final starred = <_PageRef>[];
    final unstarred = <_PageRef>[];
    for (int i = 0; i < widget.pageBlockIds.length; i++) {
      final id = widget.pageBlockIds[i];
      final ref = _PageRef(pageIndex: i, blockId: id);
      if (widget.starredBlockIds.contains(id)) {
        starred.add(ref);
      } else {
        unstarred.add(ref);
      }
    }

    final canDelete = widget.pageBlockIds.length > 1;

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
              pageCount: widget.pageBlockIds.length,
              accentColor: widget.accentColor,
              exportMode: _exportMode,
              selectedCount: _selected.length,
              allSelected: _selected.length == widget.pageBlockIds.length,
              onClose: widget.onClose,
              onAddPage: widget.onAddPage,
              onEnterExport: _enterExport,
              onExitExport: _exitExport,
              onSelectAll: _selectAll,
              onConfirmExport: _confirmExport,
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (starred.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        label: 'GUARDADAS',
                        count: starred.length,
                        icon: YuLiIcons.bookmark,
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
                            data: widget.pageData[ref.blockId],
                            accentColor: widget.accentColor,
                            imageCache: widget.imageCache,
                            isStarred: true,
                            isCurrent: ref.pageIndex == widget.currentPageIndex,
                            canDelete: canDelete,
                            showDragHandle: false,
                            exportMode: _exportMode,
                            isSelected: _selected.contains(ref.pageIndex),
                            onTap: _exportMode
                                ? () => _toggleSelect(ref.pageIndex)
                                : () => widget.onNavigate(ref.pageIndex),
                            onToggleStar: () => widget.onToggleStar(ref.blockId),
                            onDelete: () => widget.onDelete(ref.pageIndex),
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
                      icon: YuLiIcons.bookOpen,
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: unstarred.length,
                    onReorder: widget.onReorder,
                    itemBuilder: (ctx, i) {
                      final ref = unstarred[i];
                      return _PageTile(
                        key: ValueKey('u-${ref.blockId}'),
                        pageIndex: ref.pageIndex,
                        blockId: ref.blockId,
                        data: widget.pageData[ref.blockId],
                        accentColor: widget.accentColor,
                        imageCache: widget.imageCache,
                        isStarred: false,
                        isCurrent: ref.pageIndex == widget.currentPageIndex,
                        canDelete: canDelete,
                        showDragHandle: !_exportMode,
                        dragIndex: i,
                        exportMode: _exportMode,
                        isSelected: _selected.contains(ref.pageIndex),
                        onTap: _exportMode
                            ? () => _toggleSelect(ref.pageIndex)
                            : () => widget.onNavigate(ref.pageIndex),
                        onToggleStar: () => widget.onToggleStar(ref.blockId),
                        onDelete: () => widget.onDelete(ref.pageIndex),
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
  final bool exportMode;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onAddPage;
  final VoidCallback onEnterExport;
  final VoidCallback onExitExport;
  final VoidCallback onSelectAll;
  final VoidCallback onConfirmExport;

  const _DrawerHeader({
    required this.pageCount,
    required this.accentColor,
    required this.exportMode,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onAddPage,
    required this.onEnterExport,
    required this.onExitExport,
    required this.onSelectAll,
    required this.onConfirmExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yBorderStrong, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: exportMode ? _exportRow() : _normalRow(),
    );
  }

  Widget _normalRow() {
    return Row(
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
        _HeaderBtn(
          icon: YuLiIcons.share,
          label: 'EXPORTAR',
          filled: false,
          accentColor: accentColor,
          onTap: onEnterExport,
        ),
        const SizedBox(width: 8),
        _HeaderBtn(
          icon: YuLiIcons.plus,
          label: 'NUEVA',
          filled: true,
          accentColor: accentColor,
          onTap: onAddPage,
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
            child: const Icon(YuLiIcons.close, color: yInk, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _exportRow() {
    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onExitExport,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
            ),
            child: const Icon(YuLiIcons.arrowLeft, color: yInk, size: 16),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'EXPORTAR',
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
                '$selectedCount SELECCIONADA${selectedCount == 1 ? '' : 'S'}',
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
        _HeaderBtn(
          icon: allSelected ? YuLiIcons.xSquare : YuLiIcons.checkCheck,
          label: allSelected ? 'NINGUNA' : 'TODAS',
          filled: false,
          accentColor: accentColor,
          onTap: onSelectAll,
        ),
        const SizedBox(width: 8),
        Opacity(
          opacity: selectedCount == 0 ? 0.4 : 1,
          child: _HeaderBtn(
            icon: YuLiIcons.check,
            label: 'LISTO',
            filled: true,
            accentColor: accentColor,
            onTap: selectedCount == 0 ? () {} : onConfirmExport,
          ),
        ),
      ],
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final Color accentColor;
  final VoidCallback onTap;
  const _HeaderBtn({
    required this.icon,
    required this.label,
    required this.filled,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? accentColor : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: filled ? yCream : yInk),
            const SizedBox(width: 4),
            Text(
              label,
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: filled ? yCream : yInk,
              ),
            ),
          ],
        ),
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
  final Color accentColor;
  final CanvasImageCache? imageCache;
  final bool isStarred;
  final bool isCurrent;
  final bool canDelete;
  final bool showDragHandle;
  final int? dragIndex;
  final bool exportMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;
  final VoidCallback onDelete;

  const _PageTile({
    super.key,
    required this.pageIndex,
    required this.blockId,
    required this.data,
    required this.accentColor,
    this.imageCache,
    required this.isStarred,
    required this.isCurrent,
    required this.canDelete,
    required this.showDragHandle,
    this.dragIndex,
    this.exportMode = false,
    this.isSelected = false,
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
          color: isSelected
              ? accentColor.withValues(alpha: 0.18)
              : isCurrent
                  ? accentColor.withValues(alpha: 0.1)
                  : yCream,
          border: const Border(
            bottom: BorderSide(color: yBorderStrong, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (exportMode) ...[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: isSelected
                    ? const Icon(YuLiIcons.check, size: 15, color: yCream)
                    : null,
              ),
              const SizedBox(width: 10),
            ] else if (isCurrent)
              Container(width: 3, height: thumbH, color: accentColor)
            else
              const SizedBox(width: 3),
            if (!exportMode) const SizedBox(width: 8),
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
                    // Own layer: rasterized once, so the drawer's slide-in
                    // animation just offsets it instead of re-painting strokes.
                    : RepaintBoundary(
                        child: CustomPaint(
                          painter: _PageThumbnailPainter(
                            data: data!,
                            accentColor: accentColor,
                            imageCache: imageCache,
                            scale: thumbW / kNotebookPageWidth,
                          ),
                          size: const Size(thumbW, thumbH),
                        ),
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
            if (!exportMode) ...[
              _IconBtn(
                icon: YuLiIcons.bookmark,
                color: isStarred ? accentColor : yMuted,
                onTap: onToggleStar,
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon: YuLiIcons.trash,
                color: canDelete ? yInk : yMuted.withValues(alpha: 0.3),
                onTap: canDelete ? () => _confirmDelete(context) : null,
              ),
            ],
            if (!exportMode && showDragHandle && dragIndex != null) ...[
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
                  child: const Icon(YuLiIcons.gripVertical,
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

/// Renders a page thumbnail with the SAME primitives as [_NotebookCanvasPainter]
/// (paper color + pattern + images + strokes), per-page background, so a tile
/// looks like a shrunk page instead of the old hand-rolled approximation.
class _PageThumbnailPainter extends CustomPainter {
  final DrawingData data;
  final Color accentColor;
  final CanvasImageCache? imageCache;
  final double scale;

  _PageThumbnailPainter({
    required this.data,
    required this.accentColor,
    required this.imageCache,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final pageRect =
        Rect.fromLTWH(0, 0, kNotebookPageWidth, kNotebookPageHeight);
    canvas.clipRect(pageRect);

    final paper = bgPaper(data.bgColorValue, const Color(0xFFFFFDF8));
    canvas.drawRect(pageRect, Paint()..color = paper);
    paintBgPattern(canvas, pageRect, data.background, bgMark(paper));

    for (final im in data.images) {
      drawCanvasImage(canvas, imageCache?.get(im.filename), im);
    }
    // Text/task blocks are widget overlays (never painted) — at thumbnail scale
    // their text is illegible, so draw a representative card box at each block's
    // position so the page preview isn't missing content. Above images, below
    // strokes (matches the live layer order).
    _drawBlocks(canvas);
    for (final stroke in data.strokes) {
      drawStroke(canvas, stroke);
    }

    canvas.restore();
  }

  void _drawBlocks(Canvas canvas) {
    // World-unit width so it renders ~constant px after the canvas scale.
    final bw = 0.7 / scale;
    final fill = Paint()..color = yCream;
    final border = Paint()
      ..color = yBorderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = bw;
    final hint = Paint()..color = yInk.withValues(alpha: 0.28);
    final accent = Paint()..color = accentColor;

    for (final b in data.textBlocks) {
      final rect = Rect.fromLTWH(b.x, b.y, b.w, b.h);
      canvas.drawRect(rect, fill);
      // Accent left stripe (mirrors the card's left border).
      final stripeW = (b.w * 0.06).clamp(4.0, 18.0);
      canvas.drawRect(
        Rect.fromLTWH(b.x, b.y, stripeW, b.h),
        accent,
      );
      canvas.drawRect(rect, border);
      // A few faint lines to suggest text.
      final pad = stripeW + b.w * 0.06;
      final lh = b.h / 5;
      for (int i = 1; i <= 3; i++) {
        final y = b.y + lh * i;
        if (y > b.y + b.h - lh * 0.5) break;
        canvas.drawRect(
          Rect.fromLTWH(b.x + pad, y, (b.w - pad - b.w * 0.08), bw * 1.5),
          hint,
        );
      }
    }

    for (final b in data.taskBlocks) {
      final rect = Rect.fromLTWH(b.x, b.y, b.w, b.h);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
      // Rows of [checkbox + line] to suggest a checklist.
      final rowH = (b.h / 4).clamp(1.0, b.h);
      final box = (rowH * 0.5).clamp(2.0, 40.0);
      final left = b.x + b.w * 0.08;
      for (int i = 0; i < 3; i++) {
        final cy = b.y + rowH * (i + 0.6);
        if (cy + box > b.y + b.h) break;
        final sq = Rect.fromLTWH(left, cy, box, box);
        canvas.drawRect(sq, accent);
        canvas.drawRect(
          Rect.fromLTWH(left + box * 1.6, cy + box * 0.2,
              b.w - (left - b.x) - box * 1.6 - b.w * 0.08, box * 0.6),
          hint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PageThumbnailPainter old) =>
      old.data != data ||
      old.accentColor != accentColor ||
      old.imageCache != imageCache ||
      old.scale != scale;
}
