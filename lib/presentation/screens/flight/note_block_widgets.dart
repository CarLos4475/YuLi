import '../../../domain/services/pending_saves.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../providers/note_block_providers.dart';
import '../../providers/flight_workspace_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../widgets/confetti_burst.dart';
import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/models/task.dart';
import '../../../data/services/ai_chat_image_storage.dart';
import 'ai_chat_sheet.dart';
import 'drawing_stroke_persistence.dart';
import 'drawing_cell.dart';
import 'note_block_actions.dart';
import 'note_cell_model.dart';
import 'ocr_flow.dart';
import 'yuli_live_text_editor.dart';

// ─── Router ───────────────────────────────────────────────────────────────

class BlockRouter extends StatelessWidget {
  final NoteBlock block;
  final Note note;
  final Folder folder;
  final int index;
  final YuliEditorFocusChanged? onTextBlockFocusChanged;
  final ValueChanged<bool>? onScrollLockChanged;
  final bool autofocus;
  final ValueChanged<FlightWorkspaceTarget>? onOpenWorkspaceTarget;

  const BlockRouter({
    super.key,
    required this.block,
    required this.note,
    required this.folder,
    required this.index,
    this.onTextBlockFocusChanged,
    this.onScrollLockChanged,
    this.autofocus = false,
    this.onOpenWorkspaceTarget,
  });

  Color get _accent => note.color ?? folder.color;

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return _BlockShell(
      block: block,
      index: index,
      child: switch (block) {
        TextBlock t => YuliLiveTextEditor(
          block: t,
          accent: accent,
          onFocusChanged: onTextBlockFocusChanged,
          autofocus: autofocus,
          onOpenWorkspaceTarget: onOpenWorkspaceTarget,
        ),
        MathBlock m => _MathBlockBody(block: m, accentColor: accent),
        BulletsBlock bl => _BulletsBlockBody(block: bl),
        TareasBlock tb => _TareasBlockBody(
          block: tb,
          note: note,
          folder: folder,
          accent: accent,
        ),
        DrawingBlock d => _DrawingBlockBody(
          block: d,
          accent: accent,
          folderId: folder.id,
          onScrollLockChanged: onScrollLockChanged,
        ),
      },
    );
  }
}
// ─── Block shell: gutter + body + delete affordance ───────────────────────

class _BlockShell extends ConsumerStatefulWidget {
  final NoteBlock block;
  final Widget child;
  final int index;

  const _BlockShell({
    required this.block,
    required this.child,
    required this.index,
  });

  static const _glyphForType = {
    NoteBlockType.text: YuLiIcons.textInitial,
    NoteBlockType.math: YuLiIcons.sigma,
    NoteBlockType.bullets: YuLiIcons.listChecks,
    NoteBlockType.tareas: YuLiIcons.squareCheck,
    NoteBlockType.drawing: YuLiIcons.pencil,
  };

  @override
  ConsumerState<_BlockShell> createState() => _BlockShellState();
}

class _BlockShellState extends ConsumerState<_BlockShell> {
  bool _controlsVisible = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _controlsVisible = true),
      onExit: (_) => setState(() => _controlsVisible = false),
      child: Listener(
        onPointerDown: (_) {
          if (!_controlsVisible) {
            setState(() => _controlsVisible = true);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SizedBox(
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
                          border: Border.all(color: yBorderStrong, width: 1.5),
                        ),
                        child: Icon(
                          _BlockShell._glyphForType[widget.block.type] ??
                              YuLiIcons.textInitial,
                          size: 12,
                          color: yMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: const Icon(
                          YuLiIcons.gripVertical,
                          size: 14,
                          color: yMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Stack(
                children: [
                  widget.child,
                  if (_controlsVisible)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _confirmDelete(context),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            YuLiIcons.close,
                            size: 14,
                            color: yMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
            title: Text(
              'Borrar bloque',
              style: ySans(size: 18, weight: FontWeight.w700),
            ),
            content: Text(
              'Se eliminará este bloque de la nota.',
              style: yBody(size: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Borrar'),
              ),
            ],
          ),
    );
    if (ok == true) {
      await ref.read(noteBlockRepositoryProvider).delete(widget.block.id);
    }
  }
}

// ─── Autosave helper ──────────────────────────────────────────────────────

mixin _AutosaveMixin<T extends StatefulWidget> on State<T> {
  Timer? _saveTimer;
  bool _hasPendingSave = false;
  Future<void> Function()? _pendingSave;

  void scheduleSave(Future<void> Function() doSave) {
    PendingSaves.schedule(this, () => flushSave(doSave));
    _hasPendingSave = true;
    _pendingSave = doSave;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      PendingSaves.unschedule(this);
      _hasPendingSave = false;
      _pendingSave = null;
      await PendingSaves.track(doSave(), owner: this);
    });
  }

  Future<void> flushSave(Future<void> Function() doSave) async {
    PendingSaves.unschedule(this);
    _saveTimer?.cancel();
    if (_hasPendingSave) {
      _hasPendingSave = false;
      _pendingSave = null;
      await PendingSaves.track(doSave(), owner: this);
    }
  }

  /// Persist a pending debounced edit immediately (fire-and-forget). MUST be
  /// called from State.dispose BEFORE the controllers the save reads from are
  /// torn down — otherwise a debounced edit is silently dropped when the block
  /// unmounts (e.g. leaving the screen within the 2s debounce window).
  void commitPendingSave() {
    PendingSaves.unschedule(this);
    _saveTimer?.cancel();
    if (_hasPendingSave) {
      _hasPendingSave = false;
      final save = _pendingSave;
      _pendingSave = null;
      if (save != null) PendingSaves.track(save(), owner: this);
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
  final Color accent;
  final int noteId;
  final void Function(TextEditingController? ctrl, FocusNode? node)?
  onFocusChanged;
  final void Function(Widget? editor)? onRequestEditor;
  const _TextBlockBody({
    required this.block,
    required this.accent,
    required this.noteId,
    required this.onFocusChanged,
    required this.onRequestEditor,
  });

  @override
  ConsumerState<_TextBlockBody> createState() => _TextBlockBodyState();
}

class _TextBlockBodyState extends ConsumerState<_TextBlockBody>
    with _AutosaveMixin {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  bool _hasFocus = false;
  late String _lastText;

  bool _livePreview = false;
  int _cursorLine = 0;
  final List<TextEditingController> _lineCtrls = [];
  final List<FocusNode> _lineFocuses = [];

  List<int>? _editingTableIndices;
  List<int>? _editingFenceIndices;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.block.markdown);
    _lastText = _ctrl.text;
    _ctrl.addListener(_onTextChanged);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  void _onTextChanged() {
    if (_ctrl.text == _lastText) return;
    _lastText = _ctrl.text;
    scheduleSave(_persist);
  }

  @override
  void dispose() {
    commitPendingSave();
    _focus.removeListener(_onFocusChange);
    _ctrl.removeListener(_onTextChanged);
    _focus.dispose();
    _ctrl.dispose();
    _disposeLiveLines();
    super.dispose();
  }

  void _onFocusChange() {
    final focused = _focus.hasFocus;
    if (focused != _hasFocus) setState(() => _hasFocus = focused);
    if (focused) {
      widget.onFocusChanged?.call(_ctrl, _focus);
    } else {
      widget.onFocusChanged?.call(null, null);
      flushSave(_persist);
    }
  }

  Future<void> _persist() async {
    await ref.read(noteBlockRepositoryProvider).updatePayload(widget.block.id, {
      'md': _ctrl.text,
    });
  }

  // ─── Live Preview ──────────────────────────────────────────────────────────

  void _toggleLive() {
    setState(() {
      _livePreview = !_livePreview;
      if (_livePreview) {
        _enterLive();
      } else {
        _exitLive();
      }
    });
  }

  void _enterLive() {
    _disposeLiveLines();
    final lines = _ctrl.text.split('\n');
    if (lines.isEmpty) lines.add('');
    for (final line in lines) {
      final c = TextEditingController(text: line);
      c.addListener(_onLiveLineChanged);
      _lineCtrls.add(c);
      final f = FocusNode();
      f.addListener(_onLiveFocusChange);
      _lineFocuses.add(f);
    }
    _cursorLine =
        _ctrl.selection.isValid
            ? _ctrl.text
                    .substring(0, _ctrl.selection.baseOffset)
                    .split('\n')
                    .length -
                1
            : 0;
    if (_cursorLine < 0) _cursorLine = 0;
    if (_cursorLine >= _lineCtrls.length) _cursorLine = _lineCtrls.length - 1;
    _hasFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lineFocuses.isNotEmpty) {
        _lineFocuses[_cursorLine.clamp(0, _lineFocuses.length - 1)]
            .requestFocus();
      }
    });
  }

  void _exitLive() {
    _ctrl.text = _lineCtrls.map((c) => c.text).join('\n');
    _lastText = _ctrl.text;
    _disposeLiveLines();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _disposeLiveLines() {
    for (int i = 0; i < _lineCtrls.length; i++) {
      _lineCtrls[i].removeListener(_onLiveLineChanged);
      _lineCtrls[i].dispose();
      _lineFocuses[i].removeListener(_onLiveFocusChange);
      _lineFocuses[i].dispose();
    }
    _lineCtrls.clear();
    _lineFocuses.clear();
  }

  void _syncLiveToCtrl() {
    final text = _lineCtrls.map((c) => c.text).join('\n');
    if (_ctrl.text != text) {
      _ctrl.text = text;
      _lastText = text;
      scheduleSave(_persist);
    }
  }

  void _onLiveLineChanged() {
    _syncLiveToCtrl();
  }

  void _onLiveFocusChange() {
    for (int i = 0; i < _lineFocuses.length; i++) {
      if (_lineFocuses[i].hasFocus) {
        if (_cursorLine != i) setState(() => _cursorLine = i);
        widget.onFocusChanged?.call(_lineCtrls[i], _lineFocuses[i]);
        return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (int i = 0; i < _lineFocuses.length; i++) {
        if (_lineFocuses[i].hasFocus) return;
      }
      widget.onFocusChanged?.call(null, null);
    });
  }

  // ─── Atomic block detection ────────────────────────────────────────────────

  bool _isTableLine(String t) =>
      t.trimLeft().startsWith('|') && t.trimRight().endsWith('|');

  bool _isFenceLine(String t) => t.trimLeft().startsWith('```');

  bool _isInAtomicBlock(int lineIdx) {
    int fenceCount = 0;
    for (int i = 0; i <= lineIdx; i++) {
      if (_isFenceLine(_lineCtrls[i].text)) fenceCount++;
    }
    return fenceCount % 2 == 1;
  }

  List<bool> _atomicMask(int lineIdx) {
    final mask = List<bool>.filled(_lineCtrls.length, false);
    if (!_isInAtomicBlock(lineIdx)) return mask;
    int fenceCount = 0, start = -1;
    for (int i = 0; i < _lineCtrls.length; i++) {
      if (_isFenceLine(_lineCtrls[i].text)) {
        if (fenceCount % 2 == 0) {
          start = i;
        } else {
          for (int j = start; j <= i; j++) {
            mask[j] = true;
          }
        }
        fenceCount++;
      }
    }
    return mask;
  }

  List<List<int>> _findTableGroups() {
    final groups = <List<int>>[];
    List<int>? current;
    for (int i = 0; i < _lineCtrls.length; i++) {
      if (_isTableLine(_lineCtrls[i].text)) {
        current ??= <int>[];
        current.add(i);
      } else {
        if (current != null && current.length >= 2) {
          groups.add(current);
        } else if (current != null) {
          current.clear();
        }
        current = null;
      }
    }
    if (current != null && current.length >= 2) groups.add(current);
    return groups;
  }

  List<List<int>> _findImageGroups() {
    final groups = <List<int>>[];
    final seen = <int>{};
    for (int i = 0; i < _lineCtrls.length; i++) {
      if (seen.contains(i)) continue;
      if (!_isImageLine(i)) continue;
      if (i > 0 && i + 1 < _lineCtrls.length) {
        final above = _lineCtrls[i - 1].text.trim();
        final below = _lineCtrls[i + 1].text.trim();
        if (above.startsWith(':::') && below == ':::') {
          groups.add([i - 1, i, i + 1]);
          seen.addAll([i - 1, i, i + 1]);
          continue;
        }
      }
      groups.add([i]);
      seen.add(i);
    }
    return groups;
  }

  List<List<int>> _findFenceGroups() {
    final groups = <List<int>>[];
    int? start;
    for (int i = 0; i < _lineCtrls.length; i++) {
      if (_isFenceLine(_lineCtrls[i].text)) {
        if (start == null) {
          start = i;
        } else {
          groups.add(List.generate(i - start + 1, (j) => start! + j));
          start = null;
        }
      }
    }
    return groups;
  }

  bool _isImageLine(int i) {
    final t = _lineCtrls[i].text.trim();
    return t.startsWith('![') && t.contains('](');
  }

  // ─── Line navigation / edit ────────────────────────────────────────────────

  void _insertLineAfter(int lineIdx) {
    final ctrl = _lineCtrls[lineIdx];
    final cursor = ctrl.selection.baseOffset;
    final after = ctrl.text.substring(cursor);
    ctrl.text = ctrl.text.substring(0, cursor);
    final newCtrl = TextEditingController(text: after);
    newCtrl.addListener(_onLiveLineChanged);
    _lineCtrls.insert(lineIdx + 1, newCtrl);
    final newFocus = FocusNode();
    newFocus.addListener(_onLiveFocusChange);
    _lineFocuses.insert(lineIdx + 1, newFocus);
    _syncLiveToCtrl();
    setState(() => _cursorLine = lineIdx + 1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => newFocus.requestFocus(),
    );
  }

  void _mergeWithPrevLine(int lineIdx) {
    if (lineIdx <= 0) return;
    final prevCtrl = _lineCtrls[lineIdx - 1];
    final curCtrl = _lineCtrls[lineIdx];
    final prevLen = prevCtrl.text.length;
    prevCtrl.text = prevCtrl.text + curCtrl.text;
    prevCtrl.selection = TextSelection.collapsed(offset: prevLen);
    curCtrl.removeListener(_onLiveLineChanged);
    curCtrl.dispose();
    _lineFocuses[lineIdx].removeListener(_onLiveFocusChange);
    _lineFocuses[lineIdx].dispose();
    _lineCtrls.removeAt(lineIdx);
    _lineFocuses.removeAt(lineIdx);
    _syncLiveToCtrl();
    setState(() => _cursorLine = lineIdx - 1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _lineFocuses[lineIdx - 1].requestFocus(),
    );
  }

  void _moveUp() {
    if (_cursorLine > 0) {
      setState(() => _cursorLine--);
      _lineFocuses[_cursorLine].requestFocus();
    }
  }

  void _moveDown() {
    if (_cursorLine < _lineCtrls.length - 1) {
      setState(() => _cursorLine++);
      _lineFocuses[_cursorLine].requestFocus();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  Widget _buildLiveToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleLive,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
              decoration: BoxDecoration(
                color: yLab,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(YuLiIcons.eye, size: 10, color: yCream),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: yMono(
                      size: 8,
                      weight: FontWeight.w700,
                      color: yCream,
                      tracking: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleLive,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
        child: Icon(
          YuLiIcons.eye,
          size: 13,
          color: yMuted.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildLiveMode() {
    final atomicMask = _atomicMask(_cursorLine);
    final tableGroups = _findTableGroups();
    final imageGroups = _findImageGroups();
    final fenceGroups = _findFenceGroups();

    final groupSet = <int>{};
    final groupWidget = <int, Widget>{};
    for (final g in tableGroups) {
      for (final i in g) {
        groupSet.add(i);
      }
      groupWidget[g.first] = _buildTableGroup(g, g.contains(_cursorLine));
    }
    for (final g in imageGroups) {
      for (final i in g) {
        groupSet.add(i);
      }
      groupWidget[g.first] = _buildImageGroup(g, g.contains(_cursorLine));
    }
    for (final g in fenceGroups) {
      for (final i in g) {
        groupSet.add(i);
      }
      groupWidget[g.first] = _buildFenceGroup(g, g.contains(_cursorLine));
    }

    final widgets = <Widget>[_buildLiveToggle()];
    int i = 0;
    while (i < _lineCtrls.length) {
      if (groupSet.contains(i)) {
        widgets.add(groupWidget[i]!);
        int end = i;
        for (final g in [...tableGroups, ...imageGroups, ...fenceGroups]) {
          if (g.contains(i)) end = g.last;
        }
        i = end + 1;
      } else if (i == _cursorLine || atomicMask[i]) {
        final idx = i;
        final inAtomic = atomicMask[i];
        widgets.add(
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp && idx > 0) {
                  _moveUp();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                    idx < _lineCtrls.length - 1) {
                  _moveDown();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.backspace &&
                    !inAtomic) {
                  final c = _lineCtrls[idx];
                  final sel = c.selection;
                  if (sel.baseOffset == 0 && sel.extentOffset == 0 && idx > 0) {
                    _mergeWithPrevLine(idx);
                    return KeyEventResult.handled;
                  }
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _lineCtrls[i],
              focusNode: _lineFocuses[i],
              maxLines: inAtomic ? null : 1,
              onSubmitted: inAtomic ? null : (_) => _insertLineAfter(idx),
              style: yBody(size: 15, color: yInk2, height: 1.55),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        );
        i++;
      } else {
        final idx = i;
        widgets.add(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _cursorLine = idx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _lineFocuses[idx].requestFocus();
              });
            },
            child: IgnorePointer(
              child: NoteMarkdownPreview(
                data: _lineCtrls[idx].text,
                accent: widget.accent,
                tight: true,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        );
        i++;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _groupContainer({required bool selected, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        border:
            selected ? Border.all(color: widget.accent, width: yLineMid) : null,
      ),
      child: child,
    );
  }

  Widget _groupPills({
    required List<int> indices,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Positioned(
      top: 4,
      right: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
              decoration: BoxDecoration(
                color: widget.accent,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                'EDITAR',
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  color: yCream,
                  tracking: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yFight,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: const Icon(YuLiIcons.close, size: 12, color: yCream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupFocusWrapper({
    required List<int> indices,
    required bool selected,
    required Widget child,
  }) {
    if (!selected) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _cursorLine = indices.first);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _lineFocuses[indices.first].requestFocus();
          });
        },
        child: IgnorePointer(child: child),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lineFocuses[indices.first].requestFocus();
    });
    return Focus(
      focusNode: _lineFocuses[indices.first],
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final last = indices.last;
          if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
              indices.first > 0) {
            setState(() => _cursorLine = indices.first - 1);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _lineFocuses[_cursorLine].requestFocus(),
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
              last < _lineCtrls.length - 1) {
            setState(() => _cursorLine = last + 1);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _lineFocuses[_cursorLine].requestFocus(),
            );
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _deleteGroup(indices);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  Widget _buildTableGroup(List<int> indices, bool selected) {
    if (_editingTableIndices != null &&
        _listEquals(_editingTableIndices!, indices)) {
      return _TableInlineEditor(
        initialData: indices.map((i) => _lineCtrls[i].text).join('\n'),
        accent: widget.accent,
        onSave: (newMd) => _saveTableEdit(indices, newMd),
        onCancel: _cancelTableEdit,
      );
    }
    final text = indices.map((i) => _lineCtrls[i].text).join('\n');
    final preview = IgnorePointer(
      child: NoteMarkdownPreview(
        data: text,
        accent: widget.accent,
        tight: true,
        padding: EdgeInsets.zero,
      ),
    );
    return Stack(
      children: [
        _groupContainer(
          selected: selected,
          child: _groupFocusWrapper(
            indices: indices,
            selected: selected,
            child: preview,
          ),
        ),
        if (selected)
          _groupPills(
            indices: indices,
            onEdit: () => _editTableGroup(indices),
            onDelete: () => _deleteGroup(indices),
          ),
      ],
    );
  }

  Widget _buildImageGroup(List<int> indices, bool selected) {
    final text = indices.map((i) => _lineCtrls[i].text).join('\n');
    final preview = IgnorePointer(
      child: NoteMarkdownPreview(
        data: text,
        accent: widget.accent,
        tight: true,
        padding: EdgeInsets.zero,
      ),
    );
    return Stack(
      children: [
        _groupContainer(
          selected: selected,
          child: _groupFocusWrapper(
            indices: indices,
            selected: selected,
            child: preview,
          ),
        ),
        if (selected)
          _groupPills(
            indices: indices,
            onEdit: () => _editImageGroup(indices),
            onDelete: () => _deleteGroup(indices),
          ),
      ],
    );
  }

  Widget _buildFenceGroup(List<int> indices, bool selected) {
    if (_editingFenceIndices != null &&
        _listEquals(_editingFenceIndices!, indices)) {
      return _CodeInlineEditor(
        initialData: indices.map((i) => _lineCtrls[i].text).join('\n'),
        accent: widget.accent,
        onSave: (newMd) => _saveFenceEdit(indices, newMd),
        onCancel: _cancelFenceEdit,
      );
    }
    final text = indices.map((i) => _lineCtrls[i].text).join('\n');
    final preview = IgnorePointer(
      child: NoteMarkdownPreview(
        data: text,
        accent: widget.accent,
        tight: true,
        padding: EdgeInsets.zero,
      ),
    );
    return Stack(
      children: [
        _groupContainer(
          selected: selected,
          child: _groupFocusWrapper(
            indices: indices,
            selected: selected,
            child: preview,
          ),
        ),
        if (selected)
          _groupPills(
            indices: indices,
            onEdit: () => _editFenceGroup(indices),
            onDelete: () => _deleteGroup(indices),
          ),
      ],
    );
  }

  void _deleteGroup(List<int> indices) {
    for (final i in indices.reversed) {
      _lineCtrls[i].removeListener(_onLiveLineChanged);
      _lineCtrls[i].dispose();
      _lineFocuses[i].removeListener(_onLiveFocusChange);
      _lineFocuses[i].dispose();
      _lineCtrls.removeAt(i);
      _lineFocuses.removeAt(i);
    }
    _syncLiveToCtrl();
    _cursorLine = indices.first.clamp(0, _lineCtrls.length - 1);
    if (_cursorLine < 0) _cursorLine = 0;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lineFocuses.isNotEmpty) {
        _lineFocuses[_cursorLine].requestFocus();
      } else {
        _toggleLive();
      }
    });
  }

  void _editTableGroup(List<int> indices) {
    setState(() => _editingTableIndices = indices);
  }

  void _cancelTableEdit() {
    setState(() => _editingTableIndices = null);
  }

  void _saveTableEdit(List<int> indices, String newMd) {
    _replaceGroup(indices, newMd);
    setState(() => _editingTableIndices = null);
  }

  void _editFenceGroup(List<int> indices) {
    setState(() => _editingFenceIndices = indices);
  }

  void _cancelFenceEdit() {
    setState(() => _editingFenceIndices = null);
  }

  void _saveFenceEdit(List<int> indices, String newMd) {
    _replaceGroup(indices, newMd);
    setState(() => _editingFenceIndices = null);
  }

  void _editImageGroup(List<int> indices) {
    final text = indices.map((i) => _lineCtrls[i].text).join('\n');
    widget.onRequestEditor?.call(
      _ImageEditor(
        initialData: text,
        noteId: widget.noteId,
        accent: widget.accent,
        onSave: (newMd) {
          _replaceGroup(indices, newMd);
          widget.onRequestEditor?.call(null);
        },
        onClose: () => widget.onRequestEditor?.call(null),
      ),
    );
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _replaceGroup(List<int> indices, String newMd) {
    final newLines = newMd.split('\n');
    for (final i in indices.reversed) {
      _lineCtrls[i].removeListener(_onLiveLineChanged);
      _lineCtrls[i].dispose();
      _lineFocuses[i].removeListener(_onLiveFocusChange);
      _lineFocuses[i].dispose();
      _lineCtrls.removeAt(i);
      _lineFocuses.removeAt(i);
    }
    for (int j = 0; j < newLines.length; j++) {
      final c = TextEditingController(text: newLines[j]);
      c.addListener(_onLiveLineChanged);
      _lineCtrls.insert(indices.first + j, c);
      final f = FocusNode();
      f.addListener(_onLiveFocusChange);
      _lineFocuses.insert(indices.first + j, f);
    }
    _syncLiveToCtrl();
    _cursorLine = indices.first.clamp(0, _lineCtrls.length - 1);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lineFocuses.isNotEmpty) {
        _lineFocuses[_cursorLine].requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_livePreview) return _buildLiveMode();

    if (!_hasFocus && _ctrl.text.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _hasFocus = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focus.requestFocus();
          });
        },
        child: IgnorePointer(
          child: NoteMarkdownPreview(data: _ctrl.text, accent: widget.accent),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRawToggle(),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          maxLines: null,
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
        ),
      ],
    );
  }
}

// ─── Edit overlay widgets (rendered as Positioned.fill in note_editor_screen) ─

class _TableEditor extends StatefulWidget {
  final String initialData;
  final Color accent;
  final void Function(String newMarkdown) onSave;
  final VoidCallback onClose;

  const _TableEditor({
    required this.initialData,
    required this.accent,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late List<List<TextEditingController>> _cells;
  late List<List<FocusNode>> _focuses;
  int _rows = 0;
  int _cols = 0;
  String _align = 'left';

  @override
  void initState() {
    super.initState();
    _parseTable();
  }

  void _parseTable() {
    final lines =
        widget.initialData
            .trim()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
    if (lines.length < 2) {
      _cells = [
        [TextEditingController()],
        [TextEditingController()],
      ];
      _focuses = [
        [FocusNode(), FocusNode()],
        [FocusNode(), FocusNode()],
      ];
      _rows = 2;
      _cols = 1;
      return;
    }
    _cols =
        lines[0]
            .trim()
            .replaceAll(RegExp(r'^\|'), '')
            .replaceAll(RegExp(r'\|$'), '')
            .split('|')
            .length;
    final dataRows = <List<String>>[];
    for (int i = 0; i < lines.length; i++) {
      final isSep = i == 1;
      if (isSep) {
        final seps = lines[i]
            .trim()
            .replaceAll(RegExp(r'^\|'), '')
            .replaceAll(RegExp(r'\|$'), '')
            .split('|');
        if (seps.any(
          (s) => s.trim().startsWith(':') && s.trim().endsWith(':'),
        )) {
          _align = 'center';
        } else if (seps.any((s) => s.trim().endsWith(':'))) {
          _align = 'right';
        } else if (seps.any((s) => s.trim().startsWith(':'))) {
          _align = 'left';
        }
        continue;
      }
      final cells =
          lines[i]
              .trim()
              .replaceAll(RegExp(r'^\|'), '')
              .replaceAll(RegExp(r'\|$'), '')
              .split('|')
              .map((c) => c.trim())
              .toList();
      while (cells.length < _cols) {
        cells.add('');
      }
      dataRows.add(cells.take(_cols).toList());
    }
    _rows = dataRows.length;
    _cells =
        dataRows
            .map((r) => r.map((c) => TextEditingController(text: c)).toList())
            .toList();
    _focuses = List.generate(
      _rows,
      (_) => List.generate(_cols, (_) => FocusNode()),
    );
  }

  String _generateMarkdown() {
    final buf = StringBuffer();
    buf.write('|');
    for (int c = 0; c < _cols; c++) {
      buf.write(' ${_cells[0][c].text} |');
    }
    buf.write('\n|');
    for (int c = 0; c < _cols; c++) {
      switch (_align) {
        case 'center':
          buf.write(' :---: |');
        case 'right':
          buf.write(' ---: |');
        default:
          buf.write(' --- |');
      }
    }
    for (int r = 1; r < _rows; r++) {
      buf.write('\n|');
      for (int c = 0; c < _cols; c++) {
        buf.write(' ${_cells[r][c].text} |');
      }
    }
    buf.write('\n');
    final table = buf.toString().trim();
    if (_align != 'left') return '\n::: $_align\n$table\n:::\n';
    return '\n$table\n';
  }

  void _addRow() {
    setState(() {
      _rows++;
      _cells.add(List.generate(_cols, (_) => TextEditingController()));
      _focuses.add(List.generate(_cols, (_) => FocusNode()));
    });
  }

  void _removeRow() {
    if (_rows <= 2) return;
    setState(() {
      _rows--;
      for (final c in _cells.removeLast()) {
        c.dispose();
      }
      for (final f in _focuses.removeLast()) {
        f.dispose();
      }
    });
  }

  void _addCol() {
    setState(() {
      _cols++;
      for (final row in _cells) {
        row.add(TextEditingController());
      }
      for (final row in _focuses) {
        row.add(FocusNode());
      }
    });
  }

  void _removeCol() {
    if (_cols <= 1) return;
    setState(() {
      _cols--;
      for (final row in _cells) {
        row.removeLast().dispose();
      }
      for (final row in _focuses) {
        row.removeLast().dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _focuses) {
      for (final f in row) {
        f.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxW = 640.0;
    return Container(
      color: yCream,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tabla',
                      style: ySans(
                        size: 24,
                        weight: FontWeight.w700,
                        color: yInk,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(YuLiIcons.close, color: yInk, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  _counter(
                    label: 'fil',
                    value: _rows - 1,
                    onAdd: _addRow,
                    onRemove: _rows > 2 ? _removeRow : null,
                  ),
                  const SizedBox(width: 20),
                  _counter(
                    label: 'col',
                    value: _cols,
                    onAdd: _addCol,
                    onRemove: _cols > 1 ? _removeCol : null,
                  ),
                  const SizedBox(width: 20),
                  _alignBtn('left'),
                  const SizedBox(width: 4),
                  _alignBtn('center'),
                  const SizedBox(width: 4),
                  _alignBtn('right'),
                ],
              ),
            ),
            Container(height: 1, color: yBorderStrong.withValues(alpha: 0.3)),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Table(
                        border: TableBorder.all(
                          color: yBorderSoft,
                          width: yLineThin,
                        ),
                        columnWidths: {
                          for (int c = 0; c < _cols; c++)
                            c: const FixedColumnWidth(140),
                        },
                        children: [
                          for (int r = 0; r < _rows; r++)
                            TableRow(
                              decoration:
                                  r == 0
                                      ? BoxDecoration(
                                        color: yInk.withValues(alpha: 0.04),
                                      )
                                      : null,
                              children: [
                                for (int c = 0; c < _cols; c++)
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: TextField(
                                      controller: _cells[r][c],
                                      focusNode: _focuses[r][c],
                                      maxLines: null,
                                      style: yBody(
                                        size: r == 0 ? 14 : 13,
                                        color: yInk,
                                        weight:
                                            r == 0
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: r == 0 ? 'Col ${c + 1}' : '',
                                        hintStyle: yBody(
                                          size: 13,
                                          color: yMuted.withValues(alpha: 0.5),
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: const EdgeInsets.all(6),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSave(_generateMarkdown());
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: widget.accent,
                  border: const Border(
                    top: BorderSide(color: yBorderStrong, width: yLineMid),
                  ),
                ),
                child: Center(
                  child: Text(
                    'GUARDAR',
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yCream,
                    ).copyWith(letterSpacing: 1.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counter({
    required String label,
    required int value,
    required VoidCallback onAdd,
    VoidCallback? onRemove,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRemove != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                '−',
                style: yBody(size: 14, color: yInk, height: 1.0),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value $label', style: yBody(size: 12, color: yInk)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAdd,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Text('+', style: yBody(size: 14, color: yInk, height: 1.0)),
          ),
        ),
      ],
    );
  }

  Widget _alignBtn(String value) {
    final selected = _align == value;
    final label =
        value == 'left'
            ? '←'
            : value == 'center'
            ? '↔'
            : '→';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _align = value),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(size: 12, color: selected ? yCream : yInk, height: 1.0),
        ),
      ),
    );
  }
}

class _CodeEditor extends StatefulWidget {
  final String initialData;
  final Color accent;
  final void Function(String newMarkdown) onSave;
  final VoidCallback onClose;

  const _CodeEditor({
    required this.initialData,
    required this.accent,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<_CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<_CodeEditor> {
  late TextEditingController _langCtrl;
  late TextEditingController _codeCtrl;
  late FocusNode _langFocus;
  late FocusNode _codeFocus;

  @override
  void initState() {
    super.initState();
    _langFocus = FocusNode();
    _codeFocus = FocusNode();
    final lines = widget.initialData.split('\n');
    String lang = '';
    final codeLines = <String>[];
    for (int i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('```') && i == 0 && t.length > 3) {
        lang = t.substring(3).trim();
      } else if (!t.startsWith('```')) {
        codeLines.add(lines[i]);
      }
    }
    _langCtrl = TextEditingController(text: lang);
    _codeCtrl = TextEditingController(text: codeLines.join('\n'));
  }

  @override
  void dispose() {
    _langCtrl.dispose();
    _codeCtrl.dispose();
    _langFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String _generate() {
    final lang = _langCtrl.text.trim();
    final code = _codeCtrl.text;
    return '```$lang\n$code\n```';
  }

  @override
  Widget build(BuildContext context) {
    final maxW = 600.0;
    return Container(
      color: yCream,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Codigo',
                      style: ySans(
                        size: 24,
                        weight: FontWeight.w700,
                        color: yInk,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(YuLiIcons.close, color: yInk, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Text(
                'Lenguaje',
                style: yBody(size: 14, weight: FontWeight.w700, color: yInk),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: TextField(
                controller: _langCtrl,
                focusNode: _langFocus,
                style: yBody(size: 16, color: yInk),
                decoration: const InputDecoration(
                  hintText: 'python, dart, js...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderSoft,
                      width: yLineThin,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderSoft,
                      width: yLineThin,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderStrong,
                      width: yLineMid,
                    ),
                  ),
                  contentPadding: EdgeInsets.all(12),
                  isDense: true,
                ),
              ),
            ),
            Container(height: 1, color: yBorderStrong.withValues(alpha: 0.3)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _codeCtrl,
                  focusNode: _codeFocus,
                  style: yMono(size: 14, color: yInk, tracking: 0),
                  maxLines: null,
                  minLines: 8,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: yBorderSoft,
                        width: yLineThin,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: yBorderSoft,
                        width: yLineThin,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: yBorderStrong,
                        width: yLineMid,
                      ),
                    ),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                widget.onSave(_generate());
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: widget.accent,
                  border: const Border(
                    top: BorderSide(color: yBorderStrong, width: yLineMid),
                  ),
                ),
                child: Center(
                  child: Text(
                    'GUARDAR',
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yCream,
                    ).copyWith(letterSpacing: 1.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageEditor extends ConsumerStatefulWidget {
  final String initialData;
  final int noteId;
  final Color accent;
  final void Function(String newMarkdown) onSave;
  final VoidCallback onClose;

  const _ImageEditor({
    required this.initialData,
    required this.noteId,
    required this.accent,
    required this.onSave,
    required this.onClose,
  });

  @override
  ConsumerState<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends ConsumerState<_ImageEditor> {
  String _imagePath = '';
  String _alt = 'Imagen';
  String? _align;
  XFile? _newFile;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    final raw = widget.initialData.trim();
    final lines = raw.split('\n');
    if (lines.length >= 3 &&
        lines[0].trim().startsWith(':::') &&
        lines[2].trim() == ':::') {
      _align = lines[0].trim().replaceAll(':::', '').trim();
      _parseImageLine(lines[1].trim());
    } else {
      _parseImageLine(raw);
    }
  }

  void _parseImageLine(String line) {
    final re = RegExp(r'^!\[(.*)\]\((.*)\)$');
    final m = re.firstMatch(line);
    if (m != null) {
      _alt = m.group(1) ?? 'Imagen';
      _imagePath = m.group(2) ?? '';
    }
  }

  String _generate() {
    final img = '![$_alt]($_imagePath)';
    if (_align != null) return '::: $_align\n$img\n:::';
    return img;
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null && mounted) setState(() => _newFile = picked);
  }

  Future<void> _save() async {
    if (_newFile != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(
          p.join(appDir.path, 'note_images', '${widget.noteId}'),
        );
        await imagesDir.create(recursive: true);
        final ext = p.extension(_newFile!.path).toLowerCase();
        final newFilename = '${const Uuid().v4()}$ext';
        final newPath = p.join(imagesDir.path, newFilename);
        await File(_newFile!.path).copy(newPath);
        final fileSize = await File(newPath).length();
        await ref
            .read(noteRepositoryProvider)
            .addImage(widget.noteId, newFilename, newPath, fileSize);
        _imagePath = newPath;
      } catch (_) {}
    }
    widget.onSave(_generate());
  }

  @override
  Widget build(BuildContext context) {
    final maxW = 480.0;
    return Container(
      color: yCream,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Imagen',
                      style: ySans(
                        size: 24,
                        weight: FontWeight.w700,
                        color: yInk,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(YuLiIcons.close, color: yInk, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_newFile != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: Image.file(
                        File(_newFile!.path),
                        fit: BoxFit.contain,
                      ),
                    )
                  else if (_imagePath.isNotEmpty)
                    IgnorePointer(
                      child: NoteMarkdownPreview(
                        data: '![$_alt]($_imagePath)',
                        accent: widget.accent,
                        tight: true,
                        padding: EdgeInsets.zero,
                      ),
                    )
                  else
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineThin,
                        ),
                      ),
                      child: const Center(
                        child: Icon(YuLiIcons.image, size: 48, color: yMuted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineThin,
                        ),
                      ),
                      child: Text(
                        'Cambiar imagen',
                        style: yBody(
                          size: 13,
                          weight: FontWeight.w700,
                          color: yInk,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Alineacion',
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _alignPill('Izquierda', 'left'),
                      const SizedBox(width: 6),
                      _alignPill('Centro', 'center'),
                      const SizedBox(width: 6),
                      _alignPill('Derecha', 'right'),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _save,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: widget.accent,
                  border: const Border(
                    top: BorderSide(color: yBorderStrong, width: yLineMid),
                  ),
                ),
                child: Center(
                  child: Text(
                    'GUARDAR',
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yCream,
                    ).copyWith(letterSpacing: 1.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alignPill(String label, String value) {
    final selected = _align == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _align = selected ? null : value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(
            size: 11,
            weight: FontWeight.w700,
            color: selected ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

// ─── Inline editors (rendered in place of the group preview) ───────────────

class _TableInlineEditor extends StatefulWidget {
  final String initialData;
  final Color accent;
  final void Function(String newMarkdown) onSave;
  final VoidCallback onCancel;

  const _TableInlineEditor({
    required this.initialData,
    required this.accent,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_TableInlineEditor> createState() => _TableInlineEditorState();
}

class _TableInlineEditorState extends State<_TableInlineEditor> {
  late List<List<TextEditingController>> _cells;
  late List<List<FocusNode>> _focuses;
  int _rows = 0;
  int _cols = 0;
  String _align = 'left';

  @override
  void initState() {
    super.initState();
    _parseTable();
  }

  void _parseTable() {
    final lines =
        widget.initialData
            .trim()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
    if (lines.length < 2) {
      _cells = [
        [TextEditingController()],
        [TextEditingController()],
      ];
      _focuses = [
        [FocusNode(), FocusNode()],
        [FocusNode(), FocusNode()],
      ];
      _rows = 2;
      _cols = 1;
      return;
    }
    _cols =
        lines[0]
            .trim()
            .replaceAll(RegExp(r'^\|'), '')
            .replaceAll(RegExp(r'\|$'), '')
            .split('|')
            .length;
    final dataRows = <List<String>>[];
    for (int i = 0; i < lines.length; i++) {
      final isSep = i == 1;
      if (isSep) {
        final seps = lines[i]
            .trim()
            .replaceAll(RegExp(r'^\|'), '')
            .replaceAll(RegExp(r'\|$'), '')
            .split('|');
        if (seps.any(
          (s) => s.trim().startsWith(':') && s.trim().endsWith(':'),
        )) {
          _align = 'center';
        } else if (seps.any((s) => s.trim().endsWith(':'))) {
          _align = 'right';
        } else if (seps.any((s) => s.trim().startsWith(':'))) {
          _align = 'left';
        }
        continue;
      }
      final cells =
          lines[i]
              .trim()
              .replaceAll(RegExp(r'^\|'), '')
              .replaceAll(RegExp(r'\|$'), '')
              .split('|')
              .map((c) => c.trim())
              .toList();
      while (cells.length < _cols) {
        cells.add('');
      }
      dataRows.add(cells.take(_cols).toList());
    }
    _rows = dataRows.length;
    _cells =
        dataRows
            .map((r) => r.map((c) => TextEditingController(text: c)).toList())
            .toList();
    _focuses = List.generate(
      _rows,
      (_) => List.generate(_cols, (_) => FocusNode()),
    );
  }

  String _generateMarkdown() {
    final buf = StringBuffer();
    buf.write('|');
    for (int c = 0; c < _cols; c++) {
      buf.write(' ${_cells[0][c].text} |');
    }
    buf.write('\n|');
    for (int c = 0; c < _cols; c++) {
      switch (_align) {
        case 'center':
          buf.write(' :---: |');
        case 'right':
          buf.write(' ---: |');
        default:
          buf.write(' --- |');
      }
    }
    for (int r = 1; r < _rows; r++) {
      buf.write('\n|');
      for (int c = 0; c < _cols; c++) {
        buf.write(' ${_cells[r][c].text} |');
      }
    }
    buf.write('\n');
    final table = buf.toString().trim();
    if (_align != 'left') return '\n::: $_align\n$table\n:::\n';
    return '\n$table\n';
  }

  void _addRow() {
    setState(() {
      _rows++;
      _cells.add(List.generate(_cols, (_) => TextEditingController()));
      _focuses.add(List.generate(_cols, (_) => FocusNode()));
    });
  }

  void _removeRow() {
    if (_rows <= 2) return;
    setState(() {
      _rows--;
      for (final c in _cells.removeLast()) {
        c.dispose();
      }
      for (final f in _focuses.removeLast()) {
        f.dispose();
      }
    });
  }

  void _addCol() {
    setState(() {
      _cols++;
      for (final row in _cells) {
        row.add(TextEditingController());
      }
      for (final row in _focuses) {
        row.add(FocusNode());
      }
    });
  }

  void _removeCol() {
    if (_cols <= 1) return;
    setState(() {
      _cols--;
      for (final row in _cells) {
        row.removeLast().dispose();
      }
      for (final row in _focuses) {
        row.removeLast().dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _focuses) {
      for (final f in row) {
        f.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: widget.accent, width: yLineMid),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                _counter(
                  label: 'fil',
                  value: _rows - 1,
                  onAdd: _addRow,
                  onRemove: _rows > 2 ? _removeRow : null,
                ),
                const SizedBox(width: 20),
                _counter(
                  label: 'col',
                  value: _cols,
                  onAdd: _addCol,
                  onRemove: _cols > 1 ? _removeCol : null,
                ),
                const SizedBox(width: 20),
                _alignBtn('left'),
                const SizedBox(width: 4),
                _alignBtn('center'),
                const SizedBox(width: 4),
                _alignBtn('right'),
              ],
            ),
          ),
          Container(height: 1, color: yBorderStrong.withValues(alpha: 0.3)),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Table(
                  border: TableBorder.all(color: yBorderSoft, width: yLineThin),
                  columnWidths: {
                    for (int c = 0; c < _cols; c++)
                      c: const FixedColumnWidth(140),
                  },
                  children: [
                    for (int r = 0; r < _rows; r++)
                      TableRow(
                        decoration:
                            r == 0
                                ? BoxDecoration(
                                  color: yInk.withValues(alpha: 0.04),
                                )
                                : null,
                        children: [
                          for (int c = 0; c < _cols; c++)
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: TextField(
                                controller: _cells[r][c],
                                focusNode: _focuses[r][c],
                                maxLines: null,
                                style: yBody(
                                  size: r == 0 ? 14 : 13,
                                  color: yInk,
                                  weight:
                                      r == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                ),
                                decoration: InputDecoration(
                                  hintText: r == 0 ? 'Col ${c + 1}' : '',
                                  hintStyle: yBody(
                                    size: 13,
                                    color: yMuted.withValues(alpha: 0.5),
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(6),
                                  isDense: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'CANCELAR',
                        style: yBody(
                          size: 12,
                          weight: FontWeight.w700,
                          color: yInk,
                        ).copyWith(letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 44, color: yBorderStrong),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onSave(_generateMarkdown());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.accent,
                      border: const Border(
                        top: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'GUARDAR',
                        style: yBody(
                          size: 12,
                          weight: FontWeight.w700,
                          color: yCream,
                        ).copyWith(letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _counter({
    required String label,
    required int value,
    required VoidCallback onAdd,
    VoidCallback? onRemove,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onRemove != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                '−',
                style: yBody(size: 14, color: yInk, height: 1.0),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value $label', style: yBody(size: 12, color: yInk)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAdd,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Text('+', style: yBody(size: 14, color: yInk, height: 1.0)),
          ),
        ),
      ],
    );
  }

  Widget _alignBtn(String value) {
    final selected = _align == value;
    final label =
        value == 'left'
            ? '←'
            : value == 'center'
            ? '↔'
            : '→';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _align = value),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? widget.accent : Colors.transparent,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(size: 12, color: selected ? yCream : yInk, height: 1.0),
        ),
      ),
    );
  }
}

class _CodeInlineEditor extends StatefulWidget {
  final String initialData;
  final Color accent;
  final void Function(String newMarkdown) onSave;
  final VoidCallback onCancel;

  const _CodeInlineEditor({
    required this.initialData,
    required this.accent,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_CodeInlineEditor> createState() => _CodeInlineEditorState();
}

class _CodeInlineEditorState extends State<_CodeInlineEditor> {
  late TextEditingController _langCtrl;
  late TextEditingController _codeCtrl;
  late FocusNode _langFocus;
  late FocusNode _codeFocus;

  @override
  void initState() {
    super.initState();
    _langFocus = FocusNode();
    _codeFocus = FocusNode();
    final lines = widget.initialData.split('\n');
    String lang = '';
    final codeLines = <String>[];
    for (int i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.startsWith('```') && i == 0 && t.length > 3) {
        lang = t.substring(3).trim();
      } else if (!t.startsWith('```')) {
        codeLines.add(lines[i]);
      }
    }
    _langCtrl = TextEditingController(text: lang);
    _codeCtrl = TextEditingController(text: codeLines.join('\n'));
  }

  @override
  void dispose() {
    _langCtrl.dispose();
    _codeCtrl.dispose();
    _langFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String _generate() {
    final lang = _langCtrl.text.trim();
    final code = _codeCtrl.text;
    return '```$lang\n$code\n```';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: widget.accent, width: yLineMid),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: _langCtrl,
              focusNode: _langFocus,
              style: yBody(size: 14, color: yInk, weight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Lenguaje (python, dart, js...)',
                hintStyle: yBody(size: 13, color: yMuted),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
                ),
                contentPadding: const EdgeInsets.all(8),
                isDense: true,
              ),
            ),
          ),
          Container(height: 1, color: yBorderStrong.withValues(alpha: 0.3)),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _codeCtrl,
                focusNode: _codeFocus,
                style: yMono(size: 13, color: yInk, tracking: 0),
                maxLines: null,
                minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Codigo',
                  hintStyle: yBody(size: 13, color: yMuted),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderSoft,
                      width: yLineThin,
                    ),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderSoft,
                      width: yLineThin,
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: yBorderStrong,
                      width: yLineMid,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(8),
                  isDense: true,
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'CANCELAR',
                        style: yBody(
                          size: 12,
                          weight: FontWeight.w700,
                          color: yInk,
                        ).copyWith(letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 40, color: yBorderStrong),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onSave(_generate());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.accent,
                      border: const Border(
                        top: BorderSide(color: yBorderStrong, width: yLineMid),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'GUARDAR',
                        style: yBody(
                          size: 12,
                          weight: FontWeight.w700,
                          color: yCream,
                        ).copyWith(letterSpacing: 1.0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    commitPendingSave();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) flushSave(_persist);
  }

  Future<void> _persist() async {
    await ref.read(noteBlockRepositoryProvider).updatePayload(widget.block.id, {
      'latex': _ctrl.text,
    });
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
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow: const [
              BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 4,
                child: Text(
                  'LATEX · DISPLAY',
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yCream.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Center(
                child:
                    latex.trim().isEmpty
                        ? Text(
                          'introduce LaTeX abajo',
                          style: yMono(
                            size: 12,
                            color: yCream.withValues(alpha: 0.6),
                            tracking: 1.2,
                          ),
                        )
                        : Math.tex(
                          latex,
                          mathStyle: MathStyle.display,
                          textStyle: TextStyle(fontSize: 22, color: yCream),
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
            contentPadding: const EdgeInsets.symmetric(
              vertical: 6,
              horizontal: 4,
            ),
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
    commitPendingSave(); // flush before _ctrls (which _persist reads) are gone
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
    await ref.read(noteBlockRepositoryProvider).updatePayload(widget.block.id, {
      'items': _items,
    });
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'item…',
                      hintStyle: yBody(size: 14, color: yMuted, height: 1.5),
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
                child: Text(
                  '+ item',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _copyAll,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'COPIAR TODO',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  ),
                ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay spaces activos'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final picked = await showDialog<LabSpace>(
      context: context,
      builder: (ctx) => _SpacePickerDialog(spaces: spaces),
    );
    if (picked == null) return;
    await _actions.linkTaskToSpace(t, picked.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Linkeada a ${picked.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onDelete(Task t) async {
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: yCream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: yBorderStrong, width: yLineMid),
            ),
            title: Text(
              'Borrar tarea',
              style: ySans(size: 18, weight: FontWeight.w700),
            ),
            content: Text(
              '¿Solo desenlazar de la nota (sigue viva en FIGHT) o borrar de todos los lugares?',
              style: yBody(size: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _DeleteChoice.unlink),
                child: const Text('Solo desenlazar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _DeleteChoice.hard),
                child: const Text('Borrar de todos lados'),
              ),
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
    final blockTasks =
        allTasks
            .where(
              (t) =>
                  widget.block.taskIds.contains(t.id) &&
                  t.status != TaskStatus.trash,
            )
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
        border: Border.all(color: yBorderStrong, width: yLineMid),
        borderRadius: BorderRadius.zero,
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: widget.accent, width: 6)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '> BLOQUE TAREAS',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk,
                  ),
                ),
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
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: yBorderStrong,
                            width: yLineMid,
                          ),
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
                        border: Border.all(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 18,
                          color: yCream,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (blockTasks.isEmpty && !_showInput)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'sin tareas',
                  style: yMono(
                    size: 10,
                    color: yMuted.withValues(alpha: 0.6),
                    tracking: 1.2,
                  ),
                ),
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
              onTapUp: (d) {
                if (!done) {
                  burstConfetti(
                    context,
                    d.globalPosition,
                    accent: accentFlight,
                  );
                }
                onCheck();
              },
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? yInk : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child:
                    done
                        ? const Icon(YuLiIcons.check, size: 12, color: yCream)
                        : null,
              ),
            ),
            const SizedBox(width: 10),
            if (task.folderId != null) ...[
              Builder(
                builder: (context) {
                  final fColor =
                      ref
                          .watch(folderByIdProvider(task.folderId!))
                          .valueOrNull
                          ?.color;
                  if (fColor == null) return const SizedBox.shrink();
                  return Container(
                    width: 4,
                    height: 16,
                    margin: const EdgeInsets.only(right: 6),
                    color: fColor,
                  );
                },
              ),
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
                child: Icon(
                  YuLiIcons.close,
                  size: 14,
                  color: yMuted.withValues(alpha: 0.6),
                ),
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
        border: Border.all(color: yBorderStrong, width: 1.5),
      ),
      child: Text(
        text,
        style: yMono(
          size: 8,
          weight: FontWeight.w700,
          tracking: 1,
          color: yCream,
        ),
      ),
    );
  }
}

enum _DeleteChoice { unlink, hard }

/// Returns the linked space name for a task (or null if no kanban link).
/// Reactive: refreshes when the linked card is created/moved/deleted.
final _kanbanByTaskProvider = StreamProvider.family<String?, int>((
  ref,
  taskId,
) {
  final labRepo = ref.watch(labSpaceRepositoryProvider);
  return ref
      .watch(kanbanCardRepositoryProvider)
      .watchByOriginTaskId(taskId)
      .asyncMap((card) async {
        if (card == null) return null;
        final space = await labRepo.getById(card.labSpaceId);
        return space?.name;
      });
});

class _SpacePickerDialog extends StatelessWidget {
  final List<LabSpace> spaces;
  const _SpacePickerDialog({required this.spaces});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: yBorderStrong, width: yLineMid),
      ),
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
              'Linkear a space',
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
  ConsumerState<_DrawingBlockBody> createState() => _DrawingBlockBodyState();
}

class _DrawingBlockBodyState extends ConsumerState<_DrawingBlockBody> {
  late DrawingData _data;
  List<int?> _strokeIds = const [];
  Future<void> _persistTail = Future.value();

  @override
  void initState() {
    super.initState();
    _resetDataFromBlock();
    unawaited(_loadStoredStrokes());
  }

  @override
  void didUpdateWidget(covariant _DrawingBlockBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id == widget.block.id) return;
    _resetDataFromBlock();
    unawaited(_loadStoredStrokes());
  }

  void _resetDataFromBlock() {
    _data = _toDrawingData(widget.block);
    _strokeIds = _data.strokes.map((s) => s.dbId).toList();
  }

  Future<void> _loadStoredStrokes() async {
    final rows = await ref
        .read(drawingStrokeRepositoryProvider)
        .getByBlock(widget.block.id);
    if (!mounted || rows.isEmpty) return;
    setState(() {
      _data.strokes = rows.map(strokeFromRecord).toList();
      _strokeIds = _data.strokes.map((s) => s.dbId).toList();
    });
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
    final snapshot = DrawingData(
      height: data.height,
      strokes: data.strokes.map((s) => s.clone()).toList(),
      images: data.images.map((im) => im.clone()).toList(),
      taskBlocks: data.taskBlocks.map((b) => b.clone()).toList(),
      textBlocks: data.textBlocks.map((b) => b.clone()).toList(),
      background: data.background,
      bgColorValue: data.bgColorValue,
    );
    _persistTail = _persistTail
        .catchError((_) {})
        .then((_) => _persistNow(snapshot));
    await PendingSaves.track(_persistTail, owner: this);
  }

  Future<void> _persistNow(DrawingData data) async {
    final strokeRepo = ref.read(drawingStrokeRepositoryProvider);
    final appendOnly =
        data.strokes.length > _strokeIds.length &&
        _strokeIds.asMap().entries.every(
          (e) => data.strokes[e.key].dbId == e.value,
        ) &&
        data.strokes.skip(_strokeIds.length).every((s) => s.dbId == null);
    if (appendOnly) {
      for (int i = _strokeIds.length; i < data.strokes.length; i++) {
        final id = await strokeRepo.insert(
          widget.block.id,
          strokeWrite(i, data.strokes[i]),
        );
        data.strokes[i].dbId = id;
        if (i < _data.strokes.length) {
          _data.strokes[i].dbId = id;
        }
      }
    } else {
      final ids = await strokeRepo.replaceBlock(widget.block.id, [
        for (int i = 0; i < data.strokes.length; i++)
          strokeWrite(i, data.strokes[i]),
      ]);
      for (int i = 0; i < data.strokes.length && i < ids.length; i++) {
        data.strokes[i].dbId = ids[i];
        if (i < _data.strokes.length) {
          _data.strokes[i].dbId = ids[i];
        }
      }
    }
    _strokeIds = data.strokes.map((s) => s.dbId).toList();
    await ref.read(noteBlockRepositoryProvider).updatePayload(widget.block.id, {
      'h': data.height,
      's': const [],
    });
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
      onRecognizeText:
          (strokes) => runOcrFlow(
            context,
            ref,
            strokes,
            accent: widget.accent,
            folderId: widget.folderId,
            noteId: widget.block.noteId,
          ),
      onSendImageToYuli: (bytes) async {
        try {
          final prepared = await prepareAiChatImageBytes(bytes);
          if (!context.mounted) {
            await deleteAiChatImage(prepared);
            return;
          }
          await showAiChat(
            context,
            ref,
            noteId: widget.block.noteId,
            pendingImages: [prepared],
            accent: widget.accent,
          );
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No pude preparar esa selección.')),
          );
        }
      },
      onSendMathToYuli:
          kDebugMode
              ? (strokes) => runMathToYuliFlow(
                context,
                ref,
                strokes,
                accent: widget.accent,
                noteId: widget.block.noteId,
              )
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

bool _hasMarkdownTable(String md) {
  return _extractMarkdownTables(md).isNotEmpty;
}

List<String> _extractMarkdownTables(String md) {
  if (!md.contains('|')) return const [];
  final lines = md.split('\n');
  final tables = <String>[];
  final separator = RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*\|[\s:|-]*\s*$');
  String? activeFence;

  for (var i = 0; i < lines.length - 1; i++) {
    final trimmed = lines[i].trimLeft();
    if (activeFence != null) {
      if (trimmed.startsWith(activeFence)) activeFence = null;
      continue;
    }
    if (trimmed.startsWith('```')) {
      activeFence = '```';
      continue;
    }
    if (trimmed.startsWith('~~~')) {
      activeFence = '~~~';
      continue;
    }
    if (!lines[i].contains('|') || !separator.hasMatch(lines[i + 1])) continue;

    var end = i + 2;
    while (end < lines.length &&
        lines[end].trim().isNotEmpty &&
        lines[end].contains('|')) {
      end++;
    }
    tables.add(lines.sublist(i, end).join('\n').trimRight());
    i = end - 1;
  }
  return tables;
}

double _markdownTableWidth(String md, double viewportWidth) {
  final rows =
      md
          .split('\n')
          .where(
            (line) =>
                line.contains('|') &&
                !RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*\s*$').hasMatch(line),
          )
          .map(_markdownTableCells)
          .where((cells) => cells.length > 1)
          .toList();
  if (rows.isEmpty) return viewportWidth;
  final columnCount = rows.fold<int>(
    0,
    (max, cells) => cells.length > max ? cells.length : max,
  );
  final columnWidths = List<double>.filled(columnCount, 72);
  var tableHasMath = false;
  for (final cells in rows) {
    for (var i = 0; i < cells.length; i++) {
      final longestWord = cells[i]
          .split(RegExp(r'\s+'))
          .fold<int>(0, (max, word) => word.length > max ? word.length : max);
      final cellLength = cells[i].length;
      final hasMath =
          cells[i].contains(r'$') ||
          cells[i].contains('\\') ||
          cells[i].contains('∫') ||
          cells[i].contains('∑');
      tableHasMath = tableHasMath || hasMath;
      final estimated =
          hasMath
              ? (cellLength * 9.5 + 72).clamp(160, 560)
              : (longestWord * 7.5 + cellLength * 1.8 + 32).clamp(72, 220);
      if (estimated > columnWidths[i]) columnWidths[i] = estimated.toDouble();
    }
  }
  final estimated =
      tableHasMath
          ? columnWidths.reduce((a, b) => a > b ? a : b) * columnCount + 32
          : columnWidths.fold<double>(32, (sum, w) => sum + w);
  final overflowThreshold = viewportWidth * 1.08;
  if (estimated <= overflowThreshold) return viewportWidth;
  return estimated.clamp(viewportWidth, 1400).toDouble();
}

List<String> _markdownTableCells(String row) {
  var value = row.trim();
  if (value.startsWith('|')) value = value.substring(1);
  if (value.endsWith('|')) value = value.substring(0, value.length - 1);
  return value.split('|').map((cell) => cell.trim()).toList();
}

class NoteMarkdownPreview extends ConsumerWidget {
  final String data;
  final bool tight;
  final Color accent;
  final TextStyle? textStyle;
  final EdgeInsets? padding;
  final bool scrollWideTables;
  final ValueChanged<String>? onCopyBlock;
  final ValueChanged<String>? onPinBlock;
  final ValueChanged<String>? onWikiLinkTap;
  const NoteMarkdownPreview({
    super.key,
    required this.data,
    this.tight = false,
    this.accent = yFlight,
    this.textStyle,
    this.padding,
    this.scrollWideTables = true,
    this.onCopyBlock,
    this.onPinBlock,
    this.onWikiLinkTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final md = fixMarkdownTables(data);
    final tableMarkdown =
        onCopyBlock == null && onPinBlock == null
            ? const <String>[]
            : _extractMarkdownTables(md);
    var renderedTableIndex = 0;
    SpanNode? customTextGenerator(
      m.Node node,
      MarkdownConfig config,
      WidgetVisitor visitor,
    ) {
      return null;
    }

    final generator = MarkdownGenerator(
      textGenerator: customTextGenerator,
      linesMargin: tight ? EdgeInsets.zero : const EdgeInsets.only(bottom: 8),
      inlineSyntaxList: [_WikiLinkSyntax(), _LatexSyntax()],
      blockSyntaxList: [
        const _DefinitionListSyntax(),
        const _LatexBlockSyntax(),
        const _AlignmentBlockSyntax(),
      ],
      generators: [
        SpanNodeGeneratorWithTag(
          tag: 'hr',
          generator:
              (e, config, visitor) => _MarkdownHorizontalRuleNode(accent),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'wikilink',
          generator:
              (e, config, visitor) => _WikiLinkNode(
                e.attributes['label'] ?? e.textContent,
                accent,
                onWikiLinkTap,
              ),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'latex',
          generator:
              (e, config, visitor) => _LatexNode(
                e.attributes,
                e.textContent,
                config,
                accent: accent,
                onCopyBlock: onCopyBlock,
                onPinBlock: onPinBlock,
              ),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'align',
          generator:
              (e, config, visitor) => _AlignmentNode(
                e.attributes['align'] ?? 'left',
                e.textContent,
                config,
              ),
        ),
        SpanNodeGeneratorWithTag(
          tag: 'deflist',
          generator:
              (e, config, visitor) =>
                  _DefinitionListNode(e.attributes['data'] ?? '', config),
        ),
      ],
    );

    final config = MarkdownConfig(
      configs: [
        PConfig(
          textStyle: textStyle ?? yBody(size: 15, color: yInk2, height: 1.55),
        ),
        H1Config(
          style: ySans(
            size: 28,
            weight: FontWeight.w700,
            letterSpacing: -0.8,
            color: yInk,
          ),
        ),
        H2Config(
          style: ySans(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.5,
            color: yInk,
          ),
        ),
        H3Config(
          style: ySans(
            size: 18,
            weight: FontWeight.w700,
            letterSpacing: -0.3,
            color: yInk,
          ),
        ),
        CheckBoxConfig(
          builder:
              (checked) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  checked ? YuLiIcons.squareCheck : YuLiIcons.square,
                  size: 18,
                  color: yInk,
                ),
              ),
        ),
        CodeConfig(
          style: yMono(
            size: 12,
            color: yInk,
            tracking: 0.5,
          ).copyWith(backgroundColor: yCream2),
        ),
        if (onCopyBlock != null || onPinBlock != null)
          PreConfig(
            wrapper: (child, code, language) {
              final cleanCode = code.trimRight();
              final cleanLanguage = language.trim();
              final markdown = '```$cleanLanguage\n$cleanCode\n```';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  Align(
                    alignment: Alignment.centerRight,
                    child: MarkdownBlockActions(
                      accent: accent,
                      onCopy:
                          onCopyBlock == null
                              ? null
                              : () => onCopyBlock!(cleanCode),
                      onPin:
                          onPinBlock == null
                              ? null
                              : () => onPinBlock!(markdown),
                    ),
                  ),
                ],
              );
            },
          ),
        if (tableMarkdown.isNotEmpty)
          TableConfig(
            wrapper: (child) {
              final markdown =
                  tableMarkdown[renderedTableIndex % tableMarkdown.length];
              renderedTableIndex++;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MarkdownBlockActions(
                      accent: accent,
                      onCopy:
                          onCopyBlock == null
                              ? null
                              : () => onCopyBlock!(markdown),
                      onPin:
                          onPinBlock == null
                              ? null
                              : () => onPinBlock!(markdown),
                    ),
                  ),
                ],
              );
            },
          ),
        BlockquoteConfig(textColor: yMuted, sideColor: accent),
        ImgConfig(
          builder: (url, attributes) {
            final maxW = MediaQuery.of(context).size.width * 0.75;
            Widget img;
            if (url.startsWith('/')) {
              img = Image.file(
                File(url),
                fit: BoxFit.contain,
                errorBuilder:
                    (_, _, _) => Text(
                      '[Imagen no encontrada]',
                      style: yBody(size: 13, color: yMuted),
                    ),
              );
            } else {
              img = Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, _, _) => Text(
                      '[Imagen: $url]',
                      style: yBody(size: 13, color: yMuted),
                    ),
              );
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
      ],
    );
    final previewPadding =
        padding ??
        (tight
            ? const EdgeInsets.symmetric(vertical: 4)
            : const EdgeInsets.all(8.0));
    final Widget markdown =
        tight
            ? Padding(
              padding: previewPadding,
              child: MarkdownBlock(
                data: md,
                selectable: false,
                generator: generator,
                config: config,
              ),
            )
            : MarkdownWidget(
              data: md,
              shrinkWrap: true,
              padding: previewPadding,
              markdownGenerator: generator,
              config: config,
            );
    if (!_hasMarkdownTable(md) || !scrollWideTables) {
      return SizedBox(width: double.infinity, child: markdown);
    }
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.maxWidth.isFinite) return markdown;
          final tableWidth = _markdownTableWidth(md, constraints.maxWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: tableWidth, child: markdown),
          );
        },
      ),
    );
  }
}

class _WikiLinkNode extends SpanNode {
  final String label;
  final Color accent;
  final ValueChanged<String>? onTap;

  _WikiLinkNode(this.label, this.accent, this.onTap);

  @override
  InlineSpan build() {
    final style = (parentStyle ?? const TextStyle()).copyWith(
      color: accent,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: accent.withValues(alpha: 0.55),
    );
    if (onTap == null) return TextSpan(text: label, style: style);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Semantics(
        button: true,
        label: 'Abrir $label',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => onTap!(label),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

class _WikiLinkSyntax extends m.InlineSyntax {
  _WikiLinkSyntax() : super(r'\[\[([^\]\n]{1,120})\]\]');

  @override
  bool onMatch(m.InlineParser parser, Match match) {
    final label = match.group(1)?.trim() ?? '';
    final element = m.Element.text('wikilink', label);
    element.attributes['label'] = label;
    parser.addNode(element);
    return true;
  }
}

class _MarkdownHorizontalRuleNode extends SpanNode {
  final Color accent;

  _MarkdownHorizontalRuleNode(this.accent);

  @override
  InlineSpan build() {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(height: 2, color: accent),
      ),
    );
  }
}

class MarkdownBlockActions extends StatelessWidget {
  final Color accent;
  final VoidCallback? onCopy;
  final VoidCallback? onPin;

  const MarkdownBlockActions({
    super.key,
    required this.accent,
    this.onCopy,
    this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.72),
            Color.lerp(Colors.white, accent, 0.10)!.withValues(alpha: 0.58),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.11),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy != null)
            _action(
              icon: YuLiIcons.copy,
              label: 'Copiar bloque',
              onTap: onCopy!,
            ),
          if (onCopy != null && onPin != null) const SizedBox(width: 2),
          if (onPin != null)
            _action(
              icon: YuLiIcons.pin,
              label: 'Pinear en lienzo',
              onTap: onPin!,
            ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 14, color: accent),
          ),
        ),
      ),
    );
  }
}

// ─── LaTeX support ───────────────────────────────────────────────────────

class _LatexNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;
  final Color accent;
  final ValueChanged<String>? onCopyBlock;
  final ValueChanged<String>? onPinBlock;

  _LatexNode(
    this.attributes,
    this.textContent,
    this.config, {
    this.accent = yFlight,
    this.onCopyBlock,
    this.onPinBlock,
  });

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? '';
    final isInline = attributes['isInline'] == 'true';
    final style = parentStyle ?? config.p.textStyle;
    final normalizedContent = _normalizeLatexContent(content);
    if (normalizedContent.isEmpty) {
      return TextSpan(style: style, text: textContent);
    }
    final math = Math.tex(
      normalizedContent,
      mathStyle: isInline ? MathStyle.text : MathStyle.display,
      textStyle: style,
      onErrorFallback:
          (err) => Text(
            _normalizeLatexContent(textContent),
            style: style.copyWith(color: yInk),
          ),
    );
    final rendered =
        isInline
            ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: math,
            )
            : math;
    if (isInline) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: rendered,
      );
    }
    final markdown = '\$\$\n$normalizedContent\n\$\$';
    final block =
        onCopyBlock == null && onPinBlock == null
            ? rendered
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                rendered,
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: MarkdownBlockActions(
                    accent: accent,
                    onCopy:
                        onCopyBlock == null
                            ? null
                            : () => onCopyBlock!(normalizedContent),
                    onPin:
                        onPinBlock == null ? null : () => onPinBlock!(markdown),
                  ),
                ),
              ],
            );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: block,
      ),
    );
  }
}

String _normalizeLatexContent(String value) {
  return value.replaceAll('\\\\', '\\').trim();
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
        r'(\$\$\s*([\s\S]+?)\s*\$\$)|((?<![\\$])\$(?![$\s])([^$\n]*[^$\s\n][^$\n]*)\$(?!\$))',
      );

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
          generator:
              (e, cfg, visitor) => _LatexNode(e.attributes, e.textContent, cfg),
        ),
      ],
    );

    final widgets = generator.buildWidgets(trimmed, config: config);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SizedBox(
        width: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, children: widgets),
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
      children.add(
        WidgetSpan(
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
                          child: Container(width: 6, height: 2, color: yMuted),
                        ),
                        Expanded(
                          child: Text(
                            def,
                            style: yBody(size: 14, color: yInk2, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
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
