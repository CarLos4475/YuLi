import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../utils/pdf_export.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import 'note_block_widgets.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note note;
  final Folder folder;

  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.folder,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleCtrl;
  Timer? _titleSaveTimer;
  bool _dirty = false;

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

  Future<void> _addBlock(NoteBlockType type) async {
    Map<String, dynamic> payload;
    switch (type) {
      case NoteBlockType.text:
        payload = {'md': ''};
      case NoteBlockType.math:
        payload = {'latex': ''};
      case NoteBlockType.heading:
        payload = {'level': 2, 'text': ''};
      case NoteBlockType.bullets:
        payload = {
          'items': ['']
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

  Future<void> _onReorder(List<NoteBlock> blocks, int oldIdx, int newIdx) async {
    final ids = blocks.map((b) => b.id).toList();
    final id = ids.removeAt(oldIdx);
    ids.insert(newIdx > oldIdx ? newIdx - 1 : newIdx, id);
    await ref
        .read(noteBlockRepositoryProvider)
        .reorder(widget.note.id, ids);
  }

  Future<void> _exportPdf(List<NoteBlock> blocks) async {
    final md = _blocksToMarkdown(blocks);
    await exportNoteToPdf(
      context: context,
      title: _titleCtrl.text.trim().isEmpty
          ? 'Sin título'
          : _titleCtrl.text.trim(),
      content: md,
    );
  }

  String _blocksToMarkdown(List<NoteBlock> blocks) {
    final buf = StringBuffer();
    for (final b in blocks) {
      switch (b) {
        case TextBlock t:
          buf.writeln(t.markdown);
        case MathBlock m:
          buf.writeln('\$\$${m.latex}\$\$');
        case HeadingBlock h:
          buf.writeln('${'#' * h.level} ${h.text}');
        case BulletsBlock bl:
          for (final it in bl.items) {
            buf.writeln('- $it');
          }
        case TareasBlock _:
          // Skipped in PDF: tasks live as entities, not markdown.
          continue;
        case DrawingBlock _:
          buf.writeln('[dibujo]');
      }
      buf.writeln();
    }
    return buf.toString();
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
      orElse: () => columns.first,
    );
    await kanbanRepo.create(
      labSpaceId: picked.id,
      columnId: backlog.id,
      title: _titleCtrl.text.trim().isEmpty
          ? 'Nota sin título'
          : _titleCtrl.text.trim(),
      sourceNoteId: widget.note.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Vinculada a ${picked.name}'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(noteBlocksProvider(widget.note.id)).valueOrNull ?? [];
    final spaces = ref.watch(activeLabSpacesProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: yCream,
      body: SafeArea(
        child: Column(
          children: [
            ModeHeader(
              mode: 'FLIGHT',
              subtitle: 'MODO NOTAS · CARPETA · NOTA ABIERTA',
              color: yFlight,
              onBack: () => Navigator.pop(context),
              headerRight: [
                YBadge(
                  label: '@${widget.folder.name}',
                  bg: widget.folder.color,
                  fg: yCream,
                ),
                IconSquareBtn(icon: Icons.help_outline),
              ],
            ),
            _NoteHeroHeader(
              folder: widget.folder,
              titleCtrl: _titleCtrl,
              dirty: _dirty,
              lastEdit: widget.note.updatedAt,
              wordCount: _countWords(blocks),
              onSave: _saveTitle,
              onImage: () => _addBlock(NoteBlockType.drawing),
              onLink: () => _showLinkToLab(spaces),
              onPdf: () => _exportPdf(blocks),
            ),
            Expanded(
              child: Container(
                color: yCream,
                child: blocks.isEmpty
                    ? _EmptyState(onAdd: _addBlock)
                    : ReorderableListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        proxyDecorator: (child, _, _) => Material(
                          color: Colors.transparent,
                          child: child,
                        ),
                        itemBuilder: (ctx, i) => Padding(
                          key: ValueKey('block_${blocks[i].id}'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: BlockRouter(
                            block: blocks[i],
                            note: widget.note,
                            folder: widget.folder,
                            index: i,
                          ),
                        ),
                        itemCount: blocks.length,
                        onReorder: (a, b) => _onReorder(blocks, a, b),
                      ),
              ),
            ),
            _EditorFooter(
              blocks: blocks,
              wordCount: _countWords(blocks),
              onAdd: _addBlock,
            ),
          ],
        ),
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
        case HeadingBlock h:
          n += _wc(h.text);
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

// ─── Hero header ──────────────────────────────────────────────────────────

class _NoteHeroHeader extends StatelessWidget {
  final Folder folder;
  final TextEditingController titleCtrl;
  final bool dirty;
  final DateTime lastEdit;
  final int wordCount;
  final VoidCallback onSave;
  final VoidCallback onImage;
  final VoidCallback onLink;
  final VoidCallback onPdf;

  const _NoteHeroHeader({
    required this.folder,
    required this.titleCtrl,
    required this.dirty,
    required this.lastEdit,
    required this.wordCount,
    required this.onSave,
    required this.onImage,
    required this.onLink,
    required this.onPdf,
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
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 6, color: folder.color),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '// ${folder.name.toUpperCase()} / NOTA · ED. ${_lastEditLabel(lastEdit).toUpperCase()} · $wordCount PALABRAS',
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
                          color: folder.color,
                          height: 1.1,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
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
                _HeaderIcon(icon: Icons.image_outlined, onTap: onImage),
                const SizedBox(width: 6),
                _HeaderIcon(
                  icon: Icons.all_inclusive,
                  fill: true,
                  color: yFlight,
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
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final bool fill;
  final Color color;
  final VoidCallback onTap;

  const _HeaderIcon({
    required this.icon,
    this.fill = false,
    this.color = yCream,
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
          color: fill ? color : yCream,
          border: Border.all(color: yInk, width: yLineMid),
        ),
        child: Icon(
          icon,
          size: 18,
          color: fill ? yCream : yInk,
        ),
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
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
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
          _AddBlockBtn(glyph: 'Tt', label: 'Texto', onTap: () => onAdd(NoteBlockType.text)),
          const SizedBox(width: 6),
          _AddBlockBtn(glyph: '∑', label: 'Math', onTap: () => onAdd(NoteBlockType.math)),
          const SizedBox(width: 6),
          _AddBlockBtn(glyph: 'H', label: 'Título', onTap: () => onAdd(NoteBlockType.heading)),
          const SizedBox(width: 6),
          _AddBlockBtn(glyph: '•', label: 'Lista', onTap: () => onAdd(NoteBlockType.bullets)),
          const SizedBox(width: 6),
          _AddBlockBtn(glyph: '☑', label: 'Tareas', onTap: () => onAdd(NoteBlockType.tareas)),
          const SizedBox(width: 6),
          _AddBlockBtn(glyph: '✎', label: 'Dibujo', onTap: () => onAdd(NoteBlockType.drawing)),
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
          border: Border.all(color: yInk, width: yLineMid),
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
  const _EmptyState({required this.onAdd});

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: yFlight,
                  border: Border.all(color: yInk, width: yLineMid),
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
          border: Border.all(color: yInk, width: yLineHeavy),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vincular a LAB',
                style: ySans(
                  size: 20,
                  weight: FontWeight.w700,
                  color: yInk,
                )),
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
                        child: Text(s.name,
                            style: ySans(size: 16, color: yInk)),
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
