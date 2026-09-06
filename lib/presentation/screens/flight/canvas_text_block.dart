// Interactive markdown text block placed on a drawing canvas (whiteboard /
// notebook). Renders its [CanvasTextBlock.markdown] with the SAME engine as the
// note editor's text cells ([NoteMarkdownPreview]) so a chat message "sent to
// canvas" looks identical to a note. Geometry/resize mirrors the task block:
// content lays out at width `w/scale` (text reflow) and is uniformly scaled by
// a FittedBox up to `w`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart';
import '../../providers/flight_workspace_providers.dart';
import '../../widgets/yuli_design.dart';
import 'flight_wiki_links.dart';
import 'flight_wiki_suggestions.dart';
import 'note_block_widgets.dart' show NoteMarkdownPreview, fixMarkdownTables;
import 'note_cell_model.dart';

/// Default box width for a freshly inserted text block (scale 1.0). Kept small
/// so a fresh box is compact; grows via corner/side resize.
const double kCanvasTextBlockDefaultW = 220.0;

/// Minimum world-space width for a text block. Much smaller than a task block's
/// floor — the user often zooms in to write, so a large min feels huge.
const double kCanvasTextBlockMinW = 40.0;

class CanvasTextBlockOverlay extends ConsumerStatefulWidget {
  final CanvasTextBlock block;
  final Color accent;
  final int? sourceNoteId;
  final int? sourceCanvasBlockId;
  final Future<List<FlightWorkspaceTarget>> Function(String query)?
  wikiTargetSearch;

  /// True when a tap on the box opens the editor. True in lasso mode (when not
  /// selected) and in text mode; false while a drawing tool without palm-
  /// rejection is active or the block is lasso-selected / mid-gesture. Wiki
  /// labels remain available by double tap even when this is false.
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
  final ValueChanged<String>? onWikiLinkTap;

  const CanvasTextBlockOverlay({
    super.key,
    required this.block,
    required this.accent,
    this.sourceNoteId,
    this.sourceCanvasBlockId,
    this.wikiTargetSearch,
    required this.interactive,
    this.movable = false,
    required this.onPersist,
    required this.onChanged,
    required this.onHeightMeasured,
    this.onDragStart,
    this.onDragEnd,
    this.onWikiLinkTap,
  });

  @override
  ConsumerState<CanvasTextBlockOverlay> createState() =>
      _CanvasTextBlockOverlayState();
}

class _CanvasTextBlockOverlayState
    extends ConsumerState<CanvasTextBlockOverlay> {
  final _contentKey = GlobalKey();
  OverlayEntry? _editorEntry;
  TextEditingController? _editorController;
  FocusNode? _editorFocus;
  _CanvasWikiDraft? _wikiDraft;
  Future<List<FlightWorkspaceTarget>>? _wikiMatches;

  // Cache the parsed markdown widget: the overlay rebuilds on every editor
  // setState (e.g. once per frame during a lasso drag), and re-parsing markdown
  // each time froze the UI thread (ANR). Reusing the SAME widget instance lets
  // Flutter skip the subtree unless the source actually changed.
  String? _mdRawCache;
  Widget? _mdWidgetCache;

  Widget _markdownWidget(String raw) {
    if (_mdRawCache != raw || _mdWidgetCache == null) {
      _mdRawCache = raw;
      _mdWidgetCache = NoteMarkdownPreview(
        data: fixMarkdownTables(raw),
        tight: true,
        accent: widget.accent,
        onWikiLinkTap: widget.onWikiLinkTap,
      );
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
    _editorController = ctrl;
    _editorFocus = focus;
    ctrl.addListener(_refreshWikiDraft);
    focus.addListener(_refreshWikiDraft);
    _editorEntry = OverlayEntry(
      builder: (ctx) => _buildEditorBar(ctx, ctrl, focus),
    );
    Overlay.of(context, rootOverlay: true).insert(_editorEntry!);
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void _removeEditor() {
    _editorEntry?.remove();
    _editorEntry = null;
    _editorController?.removeListener(_refreshWikiDraft);
    _editorFocus?.removeListener(_refreshWikiDraft);
    _editorController?.dispose();
    _editorFocus?.dispose();
    _editorController = null;
    _editorFocus = null;
    _wikiDraft = null;
    _wikiMatches = null;
  }

  void _refreshWikiDraft() {
    final ctrl = _editorController;
    final focus = _editorFocus;
    _CanvasWikiDraft? next;
    if (ctrl != null && focus?.hasFocus == true) {
      final selection = ctrl.selection;
      if (selection.isValid && selection.isCollapsed) {
        final before = ctrl.text.substring(0, selection.extentOffset);
        final start = before.lastIndexOf('[[');
        if (start >= 0) {
          final query = before.substring(start + 2);
          if (!query.contains(']]') &&
              !query.contains('\n') &&
              query.length <= 120) {
            next = _CanvasWikiDraft(
              start: start,
              end: selection.extentOffset,
              query: query,
            );
          }
        }
      }
    }
    if (next == _wikiDraft) return;
    _wikiDraft = next;
    final sourceNoteId = widget.sourceNoteId;
    final targetSearch = widget.wikiTargetSearch;
    _wikiMatches =
        next == null
            ? null
            : targetSearch != null
            ? targetSearch(next.query)
            : sourceNoteId == null
            ? null
            : findFlightWikiTargets(
              ref,
              sourceNoteId: sourceNoteId,
              query: next.query,
            );
    _editorEntry?.markNeedsBuild();
  }

  String? _replaceWikiDraft(String label) {
    final draft = _wikiDraft;
    final ctrl = _editorController;
    if (draft == null || ctrl == null || draft.end > ctrl.text.length) {
      return null;
    }
    final clean = label.replaceAll(RegExp(r'[\[\]\r\n]'), ' ').trim();
    final replacement = '[[$clean]]';
    final updated = ctrl.text.replaceRange(draft.start, draft.end, replacement);
    ctrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: draft.start + replacement.length,
      ),
    );
    _wikiDraft = null;
    _wikiMatches = null;
    return updated;
  }

  Future<void> _commitWikiTarget(FlightWorkspaceTarget target) async {
    final updated = _replaceWikiDraft(target.label);
    if (updated == null) return;
    await _saveEditor(updated);
    if (!mounted) return;
    widget.onWikiLinkTap?.call(target.label);
  }

  Future<void> _commitCreatedWikiTarget(FlightWorkspaceTarget target) async {
    final updated = _replaceWikiDraft(target.label);
    if (updated == null) return;
    final trimmed = updated.trim();
    if (trimmed != widget.block.markdown) {
      widget.block.markdown = trimmed;
      await widget.onPersist();
      widget.onChanged();
    }
    if (!mounted) return;
    _editorEntry?.markNeedsBuild();
    setState(() {});
  }

  Future<void> _createWikiTarget(NoteKind kind) async {
    final draft = _wikiDraft;
    final sourceNoteId = widget.sourceNoteId;
    if (draft == null || sourceNoteId == null || draft.query.trim().isEmpty) {
      return;
    }
    final target = await resolveFlightWikiTarget(
      ref,
      sourceNoteId: sourceNoteId,
      label: draft.query,
      createKind: kind,
      sourceCanvasBlockId: widget.sourceCanvasBlockId,
    );
    if (target == null || !mounted) return;
    await _commitCreatedWikiTarget(target);
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
    BuildContext context,
    TextEditingController ctrl,
    FocusNode focus,
  ) {
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
                  border: Border(
                    top: BorderSide(color: yBorderStrong, width: yLineHeavy),
                  ),
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
                          Text(
                            '> EDITAR TEXTO',
                            style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: yInk,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _saveEditor(ctrl.text),
                            child: Text(
                              'GUARDAR',
                              style: yMono(
                                size: 10,
                                weight: FontWeight.w700,
                                tracking: 1.4,
                                color: yInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: yCream,
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
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
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: 'Escribe en markdown…',
                            hintStyle: yBody(size: 15, color: yMuted),
                          ),
                        ),
                      ),
                      if (_wikiDraft != null && _wikiMatches != null) ...[
                        const SizedBox(height: 6),
                        FlightWikiLinkSuggestions(
                          query: _wikiDraft!.query,
                          matches: _wikiMatches!,
                          accent: widget.accent,
                          onSelect: (target) {
                            unawaited(_commitWikiTarget(target));
                          },
                          onCreate: (kind) {
                            unawaited(_createWikiTarget(kind));
                          },
                        ),
                      ],
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
      angle: angle,
      alignment: Alignment.center,
      child: box,
    );
  }

  Widget _buildCard() {
    final empty = widget.block.markdown.trim().isEmpty;
    final card = Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        borderRadius: BorderRadius.zero,
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: widget.accent, width: 6)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child:
            empty
                ? Text(
                  'Toca para editar',
                  style: yBody(
                    size: 14,
                    color: yMuted.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                )
                : _markdownWidget(widget.block.markdown),
      ),
    );

    if (!widget.interactive) return card;
    // Tap anywhere on the card opens the editor (easy to hit). In text mode a
    // one-finger drag moves the block; `delta` is in the canvas/world space of
    // the InteractiveViewer child, so it applies directly to x/y.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openEditor,
      onPanStart: widget.movable ? (_) => widget.onDragStart?.call() : null,
      onPanUpdate:
          widget.movable
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

class _CanvasWikiDraft {
  final int start;
  final int end;
  final String query;

  const _CanvasWikiDraft({
    required this.start,
    required this.end,
    required this.query,
  });

  @override
  bool operator ==(Object other) =>
      other is _CanvasWikiDraft &&
      other.start == start &&
      other.end == end &&
      other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);
}
