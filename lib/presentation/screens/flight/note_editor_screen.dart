import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../providers/note_providers.dart';
import '../../utils/pdf_export.dart';
import '../../widgets/fight_panel.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/ai_link_badge.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import 'block_insert_menu.dart';
import 'block_insert_panels.dart';
import 'format_toolbar.dart';
import 'note_block_widgets.dart';
import 'note_cell_model.dart';
import 'drawing_cell.dart';
import 'ai_chat_sheet.dart';
import '../lab/lab_space_detail_screen.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final Folder folder;

  const NoteEditorScreen({super.key, required this.note, required this.folder});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleCtrl;
  Timer? _titleSaveTimer;
  bool _dirty = false;
  TextEditingController? _activeTextCtrl;
  TextEditingController? _lastTextCtrl;
  InsertPanelType? _activePanel;
  bool _isPreview = false;
  bool _scrollLocked = false;
  bool _headerCollapsed = true;

  Color get _accent => widget.note.color ?? widget.folder.color;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note.title ?? '');
    _titleCtrl.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleSaveTimer?.cancel();
    _saveTitle();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    if (!_dirty) setState(() => _dirty = true);
    _titleSaveTimer?.cancel();
    _titleSaveTimer = Timer(const Duration(seconds: 2), _saveTitle);
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleCtrl.text.trim();
    final currentTitle = widget.note.title?.trim() ?? '';
    if (newTitle == currentTitle) {
      if (mounted && _dirty) setState(() => _dirty = false);
      return;
    }
    final updated = widget.note.copyWith(title: newTitle);
    await ref.read(noteRepositoryProvider).update(updated);
    if (mounted) setState(() => _dirty = false);
  }

  /// Apply an AI-suggested title to the note's title field + persist.
  void _applyAiTitle(String title) {
    _titleCtrl.text = title;
    _titleCtrl.selection = TextSelection.collapsed(
      offset: _titleCtrl.text.length,
    );
    _saveTitle();
  }

  /// Open the AI chat for this note. The persisted anchor (if any) is loaded
  /// automatically by [AiChatSession]; no new context is injected here.
  void _openAiChat() {
    showAiChat(
      context,
      ref,
      noteId: widget.note.id,
      accent: _accent,
      onApplyTitle: _applyAiTitle,
    );
  }

  /// Explicitly push the current note content as the AI context anchor.
  /// If the note text is already contained in the persisted anchor, the
  /// chat simply opens without prompting. Otherwise it asks Añadir/Reemplazar.
  void _pushNoteContextToAi(List<NoteBlock> blocks) {
    String? ctx;
    try {
      ctx = _noteContext(blocks);
    } catch (_) {
      // If reading blocks fails (e.g. a locked drawing cell), fall back to
      // opening the chat without injecting new context.
    }
    if (ctx != null && ctx.isNotEmpty) {
      final session = ref.read(aiSessionProvider(widget.note.id));
      final anchor = session.anchor;
      // If the note content is already present in the anchor (with normalised
      // whitespace), skip injecting it again to avoid duplication.
      if (anchor != null &&
          anchor.isNotEmpty &&
          _normalise(anchor).contains(_normalise(ctx))) {
        showAiChat(
          context,
          ref,
          noteId: widget.note.id,
          accent: _accent,
          onApplyTitle: _applyAiTitle,
        );
        return;
      }
    }
    showAiChat(
      context,
      ref,
      noteId: widget.note.id,
      newContext: ctx,
      accent: _accent,
      onApplyTitle: _applyAiTitle,
    );
  }

  String _normalise(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  /// Flatten the note's textual cells into a plain-text context for the AI.
  /// Skips tasks and drawings.
  String _noteContext(List<NoteBlock> blocks) {
    final buf = StringBuffer();
    final title = _titleCtrl.text.trim();
    if (title.isNotEmpty) buf.writeln('# $title\n');
    for (final b in blocks) {
      if (b is TextBlock) {
        if (b.markdown.trim().isNotEmpty) buf.writeln('${b.markdown}\n');
      } else if (b is BulletsBlock) {
        for (final it in b.items) {
          if (it.trim().isNotEmpty) buf.writeln('- $it');
        }
        buf.writeln();
      } else if (b is MathBlock) {
        if (b.latex.trim().isNotEmpty) buf.writeln('\$\$${b.latex}\$\$\n');
      }
      // TareasBlock and DrawingBlock are intentionally skipped.
    }
    return buf.toString().trim();
  }

  Future<void> _addBlock(NoteBlockType type) async {
    Map<String, dynamic> payload;
    switch (type) {
      case NoteBlockType.text:
        payload = {'md': ''};
      case NoteBlockType.math:
        payload = {'latex': ''};
      case NoteBlockType.heading:
        payload = {'md': ''};
      case NoteBlockType.bullets:
        payload = {
          'items': [''],
        };
      case NoteBlockType.tareas:
        payload = {'taskIds': <int>[]};
      case NoteBlockType.drawing:
        payload = {'h': 240, 's': []};
    }
    await ref
        .read(noteBlockRepositoryProvider)
        .insertAtEnd(widget.note.id, type, payload: payload);
  }

  Future<void> _onReorder(
    List<NoteBlock> blocks,
    int oldIdx,
    int newIdx,
  ) async {
    final ids = blocks.map((b) => b.id).toList();
    final id = ids.removeAt(oldIdx);
    ids.insert(newIdx > oldIdx ? newIdx - 1 : newIdx, id);
    await ref.read(noteBlockRepositoryProvider).reorder(widget.note.id, ids);
  }

  Future<void> _exportPdf(List<NoteBlock> blocks) async {
    await exportNoteToPdf(
      context: context,
      title:
          _titleCtrl.text.trim().isEmpty
              ? 'Sin título'
              : _titleCtrl.text.trim(),
      blocks: blocks,
    );
  }

  void _onTextBlockFocusChanged(TextEditingController? ctrl) {
    setState(() {
      _activeTextCtrl = ctrl;
      if (ctrl != null) _lastTextCtrl = ctrl;
    });
  }

  void _insertSyntax(String syntax) {
    final ctrl = _lastTextCtrl ?? _activeTextCtrl;
    if (ctrl == null) return;
    final cursor = ctrl.selection.baseOffset;
    final text = ctrl.text;
    final newText =
        cursor >= 0
            ? text.substring(0, cursor) + syntax + text.substring(cursor)
            : text + syntax;
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: (cursor >= 0 ? cursor : text.length) + syntax.length,
      ),
    );
  }

  void _showInsertMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => BlockInsertMenu(
            onDirectInsert: (syntax) => _insertSyntax(syntax),
            onOpenPanel: (type) => setState(() => _activePanel = type),
          ),
    );
  }

  void _showFightPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.2,
            maxChildSize: 0.9,
            builder:
                (ctx, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: yCream,
                    border: Border(
                      top: BorderSide(color: yBorderStrong, width: yLineMid),
                    ),
                  ),
                  child: FightPanel(
                    folderId: widget.folder.id,
                    scrollController: scrollController,
                    onTapTask: (task) async {
                      _insertSyntax('\n- [ ] ${task.content}\n');
                      await setTaskDone(ref, task.id, done: true);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tarea insertada como checklist y completada',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ),
          ),
    );
  }

  Future<void> _showLinkToLab(List<LabSpace> spaces) async {
    if (spaces.isEmpty) return;
    final picked = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => _LabPickerDialog(spaces: spaces),
    );
    if (picked == null) return;
    final kanbanRepo = ref.read(kanbanCardRepositoryProvider);
    final labRepo = ref.read(labSpaceRepositoryProvider);
    final columns = await labRepo.getColumns(picked.id);
    if (columns.isEmpty) return;
    final backlog = columns.firstWhere(
      (c) => c.name == 'Backlog' || c.name.toLowerCase() == 'backlog',
      orElse:
          () => columns.firstWhere(
            (c) => !c.isTerminal && !c.isExpired,
            orElse: () => columns.first,
          ),
    );
    await kanbanRepo.create(
      labSpaceId: picked.id,
      columnId: backlog.id,
      title:
          _titleCtrl.text.trim().isEmpty
              ? 'Nota sin título'
              : _titleCtrl.text.trim(),
      sourceNoteId: widget.note.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Vinculada a ${picked.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks =
        ref.watch(noteBlocksProvider(widget.note.id)).valueOrNull ?? [];
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];
    final linkedCards =
        ref.watch(kanbanCardsByNoteProvider(widget.note.id)).valueOrNull ?? [];
    final hasAiKey = ref.watch(aiHasKeyProvider).valueOrNull ?? false;
    final aiLinked =
        hasAiKey &&
        (widget.note.kind == NoteKind.block
            ? blocks.isNotEmpty
            : (ref
                    .watch(canvasContextSourcesProvider(widget.note.id))
                    .valueOrNull
                    ?.isNotEmpty ??
                false));
    // Pin the per-note AI session to this view's lifetime (discarded on leave).
    ref.watch(aiSessionProvider(widget.note.id));

    return Scaffold(
      backgroundColor: yCream,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (_headerCollapsed)
                  _CollapsedHeader(
                    folder: widget.folder,
                    titleCtrl: _titleCtrl,
                    dirty: _dirty,
                    isPreview: _isPreview,
                    hasAiKey: hasAiKey,
                    aiLinked: aiLinked,
                    accent: _accent,
                    onBack: () => Navigator.pop(context),
                    onSave: _saveTitle,
                    onTogglePreview:
                        () => setState(() => _isPreview = !_isPreview),
                    onExpand: () => setState(() => _headerCollapsed = false),
                    onAi: () => _openAiChat(),
                    onAiLongPress: () => _pushNoteContextToAi(blocks),
                  )
                else ...[
                  ModeHeader(
                    mode: 'NOTA',
                    subtitle: 'MODO NOTAS · CARPETA · NOTA ABIERTA',
                    color: _accent,
                    onBack: () => Navigator.pop(context),
                    headerRight: [
                      YBadge(
                        label: '@${widget.folder.name}',
                        bg: widget.folder.color,
                        fg: yCream,
                      ),
                      AiLinkBadge(
                        active: aiLinked,
                        color: _accent,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: hasAiKey ? _openAiChat : null,
                          child: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hasAiKey ? _accent : yMuted,
                              border: Border.all(
                                color: yBorderStrong,
                                width: yLineMid,
                              ),
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              color: hasAiKey ? yCream : yCream2,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _headerCollapsed = true),
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: yCream,
                            border: Border.all(
                              color: yBorderStrong,
                              width: yLineMid,
                            ),
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: yInk,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _NoteHeroHeader(
                    folder: widget.folder,
                    titleCtrl: _titleCtrl,
                    dirty: _dirty,
                    lastEdit: widget.note.updatedAt,
                    wordCount: _countWords(blocks),
                    linkedCards: linkedCards,
                    accent: _accent,
                    onSave: _saveTitle,
                    onImage: () => _addBlock(NoteBlockType.drawing),
                    onLink: () => _showLinkToLab(spaces),
                    onPdf: () => _exportPdf(blocks),
                    onFight: _showFightPanel,
                    onTogglePreview:
                        () => setState(() => _isPreview = !_isPreview),
                    isPreview: _isPreview,
                  ),
                ],
                Expanded(
                  child: Container(
                    color: yCream,
                    child:
                        blocks.isEmpty
                            ? _EmptyState(onAdd: _addBlock, accent: _accent)
                            : _isPreview
                            ? _buildPreview(blocks)
                            : ReorderableListView.builder(
                              physics:
                                  _scrollLocked
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              buildDefaultDragHandles: false,
                              proxyDecorator:
                                  (child, _, _) => Material(
                                    color: Colors.transparent,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _accent,
                                          width: yLineThin,
                                        ),
                                      ),
                                      child: child,
                                    ),
                                  ),
                              itemBuilder:
                                  (ctx, i) => Padding(
                                    key: ValueKey('block_${blocks[i].id}'),
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: BlockRouter(
                                      block: blocks[i],
                                      note: widget.note,
                                      folder: widget.folder,
                                      index: i,
                                      onTextBlockFocusChanged:
                                          _onTextBlockFocusChanged,
                                      onScrollLockChanged: (locked) {
                                        setState(() => _scrollLocked = locked);
                                      },
                                    ),
                                  ),
                              itemCount: blocks.length,
                              onReorder: (a, b) => _onReorder(blocks, a, b),
                            ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child:
                      _activeTextCtrl != null && !_isPreview
                          ? FormatToolbar(
                            controller: _activeTextCtrl,
                            onOpenInsertMenu: _showInsertMenu,
                            accent: _accent,
                          )
                          : const SizedBox.shrink(),
                ),
                _EditorFooter(
                  blocks: blocks,
                  wordCount: _countWords(blocks),
                  onAdd: _addBlock,
                ),
              ],
            ),
            if (_activePanel != null)
              Positioned.fill(
                child: InsertPanelOverlay(
                  type: _activePanel!,
                  noteId: widget.note.id,
                  onInsert: (md) {
                    _insertSyntax(md);
                    setState(() => _activePanel = null);
                  },
                  onClose: () => setState(() => _activePanel = null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(List<NoteBlock> blocks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: switch (b) {
                TextBlock t =>
                  t.markdown.isNotEmpty
                      ? NoteMarkdownPreview(data: t.markdown)
                      : const SizedBox.shrink(),
                MathBlock m =>
                  m.latex.isNotEmpty
                      ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: widget.folder.color,
                          border: Border.all(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                          boxShadow: const [
                            BoxShadow(color: yInk, offset: Offset(3, 3)),
                          ],
                        ),
                        child: Center(
                          child: Math.tex(
                            m.latex,
                            mathStyle: MathStyle.display,
                            textStyle: const TextStyle(
                              fontSize: 22,
                              color: yCream,
                            ),
                            onErrorFallback:
                                (err) => Text(
                                  err.message,
                                  style: yMono(
                                    size: 11,
                                    color: yAmber2,
                                    tracking: 0.8,
                                  ),
                                ),
                          ),
                        ),
                      )
                      : const SizedBox.shrink(),
                BulletsBlock bl => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final it in bl.items)
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
                                style: yBody(
                                  size: 14,
                                  color: yInk2,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                TareasBlock _ => const SizedBox.shrink(),
                DrawingBlock d => SizedBox(
                  height: d.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: DrawingPreviewPainter(
                      strokes: DrawingData.fromJson(d.payloadJson()).strokes,
                    ),
                    size: Size.infinite,
                  ),
                ),
              },
            ),
        ],
      ),
    );
  }

  int _countWords(List<NoteBlock> blocks) {
    int n = 0;
    for (final b in blocks) {
      switch (b) {
        case TextBlock t:
          n += _wc(t.markdown);
        case MathBlock _:
          break;
        case BulletsBlock bl:
          for (final it in bl.items) {
            n += _wc(it);
          }
        case TareasBlock _:
          break;
        case DrawingBlock _:
          break;
      }
    }
    return n;
  }

  int _wc(String s) =>
      s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;
}

// ─── Collapsed header ─────────────────────────────────────────────────────

class _CollapsedHeader extends StatelessWidget {
  final Folder folder;
  final TextEditingController titleCtrl;
  final bool dirty;
  final bool isPreview;
  final bool hasAiKey;
  final bool aiLinked;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onTogglePreview;
  final VoidCallback onExpand;
  final VoidCallback onAi;
  final VoidCallback? onAiLongPress;

  const _CollapsedHeader({
    required this.folder,
    required this.titleCtrl,
    required this.dirty,
    required this.isPreview,
    required this.hasAiKey,
    required this.aiLinked,
    required this.accent,
    required this.onBack,
    required this.onSave,
    required this.onTogglePreview,
    required this.onExpand,
    required this.onAi,
    this.onAiLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(Icons.arrow_back, color: yInk, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 4, height: 24, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titleCtrl.text.isEmpty ? 'Sin titulo' : titleCtrl.text,
              style: ySans(
                size: 16,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
                color: accent,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          AiLinkBadge(
            active: aiLinked,
            color: accent,
            child: _HeaderIcon(
              icon: Icons.auto_awesome,
              fill: hasAiKey,
              color: hasAiKey ? accent : yMuted,
              onTap: hasAiKey ? onAi : null,
              onLongPress: hasAiKey ? onAiLongPress : null,
            ),
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            icon: Icons.check,
            fill: !dirty,
            color: dirty ? yAmber2 : yLab,
            onTap: onSave,
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            icon: isPreview ? Icons.edit_outlined : Icons.visibility_outlined,
            fill: isPreview,
            color: yLab,
            onTap: onTogglePreview,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onExpand,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: yInk,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────

class _NoteHeroHeader extends ConsumerWidget {
  final Folder folder;
  final TextEditingController titleCtrl;
  final bool dirty;
  final DateTime lastEdit;
  final int wordCount;
  final List<KanbanCard> linkedCards;
  final VoidCallback onSave;
  final VoidCallback onImage;
  final VoidCallback onLink;
  final VoidCallback onPdf;
  final VoidCallback onFight;
  final VoidCallback onTogglePreview;
  final bool isPreview;
  final Color accent;

  const _NoteHeroHeader({
    required this.folder,
    required this.titleCtrl,
    required this.dirty,
    required this.lastEdit,
    required this.wordCount,
    required this.linkedCards,
    required this.onSave,
    required this.onImage,
    required this.onLink,
    required this.onPdf,
    required this.onFight,
    required this.onTogglePreview,
    required this.isPreview,
    required this.accent,
  });

  String _lastEditLabel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return 'hace ${(diff.inDays / 7).floor()} sem';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uniqueSpaceIds = linkedCards.map((c) => c.labSpaceId).toSet();

    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(
          bottom: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 6, color: accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '> ${folder.name.toUpperCase()} / NOTA · ED. ${_lastEditLabel(lastEdit).toUpperCase()} · $wordCount PALABRAS',
                            style: yMono(
                              size: 10,
                              weight: FontWeight.w700,
                              tracking: 1.4,
                              color: yMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: titleCtrl,
                            style: ySans(
                              size: 28,
                              weight: FontWeight.w700,
                              letterSpacing: -1,
                              color: accent,
                              height: 1.1,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              hintText: 'Sin título',
                              hintStyle: ySans(
                                size: 28,
                                weight: FontWeight.w700,
                                letterSpacing: -1,
                                color: yMuted,
                                height: 1.1,
                              ),
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _HeaderIcon(
                      icon: Icons.check,
                      fill: !dirty,
                      color: dirty ? yAmber2 : yLab,
                      onTap: onSave,
                    ),
                    const SizedBox(width: 6),
                    _HeaderIcon(
                      icon:
                          isPreview
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                      fill: isPreview,
                      color: yLab,
                      onTap: onTogglePreview,
                    ),
                    const SizedBox(width: 6),
                    _HeaderIcon(
                      icon: Icons.flash_on,
                      fill: true,
                      color: yFight,
                      onTap: onFight,
                    ),
                    const SizedBox(width: 6),
                    _HeaderIcon(icon: Icons.image_outlined, onTap: onImage),
                    const SizedBox(width: 6),
                    _HeaderIcon(
                      icon: Icons.all_inclusive,
                      fill: true,
                      color: accent,
                      onTap: onLink,
                    ),
                    const SizedBox(width: 6),
                    _HeaderIcon(
                      icon: Icons.picture_as_pdf,
                      fill: true,
                      color: yAmber,
                      onTap: onPdf,
                    ),
                  ],
                ),
                if (uniqueSpaceIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        uniqueSpaceIds
                            .map((spaceId) => _LabBadge(spaceId: spaceId))
                            .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LabBadge extends ConsumerWidget {
  final int spaceId;
  const _LabBadge({required this.spaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceAsync = ref.watch(labSpaceByIdProvider(spaceId));
    final space = spaceAsync.valueOrNull;
    if (space == null || !space.isActive) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LabSpaceDetailScreen(space: space)),
          (route) => route.isFirst,
        );
        ref.read(currentModeProvider.notifier).state = AppMode.lab;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: space.accentColor,
          border: Border.all(color: yBorderStrong, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_outlined, size: 10, color: yCream),
            const SizedBox(width: 4),
            Text(
              space.name.toUpperCase(),
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                color: yCream,
                tracking: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final bool fill;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _HeaderIcon({
    required this.icon,
    this.fill = false,
    this.color = yCream,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Icon(icon, size: 18, color: fill ? yCream : yInk),
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────

class _EditorFooter extends StatelessWidget {
  final List<NoteBlock> blocks;
  final int wordCount;
  final void Function(NoteBlockType) onAdd;

  const _EditorFooter({
    required this.blocks,
    required this.wordCount,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          Text(
            '${blocks.length} BLOQUES · $wordCount PALABRAS',
            style: yMono(
              size: 10,
              weight: FontWeight.w700,
              tracking: 1.4,
              color: yMuted,
            ),
          ),
          const Spacer(),
          _AddBlockBtn(
            glyph: 'Tt',
            label: 'Texto',
            onTap: () => onAdd(NoteBlockType.text),
          ),
          const SizedBox(width: 6),
          _AddBlockBtn(
            glyph: '∑',
            label: 'Math',
            onTap: () => onAdd(NoteBlockType.math),
          ),
          const SizedBox(width: 6),
          _AddBlockBtn(
            glyph: '•',
            label: 'Lista',
            onTap: () => onAdd(NoteBlockType.bullets),
          ),
          const SizedBox(width: 6),
          _AddBlockBtn(
            glyph: '☑',
            label: 'Tareas',
            onTap: () => onAdd(NoteBlockType.tareas),
          ),
          const SizedBox(width: 6),
          _AddBlockBtn(
            glyph: '✎',
            label: 'Dibujo',
            onTap: () => onAdd(NoteBlockType.drawing),
          ),
        ],
      ),
    );
  }
}

class _AddBlockBtn extends StatelessWidget {
  final String glyph;
  final String label;
  final VoidCallback onTap;

  const _AddBlockBtn({
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 7),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: yInk),
              child: Text(
                glyph,
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 0,
                  color: yCream,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '+ $label',
              style: yBody(
                size: 12,
                weight: FontWeight.w700,
                color: yInk,
              ).copyWith(letterSpacing: -0.1),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final void Function(NoteBlockType) onAdd;
  final Color accent;
  const _EmptyState({required this.onAdd, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NOTA VACÍA',
              style: yMono(size: 11, color: yMuted, tracking: 1.6),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un bloque con los botones del pie',
              style: yBody(size: 13, color: yMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onAdd(NoteBlockType.text),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  border: Border.all(color: yBorderStrong, width: yLineMid),
                ),
                child: Text(
                  '+ EMPEZAR CON TEXTO',
                  style: yBody(
                    size: 12,
                    weight: FontWeight.w700,
                    color: yCream,
                  ).copyWith(letterSpacing: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Lab picker dialog ────────────────────────────────────────────────────

class _LabPickerDialog extends StatelessWidget {
  final List<LabSpace> spaces;
  const _LabPickerDialog({required this.spaces});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vincular a LAB',
              style: ySans(size: 20, weight: FontWeight.w700, color: yInk),
            ),
            const SizedBox(height: 12),
            for (final s in spaces)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, color: s.accentColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.name,
                          style: ySans(size: 16, color: yInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
