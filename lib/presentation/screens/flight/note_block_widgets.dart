import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:markdown/markdown.dart' as m;

import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import 'drawing_cell.dart';
import 'note_block_actions.dart';
import 'note_cell_model.dart';
import 'ocr_flow.dart';

// ─── Router ───────────────────────────────────────────────────────────────

class BlockRouter extends StatelessWidget {
  final NoteBlock block;
  final Note note;
  final Folder folder;
  final int index;
  final void Function(TextEditingController? ctrl)? onTextBlockFocusChanged;
  final ValueChanged<bool>? onScrollLockChanged;

  const BlockRouter({
    super.key,
    required this.block,
    required this.note,
    required this.folder,
    required this.index,
    this.onTextBlockFocusChanged,
    this.onScrollLockChanged,
  });

  Color get _accent => note.color ?? folder.color;

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return _BlockShell(
      block: block,
      index: index,
      child: switch (block) {
        TextBlock t => _TextBlockBody(
            block: t, onFocusChanged: onTextBlockFocusChanged),
        MathBlock m => _MathBlockBody(block: m, accentColor: accent),
        BulletsBlock bl => _BulletsBlockBody(block: bl),
        TareasBlock tb =>
            _TareasBlockBody(block: tb, note: note, folder: folder, accent: accent),
        DrawingBlock d => _DrawingBlockBody(
            block: d, accent: accent, folderId: folder.id,
            onScrollLockChanged: onScrollLockChanged),
      },
    );
  }
}

// ─── Block shell: gutter + body + delete affordance ───────────────────────

class _BlockShell extends ConsumerWidget {
  final NoteBlock block;
  final Widget child;
  final int index;

  const _BlockShell({required this.block, required this.child, required this.index});

  static const _glyphForType = {
    NoteBlockType.text: 'Tt',
    NoteBlockType.math: '∑',

    NoteBlockType.bullets: '•',
    NoteBlockType.tareas: '☑',
    NoteBlockType.drawing: '✎',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 2),
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yInk, width: 1.5),
                ),
                child: Text(
                  _glyphForType[block.type] ?? '·',
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 0.4,
                    color: yMuted,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator, size: 14, color: yMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Stack(
            children: [
              child,
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _confirmDelete(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 14, color: yMuted.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Borrar bloque',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text('Se eliminará este bloque de la nota.',
            style: yBody(size: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteBlockRepositoryProvider).delete(block.id);
    }
  }
}

// ─── Autosave helper ──────────────────────────────────────────────────────

mixin _AutosaveMixin<T extends StatefulWidget> on State<T> {
  Timer? _saveTimer;
  bool _hasPendingSave = false;

  void scheduleSave(Future<void> Function() doSave) {
    _hasPendingSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      _hasPendingSave = false;
      await doSave();
    });
  }

  Future<void> flushSave(Future<void> Function() doSave) async {
    _saveTimer?.cancel();
    if (_hasPendingSave) {
      _hasPendingSave = false;
      await doSave();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

// ─── Text block ───────────────────────────────────────────────────────────

class _TextBlockBody extends ConsumerStatefulWidget {
  final TextBlock block;
  final void Function(TextEditingController? ctrl)? onFocusChanged;
  const _TextBlockBody({required this.block, this.onFocusChanged});

  @override
  ConsumerState<_TextBlockBody> createState() => _TextBlockBodyState();
}

class _TextBlockBodyState extends ConsumerState<_TextBlockBody>
    with _AutosaveMixin {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.block.markdown);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _focus.hasFocus;
    if (focused != _hasFocus) setState(() => _hasFocus = focused);
    if (focused) {
      widget.onFocusChanged?.call(_ctrl);
    } else {
      widget.onFocusChanged?.call(null);
      flushSave(_persist);
    }
  }

  Future<void> _persist() async {
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(widget.block.id, {'md': _ctrl.text});
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasFocus && _ctrl.text.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _hasFocus = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focus.requestFocus();
          });
        },
        child: IgnorePointer(child: NoteMarkdownPreview(data: _ctrl.text)),
      );
    }
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      maxLines: null,
      onChanged: (_) => scheduleSave(_persist),
      style: yBody(size: 15, color: yInk2, height: 1.55),
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: 'Escribe…',
        hintStyle: yBody(size: 15, color: yMuted, height: 1.55),
      ),
    );
  }
}

// ─── Math block (display LaTeX) ───────────────────────────────────────────

class _MathBlockBody extends ConsumerStatefulWidget {
  final MathBlock block;
  final Color accentColor;
  const _MathBlockBody({required this.block, required this.accentColor});

  @override
  ConsumerState<_MathBlockBody> createState() => _MathBlockBodyState();
}

class _MathBlockBodyState extends ConsumerState<_MathBlockBody>
    with _AutosaveMixin {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.block.latex);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) flushSave(_persist);
  }

  Future<void> _persist() async {
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(widget.block.id, {'latex': _ctrl.text});
  }

  @override
  Widget build(BuildContext context) {
    final latex = _ctrl.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: widget.accentColor,
            border: Border.all(color: yInk, width: yLineMid),
            boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 4,
                child: Text('LATEX · DISPLAY',
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yCream.withValues(alpha: 0.55),
                    )),
              ),
              Center(
                child: latex.trim().isEmpty
                    ? Text('introduce LaTeX abajo',
                        style: yMono(
                          size: 12,
                          color: yCream.withValues(alpha: 0.6),
                          tracking: 1.2,
                        ))
                    : Math.tex(
                        latex,
                        mathStyle: MathStyle.display,
                        textStyle: TextStyle(
                          fontSize: 22,
                          color: yCream,
                        ),
                        onErrorFallback: (err) => Text(
                          err.message,
                          style: yMono(
                            size: 11,
                            color: yAmber2,
                            tracking: 0.8,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          maxLines: null,
          onChanged: (_) {
            scheduleSave(_persist);
            setState(() {}); // re-render preview
          },
          style: yMono(size: 12, color: yInk, tracking: 0.5),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintText: r't = \frac{\bar{x} - \mu_0}{s / \sqrt{n}}',
            hintStyle: yMono(size: 12, color: yMuted, tracking: 0.5),
          ),
        ),
      ],
    );
  }
}

// ─── Bullets block ────────────────────────────────────────────────────────

class _BulletsBlockBody extends ConsumerStatefulWidget {
  final BulletsBlock block;
  const _BulletsBlockBody({required this.block});

  @override
  ConsumerState<_BulletsBlockBody> createState() => _BulletsBlockBodyState();
}

class _BulletsBlockBodyState extends ConsumerState<_BulletsBlockBody>
    with _AutosaveMixin {
  late List<String> _items;
  final List<TextEditingController> _ctrls = [];
  final List<FocusNode> _focuses = [];

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(widget.block.items);
    if (_items.isEmpty) _items.add('');
    for (final v in _items) {
      _addCtrl(v);
    }
  }

  void _addCtrl(String text) {
    final c = TextEditingController(text: text);
    late final FocusNode f;
    f = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final idx = _focuses.indexOf(f);
        if (event.logicalKey == LogicalKeyboardKey.backspace &&
            c.text.isEmpty &&
            idx >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _removeItem(idx);
          });
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _addItem();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    f.addListener(() {
      if (!f.hasFocus) flushSave(_persist);
    });
    _ctrls.add(c);
    _focuses.add(f);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focuses) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _persist() async {
    _items = _ctrls.map((c) => c.text).toList();
    await ref
        .read(noteBlockRepositoryProvider)
        .updatePayload(widget.block.id, {'items': _items});
  }

  void _addItem() {
    setState(() {
      _items.add('');
      _addCtrl('');
    });
    scheduleSave(_persist);
    _focuses.last.requestFocus();
  }

  void _copyAll() {
    final text = _ctrls
        .map((c) => c.text)
        .where((t) => t.isNotEmpty)
        .map((t) => '- $t')
        .join('\n');
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lista copiada'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _removeItem(int i) {
    if (_ctrls.length <= 1) return;
    setState(() {
      _items.removeAt(i);
      _ctrls.removeAt(i).dispose();
      _focuses.removeAt(i).dispose();
    });
    scheduleSave(_persist);
    final focusIdx = (i > 0) ? i - 1 : 0;
    if (_focuses.isNotEmpty) {
      _focuses[focusIdx].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _ctrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 9, right: 10),
                  child: SizedBox(
                    width: 6,
                    height: 6,
                    child: ColoredBox(color: yInk),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrls[i],
                    focusNode: _focuses[i],
                    maxLines: null,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\n')),
                    ],
                    onChanged: (_) => scheduleSave(_persist),
                    style: yBody(size: 14, color: yInk2, height: 1.5),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'item…',
                      hintStyle:
                          yBody(size: 14, color: yMuted, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _addItem,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, left: 16),
                child: Text('+ item',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted,
                    )),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _copyAll,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('COPIAR TODO',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted,
                    )),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Tareas block ─────────────────────────────────────────────────────────

class _TareasBlockBody extends ConsumerStatefulWidget {
  final TareasBlock block;
  final Note note;
  final Folder folder;
  final Color accent;

  const _TareasBlockBody({
    required this.block,
    required this.note,
    required this.folder,
    required this.accent,
  });

  @override
  ConsumerState<_TareasBlockBody> createState() => _TareasBlockBodyState();
}

class _TareasBlockBodyState extends ConsumerState<_TareasBlockBody> {
  final _newTaskCtrl = TextEditingController();
  bool _showInput = false;

  NoteBlockActions get _actions => NoteBlockActions(
        ref: ref,
        noteId: widget.note.id,
        folderId: widget.note.folderId,
      );

  @override
  void dispose() {
    _newTaskCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitNew() async {
    final content = _newTaskCtrl.text.trim();
    if (content.isEmpty) return;
    await _actions.createTaskInBlock(widget.block, content);
    _newTaskCtrl.clear();
    setState(() => _showInput = false);
  }

  Future<void> _onCheck(Task t) => _actions.toggleDone(t);

  Future<void> _onLongPress(Task t) async {
    final spaces = ref.read(activeLabSpacesProvider).valueOrNull ?? [];
    if (spaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay spaces activos'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final picked = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => _SpacePickerDialog(spaces: spaces),
    );
    if (picked == null) return;
    await _actions.linkTaskToSpace(t, picked.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Linkeada a ${picked.name}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _onDelete(Task t) async {
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Borrar tarea',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text(
          '¿Solo desenlazar de la nota (sigue viva en FIGHT) o borrar de todos los lugares?',
          style: yBody(size: 13),
        ),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _DeleteChoice.unlink),
              child: const Text('Solo desenlazar')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _DeleteChoice.hard),
              child: const Text('Borrar de todos lados')),
        ],
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case _DeleteChoice.unlink:
        await _actions.unlinkFromBlock(widget.block, t);
      case _DeleteChoice.hard:
        await _actions.hardDeleteTask(widget.block, t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(noteLinkedTasksProvider(widget.note.id));
    final allTasks = tasksAsync.valueOrNull ?? [];
    final blockTasks = allTasks
        .where((t) =>
            widget.block.taskIds.contains(t.id) &&
            t.status != TaskStatus.trash)
        .toList()
      ..sort((a, b) {
        final aDone = a.status == TaskStatus.done;
        final bDone = b.status == TaskStatus.done;
        if (aDone != bDone) return aDone ? 1 : -1;
        return a.createdAt.compareTo(b.createdAt);
      });

    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        borderRadius: BorderRadius.zero,
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: widget.accent, width: 6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('// BLOQUE TAREAS',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    )),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'se enlazan a fight con @${widget.folder.name.toLowerCase()}',
                    overflow: TextOverflow.ellipsis,
                    style: yMono(size: 10, color: yMuted, tracking: 1),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _showInput = !_showInput),
                  child: Text(
                    _showInput ? 'CERRAR' : '+ TAREA',
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
            const SizedBox(height: 6),
            if (_showInput) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTaskCtrl,
                      autofocus: true,
                      onSubmitted: (_) => _submitNew(),
                      style: yBody(size: 14, color: yInk),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide:
                              BorderSide(color: yInk, width: yLineMid),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide:
                              BorderSide(color: yInk, width: yLineMid),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide:
                              BorderSide(color: yInk, width: yLineMid),
                        ),
                        filled: false,
                        hintText: 'nueva tarea…',
                        hintStyle: yBody(size: 14, color: yMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _submitNew,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yFight,
                        border: Border.all(color: yInk, width: yLineMid),
                      ),
                      child: const Text('+',
                          style: TextStyle(
                              fontSize: 18, color: yCream, height: 1.0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (blockTasks.isEmpty && !_showInput)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('sin tareas',
                    style: yMono(
                      size: 10,
                      color: yMuted.withValues(alpha: 0.6),
                      tracking: 1.2,
                    )),
              ),
            for (final t in blockTasks)
              _NoteTaskRow(
                task: t,
                onCheck: () => _onCheck(t),
                onLongPress: () => _onLongPress(t),
                onDelete: () => _onDelete(t),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteTaskRow extends ConsumerWidget {
  final Task task;
  final VoidCallback onCheck;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _NoteTaskRow({
    required this.task,
    required this.onCheck,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = task.status == TaskStatus.done;
    final linkedCardAsync = ref.watch(_kanbanByTaskProvider(task.id));
    final linkedSpaceName = linkedCardAsync.valueOrNull;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Container(
        color: done ? yCream2 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCheck,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? yInk : yCream,
                  border: Border.all(color: yInk, width: yLineThin),
                ),
                child: done
                    ? const Text('✓',
                        style: TextStyle(
                            fontSize: 12,
                            color: yCream,
                            height: 1.0,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            if (task.folderId != null) ...[
              Builder(builder: (context) {
                final fColor = ref.watch(folderByIdProvider(task.folderId!)).valueOrNull?.color;
                if (fColor == null) return const SizedBox.shrink();
                return Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsets.only(right: 6),
                  color: fColor,
                );
              }),
            ],
            Expanded(
              child: Text(
                cleanMention(task.content),
                style: yBody(
                  size: 14,
                  weight: FontWeight.w500,
                  color: done ? yMuted : yInk,
                  height: 1.3,
                ).copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (task.dueDate != null) ...[
              const SizedBox(width: 6),
              Text(
                'DUE ${_fmtDue(task.dueDate!).toUpperCase()}',
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1,
                  color: yMuted,
                ),
              ),
            ],
            const SizedBox(width: 6),
            _LinkChip(text: '→ FIGHT', bg: yFight),
            if (linkedSpaceName != null) ...[
              const SizedBox(width: 4),
              _LinkChip(text: '→ ${linkedSpaceName.toUpperCase()}', bg: yLab),
            ],
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.close,
                    size: 14, color: yMuted.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDue(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _LinkChip extends StatelessWidget {
  final String text;
  final Color bg;

  const _LinkChip({required this.text, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 5, 2),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: yInk, width: 1.5),
      ),
      child: Text(text,
          style: yMono(
            size: 8,
            weight: FontWeight.w700,
            tracking: 1,
            color: yCream,
          )),
    );
  }
}

enum _DeleteChoice { unlink, hard }

/// Returns the linked space name for a task (or null if no kanban link).
final _kanbanByTaskProvider =
    FutureProvider.family<String?, int>((ref, taskId) async {
  final card =
      await ref.watch(kanbanCardRepositoryProvider).getByOriginTaskId(taskId);
  if (card == null) return null;
  final space =
      await ref.watch(labSpaceRepositoryProvider).getById(card.labSpaceId);
  return space?.name;
});

class _SpacePickerDialog extends StatelessWidget {
  final List<LabSpace> spaces;
  const _SpacePickerDialog({required this.spaces});

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
            Text('Linkear a space',
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

// ─── Drawing block (wraps existing DrawingCell) ───────────────────────────

class _DrawingBlockBody extends ConsumerStatefulWidget {
  final DrawingBlock block;
  final Color accent;
  final int? folderId;
  final ValueChanged<bool>? onScrollLockChanged;

  const _DrawingBlockBody({
    required this.block,
    required this.accent,
    this.folderId,
    this.onScrollLockChanged,
  });

  @override
  ConsumerState<_DrawingBlockBody> createState() =>
      _DrawingBlockBodyState();
}

class _DrawingBlockBodyState extends ConsumerState<_DrawingBlockBody> {
  late DrawingData _data;

  @override
  void initState() {
    super.initState();
    _data = _toDrawingData(widget.block);
  }

  DrawingData _toDrawingData(DrawingBlock b) {
    List<dynamic> strokes = const [];
    try {
      final raw = b.strokesJson.isEmpty ? '[]' : b.strokesJson;
      final decoded = jsonDecode(raw);
      if (decoded is List) strokes = decoded;
    } catch (_) {}
    return DrawingData.fromJson({'h': b.height, 's': strokes});
  }

  Future<void> _persist(DrawingData data) async {
    _data = data;
    await ref.read(noteBlockRepositoryProvider).updatePayload(
      widget.block.id,
      {
        'h': data.height,
        's': data.strokes.map((s) => s.toJson()).toList(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawingCell(
      data: _data,
      accent: widget.accent,
      onChanged: _persist,
      onDelete: () async {
        await ref.read(noteBlockRepositoryProvider).delete(widget.block.id);
      },
      onDrawStart: () {},
      onDrawEnd: () {},
      onScrollLockChanged: (locked) {
        widget.onScrollLockChanged?.call(locked);
      },
      onRecognizeText: (strokes) => runOcrFlow(context, ref, strokes,
          accent: widget.accent,
          folderId: widget.folderId,
          noteId: widget.block.noteId),
      onSendToYuli: (strokes) => runOcrToYuliFlow(context, ref, strokes,
          accent: widget.accent,
          noteId: widget.block.noteId),
      onSendMathToYuli: kDebugMode
          ? (strokes) => runMathToYuliFlow(context, ref, strokes,
              accent: widget.accent, noteId: widget.block.noteId)
          : null,
    );
  }
}

// ─── Markdown preview (compiled) ─────────────────────────────────────────

/// Repairs malformed GFM tables (a delimiter row `|---|---|` with the wrong
/// column count) by rebuilding each delimiter to match its header's columns.
/// `markdown_widget` (strict) otherwise refuses to render them → raw pipes, and
/// some malformed shapes can throw. Conservative: only touches delimiter rows,
/// leaves non-table text untouched. Shared by the AI chat and canvas text
/// blocks (both render raw model output).
String fixMarkdownTables(String md) {
  if (!md.contains('|')) return md;
  final lines = md.split('\n');
  final sepRe = RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$');
  int colCount(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').length;
  }

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (!line.contains('|') || !sepRe.hasMatch(line)) continue;
    final header = lines[i - 1];
    if (!header.contains('|')) continue;
    final cols = colCount(header);
    if (cols < 1) continue;
    final rebuilt = '|${List.filled(cols, '---').join('|')}|';
    if (rebuilt != line.trim()) lines[i] = rebuilt;
  }
  return lines.join('\n');
}

class NoteMarkdownPreview extends ConsumerWidget {
  final String data;
  final bool tight;
  const NoteMarkdownPreview({required this.data, this.tight = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SpanNode? customTextGenerator(
        m.Node node, MarkdownConfig config, WidgetVisitor visitor) {
      return null;
    }

    final generator = MarkdownGenerator(
      textGenerator: customTextGenerator,
      linesMargin: tight ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      inlineSyntaxList: [_LatexSyntax()],
      blockSyntaxList: [const _DefinitionListSyntax(), const _LatexBlockSyntax(), const _AlignmentBlockSyntax()],
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'latex',
          generator: (e, config, visitor) =>
              _LatexNode(e.attributes, e.textContent, config),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'align',
          generator: (e, config, visitor) =>
              _AlignmentNode(e.attributes['align'] ?? 'left', e.textContent, config),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'deflist',
          generator: (e, config, visitor) =>
              _DefinitionListNode(e.attributes['data'] ?? '', config),
        ),
      ],
    );

    return MarkdownWidget(
      data: data,
      shrinkWrap: true,
      markdownGenerator: generator,
      config: MarkdownConfig(configs: [
        PConfig(textStyle: yBody(size: 15, color: yInk2, height: 1.55)),
        H1Config(style: ySans(size: 28, weight: FontWeight.w700, letterSpacing: -0.8, color: yInk)),
        H2Config(style: ySans(size: 22, weight: FontWeight.w700, letterSpacing: -0.5, color: yInk)),
        H3Config(style: ySans(size: 18, weight: FontWeight.w700, letterSpacing: -0.3, color: yInk)),
        CheckBoxConfig(builder: (checked) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: yInk,
          ),
        )),
        CodeConfig(style: yMono(size: 12, color: yInk, tracking: 0.5).copyWith(backgroundColor: yCream2)),
        BlockquoteConfig(textColor: yMuted, sideColor: yFlight),
        ImgConfig(
          builder: (url, attributes) {
            final maxW = MediaQuery.of(context).size.width * 0.75;
            Widget img;
            if (url.startsWith('/')) {
              img = Image.file(File(url),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text('[Imagen no encontrada]',
                      style: yBody(size: 13, color: yMuted)));
            } else {
              img = Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text('[Imagen: $url]',
                      style: yBody(size: 13, color: yMuted)));
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 300, maxWidth: maxW),
                child: img,
              ),
            );
          },
        ),
      ]),
    );
  }
}

// ─── LaTeX support ───────────────────────────────────────────────────────

class _LatexNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  _LatexNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] == 'true';
    final style = parentStyle ?? config.p.textStyle;
    if (content.isEmpty) {
      return TextSpan(style: style, text: textContent);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Math.tex(
        content,
        mathStyle: isInline ? MathStyle.text : MathStyle.display,
        textStyle: style,
        onErrorFallback: (err) =>
            Text(textContent, style: style.copyWith(color: Colors.red)),
      ),
    );
  }
}

class _LatexBlockSyntax extends m.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\$\$\s*$');
  const _LatexBlockSyntax() : super();

  @override
  m.Node? parse(m.BlockParser parser) {
    final contentLines = <String>[];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      if (pattern.hasMatch(line)) {
        parser.advance();
        break;
      }
      contentLines.add(line);
      parser.advance();
    }
    final content = contentLines.join('\n');
    final element = m.Element('latex', [m.Text(content)]);
    element.attributes['content'] = content;
    element.attributes['isInline'] = 'false';
    return element;
  }
}

class _LatexSyntax extends m.InlineSyntax {
  _LatexSyntax()
      : super(
            r'(\$\$\s*([\s\S]+?)\s*\$\$)|(\$(?!\s)([^$\n]+?)(?<!\s)\$)');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final matchValue = match.group(0)!;
    String content = '';
    bool isInline = true;
    if (matchValue.startsWith(r'$$') && matchValue.endsWith(r'$$')) {
      isInline = false;
      content = matchValue.substring(2, matchValue.length - 2).trim();
    } else if (matchValue.startsWith(r'$') && matchValue.endsWith(r'$')) {
      isInline = true;
      content = matchValue.substring(1, matchValue.length - 1).trim();
    }
    final element = m.Element.text('latex', matchValue);
    element.attributes['content'] = content;
    element.attributes['isInline'] = '$isInline';
    parser.addNode(element);
    return true;
  }
}

class _AlignmentNode extends SpanNode {
  final String align;
  final String textContent;
  final MarkdownConfig config;

  _AlignmentNode(this.align, this.textContent, this.config);

  @override
  InlineSpan build() {
    final textAlignment = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    final trimmed = textContent.trim();
    if (trimmed.isEmpty) return const TextSpan();

    final generator = MarkdownGenerator(
      linesMargin: const EdgeInsets.symmetric(vertical: 2),
      inlineSyntaxList: [_LatexSyntax()],
      blockSyntaxList: [const _LatexBlockSyntax()],
      richTextBuilder: (span) => Text.rich(span, textAlign: textAlignment),
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'latex',
          generator: (e, cfg, visitor) =>
              _LatexNode(e.attributes, e.textContent, cfg),
        ),
      ],
    );

    final widgets = generator.buildWidgets(trimmed, config: config);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        ),
      ),
    );
  }
}

class _AlignmentBlockSyntax extends m.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^:::\s*(left|center|right)\s*$');
  const _AlignmentBlockSyntax() : super();

  @override
  m.Node? parse(m.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return null;
    final align = match.group(1)!;
    final contentLines = <String>[];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      if (RegExp(r'^:::\s*$').hasMatch(line)) {
        parser.advance();
        break;
      }
      contentLines.add(line);
      parser.advance();
    }
    final content = contentLines.join('\n');
    final element = m.Element('align', [m.Text(content)]);
    element.attributes['align'] = align;
    return element;
  }
}

// ─── Definition list syntax ─────────────────────────────────────────────

class _DefinitionListSyntax extends m.BlockSyntax {
  const _DefinitionListSyntax() : super();

  static final _defLine = RegExp(r'^:\s+(.+)$');

  @override
  RegExp get pattern => RegExp(r'^.+$');

  @override
  bool canParse(m.BlockParser parser) {
    if (parser.isDone) return false;
    final current = parser.current.content;
    if (current.trim().isEmpty || _defLine.hasMatch(current)) return false;
    final next = parser.next;
    return next != null && _defLine.hasMatch(next.content);
  }

  @override
  m.Node? parse(m.BlockParser parser) {
    final pairs = <String>[];
    while (!parser.isDone) {
      final termLine = parser.current.content;
      if (termLine.trim().isEmpty) break;
      if (_defLine.hasMatch(termLine)) break;
      final term = termLine.trim();
      parser.advance();
      final defs = <String>[];
      while (!parser.isDone && _defLine.hasMatch(parser.current.content)) {
        defs.add(_defLine.firstMatch(parser.current.content)!.group(1)!);
        parser.advance();
      }
      if (defs.isEmpty) break;
      pairs.add('$term\x00${defs.join('\x00')}');
    }
    if (pairs.isEmpty) return null;
    final element = m.Element('deflist', [m.Text(pairs.join('\x01'))]);
    element.attributes['data'] = pairs.join('\x01');
    return element;
  }
}

class _DefinitionListNode extends SpanNode {
  final String data;
  final MarkdownConfig config;

  _DefinitionListNode(this.data, this.config);

  @override
  InlineSpan build() {
    final pairs = data.split('\x01');
    final children = <InlineSpan>[];
    for (final pair in pairs) {
      final parts = pair.split('\x00');
      if (parts.length < 2) continue;
      final term = parts[0];
      final defs = parts.sublist(1);
      children.add(WidgetSpan(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                term,
                style: ySans(
                  size: 15,
                  weight: FontWeight.w700,
                  color: yInk,
                  height: 1.4,
                ),
              ),
              for (final def in defs)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5, right: 8),
                        child: Container(
                          width: 6,
                          height: 2,
                          color: yMuted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          def,
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
        ),
      ));
    }
    if (children.isEmpty) return const TextSpan();
    if (children.length == 1) return children.first;
    return WidgetSpan(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in children)
            Builder(builder: (_) => Text.rich(TextSpan(children: [c]))),
        ],
      ),
    );
  }
}
