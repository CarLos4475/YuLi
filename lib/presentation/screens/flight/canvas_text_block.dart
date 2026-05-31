// Interactive markdown text block placed on a drawing canvas (whiteboard /
// notebook). Renders its [CanvasTextBlock.markdown] with the SAME engine as the
// note editor's text cells ([NoteMarkdownPreview]) so a chat message "sent to
// canvas" looks identical to a note. Geometry/resize mirrors the task block:
// content lays out at width `w/scale` (text reflow) and is uniformly scaled by
// a FittedBox up to `w`.

import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import 'note_block_widgets.dart' show NoteMarkdownPreview, fixMarkdownTables;
import 'note_cell_model.dart';

/// Default box width for a freshly inserted text block (scale 1.0). Kept small
/// so a fresh box is compact; grows via corner/side resize.
const double kCanvasTextBlockDefaultW = 220.0;

/// Minimum world-space width for a text block. Much smaller than a task block's
/// floor — the user often zooms in to write, so a large min feels huge.
const double kCanvasTextBlockMinW = 40.0;

class CanvasTextBlockOverlay extends StatefulWidget {
  final CanvasTextBlock block;
  final Color accent;

  /// True when a tap on the box opens the editor. True in lasso mode (when not
  /// selected) and in text mode; false while a drawing tool without palm-
  /// rejection is active or the block is lasso-selected / mid-gesture.
  final bool interactive;

  /// True in text mode: a one-finger drag on the box moves it (tap still edits).
  final bool movable;

  /// Persist the canvas DrawingData after the markdown changed.
  final Future<void> Function() onPersist;

  /// Rebuild the editor after the markdown / position changed (the block isn't
  /// a watched provider).
  final VoidCallback onChanged;

  /// Reports the block's natural height (in world px, after scaling) so the
  /// editor can keep [CanvasTextBlock.h] in sync for the lasso bounding box.
  final ValueChanged<double> onHeightMeasured;

  /// Text-mode drag: capture an undo snapshot at start, commit + persist at end.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const CanvasTextBlockOverlay({
    super.key,
    required this.block,
    required this.accent,
    required this.interactive,
    this.movable = false,
    required this.onPersist,
    required this.onChanged,
    required this.onHeightMeasured,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<CanvasTextBlockOverlay> createState() => _CanvasTextBlockOverlayState();
}

class _CanvasTextBlockOverlayState extends State<CanvasTextBlockOverlay> {
  final _contentKey = GlobalKey();
  OverlayEntry? _editorEntry;

  // Cache the parsed markdown widget: the overlay rebuilds on every editor
  // setState (e.g. once per frame during a lasso drag), and re-parsing markdown
  // each time froze the UI thread (ANR). Reusing the SAME widget instance lets
  // Flutter skip the subtree unless the source actually changed.
  String? _mdRawCache;
  Widget? _mdWidgetCache;

  Widget _markdownWidget(String raw) {
    if (_mdRawCache != raw || _mdWidgetCache == null) {
      _mdRawCache = raw;
      _mdWidgetCache = NoteMarkdownPreview(data: fixMarkdownTables(raw));
    }
    return _mdWidgetCache!;
  }

  @override
  void dispose() {
    _removeEditor();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CanvasTextBlockOverlay old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());
  }

  /// Reports the rendered footprint height: the content's natural height at the
  /// current layout width, times [CanvasTextBlock.scale].
  void _reportHeight() {
    final ctx = _contentKey.currentContext;
    if (ctx == null || !mounted) return;
    final hb = ctx.size?.height;
    if (hb == null || hb <= 0) return;
    final target = hb * widget.block.scale;
    if ((target - widget.block.h).abs() > 0.5) {
      widget.onHeightMeasured(target);
    }
  }

  // ─── Markdown editor, docked above the keyboard ───────────────────────────

  void _openEditor() {
    if (_editorEntry != null) return;
    final ctrl = TextEditingController(text: widget.block.markdown);
    final focus = FocusNode();
    _editorEntry = OverlayEntry(
        builder: (ctx) => _buildEditorBar(ctx, ctrl, focus));
    Overlay.of(context, rootOverlay: true).insert(_editorEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _removeEditor() {
    _editorEntry?.remove();
    _editorEntry = null;
  }

  Future<void> _saveEditor(String value) async {
    final t = value.trim();
    _removeEditor();
    if (t == widget.block.markdown) {
      if (mounted) setState(() {});
      return;
    }
    widget.block.markdown = t;
    await widget.onPersist();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Widget _buildEditorBar(
      BuildContext context, TextEditingController ctrl, FocusNode focus) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _saveEditor(ctrl.text),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: insets,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  color: yCream,
                  border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 16,
                            margin: const EdgeInsets.only(right: 8),
                            color: widget.accent,
                          ),
                          Text('// EDITAR TEXTO',
                              style: yMono(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  tracking: 1.4,
                                  color: yInk)),
                          const Spacer(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _saveEditor(ctrl.text),
                            child: Text('GUARDAR',
                                style: yMono(
                                    size: 10,
                                    weight: FontWeight.w700,
                                    tracking: 1.4,
                                    color: yInk)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: yCream,
                          border: Border.all(color: yInk, width: yLineMid),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: TextField(
                          controller: ctrl,
                          focusNode: focus,
                          maxLines: 8,
                          minLines: 3,
                          keyboardType: TextInputType.multiline,
                          style: yBody(size: 15, color: yInk, height: 1.45),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Escribe en markdown…',
                            hintStyle: yBody(size: 15, color: yMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());

    final scale = widget.block.scale;
    final contentWidth = scale > 0 ? widget.block.w / scale : widget.block.w;

    final Widget box = SizedBox(
      width: widget.block.w,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: contentWidth,
          child: KeyedSubtree(key: _contentKey, child: _buildCard()),
        ),
      ),
    );

    final angle = widget.block.rotation;
    if (angle == 0.0) return box;
    return Transform.rotate(
        angle: angle, alignment: Alignment.center, child: box);
  }

  Widget _buildCard() {
    final empty = widget.block.markdown.trim().isEmpty;
    final card = Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        borderRadius: BorderRadius.zero,
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: widget.accent, width: 6)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: empty
            ? Text('Toca para editar',
                style: yBody(
                    size: 14, color: yMuted.withValues(alpha: 0.7), height: 1.3))
            : _markdownWidget(widget.block.markdown),
      ),
    );

    if (!widget.interactive) return IgnorePointer(child: card);
    // Tap anywhere on the card opens the editor (easy to hit). In text mode a
    // one-finger drag moves the block; `delta` is in the canvas/world space of
    // the InteractiveViewer child, so it applies directly to x/y.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openEditor,
      onPanStart: widget.movable ? (_) => widget.onDragStart?.call() : null,
      onPanUpdate: widget.movable
          ? (d) {
              widget.block.x += d.delta.dx;
              widget.block.y += d.delta.dy;
              widget.onChanged();
            }
          : null,
      onPanEnd: widget.movable ? (_) => widget.onDragEnd?.call() : null,
      child: card,
    );
  }
}
