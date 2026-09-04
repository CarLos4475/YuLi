// Single source of truth for the READ-ONLY visual of a block note. Both the
// in-editor preview pane and the PDF export rasterizer build from
// [buildNoteExportItems], so what you see in preview is exactly what the PDF
// shows — no second markdown engine, no divergence.
//
// Each returned widget is one self-contained visual item (optional title header
// + one per renderable block) with NO outer spacing: the preview pane stacks
// them in a Column with gaps, while the exporter rasterizes each item on its own
// for clean page breaks.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import '../../providers/database_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'drawing_engine.dart';
import 'drawing_stroke_persistence.dart';
import 'note_block_widgets.dart';
import 'note_cell_model.dart';
import 'stroke_bounds.dart';

/// Ordered read-only items for a note: optional [title] header, then one widget
/// per renderable block. Empty blocks are skipped. Tasks render only when
/// [includeTasks] is true and the referenced tasks are present in [tasksById]
/// (the preview pane passes an empty map, so it shows no task boxes — matching
/// the previous behavior — while export loads them).
List<Widget> buildNoteExportItems({
  required List<NoteBlock> blocks,
  required Color accent,
  String? title,
  Map<int, Task> tasksById = const {},
  Map<int, List<DrawingStroke>> drawingStrokesByBlock = const {},
  bool includeTasks = true,
  ValueChanged<String>? onWikiLinkTap,
}) {
  final items = <Widget>[];
  final cleanTitle = title?.trim() ?? '';
  if (cleanTitle.isNotEmpty) {
    items.add(_ExportTitle(title: cleanTitle));
  }
  for (final block in blocks) {
    final item = _blockItem(
      block,
      accent,
      tasksById,
      drawingStrokesByBlock,
      includeTasks,
      onWikiLinkTap,
    );
    if (item != null) items.add(item);
  }
  return items;
}

Widget? _blockItem(
  NoteBlock block,
  Color accent,
  Map<int, Task> tasksById,
  Map<int, List<DrawingStroke>> drawingStrokesByBlock,
  bool includeTasks,
  ValueChanged<String>? onWikiLinkTap,
) {
  return switch (block) {
    TextBlock t =>
      t.markdown.trim().isEmpty
          ? null
          : NoteMarkdownPreview(
            data: t.markdown,
            accent: accent,
            onWikiLinkTap: onWikiLinkTap,
          ),
    MathBlock m =>
      m.latex.trim().isEmpty ? null : _MathItem(latex: m.latex, accent: accent),
    BulletsBlock b => b.items.isEmpty ? null : _BulletsItem(items: b.items),
    TareasBlock t => includeTasks ? _tasksItem(t, tasksById) : null,
    DrawingBlock d => _DrawingItem(
      block: d,
      strokes: drawingStrokesByBlock[d.id],
    ),
  };
}

Widget? _tasksItem(TareasBlock block, Map<int, Task> tasksById) {
  final tasks =
      block.taskIds
          .map((id) => tasksById[id])
          .whereType<Task>()
          .where((task) => task.status != TaskStatus.trash)
          .toList()
        ..sort((a, b) {
          final aDone = a.status == TaskStatus.done;
          final bDone = b.status == TaskStatus.done;
          if (aDone != bDone) return aDone ? 1 : -1;
          return a.createdAt.compareTo(b.createdAt);
        });
  if (tasks.isEmpty) return null;
  return _TasksItem(tasks: tasks);
}

/// Stacks [buildNoteExportItems] into a Column for the in-editor preview pane.
/// (The editor wraps this in its own scroll view.)
class NoteExportView extends ConsumerStatefulWidget {
  final List<NoteBlock> blocks;
  final Color accent;
  final String? title;
  final Map<int, Task> tasksById;
  final Map<int, List<DrawingStroke>> drawingStrokesByBlock;
  final bool includeTasks;
  final ValueChanged<String>? onWikiLinkTap;

  const NoteExportView({
    super.key,
    required this.blocks,
    required this.accent,
    this.title,
    this.tasksById = const {},
    this.drawingStrokesByBlock = const {},
    this.includeTasks = true,
    this.onWikiLinkTap,
  });

  @override
  ConsumerState<NoteExportView> createState() => _NoteExportViewState();
}

class _NoteExportViewState extends ConsumerState<NoteExportView> {
  Map<int, List<DrawingStroke>> _loadedDrawingStrokes = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadDrawingStrokes());
  }

  @override
  void didUpdateWidget(covariant NoteExportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.blocks
        .whereType<DrawingBlock>()
        .map((b) => b.id)
        .join(',');
    final newIds = widget.blocks
        .whereType<DrawingBlock>()
        .map((b) => b.id)
        .join(',');
    if (oldIds != newIds || oldWidget.blocks != widget.blocks) {
      unawaited(_loadDrawingStrokes());
    }
  }

  Future<void> _loadDrawingStrokes() async {
    final ids =
        widget.blocks.whereType<DrawingBlock>().map((b) => b.id).toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _loadedDrawingStrokes = const {});
      return;
    }
    final repo = ref.read(drawingStrokeRepositoryProvider);
    final loaded = <int, List<DrawingStroke>>{};
    for (final id in ids) {
      final rows = await repo.getByBlock(id);
      if (rows.isNotEmpty) {
        loaded[id] = rows.map(strokeFromRecord).toList();
      }
    }
    if (mounted) setState(() => _loadedDrawingStrokes = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final drawingStrokesByBlock = {
      ..._loadedDrawingStrokes,
      ...widget.drawingStrokesByBlock,
    };
    final items = buildNoteExportItems(
      blocks: widget.blocks,
      accent: widget.accent,
      title: widget.title,
      tasksById: widget.tasksById,
      drawingStrokesByBlock: drawingStrokesByBlock,
      includeTasks: widget.includeTasks,
      onWikiLinkTap: widget.onWikiLinkTap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(padding: const EdgeInsets.only(bottom: 16), child: item),
      ],
    );
  }
}

class _ExportTitle extends StatelessWidget {
  final String title;
  const _ExportTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: ySans(
            size: 26,
            weight: FontWeight.w700,
            letterSpacing: -0.4,
            color: yInk,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Container(width: double.infinity, height: 2, color: yInk),
      ],
    );
  }
}

class _MathItem extends StatelessWidget {
  final String latex;
  final Color accent;
  const _MathItem({required this.latex, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      child: Center(
        child: Math.tex(
          latex,
          mathStyle: MathStyle.display,
          textStyle: const TextStyle(fontSize: 22, color: yCream),
          onErrorFallback:
              (err) => Text(
                err.message,
                style: yMono(size: 11, color: yAmber2, tracking: 0.8),
              ),
        ),
      ),
    );
  }
}

class _BulletsItem extends StatelessWidget {
  final List<String> items;
  const _BulletsItem({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8, right: 10),
                  child: SizedBox(
                    width: 6,
                    height: 6,
                    child: ColoredBox(color: yInk),
                  ),
                ),
                Expanded(
                  child: Text(
                    it,
                    style: yBody(size: 14, color: yInk2, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DrawingItem extends StatelessWidget {
  final DrawingBlock block;
  final List<DrawingStroke>? strokes;
  const _DrawingItem({required this.block, this.strokes});

  @override
  Widget build(BuildContext context) {
    final data = DrawingData.fromJson(block.payloadJson());
    if (strokes != null) data.strokes = strokes!;
    final region =
        _strokesRegion(data.strokes) ?? Rect.fromLTWH(0, 0, 400, block.height);
    // Scale the drawing to fill the available width (the page is narrower than
    // the landscape editor), preserving aspect ratio so nothing is clipped.
    return SizedBox(
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: region.width / region.height,
        child: CustomPaint(
          painter: _FitDrawingPainter(strokes: data.strokes, region: region),
        ),
      ),
    );
  }
}

/// Bounding box of all strokes, padded so caps/joins near the edge aren't
/// clipped. Null when there are no strokes.
Rect? _strokesRegion(List<DrawingStroke> strokes) {
  Rect? acc;
  for (final s in strokes) {
    if (s.points.isEmpty) continue;
    final b = strokeBounds(s);
    acc = acc == null ? b : acc.expandToInclude(b);
  }
  return acc?.inflate(12);
}

class _FitDrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final Rect region;
  const _FitDrawingPainter({required this.strokes, required this.region});

  @override
  void paint(Canvas canvas, Size size) {
    if (region.width <= 0 || region.height <= 0) return;
    canvas.save();
    canvas.scale(size.width / region.width);
    canvas.translate(-region.left, -region.top);
    canvas.clipRect(region);
    for (final s in strokes) {
      drawStroke(canvas, s);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FitDrawingPainter old) =>
      old.strokes != strokes || old.region != region;
}

class _TasksItem extends StatelessWidget {
  final List<Task> tasks;
  const _TasksItem({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TAREAS',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const SizedBox(height: 8),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 8),
                    child: Icon(
                      task.status == TaskStatus.done
                          ? YuLiIcons.squareCheck
                          : YuLiIcons.square,
                      size: 18,
                      color: yInk,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task.content,
                      style:
                          task.status == TaskStatus.done
                              ? yBody(
                                size: 14,
                                color: yMuted,
                                height: 1.4,
                              ).copyWith(decoration: TextDecoration.lineThrough)
                              : yBody(size: 14, color: yInk2, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
