import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../providers/note_providers.dart';
import '../../utils/pdf_export.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/status_bar_flood.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import 'block_pdf_export_sheet.dart';
import 'block_insert_menu.dart';
import 'block_insert_panels.dart';
import 'canvas_export_sheet.dart';
import 'drawing_stroke_persistence.dart';
import 'format_toolbar.dart';
import 'note_block_widgets.dart';
import 'note_cell_model.dart';
import 'note_export_view.dart';
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
  final AiChatDockController _chatDock = AiChatDockController();

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
    _chatDock.dispose();
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
    final hasTasks = blocks.any(
      (b) => b is TareasBlock && b.taskIds.isNotEmpty,
    );
    final opts = await showBlockPdfExportSheet(
      context,
      accent: _accent,
      hasTasks: hasTasks,
    );
    if (opts == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportProgressDialog(accent: _accent),
    );

    try {
      final tasksById =
          opts.includeTasks
              ? await _loadExportTasks(blocks)
              : const <int, Task>{};
      final drawingStrokesByBlock = await _loadExportDrawingStrokes(blocks);
      if (!mounted) return;
      await exportNoteToPdf(
        context: context,
        title:
            _titleCtrl.text.trim().isEmpty
                ? 'Sin titulo'
                : _titleCtrl.text.trim(),
        blocks: blocks,
        accent: _accent,
        options: opts,
        tasksById: tasksById,
        drawingStrokesByBlock: drawingStrokesByBlock,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo exportar'),
          duration: Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<Map<int, Task>> _loadExportTasks(List<NoteBlock> blocks) async {
    final ids = <int>{
      for (final block in blocks)
        if (block is TareasBlock) ...block.taskIds,
    };
    if (ids.isEmpty) return const {};
    final repo = ref.read(taskRepositoryProvider);
    final entries = await Future.wait(
      ids.map((id) async => MapEntry(id, await repo.getById(id))),
    );
    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  Future<Map<int, List<DrawingStroke>>> _loadExportDrawingStrokes(
    List<NoteBlock> blocks,
  ) async {
    final ids = blocks.whereType<DrawingBlock>().map((b) => b.id).toList();
    if (ids.isEmpty) return const {};
    final repo = ref.read(drawingStrokeRepositoryProvider);
    final loaded = <int, List<DrawingStroke>>{};
    for (final id in ids) {
      final rows = await repo.getByBlock(id);
      if (rows.isNotEmpty) {
        loaded[id] = rows.map(strokeFromRecord).toList();
      }
    }
    return loaded;
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

  /// Wraps the editor in the chat dock scope + the sliding panel (sibling of the
  /// body, so opening/streaming never repaints the editor; its transparent area
  /// passes pointers through to the note).
  Widget _wrapWithChatDock(Widget child, {required bool linked}) {
    return AiChatDockScope(
      controller: _chatDock,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: AiChatDock(
              controller: _chatDock,
              session: ref.read(aiSessionProvider(widget.note.id)),
              accent: _accent,
              linked: linked,
            ),
          ),
        ],
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

    return _wrapWithChatDock(Scaffold(
      backgroundColor: yCream,
      body: StatusBarFlood(
        // Header is the note accent when expanded, cream2 when collapsed.
        color: _headerCollapsed ? yCream2 : _accent,
        child: SafeArea(
          top: false,
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
                      accent: _accent,
                      onBack: () => Navigator.pop(context),
                      onSave: _saveTitle,
                      onTogglePreview:
                          () => setState(() => _isPreview = !_isPreview),
                      onPdf: () => _exportPdf(blocks),
                      onExpand: () => setState(() => _headerCollapsed = false),
                    )
                  else ...[
                    ModeHeader(
                      mode: 'NOTA',
                      subtitle: _buildSubtitle(),
                      subtitleWidget: _buildNoteSubtitleWidget(linkedCards),
                      color: _accent,
                      onBack: () => Navigator.pop(context),
                      headerRight: _buildExpandedHeaderRight(
                        dirty: _dirty,
                        isPreview: _isPreview,
                        onSave: _saveTitle,
                        onTogglePreview:
                            () => setState(() => _isPreview = !_isPreview),
                        onLink: () => _showLinkToLab(spaces),
                        onPdf: () => _exportPdf(blocks),
                        onCollapse:
                            () => setState(() => _headerCollapsed = true),
                      ),
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
                              : ScrollConfiguration(
                                // Stylus draws on canvas blocks; only the finger
                                // scrolls the note (pen excluded from dragDevices),
                                // so a pen stroke never scrolls the list.
                                behavior: const _NoteScrollBehavior(),
                                child: ReorderableListView.builder(
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
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: BlockRouter(
                                          block: blocks[i],
                                          note: widget.note,
                                          folder: widget.folder,
                                          index: i,
                                          onTextBlockFocusChanged:
                                              _onTextBlockFocusChanged,
                                          onScrollLockChanged: (locked) {
                                            setState(
                                              () => _scrollLocked = locked,
                                            );
                                          },
                                        ),
                                      ),
                                  itemCount: blocks.length,
                                  onReorder: (a, b) => _onReorder(blocks, a, b),
                                ),
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
                    accent: _accent,
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
      ),
    ), linked: aiLinked);
  }

  Widget _buildPreview(List<NoteBlock> blocks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: NoteExportView(blocks: blocks, accent: _accent),
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

  String _buildSubtitle() {
    final title = _titleCtrl.text.trim();
    final base = 'MODO NOTAS · CARPETA · NOTA ABIERTA';
    return title.isEmpty ? base : '$base · ${title.toUpperCase()}';
  }

  /// Subtitle slot for the expanded [ModeHeader]. Holds the editable note
  /// title (cream text on the accent background) plus linked lab badges.
  Widget _buildNoteSubtitleWidget(List<KanbanCard> linkedCards) {
    final uniqueSpaceIds = linkedCards.map((c) => c.labSpaceId).toSet();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _titleCtrl,
            style: ySans(
              size: 22,
              weight: FontWeight.w700,
              letterSpacing: -0.6,
              color: yCream,
              height: 1.1,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintText: 'Sin título',
              hintStyle: ySans(
                size: 22,
                weight: FontWeight.w700,
                letterSpacing: -0.6,
                color: yCream.withValues(alpha: 0.55),
                height: 1.1,
              ),
            ),
            maxLines: 1,
          ),
        ),
        if (uniqueSpaceIds.isNotEmpty) ...[
          const SizedBox(width: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children:
                uniqueSpaceIds
                    .map((spaceId) => _LabBadge(spaceId: spaceId))
                    .toList(),
          ),
        ],
      ],
    );
  }

  /// Action icons rendered in the expanded [ModeHeader] headerRight, matching
  /// pizarra/cuaderno. Order: @carpeta, save, preview, link, PDF, AI, collapse.
  List<Widget> _buildExpandedHeaderRight({
    required bool dirty,
    required bool isPreview,
    required VoidCallback onSave,
    required VoidCallback onTogglePreview,
    required VoidCallback onLink,
    required VoidCallback onPdf,
    required VoidCallback onCollapse,
  }) {
    return [
      YBadge(
        label: '@${widget.folder.name}',
        bg: widget.folder.color,
        fg: yCream,
      ),
      _HeaderIcon(
        icon: YuLiIcons.check,
        fill: !dirty,
        color: dirty ? yAmber2 : yLab,
        onTap: onSave,
      ),
      _HeaderIcon(
        icon: isPreview ? YuLiIcons.pen : YuLiIcons.eye,
        fill: isPreview,
        color: yLab,
        onTap: onTogglePreview,
      ),
      _HeaderIcon(
        icon: YuLiIcons.infinity,
        fill: true,
        color: yLab,
        onTap: onLink,
      ),
      _HeaderIcon(
        icon: YuLiIcons.fileText,
        fill: true,
        color: yAmber,
        onTap: onPdf,
      ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCollapse,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
          ),
          child: const Icon(YuLiIcons.chevronUp, color: yInk, size: 18),
        ),
      ),
    ];
  }
}

// ─── Collapsed header ─────────────────────────────────────────────────────

class _CollapsedHeader extends StatelessWidget {
  final Folder folder;
  final TextEditingController titleCtrl;
  final bool dirty;
  final bool isPreview;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onTogglePreview;
  final VoidCallback onPdf;
  final VoidCallback onExpand;

  const _CollapsedHeader({
    required this.folder,
    required this.titleCtrl,
    required this.dirty,
    required this.isPreview,
    required this.accent,
    required this.onBack,
    required this.onSave,
    required this.onTogglePreview,
    required this.onPdf,
    required this.onExpand,
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
              child: const Icon(YuLiIcons.arrowLeft, color: yInk, size: 16),
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
          _HeaderIcon(
            icon: YuLiIcons.check,
            fill: !dirty,
            color: dirty ? yAmber2 : yLab,
            onTap: onSave,
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            icon: isPreview ? YuLiIcons.pen : YuLiIcons.eye,
            fill: isPreview,
            color: yLab,
            onTap: onTogglePreview,
          ),
          const SizedBox(width: 6),
          _HeaderIcon(
            icon: YuLiIcons.fileText,
            fill: true,
            color: yAmber,
            onTap: onPdf,
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
              child: const Icon(YuLiIcons.chevronDown, color: yInk, size: 18),
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
            const Icon(YuLiIcons.flaskConical, size: 10, color: yCream),
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

  const _HeaderIcon({
    required this.icon,
    this.fill = false,
    this.color = yCream,
    this.onTap,
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
          color: fill ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Icon(icon, size: 18, color: fill ? yCream : yInk),
      ),
    );
  }
}

/// Scroll behavior for the note's block list that EXCLUDES the stylus from its
/// drag devices. A pen over a drawing block draws (the block's canvas handles
/// it) instead of scrolling the note; the finger keeps scrolling normally.
class _NoteScrollBehavior extends MaterialScrollBehavior {
  const _NoteScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

// ─── Footer ───────────────────────────────────────────────────────────────

class _EditorFooter extends StatelessWidget {
  final List<NoteBlock> blocks;
  final int wordCount;
  final void Function(NoteBlockType) onAdd;
  final Color accent;

  const _EditorFooter({
    required this.blocks,
    required this.wordCount,
    required this.onAdd,
    required this.accent,
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
          const SizedBox(width: 12),
          // Scrollable so the add-block buttons stay reachable on narrower tablet
          // widths (portrait / split-screen) instead of overflowing the Row.
          // reverse:true keeps them right-aligned when there's room.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _AddBlockBtn(
                    icon: YuLiIcons.textInitial,
                    label: 'Texto',
                    color: accent,
                    onTap: () => onAdd(NoteBlockType.text),
                  ),
                  const SizedBox(width: 6),
                  _AddBlockBtn(
                    icon: YuLiIcons.sigma,
                    label: 'Math',
                    color: accent,
                    onTap: () => onAdd(NoteBlockType.math),
                  ),
                  const SizedBox(width: 6),
                  _AddBlockBtn(
                    icon: YuLiIcons.listChecks,
                    label: 'Lista',
                    color: accent,
                    onTap: () => onAdd(NoteBlockType.bullets),
                  ),
                  const SizedBox(width: 6),
                  _AddBlockBtn(
                    icon: YuLiIcons.squareCheck,
                    label: 'Tareas',
                    color: accent,
                    onTap: () => onAdd(NoteBlockType.tareas),
                  ),
                  const SizedBox(width: 6),
                  _AddBlockBtn(
                    icon: YuLiIcons.pencil,
                    label: 'Dibujo',
                    color: accent,
                    onTap: () => onAdd(NoteBlockType.drawing),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBlockBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _AddBlockBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
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
              decoration: BoxDecoration(color: color),
              child: Icon(icon, size: 12, color: yCream),
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
