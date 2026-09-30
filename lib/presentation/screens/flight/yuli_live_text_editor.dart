import '../../../domain/services/pending_saves.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/database_providers.dart';
import '../../providers/ai_providers.dart';
import '../../providers/flight_workspace_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/note.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/repositories/note_block_repository.dart';
import '../../../domain/services/ai_assistant.dart';
import 'flight_wiki_links.dart';
import 'flight_wiki_suggestions.dart';
import 'yuli_code_language_picker.dart';
import 'yuli_markdown_commands.dart';
import 'yuli_markdown_document.dart';
import 'yuli_note_image_importer.dart';
import 'yuli_block_actions.dart';
import 'fast_typing_panel.dart';
import 'yuli_table_tools.dart';
import 'yuli_image_resize_frame.dart';

typedef YuliEditorFocusChanged =
    void Function(EditorState? editorState, FocusNode? focusNode);

class YuliLiveTextEditorController {
  VoidCallback? _openFastTyping;

  void openFastTyping() => _openFastTyping?.call();
}

TextStyle applyYuliLiveTextStyle(
  TextStyle base,
  Map<String, dynamic> attributes,
  Color accent,
) {
  var style = base;
  if (attributes[AppFlowyRichTextKeys.bold] == true) {
    style = style.merge(const TextStyle(fontWeight: FontWeight.w700));
  }
  if (attributes[AppFlowyRichTextKeys.italic] == true) {
    style = style.merge(const TextStyle(fontStyle: FontStyle.italic));
  }
  if (attributes[AppFlowyRichTextKeys.strikethrough] == true) {
    style = style.merge(
      const TextStyle(decoration: TextDecoration.lineThrough),
    );
  }
  if (attributes[AppFlowyRichTextKeys.code] == true) {
    style = style.merge(
      yMono(
        size: 14,
        color: yInk,
        tracking: 0,
      ).copyWith(backgroundColor: yCream2),
    );
  }
  final heading = attributes[yuliHeadingLevel] as int?;
  if (heading != null) {
    style = style.merge(
      ySans(
        size: switch (heading) {
          1 => 28,
          2 => 23,
          3 => 19,
          _ => 16,
        },
        weight: FontWeight.w700,
        color: yInk,
        height: 1.2,
      ),
    );
  }
  if (attributes[yuliQuoteText] == true) {
    style = style.copyWith(
      color: yInk2.withValues(alpha: 0.82),
      fontStyle: FontStyle.normal,
    );
  }
  if (attributes[yuliHighlight] == true) {
    style = style.copyWith(backgroundColor: accent.withValues(alpha: 0.24));
  }
  if (attributes[yuliWikiLink] == true) {
    style = style.copyWith(
      color: accent,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: accent.withValues(alpha: 0.55),
    );
  }
  return style;
}

class YuliLiveTextEditor extends ConsumerStatefulWidget {
  final TextBlock block;
  final Color accent;
  final YuliEditorFocusChanged? onFocusChanged;
  final bool autofocus;
  final Future<String?> Function()? debugPickImagePath;
  final ValueChanged<FlightWorkspaceTarget>? onOpenWorkspaceTarget;
  final YuliLiveTextEditorController? controller;

  const YuliLiveTextEditor({
    super.key,
    required this.block,
    required this.accent,
    this.onFocusChanged,
    this.autofocus = false,
    this.debugPickImagePath,
    this.onOpenWorkspaceTarget,
    this.controller,
  });

  @override
  ConsumerState<YuliLiveTextEditor> createState() => _YuliLiveTextEditorState();
}

class _YuliLiveTextEditorState extends ConsumerState<YuliLiveTextEditor>
    with WidgetsBindingObserver {
  late final EditorState _editorState;
  late final EditorScrollController _scrollController;
  late final FocusNode _focusNode;
  late final NoteBlockRepository _repository;
  late final YuliBlockActions _blockActions;
  final _actionsOverlay = OverlayPortalController();
  Selection? _tableMenuSelection;
  StreamSubscription<EditorTransactionValue>? _transactionSubscription;
  Timer? _saveTimer;
  final Map<String, DoubleTapGestureRecognizer> _wikiLinkRecognizers = {};
  bool _pendingSave = false;
  bool _focused = false;
  bool? _reportedActive;
  bool _syncingStyles = false;
  bool _repairingEmptyDocument = false;
  bool _styleSyncScheduled = false;
  bool _selectionRefreshScheduled = false;
  bool _snappingMarkdownMarkerSelection = false;
  String? _lastCollapsedSelectionPath;
  int? _lastCollapsedSelectionOffset;
  String? _openAtomicMenuKey;
  final Set<String> _editingLatex = {};
  _WikiDraft? _wikiDraft;
  Future<List<FlightWorkspaceTarget>>? _wikiMatches;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _editorState = EditorState(
      document: YuliMarkdownDocument.restore(
        widget.block.markdown,
        widget.block.document,
      ),
    );
    _applyInitialLiveStyles();
    _blockActions = YuliBlockActions(_editorState)
      ..addListener(_actionsChanged);
    widget.controller?._openFastTyping = _openFastTyping;
    _scrollController = EditorScrollController(
      editorState: _editorState,
      shrinkWrap: true,
    );
    _repository = ref.read(noteBlockRepositoryProvider);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    _editorState.selectionNotifier.addListener(_onSelectionChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
    }
    _transactionSubscription = _editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) {
        if (_editorState.document.root.children.isEmpty) {
          unawaited(_restoreEditableRow());
        }
        _scheduleLiveStyleSync();
        _refreshWikiDraft();
        _pendingSave = true;
        PendingSaves.schedule(this, _persist);
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(seconds: 2), _persist);
      }
    });
  }

  @override
  void didUpdateWidget(YuliLiveTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._openFastTyping = null;
      widget.controller?._openFastTyping = _openFastTyping;
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?._openFastTyping = null;
    _saveTimer?.cancel();
    if (_pendingSave) {
      _persist();
    }
    _transactionSubscription?.cancel();
    _editorState.selectionNotifier.removeListener(_onSelectionChanged);
    for (final recognizer in _wikiLinkRecognizers.values) {
      recognizer.dispose();
    }
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _scrollController.dispose();
    _blockActions.removeListener(_actionsChanged);
    _blockActions.dispose();
    _editorState.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (!_focused && mounted) setState(() => _focused = true);
      _reportedActive = true;
      widget.onFocusChanged?.call(_editorState, _focusNode);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNode.hasFocus || _tableMenuSelection != null) {
        return;
      }
      if (_focused || _openAtomicMenuKey != null) {
        setState(() {
          _focused = false;
          _openAtomicMenuKey = null;
        });
      }
      if (_reportedActive != false) {
        _reportedActive = false;
        widget.onFocusChanged?.call(null, null);
      }
      if (_pendingSave) _persist();
    });
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  void _actionsChanged() {
    if (!mounted) return;
    setState(() {});
    if (_blockActions.selected.isNotEmpty ||
        _blockActions.busy ||
        _blockActions.notice != null) {
      _actionsOverlay.show();
    } else {
      _actionsOverlay.hide();
    }
  }

  void _openFastTyping() {
    _focusNode.requestFocus();
    _blockActions.selectWholeBlock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _blockActions.selected.isNotEmpty) {
        _actionsOverlay.show();
      }
    });
  }

  Future<void> _correctSelected() {
    return _blockActions.correct(ref.read(aiAssistantProvider), () async {
      if (!await ref.read(aiKeyStoreProvider).hasKey()) {
        throw const AiException(
          'Configura tu clave en Ajustes → YuLi AI para usar Fast Typing.',
        );
      }
      if (!mounted) return false;
      final limiter = ref.read(aiUsageLimiterProvider);
      return limiter.tryRecord();
    });
  }

  Node? get _activeTable {
    final path = (_tableMenuSelection ?? _editorState.selection)?.start.path;
    if (path == null || path.isEmpty) return null;
    final node = _editorState.getNodeAtPath([path.first]);
    return node?.type == TableBlockKeys.type ? node : null;
  }

  bool _atomicMenuOpen(Node node) =>
      _focused && _openAtomicMenuKey == _nodeKey(node);

  void _toggleAtomicMenu(Node node) {
    _focusNode.requestFocus();
    setState(() {
      final key = _nodeKey(node);
      _openAtomicMenuKey = _openAtomicMenuKey == key ? null : key;
    });
  }

  Future<void> _replaceTable(
    Node node,
    Node replacement,
    int row,
    int col,
  ) async {
    final path = node.path.toList();
    final transaction =
        _editorState.transaction
          ..insertNode(path, replacement)
          ..deleteNode(node);
    transaction.afterSelection = null;
    await _blockActions.applyIsolated(transaction);
    if (!mounted) return;
    final inserted = _editorState.getNodeAtPath(path);
    if (inserted == null) return;
    final cell = yuliTableCell(inserted, row, col);
    await _activateNode(cell.children.first, 0);
  }

  void _tableAction(
    Node node,
    TableDirection direction,
    String action, {
    int? selectedRow,
    int? selectedCol,
  }) {
    final row = selectedRow ?? _selectedTableRow(node);
    final col = selectedCol ?? _selectedTableCol(node);
    final index = direction == TableDirection.row ? row : col;
    final count =
        node.attributes[direction == TableDirection.row
                ? TableBlockKeys.rowsLen
                : TableBlockKeys.colsLen]
            as int;
    if (direction == TableDirection.col &&
        (action == 'narrow' || action == 'widen')) {
      unawaited(
        _resizeTableColumn(node, row, col, action == 'narrow' ? -40 : 40),
      );
    } else if (action == 'back' || action == 'forward') {
      final target = index + (action == 'back' ? -1 : 1);
      if (target < 0 || target >= count) return;
      _replaceTable(
        node,
        yuliReorderTableAxis(node, direction, index, target),
        direction == TableDirection.row ? target : row,
        direction == TableDirection.col ? target : col,
      );
    } else if (action == 'delete') {
      if (count > 1) TableActions.delete(node, index, _editorState, direction);
    } else if (action == 'duplicate') {
      if (count < (direction == TableDirection.row ? 100 : 40)) {
        TableActions.duplicate(node, index, _editorState, direction);
      }
    } else {
      if (count >= (direction == TableDirection.row ? 100 : 40)) return;
      TableActions.add(
        node,
        action == 'append' ? count : index + (action == 'before' ? 0 : 1),
        _editorState,
        direction,
      );
    }
  }

  Future<void> _resizeTableColumn(
    Node node,
    int row,
    int col,
    double delta,
  ) async {
    final replacement = node.deepCopy();
    final table = TableNode(node: replacement);
    table.setColWidth(col, (table.getColWidth(col) + delta).clamp(80, 800));
    await _replaceTable(node, replacement, row, col);
  }

  Widget _tableTools(Node node) {
    final row = _selectedTableRow(node);
    final col = _selectedTableCol(node);
    return YuliTableTools(
      accent: widget.accent,
      onMenuOpen: () => _tableMenuSelection = _editorState.selection,
      onMenuClose: () {
        _tableMenuSelection = null;
        _focusNode.requestFocus();
        _onSelectionChanged();
      },
      paste: () => _pasteTable(node),
      exit: () => _continueAfterAtomic(node),
      selectTable: () => _selectAtomicNode(node),
      deleteTable: () => _deleteAtomicNode(node),
      onAction:
          (direction, action) => _tableAction(
            node,
            direction,
            action,
            selectedRow: row,
            selectedCol: col,
          ),
    );
  }

  void _continueAfterAtomic(Node node) {
    final next = _editorState.getNodeAtPath([node.path.first + 1]);
    if (next?.delta != null) {
      _activateNode(next!, 0);
    } else {
      _appendParagraphAfter(node);
    }
  }

  Future<void> _pasteTable(Node node) async {
    final row = _selectedTableRow(node);
    final col = _selectedTableCol(node);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        data?.text == null ||
        _editorState.getNodeAtPath(node.path) != node) {
      return;
    }
    try {
      final values = yuliParseTableClipboard(data!.text!);
      await _replaceTable(
        node,
        yuliPasteTableCells(node, row, col, values),
        row,
        col,
      );
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _onSelectionChanged() {
    if (_snapHiddenMarkdownMarkerSelection()) return;
    _refreshWikiDraft();
    if (_selectionRefreshScheduled) return;
    _selectionRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionRefreshScheduled = false;
      if (!mounted) return;
      final visibleSelection = _tableMenuSelection ?? _editorState.selection;
      final active =
          (_focusNode.hasFocus || _tableMenuSelection != null) &&
          visibleSelection != null;
      final selectionPath = visibleSelection?.start.path;
      final activeRoot =
          selectionPath == null || selectionPath.isEmpty
              ? null
              : _editorState.getNodeAtPath([selectionPath.first]);
      setState(() {
        _focused = active;
        if (_openAtomicMenuKey != null &&
            (activeRoot == null ||
                _openAtomicMenuKey != _nodeKey(activeRoot))) {
          _openAtomicMenuKey = null;
        }
      });
      if (_blockActions.selected.isEmpty &&
          !_blockActions.busy &&
          _blockActions.notice == null) {
        _actionsOverlay.hide();
      }
      if (_reportedActive != active) {
        _reportedActive = active;
        widget.onFocusChanged?.call(
          active ? _editorState : null,
          active ? _focusNode : null,
        );
      }
    });
  }

  void _refreshWikiDraft() {
    final selection = _editorState.selection?.normalized;
    _WikiDraft? next;
    if (_focusNode.hasFocus &&
        selection != null &&
        selection.isCollapsed &&
        selection.start.path.equals(selection.end.path)) {
      final node = _editorState.getNodeAtPath(selection.start.path);
      final source = node?.delta?.toPlainText();
      final cursor = selection.start.offset;
      if (node != null &&
          source != null &&
          cursor >= 0 &&
          cursor <= source.length) {
        final before = source.substring(0, cursor);
        final start = before.lastIndexOf('[[');
        if (start >= 0) {
          final query = before.substring(start + 2);
          if (!query.contains(']]') &&
              !query.contains('\n') &&
              query.length <= 120) {
            next = _WikiDraft(
              path: [...node.path],
              start: start,
              end: cursor,
              query: query,
            );
          }
        }
      }
    }
    if (next == _wikiDraft) return;
    if (!mounted) return;
    setState(() {
      _wikiDraft = next;
      _wikiMatches =
          next == null
              ? null
              : findFlightWikiTargets(
                ref,
                sourceNoteId: widget.block.noteId,
                query: next.query,
              );
    });
  }

  Future<void> _commitWikiTarget(
    FlightWorkspaceTarget target,
    String label,
  ) async {
    await _replaceWikiDraft(label);
    if (!mounted) return;
    widget.onOpenWorkspaceTarget?.call(target);
  }

  Future<void> _createWikiTarget(NoteKind kind) async {
    final draft = _wikiDraft;
    if (draft == null || draft.query.trim().isEmpty) return;
    final target = await resolveFlightWikiTarget(
      ref,
      sourceNoteId: widget.block.noteId,
      label: draft.query,
      createKind: kind,
    );
    if (target == null || !mounted) return;
    await _commitWikiTarget(target, flightWikiTargetLabel(target));
  }

  DoubleTapGestureRecognizer _wikiLinkRecognizer(String label) {
    return _wikiLinkRecognizers.putIfAbsent(
      label,
      () =>
          DoubleTapGestureRecognizer()
            ..onDoubleTap = () => unawaited(_openWikiLink(label)),
    );
  }

  Future<void> _openWikiLink(String label) async {
    final target = await resolveFlightWikiTarget(
      ref,
      sourceNoteId: widget.block.noteId,
      label: label,
      createKind: NoteKind.block,
    );
    if (target == null || !mounted) return;
    widget.onOpenWorkspaceTarget?.call(target);
  }

  Future<void> _replaceWikiDraft(String label) async {
    final draft = _wikiDraft;
    if (draft == null) return;
    final node = _editorState.getNodeAtPath(draft.path);
    final source = node?.delta?.toPlainText();
    if (node == null || source == null || draft.end > source.length) return;
    final clean = label.replaceAll(RegExp(r'[\[\]\r\n]'), ' ').trim();
    final replacement = '[[$clean]]';
    final updated = source.replaceRange(draft.start, draft.end, replacement);
    final transaction =
        _editorState.transaction
          ..updateNode(node, {
            blockComponentDelta: (Delta()..insert(updated)).toJson(),
          })
          ..afterSelection = Selection.collapsed(
            Position(path: node.path, offset: draft.start + replacement.length),
          );
    setState(() {
      _wikiDraft = null;
      _wikiMatches = null;
    });
    await _editorState.apply(transaction);
    _pendingSave = true;
    await _persist();
  }

  bool _snapHiddenMarkdownMarkerSelection() {
    if (_snappingMarkdownMarkerSelection) return false;
    final selection = _editorState.selection?.normalized;
    if (selection == null || !selection.isCollapsed) {
      _lastCollapsedSelectionPath = null;
      _lastCollapsedSelectionOffset = null;
      return false;
    }
    final node = _editorState.getNodeAtPath(selection.start.path);
    final source = node?.delta?.toPlainText();
    if (node == null || source == null) return false;

    final pathKey = node.path.join('.');
    final previousOffset =
        _lastCollapsedSelectionPath == pathKey
            ? _lastCollapsedSelectionOffset
            : null;
    final snapOffset = snapHiddenMarkdownMarkerCaretOffset(
      text: source,
      offset: selection.start.offset,
      previousOffset: previousOffset,
    );
    _lastCollapsedSelectionPath = pathKey;
    _lastCollapsedSelectionOffset = snapOffset ?? selection.start.offset;
    if (snapOffset == null || snapOffset == selection.start.offset) {
      return false;
    }

    _snappingMarkdownMarkerSelection = true;
    _editorState
        .updateSelectionWithReason(
          Selection.collapsed(Position(path: node.path, offset: snapOffset)),
          reason: SelectionUpdateReason.uiEvent,
        )
        .whenComplete(() => _snappingMarkdownMarkerSelection = false);
    return true;
  }

  Future<void> _activate() async {
    if (!mounted) return;
    _focusNode.requestFocus();
    await _editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: const [0])),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  bool _isNodeActive(Node node) {
    final selection = _editorState.selection?.normalized;
    return selection != null &&
        selection.start.path.equals(node.path) &&
        selection.end.path.equals(node.path);
  }

  String _nodeKey(Node node) => node.path.join('.');

  Future<void> _activateNode(Node node, int offset) async {
    if (!mounted) return;
    _focusNode.requestFocus();
    final length = node.delta?.length ?? 0;
    await _editorState.updateSelectionWithReason(
      Selection.collapsed(
        Position(path: node.path, offset: offset.clamp(0, length)),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  Future<void> _selectAtomicNode(Node node) async {
    if (!mounted) return;
    _focusNode.requestFocus();
    await _editorState.updateSelectionWithReason(
      Selection.single(path: node.path, startOffset: 0, endOffset: 1),
      reason: SelectionUpdateReason.uiEvent,
    );
    _editorState.selectionType = SelectionType.block;
  }

  bool _containsInlineLatex(String source) {
    return RegExp(
      r'(?<![\\$])\$(?![$\s])([^$\n]*[^$\s\n][^$\n]*)\$(?!\$)',
    ).hasMatch(source);
  }

  void _applyInitialLiveStyles() {
    for (final node in _editorState.document.root.children) {
      _applyInitialLiveStyle(node);
    }
  }

  void _applyInitialLiveStyle(Node node) {
    if (node.type == yuliCodeBlockType || node.type == yuliLatexBlockType) {
      return;
    }
    final delta = node.delta;
    if (delta != null && _shouldApplyLiveMarkdownDelta(delta)) {
      node.updateAttributes({
        blockComponentDelta:
            buildLiveMarkdownDelta(delta.toPlainText()).toJson(),
      });
    }
    for (final child in node.children) {
      _applyInitialLiveStyle(child);
    }
  }

  void _scheduleLiveStyleSync() {
    if (_syncingStyles || _styleSyncScheduled) return;
    _styleSyncScheduled = true;
    scheduleMicrotask(() async {
      _styleSyncScheduled = false;
      if (!mounted || _syncingStyles) return;
      await _syncLiveStyles();
    });
  }

  Future<void> _syncLiveStyles() async {
    if (_syncingStyles || !mounted) return;
    final transaction = _editorState.transaction;
    var changed = false;
    for (final node in _editorState.document.root.children) {
      if (node.type == ImageBlockKeys.type) {
        final width = node.attributes[ImageBlockKeys.width] as num?;
        final safeWidth = (width?.toDouble() ?? 320.0).clamp(80.0, 1200.0);
        final height = node.attributes[ImageBlockKeys.height];
        if (width?.toDouble() != safeWidth || height != null) {
          transaction.updateNode(node, {
            ImageBlockKeys.width: safeWidth,
            ImageBlockKeys.height: null,
          });
          changed = true;
        }
        continue;
      }
      if (node.type == TableBlockKeys.type) {
        changed = _syncTableRowHeightHints(node, transaction) || changed;
      }
      changed = _syncLiveStyleNode(node, transaction) || changed;
    }
    if (!changed) return;
    transaction.afterSelection = _editorState.selection;
    _syncingStyles = true;
    try {
      await _editorState.apply(
        transaction,
        options: const ApplyOptions(recordUndo: false),
      );
    } finally {
      _syncingStyles = false;
    }
  }

  bool _syncLiveStyleNode(Node node, Transaction transaction) {
    if (node.type == yuliLatexBlockType || node.type == yuliCodeBlockType) {
      return false;
    }
    var changed = false;
    final delta = node.delta;
    if (delta != null && _shouldApplyLiveMarkdownDelta(delta)) {
      final styled = buildLiveMarkdownDelta(delta.toPlainText());
      if (jsonEncode(styled.toJson()) != jsonEncode(delta.toJson())) {
        transaction.updateNode(node, {blockComponentDelta: styled.toJson()});
        changed = true;
      }
    }
    for (final child in node.children) {
      changed = _syncLiveStyleNode(child, transaction) || changed;
    }
    return changed;
  }

  bool _syncTableRowHeightHints(Node table, Transaction transaction) {
    final rows = table.attributes[TableBlockKeys.rowsLen] as int? ?? 0;
    if (rows == 0) return false;
    final defaultHeight =
        (table.attributes[TableBlockKeys.rowDefaultHeight] as num?)
            ?.toDouble() ??
        TableDefaults.rowHeight;
    final borderWidth =
        (table.attributes[TableBlockKeys.borderWidth] as num?)?.toDouble() ??
        TableDefaults.borderWidth;
    final nextHeights = <int, double>{};
    var changed = false;

    for (var row = 0; row < rows; row++) {
      var maxLines = 1;
      for (final cell in table.children) {
        if (cell.type != TableCellBlockKeys.type ||
            cell.attributes[TableCellBlockKeys.rowPosition] != row) {
          continue;
        }
        final child = cell.children.isEmpty ? null : cell.children.first;
        final text = child?.delta?.toPlainText() ?? '';
        final lines = '\n'.allMatches(text).length + 1;
        if (lines > maxLines) maxLines = lines;
      }
      if (maxLines <= 1) continue;
      final estimated =
          (18 + maxLines * 26).clamp(defaultHeight, 420).toDouble();
      nextHeights[row] = estimated;
      for (final cell in table.children) {
        if (cell.type != TableCellBlockKeys.type ||
            cell.attributes[TableCellBlockKeys.rowPosition] != row) {
          continue;
        }
        final current =
            (cell.attributes[TableCellBlockKeys.height] as num?)?.toDouble() ??
            defaultHeight;
        if (current < estimated) {
          transaction.updateNode(cell, {TableCellBlockKeys.height: estimated});
          changed = true;
        }
      }
    }

    if (!changed) return false;
    var colsHeight = borderWidth;
    for (var row = 0; row < rows; row++) {
      final hinted = nextHeights[row];
      if (hinted != null) {
        colsHeight += hinted + borderWidth;
        continue;
      }
      Node? firstCell;
      for (final cell in table.children) {
        if (cell.type == TableCellBlockKeys.type &&
            cell.attributes[TableCellBlockKeys.rowPosition] == row) {
          firstCell = cell;
          break;
        }
      }
      colsHeight +=
          ((firstCell?.attributes[TableCellBlockKeys.height] as num?)
                  ?.toDouble() ??
              defaultHeight) +
          borderWidth;
    }
    transaction.updateNode(table, {TableBlockKeys.colsHeight: colsHeight});
    return true;
  }

  bool _shouldApplyLiveMarkdownDelta(Delta delta) {
    final text = delta.toPlainText();
    if (_containsLiveMarkdownSource(text)) return true;
    return delta.toList().whereType<TextInsert>().any((operation) {
      final attributes = operation.attributes;
      return attributes != null && attributes.keys.any(_isYuliLiveAttribute);
    });
  }

  bool _containsLiveMarkdownSource(String text) {
    if (text.isEmpty) return false;
    return RegExp(
      r'(^|\n)\s*(#{1,6}\s|>\s?|[-+*]\s+\[[ xX]\]\s+|[-+*]\s+|\d+[.)]\s+)|(\[\[[^\]\n]{1,120}\]\]|\*\*|__|~~|==|`|\$|\*[^*\n]+\*|_[^_\n]+_)',
    ).hasMatch(text);
  }

  bool _isYuliLiveAttribute(String key) =>
      key == yuliMarkdownMarker ||
      key == yuliMarkdownBlockMarker ||
      key == yuliMarkdownDomainStart ||
      key == yuliMarkdownDomainEnd ||
      key == yuliHeadingLevel ||
      key == yuliQuoteText ||
      key == yuliHighlight ||
      key == yuliLatex ||
      key == yuliLatexDisplay ||
      key == yuliWikiLink;

  Future<void> _persist() {
    PendingSaves.unschedule(this);
    return PendingSaves.track(_persistNow(), owner: this);
  }

  Future<void> _persistNow() async {
    _saveTimer?.cancel();
    _pendingSave = false;
    final markdown = YuliMarkdownDocument.encode(_editorState.document);
    await _repository.updatePayload(widget.block.id, {
      'md': markdown,
      'document': _editorState.document.toJson(),
    });
  }

  Future<void> _appendParagraphAfter(Node node) async {
    final path = [node.path.first + 1];
    final transaction =
        _editorState.transaction
          ..insertNode(path, paragraphNode())
          ..afterSelection = Selection.collapsed(Position(path: path));
    await _editorState.apply(transaction);
    _focusNode.requestFocus();
    if (mounted) setState(() {});
  }

  Future<void> _restoreEditableRow() async {
    if (_repairingEmptyDocument ||
        _editorState.document.root.children.isNotEmpty) {
      return;
    }
    _repairingEmptyDocument = true;
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted || _editorState.document.root.children.isNotEmpty) return;
      final transaction =
          _editorState.transaction
            ..insertNode([0], paragraphNode())
            ..afterSelection = Selection.collapsed(Position(path: const [0]));
      await _editorState.apply(
        transaction,
        options: const ApplyOptions(recordUndo: false),
      );
      _editorState.selectionType = null;
    } finally {
      _repairingEmptyDocument = false;
    }
  }

  Future<void> _deleteAtomicNode(Node node) async {
    final children = _editorState.document.root.children;
    final index = node.path.first;
    final transaction = _editorState.transaction..deleteNode(node);
    if (children.length == 1) {
      transaction.insertNode([0], paragraphNode());
      transaction.afterSelection = Selection.collapsed(
        Position(path: const [0]),
      );
    } else {
      final targetIndex = index < children.length - 1 ? index : index - 1;
      final target = children[targetIndex];
      transaction.afterSelection = Selection.collapsed(
        Position(path: [targetIndex], offset: target.delta?.length ?? 0),
      );
    }
    await _editorState.apply(transaction);
    _focusNode.requestFocus();
    if (mounted) setState(() {});
  }

  Future<void> _saveLatex(Node node, String formula) async {
    final transaction =
        _editorState.transaction
          ..updateNode(node, {yuliLatexBlockContent: formula})
          ..afterSelection = Selection.single(
            path: node.path,
            startOffset: 0,
            endOffset: 1,
          );
    await _editorState.apply(transaction);
    if (!mounted) return;
    setState(() => _editingLatex.remove(_nodeKey(node)));
    _focusNode.requestFocus();
  }

  Node? _selectedTableCell(Node tableNode) {
    final selection =
        (_tableMenuSelection ?? _editorState.selection)?.normalized;
    final path = selection?.start.path;
    if (selection == null ||
        path == null ||
        path.length < tableNode.path.length ||
        !tableNode.path.indexed.every((entry) => path[entry.$1] == entry.$2)) {
      return null;
    }
    var current = _editorState.getNodeAtPath(selection.start.path);
    while (current != null && current != tableNode) {
      if (current.type == TableCellBlockKeys.type) return current;
      current = current.parent;
    }
    return null;
  }

  int _selectedTableRow(Node tableNode) {
    final cell = _selectedTableCell(tableNode);
    return cell?.attributes[TableCellBlockKeys.rowPosition] as int? ??
        (tableNode.attributes[TableBlockKeys.rowsLen] as num).toInt() - 1;
  }

  int _selectedTableCol(Node tableNode) {
    final cell = _selectedTableCell(tableNode);
    return cell?.attributes[TableCellBlockKeys.colPosition] as int? ??
        (tableNode.attributes[TableBlockKeys.colsLen] as num).toInt() - 1;
  }

  Future<void> _setNodeAlignment(Node node, String align) async {
    final transaction =
        _editorState.transaction
          ..updateNode(node, {
            if (node.type == ImageBlockKeys.type)
              ImageBlockKeys.align: align
            else if (align == 'left')
              blockComponentAlign: null
            else
              blockComponentAlign: align,
          })
          ..afterSelection = Selection.single(
            path: node.path,
            startOffset: 0,
            endOffset: 1,
          );
    await _editorState.apply(transaction);
    _focusNode.requestFocus();
  }

  Future<void> _saveImage(
    Node node, {
    required String url,
    required double width,
    required String align,
  }) async {
    final transaction =
        _editorState.transaction
          ..updateNode(node, {
            ImageBlockKeys.url: url.trim(),
            ImageBlockKeys.width: width.clamp(80.0, 1200.0),
            ImageBlockKeys.height: null,
            ImageBlockKeys.align: align,
          })
          ..afterSelection = Selection.single(
            path: node.path,
            startOffset: 0,
            endOffset: 1,
          );
    await _editorState.apply(transaction);
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<String?> _pickImageForInlineEditor() {
    final testPicker = widget.debugPickImagePath;
    if (testPicker != null) return testPicker();
    return _pickAndImportImageForInlineEditor();
  }

  Future<String?> _pickAndImportImageForInlineEditor() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null) return null;

    final imported = await importYuliNoteImage(
      noteId: widget.block.noteId,
      sourcePath: picked.path,
      noteRepository: ref.read(noteRepositoryProvider),
    );
    return imported.path;
  }

  BlockComponentConfiguration get _textConfiguration =>
      BlockComponentConfiguration(
        padding: (_) => const EdgeInsets.symmetric(vertical: 3),
        placeholderText: (_) => 'Escribe…',
        textStyle: (_, {textSpan}) => const TextStyle(),
        placeholderTextStyle:
            (_, {textSpan}) => yBody(size: 15, color: yMuted, height: 1.55),
        textAlign:
            (node) => switch (node.attributes[blockComponentAlign]) {
              'center' => TextAlign.center,
              'right' => TextAlign.right,
              _ => TextAlign.left,
            },
      );

  Map<String, BlockComponentBuilder> get _builders {
    final text = _textConfiguration;
    return {
      ...standardBlockComponentBuilderMap,
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
        configuration: text,
      ),
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: text,
        textStyleBuilder:
            (level) => ySans(
              size: switch (level) {
                1 => 28,
                2 => 23,
                3 => 19,
                _ => 16,
              },
              weight: FontWeight.w700,
              color: yInk,
              height: 1.2,
            ),
      ),
      QuoteBlockKeys.type: QuoteBlockComponentBuilder(
        configuration: text.copyWith(
          textStyle:
              (_, {textSpan}) => yBody(
                size: 15,
                color: yInk2,
                height: 1.55,
              ).copyWith(fontStyle: FontStyle.italic),
        ),
      ),
      BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
        configuration: text,
      ),
      NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
        configuration: text,
      ),
      TodoListBlockKeys.type: TodoListBlockComponentBuilder(
        configuration: text,
      ),
      ImageBlockKeys.type: ImageBlockComponentBuilder(),
      yuliLatexBlockType: _YuliLatexBlockComponentBuilder(
        editorState: _editorState,
        accent: widget.accent,
      ),
      TableBlockKeys.type: TableBlockComponentBuilder(
        menuBuilder: (_, _, _, _, _, _) => const SizedBox.shrink(),
        tableStyle: TableStyle(
          colWidth: 140,
          rowHeight: 44,
          borderWidth: yLineThin,
          borderColor: yInk,
          borderHoverColor: yInk,
          addIcon: const SizedBox.shrink(),
          handlerIcon: const SizedBox.shrink(),
        ),
      ),
      yuliCodeBlockType: _YuliCodeBlockComponentBuilder(
        configuration: text.copyWith(
          textStyle:
              (_, {textSpan}) => yMono(
                size: 13,
                color: yInk,
                tracking: 0,
              ).copyWith(height: 1.5),
          padding: (_) => const EdgeInsets.all(12),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    InlineSpan markdownDecorator(
      BuildContext context,
      Node node,
      int index,
      TextInsert text,
      TextSpan before,
      TextSpan after,
    ) {
      final link = defaultTextSpanDecoratorForAttribute(
        context,
        node,
        index,
        text,
        before,
        after,
      );
      final attrs = text.attributes ?? const <String, dynamic>{};
      final base = link.recognizer == null ? after : link;
      final wikiLabel = attrs[yuliWikiLink] == true ? text.text.trim() : '';
      var style = applyYuliLiveTextStyle(
        after.style ?? const TextStyle(),
        attrs,
        widget.accent,
      );
      if (attrs[yuliMarkdownMarker] == true) {
        final selection = _editorState.selection?.normalized;
        final sameNode =
            selection != null &&
            selection.start.path.equals(node.path) &&
            selection.end.path.equals(node.path);
        final active = isMarkdownMarkerActive(
          attributes: attrs,
          selectionIsInNode: sameNode,
          selectionStart: selection?.start.offset ?? -1,
          selectionEnd: selection?.end.offset ?? -1,
        );
        style = style.copyWith(
          color:
              active
                  ? widget.accent.withValues(alpha: 0.95)
                  : Colors.transparent,
          fontSize: active ? style.fontSize : 0,
          letterSpacing: active ? style.letterSpacing : 0,
          wordSpacing: active ? style.wordSpacing : 0,
          fontWeight: FontWeight.w600,
        );
      }
      if (attrs[yuliLatex] == true) {
        style = style.merge(yMono(size: 14, color: yInk, tracking: 0));
      }
      return TextSpan(
        text: base.text,
        children: base.children,
        recognizer:
            wikiLabel.isNotEmpty && widget.onOpenWorkspaceTarget != null
                ? _wikiLinkRecognizer(wikiLabel)
                : base.recognizer,
        mouseCursor: base.mouseCursor,
        semanticsLabel: base.semanticsLabel,
        locale: base.locale,
        spellOut: base.spellOut,
        style: style,
      );
    }

    Widget blockContent(
      BuildContext context, {
      required Node node,
      required Widget child,
    }) {
      return AnimatedBuilder(
        animation: Listenable.merge([node, _editorState.selectionNotifier]),
        child: child,
        builder: (context, child) {
          final source = node.delta?.toPlainText() ?? '';
          final text = source.trimLeft();
          final active = _focused && _isNodeActive(node);
          final key = _nodeKey(node);
          if (node.type == yuliLatexBlockType) {
            final editing = _editingLatex.contains(key);
            final formula =
                node.attributes[yuliLatexBlockContent] as String? ?? '';
            return _YuliAtomicFrame(
              key: ValueKey('yuli_atomic_latex_${node.path.join('_')}'),
              accent: widget.accent,
              selected: active,
              editing: editing,
              label: 'LATEX',
              interceptContent: !editing,
              onSelect: () => _selectAtomicNode(node),
              actions: [
                if (!editing)
                  _YuliAtomicAction(
                    label: 'EDITAR',
                    icon: YuLiIcons.pencil,
                    onTap: () {
                      setState(() => _editingLatex.add(key));
                    },
                  ),
                _YuliAtomicAction(
                  label: 'BORRAR',
                  icon: YuLiIcons.trash,
                  destructive: true,
                  onTap: () => _deleteAtomicNode(node),
                ),
              ],
              child:
                  editing
                      ? _YuliLatexInlineEditor(
                        initialFormula: formula,
                        accent: widget.accent,
                        onCancel: () {
                          setState(() => _editingLatex.remove(key));
                          _selectAtomicNode(node);
                        },
                        onSave: (value) => _saveLatex(node, value),
                      )
                      : child!,
            );
          }
          if (!active && _containsInlineLatex(source)) {
            final formulaOffset = source.indexOf(r'$') + 1;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _activateNode(node, formulaOffset),
              child: IgnorePointer(
                child: _YuliInlineLatexPreview(
                  source: source,
                  accent: widget.accent,
                  textAlign: switch (node.attributes[blockComponentAlign]) {
                    'center' => TextAlign.center,
                    'right' => TextAlign.right,
                    _ => TextAlign.left,
                  },
                ),
              ),
            );
          }
          final listPreview = _YuliListLinePreview.tryParse(
            source: source,
            accent: widget.accent,
          );
          if (!active && listPreview != null) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _activateNode(node, listPreview.contentOffset),
              child: IgnorePointer(child: listPreview),
            );
          }
          if (text.trim() == '---') {
            if (active) return child!;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _activateNode(node, source.length),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(height: yLineThin, color: widget.accent),
              ),
            );
          }
          Widget result = child!;
          if (node.type == yuliCodeBlockType) {
            final code = node.delta?.toPlainText() ?? '';
            final menuOpen = _atomicMenuOpen(node);
            final availableWidth = MediaQuery.sizeOf(context).width - 24;
            final toolbarWidth = availableWidth < 620 ? availableWidth : 620.0;
            return _YuliFloatingAtomicControls(
              visible: active,
              controls:
                  menuOpen
                      ? SizedBox(
                        width: toolbarWidth,
                        child: _YuliAtomicToolbar(
                          child: Row(
                            children: [
                              Expanded(
                                child: YuliCodeLanguagePicker(
                                  language:
                                      node.attributes['language'] as String? ??
                                      '',
                                  accent: widget.accent,
                                  onChanged: (language) {
                                    final transaction =
                                        _editorState.transaction..updateNode(
                                          node,
                                          {'language': language},
                                        );
                                    transaction.afterSelection =
                                        _editorState.selection;
                                    _blockActions.applyIsolated(transaction);
                                  },
                                ),
                              ),
                              _YuliTableAxisButton(
                                tooltip: 'Copiar código',
                                icon: YuLiIcons.copy,
                                color: widget.accent,
                                onTap:
                                    () => Clipboard.setData(
                                      ClipboardData(text: code),
                                    ),
                              ),
                              _YuliTableAxisButton(
                                tooltip: 'Seleccionar código',
                                icon: YuLiIcons.squareDashedMousePointer,
                                color: widget.accent,
                                onTap: () => _selectAtomicNode(node),
                              ),
                              _YuliTableAxisButton(
                                tooltip: 'Eliminar código',
                                icon: YuLiIcons.trash,
                                color: widget.accent,
                                onTap: () => _deleteAtomicNode(node),
                              ),
                            ],
                          ),
                        ),
                      )
                      : _YuliAtomicMenuButton(
                        accent: widget.accent,
                        onTap: () => _toggleAtomicMenu(node),
                      ),
              child: Container(
                key: ValueKey('yuli_atomic_code_${node.path.join('_')}'),
                decoration: BoxDecoration(
                  color: yCream2,
                  border: Border.all(color: yBorderSoft, width: yLineThin),
                ),
                child:
                    active
                        ? result
                        : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _activateNode(node, 0),
                          child: _YuliCodePreview(
                            code: code,
                            language:
                                node.attributes['language'] as String? ?? '',
                            accent: widget.accent,
                          ),
                        ),
              ),
            );
          }
          if (node.type == TableBlockKeys.type) {
            final table = TableNode(node: node);
            final tableActive = _focused && _activeTable == node;
            final alignment = switch (node.attributes[blockComponentAlign]) {
              'left' => Alignment.centerLeft,
              'right' => Alignment.centerRight,
              _ => Alignment.center,
            };
            final menuOpen = tableActive && _atomicMenuOpen(node);
            final controls =
                menuOpen
                    ? _tableTools(node)
                    : _YuliAtomicMenuButton(
                      accent: widget.accent,
                      onTap: () => _toggleAtomicMenu(node),
                    );
            final contentWidth = table.tableWidth + 12 + yLineThin;
            return Align(
              key:
                  tableActive
                      ? ValueKey('yuli_atomic_table_${node.path.join('_')}')
                      : null,
              alignment: alignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(right: yLineThin),
                    child: _YuliFloatingAtomicControls(
                      visible: tableActive,
                      controls: controls,
                      child: SizedBox(
                        key: ValueKey(
                          'yuli_table_frame_${node.path.join('_')}',
                        ),
                        width: table.tableWidth + 12,
                        child: CustomPaint(
                          foregroundPainter: _YuliTableGridFramePainter(
                            width: table.tableWidth,
                            height:
                                (node.attributes[TableBlockKeys.colsHeight]
                                        as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                          child: result,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          if (node.type == ImageBlockKeys.type) {
            final imageUrl =
                node.attributes[ImageBlockKeys.url] as String? ?? '';
            final imageWidth =
                (node.attributes[ImageBlockKeys.width] as num?)?.toDouble() ??
                320;
            final align =
                node.attributes[ImageBlockKeys.align] as String? ?? 'center';
            final menuOpen = _atomicMenuOpen(node);
            final controls =
                menuOpen
                    ? _YuliAtomicToolbar(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _YuliAtomicActionButton(
                            accent: widget.accent,
                            action: _YuliAtomicAction(
                              label: 'Reemplazar',
                              icon: YuLiIcons.image,
                              onTap: () async {
                                final path = await _pickImageForInlineEditor();
                                if (!mounted ||
                                    path == null ||
                                    _editorState.getNodeAtPath(node.path) !=
                                        node) {
                                  return;
                                }
                                await _saveImage(
                                  node,
                                  url: path,
                                  width: imageWidth,
                                  align: align,
                                );
                              },
                            ),
                          ),
                          for (final entry
                              in {
                                'left': 'Izquierda',
                                'center': 'Centro',
                                'right': 'Derecha',
                              }.entries)
                            _YuliAtomicActionButton(
                              accent: widget.accent,
                              action: _YuliAtomicAction(
                                label: entry.value,
                                icon:
                                    entry.key == 'left'
                                        ? YuLiIcons.textAlignStart
                                        : entry.key == 'right'
                                        ? YuLiIcons.textAlignEnd
                                        : YuLiIcons.textAlignCenter,
                                onTap: () => _setNodeAlignment(node, entry.key),
                              ),
                            ),
                          _YuliAtomicActionButton(
                            accent: widget.accent,
                            action: _YuliAtomicAction(
                              label: 'Eliminar',
                              icon: YuLiIcons.trash,
                              onTap: () => _deleteAtomicNode(node),
                            ),
                          ),
                        ],
                      ),
                    )
                    : _YuliAtomicMenuButton(
                      accent: widget.accent,
                      onTap: () => _toggleAtomicMenu(node),
                    );
            return Align(
              key: ValueKey('yuli_atomic_image_${node.path.join('_')}'),
              alignment:
                  align == 'left'
                      ? Alignment.centerLeft
                      : align == 'right'
                      ? Alignment.centerRight
                      : Alignment.center,
              child: _YuliFloatingAtomicControls(
                visible: active,
                controls: controls,
                child: GestureDetector(
                  onTap: () => _selectAtomicNode(node),
                  child: YuliImageResizeFrame(
                    width: imageWidth,
                    maxWidth: MediaQuery.sizeOf(context).width - 112,
                    selected: active,
                    accent: widget.accent,
                    onResize:
                        (width) => _saveImage(
                          node,
                          url: imageUrl,
                          width: width,
                          align: align,
                        ),
                    builder:
                        (width) => _YuliImageBlockPreview(
                          previewKey: ValueKey(
                            'yuli_image_preview_${node.path.join('_')}',
                          ),
                          url: imageUrl,
                          width: width,
                          align: align,
                        ),
                  ),
                ),
              ),
            );
          }
          if (!text.startsWith('>')) return result;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: widget.accent),
                const SizedBox(width: 8),
                Expanded(child: result),
              ],
            ),
          );
        },
      );
    }

    Widget blockWrapper(
      BuildContext context, {
      required Node node,
      required Widget child,
    }) => blockContent(context, node: node, child: child);

    final rootChildren = _editorState.document.root.children;
    final lastNode = rootChildren.isEmpty ? null : rootChildren.last;
    final showContinue =
        _focused &&
        lastNode != null &&
        (lastNode.type == ImageBlockKeys.type ||
            lastNode.type == TableBlockKeys.type ||
            lastNode.type == yuliLatexBlockType ||
            lastNode.type == yuliCodeBlockType);

    final style = EditorStyle.mobile(
      padding: EdgeInsets.zero,
      cursorColor: widget.accent,
      dragHandleColor: widget.accent,
      selectionColor: widget.accent.withValues(alpha: 0.18),
      textStyleConfiguration: TextStyleConfiguration(
        text: yBody(size: 15, color: yInk2, height: 1.55),
        bold: const TextStyle(fontWeight: FontWeight.w700),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        underline: const TextStyle(decoration: TextDecoration.underline),
        strikethrough: const TextStyle(decoration: TextDecoration.lineThrough),
        href: TextStyle(
          color: widget.accent,
          decoration: TextDecoration.underline,
        ),
        code: yMono(
          size: 14,
          color: yInk,
          tracking: 0,
        ).copyWith(backgroundColor: yCream2),
      ),
      textSpanDecorator: markdownDecorator,
    );
    final editor = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: _focused ? widget.accent : Colors.transparent,
            width: yLineMid,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 8, right: 20),
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: IntrinsicHeight(
            child: AppFlowyEditor(
              editorState: _editorState,
              editorScrollController: _scrollController,
              focusNode: _focusNode,
              shrinkWrap: true,
              editorStyle: style,
              blockComponentBuilders: _builders,
              characterShortcutEvents: yuliMarkdownCharacterShortcuts,
              commandShortcutEvents: yuliMarkdownCommandShortcuts,
              blockWrapper: blockWrapper,
              contextMenuItems: const [],
              enableAutoComplete: false,
              footer:
                  showContinue
                      ? _YuliContinueWriting(
                        accent: widget.accent,
                        onTap: () => _appendParagraphAfter(lastNode),
                      )
                      : null,
            ),
          ),
        ),
      ),
    );
    return OverlayPortal(
      controller: _actionsOverlay,
      overlayChildBuilder:
          (context) => Positioned(
            left: 12,
            right: 12,
            bottom:
                MediaQueryData.fromView(View.of(context)).viewInsets.bottom +
                MediaQuery.paddingOf(context).bottom +
                12,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: (MediaQuery.sizeOf(context).height -
                          MediaQueryData.fromView(
                            View.of(context),
                          ).viewInsets.bottom -
                          48)
                      .clamp(80, 300),
                ),
                child: SingleChildScrollView(
                  child: FastTypingPanel(
                    actions: _blockActions,
                    accent: widget.accent,
                    onCorrect: _correctSelected,
                    onClose: _blockActions.clear,
                  ),
                ),
              ),
            ),
          ),
      child:
          _wikiDraft == null
              ? editor
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  editor,
                  if (_wikiMatches != null)
                    FlightWikiLinkSuggestions(
                      query: _wikiDraft!.query,
                      matches: _wikiMatches!,
                      accent: widget.accent,
                      onSelect: _commitWikiTarget,
                      onCreate: _createWikiTarget,
                    ),
                ],
              ),
    );
  }
}

class _WikiDraft {
  final List<int> path;
  final int start;
  final int end;
  final String query;

  const _WikiDraft({
    required this.path,
    required this.start,
    required this.end,
    required this.query,
  });

  @override
  bool operator ==(Object other) =>
      other is _WikiDraft &&
      other.start == start &&
      other.end == end &&
      other.query == query &&
      _samePath(other.path, path);

  @override
  int get hashCode => Object.hash(Object.hashAll(path), start, end, query);
}

bool _samePath(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _YuliFloatingAtomicControls extends StatefulWidget {
  final bool visible;
  final Widget controls;
  final Widget child;

  const _YuliFloatingAtomicControls({
    required this.visible,
    required this.controls,
    required this.child,
  });

  @override
  State<_YuliFloatingAtomicControls> createState() =>
      _YuliFloatingAtomicControlsState();
}

class _YuliFloatingAtomicControlsState
    extends State<_YuliFloatingAtomicControls> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  final _targetKey = GlobalKey();
  bool _showBelow = false;
  double _expandedOffsetX = 0;

  @override
  void initState() {
    super.initState();
    _syncVisibility();
  }

  @override
  void didUpdateWidget(_YuliFloatingAtomicControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.controls.runtimeType != widget.controls.runtimeType) {
      _syncVisibility();
    }
  }

  void _syncVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.visible) {
        final target =
            _targetKey.currentContext?.findRenderObject() as RenderBox?;
        final showBelow =
            target != null && target.localToGlobal(Offset.zero).dy < 80;
        final expanded = widget.controls is! _YuliAtomicMenuButton;
        final expandedOffsetX =
            target == null || !expanded
                ? 0.0
                : MediaQuery.sizeOf(context).width / 2 -
                    target.localToGlobal(Offset(target.size.width / 2, 0)).dx;
        if (_showBelow != showBelow || _expandedOffsetX != expandedOffsetX) {
          setState(() {
            _showBelow = showBelow;
            _expandedOffsetX = expandedOffsetX;
          });
        }
        _controller.show();
      } else {
        _controller.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.controls is! _YuliAtomicMenuButton;
    final overlayWidth = MediaQuery.sizeOf(context).width - 24;
    final controls =
        expanded
            ? SizedBox(
              width: overlayWidth,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: overlayWidth),
                  child: Center(child: widget.controls),
                ),
              ),
            )
            : widget.controls;
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder:
          (_) => UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor:
                  expanded
                      ? (_showBelow
                          ? Alignment.bottomCenter
                          : Alignment.topCenter)
                      : (_showBelow
                          ? Alignment.bottomRight
                          : Alignment.topRight),
              followerAnchor:
                  expanded
                      ? (_showBelow
                          ? Alignment.topCenter
                          : Alignment.bottomCenter)
                      : (_showBelow
                          ? Alignment.topRight
                          : Alignment.bottomRight),
              offset: Offset(
                expanded ? _expandedOffsetX : 0,
                _showBelow ? 8 : -8,
              ),
              child: Material(type: MaterialType.transparency, child: controls),
            ),
          ),
      child: CompositedTransformTarget(
        key: _targetKey,
        link: _link,
        child: widget.child,
      ),
    );
  }
}

class _YuliTableGridFramePainter extends CustomPainter {
  final double width;
  final double height;

  const _YuliTableGridFramePainter({required this.width, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    if (height <= 0) return;
    final paint =
        Paint()
          ..color = yInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = yLineThin;
    // AppFlowy reserves space around the grid for its hidden row/column handles.
    canvas.drawRect(Rect.fromLTWH(10, 14, width, height), paint);
  }

  @override
  bool shouldRepaint(_YuliTableGridFramePainter oldDelegate) =>
      width != oldDelegate.width || height != oldDelegate.height;
}

class _YuliAtomicMenuButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _YuliAtomicMenuButton({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Más opciones',
    child: Semantics(
      button: true,
      label: 'Más opciones',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: const ValueKey('yuli_atomic_more'),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent,
            border: Border.all(color: yBorderStrong, width: yLineThin),
            boxShadow: const [
              BoxShadow(color: yInk, offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          child: const Icon(YuLiIcons.moreHorizontal, size: 19, color: yCream),
        ),
      ),
    ),
  );
}

class _YuliAtomicToolbar extends StatelessWidget {
  final Widget child;

  const _YuliAtomicToolbar({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: yCream,
      border: Border.all(color: yBorderStrong, width: yLineThin),
      boxShadow: const [
        BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0),
      ],
    ),
    child: child,
  );
}

class _YuliAtomicAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;

  const _YuliAtomicAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
}

class _YuliAtomicFrame extends StatelessWidget {
  final Color accent;
  final bool selected;
  final bool editing;
  final String label;
  final bool interceptContent;
  final VoidCallback onSelect;
  final List<_YuliAtomicAction> actions;
  final Widget child;

  const _YuliAtomicFrame({
    super.key,
    required this.accent,
    required this.selected,
    required this.editing,
    required this.label,
    required this.interceptContent,
    required this.onSelect,
    required this.actions,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final showHeader = selected || editing;
    final framed = selected || editing;
    return Container(
      margin:
          framed
              ? const EdgeInsets.fromLTRB(0, 4, 4, 8)
              : const EdgeInsets.symmetric(vertical: 4),
      padding: framed ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: framed ? yCream : Colors.transparent,
        border:
            framed ? Border.all(color: yBorderStrong, width: yLineThin) : null,
        boxShadow:
            framed
                ? const [
                  BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selected || editing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      color: accent,
                      child: Text(
                        editing ? '$label - EDITANDO' : label,
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: yCream,
                          tracking: 0.7,
                        ),
                      ),
                    ),
                  if (selected || editing) const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final action in actions)
                          _YuliAtomicActionButton(
                            accent: accent,
                            action: action,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Stack(
            children: [
              child,
              if (interceptContent)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSelect,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YuliAtomicActionButton extends StatelessWidget {
  final Color accent;
  final _YuliAtomicAction action;

  const _YuliAtomicActionButton({required this.accent, required this.action});

  @override
  Widget build(BuildContext context) {
    final color = accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: [
            BoxShadow(color: yInk, offset: const Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, size: 13, color: yCream),
            const SizedBox(width: 5),
            Text(
              action.label,
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                color: yCream,
                tracking: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YuliContinueWriting extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _YuliContinueWriting({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: const ValueKey('yuli_continue_writing'),
        margin: const EdgeInsets.fromLTRB(0, 8, 4, 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: const [
            BoxShadow(color: yInk, offset: Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(YuLiIcons.plus, size: 14, color: accent),
            const SizedBox(width: 7),
            Text(
              'CONTINUAR ESCRIBIENDO',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                color: accent,
                tracking: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YuliInlineLatexPreview extends StatelessWidget {
  final String source;
  final Color accent;
  final TextAlign textAlign;

  const _YuliInlineLatexPreview({
    required this.source,
    required this.accent,
    required this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final operation in buildLiveMarkdownDelta(source).toList()) {
      if (operation is! TextInsert) continue;
      final attributes = operation.attributes ?? const <String, dynamic>{};
      if (attributes[yuliMarkdownMarker] == true) continue;
      if (attributes[yuliLatex] == true) {
        final formula = operation.text.replaceAll('\\\\', '\\').trim();
        if (formula.isEmpty) continue;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              formula,
              mathStyle: MathStyle.text,
              textStyle: yBody(size: 16, color: yInk2, height: 1.45),
              onErrorFallback:
                  (_) => Text(
                    operation.text,
                    style: yBody(size: 15, color: yInk2, height: 1.55),
                  ),
            ),
          ),
        );
        continue;
      }
      spans.add(
        TextSpan(
          text: operation.text,
          style: applyYuliLiveTextStyle(
            yBody(size: 15, color: yInk2, height: 1.55),
            attributes,
            accent,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SizedBox(
        width: double.infinity,
        child: Text.rich(
          TextSpan(children: spans),
          textAlign: textAlign,
          softWrap: true,
        ),
      ),
    );
  }
}

enum _YuliListLineKind { bullet, numbered, taskOpen, taskDone }

class _YuliListLinePreview extends StatelessWidget {
  final _YuliListLineKind kind;
  final String marker;
  final String content;
  final int contentOffset;
  final Color accent;

  const _YuliListLinePreview({
    required this.kind,
    required this.marker,
    required this.content,
    required this.contentOffset,
    required this.accent,
  });

  static _YuliListLinePreview? tryParse({
    required String source,
    required Color accent,
  }) {
    final task = RegExp(
      r'^(\s*[-+*]\s+\[([ xX])\]\s+)(.*)$',
    ).firstMatch(source);
    if (task != null) {
      final checked = task.group(2)!.toLowerCase() == 'x';
      return _YuliListLinePreview(
        kind: checked ? _YuliListLineKind.taskDone : _YuliListLineKind.taskOpen,
        marker: checked ? '[x]' : '[ ]',
        content: task.group(3)!,
        contentOffset: task.group(1)!.length,
        accent: accent,
      );
    }
    final bullet = RegExp(r'^(\s*[-+*]\s+)(.*)$').firstMatch(source);
    if (bullet != null) {
      return _YuliListLinePreview(
        kind: _YuliListLineKind.bullet,
        marker: '•',
        content: bullet.group(2)!,
        contentOffset: bullet.group(1)!.length,
        accent: accent,
      );
    }
    final numbered = RegExp(r'^(\s*(\d+[.)])\s+)(.*)$').firstMatch(source);
    if (numbered != null) {
      return _YuliListLinePreview(
        kind: _YuliListLineKind.numbered,
        marker: numbered.group(2)!,
        content: numbered.group(3)!,
        contentOffset: numbered.group(1)!.length,
        accent: accent,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: _marker()),
          Expanded(
            child: Text.rich(
              TextSpan(children: _contentSpans()),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marker() {
    if (kind == _YuliListLineKind.taskOpen ||
        kind == _YuliListLineKind.taskDone) {
      final done = kind == _YuliListLineKind.taskDone;
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Icon(
          done ? YuLiIcons.squareCheck : YuLiIcons.square,
          size: 16,
          color: done ? accent : yInk,
        ),
      );
    }
    return Text(
      marker,
      textAlign: TextAlign.center,
      style: yMono(
        size: kind == _YuliListLineKind.bullet ? 18 : 11,
        weight: FontWeight.w700,
        color: accent,
        tracking: 0,
      ),
    );
  }

  List<InlineSpan> _contentSpans() {
    final spans = <InlineSpan>[];
    for (final operation in buildLiveMarkdownDelta(content).toList()) {
      if (operation is! TextInsert) continue;
      final attributes = operation.attributes ?? const <String, dynamic>{};
      if (attributes[yuliMarkdownMarker] == true) continue;
      spans.add(
        TextSpan(
          text: operation.text,
          style: applyYuliLiveTextStyle(
            yBody(
              size: 15,
              color: kind == _YuliListLineKind.taskDone ? yMuted : yInk2,
              height: 1.55,
            ).copyWith(
              decoration:
                  kind == _YuliListLineKind.taskDone
                      ? TextDecoration.lineThrough
                      : null,
              decorationColor: yMuted,
            ),
            attributes,
            accent,
          ),
        ),
      );
    }
    return spans;
  }
}

class _YuliLatexInlineEditor extends StatefulWidget {
  final String initialFormula;
  final Color accent;
  final VoidCallback onCancel;
  final ValueChanged<String> onSave;

  const _YuliLatexInlineEditor({
    required this.initialFormula,
    required this.accent,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_YuliLatexInlineEditor> createState() => _YuliLatexInlineEditorState();
}

class _YuliLatexInlineEditorState extends State<_YuliLatexInlineEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialFormula);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formula = _controller.text.trim();
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            style: yMono(size: 14, color: yInk, tracking: 0),
            decoration: const InputDecoration(
              hintText: 'FORMULA LATEX',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: yBorderSoft, width: yLineThin),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 72),
            alignment: Alignment.center,
            child:
                formula.isEmpty
                    ? Text(
                      'VISTA PREVIA',
                      style: yMono(size: 10, color: yMuted, tracking: 0.8),
                    )
                    : Math.tex(
                      formula.replaceAll('\\\\', '\\'),
                      mathStyle: MathStyle.display,
                      textStyle: yBody(size: 20, color: yInk),
                      onErrorFallback:
                          (_) => Text(
                            formula,
                            style: yMono(size: 13, color: yMuted, tracking: 0),
                          ),
                    ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _YuliInlineEditorButton(
                  label: 'CANCELAR',
                  color: yCream,
                  foreground: yInk,
                  onTap: widget.onCancel,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _YuliInlineEditorButton(
                  label: 'GUARDAR',
                  color: widget.accent,
                  foreground: yCream,
                  onTap:
                      formula.isEmpty
                          ? null
                          : () => widget.onSave(_controller.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YuliCodePreview extends StatelessWidget {
  final String code;
  final String language;
  final Color accent;

  const _YuliCodePreview({
    required this.code,
    required this.language,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = yuliNormalizeCodeLanguage(language);
    final label = yuliCodeLanguageFor(normalized).label.toUpperCase();
    final highlightLanguage = _highlightLanguageFor(normalized);
    final textStyle = yMono(
      size: 13,
      color: yInk,
      tracking: 0,
    ).copyWith(height: 1.45);
    return Container(
      width: double.infinity,
      color: yCream2,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  color: yMuted,
                  tracking: 0.9,
                ),
              ),
            ),
          if (code.isEmpty)
            Text('CODIGO VACIO', softWrap: true, style: textStyle)
          else if (highlightLanguage == null)
            Text(code, softWrap: true, style: textStyle)
          else
            HighlightView(
              code,
              language: highlightLanguage,
              theme: _yuliCodeHighlightTheme(accent),
              textStyle: textStyle,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

String? _highlightLanguageFor(String language) {
  final normalized = yuliNormalizeCodeLanguage(language);
  return switch (normalized) {
    '' => null,
    'js' => 'javascript',
    'ts' => 'typescript',
    'csharp' => 'cs',
    'c' => 'cpp',
    'html' => 'xml',
    'cpp' => 'cpp',
    'dart' ||
    'python' ||
    'java' ||
    'kotlin' ||
    'swift' ||
    'go' ||
    'rust' ||
    'php' ||
    'ruby' ||
    'sql' ||
    'css' ||
    'scss' ||
    'json' ||
    'yaml' ||
    'xml' ||
    'markdown' ||
    'bash' ||
    'powershell' ||
    'dockerfile' ||
    'r' ||
    'matlab' ||
    'julia' ||
    'lua' ||
    'scala' ||
    'elixir' ||
    'erlang' ||
    'haskell' ||
    'clojure' ||
    'solidity' => normalized,
    _ => null,
  };
}

Map<String, TextStyle> _yuliCodeHighlightTheme(Color accent) {
  final primary = _accentTone(
    accent,
    lightnessShift: -0.1,
    saturationShift: 0.08,
  );
  final secondary = _accentTone(
    accent,
    hueShift: 18,
    lightnessShift: -0.04,
    saturationShift: -0.02,
  );
  final tertiary = _accentTone(
    accent,
    hueShift: -22,
    lightnessShift: 0.06,
    saturationShift: -0.08,
  );
  final subdued = _accentMix(accent, yInk2, 0.52);
  final keyword = TextStyle(color: primary, fontWeight: FontWeight.w700);
  final warm = TextStyle(color: secondary);
  final calm = TextStyle(color: tertiary);
  final muted = TextStyle(color: yMuted, fontStyle: FontStyle.italic);
  final strong = TextStyle(color: yInk, fontWeight: FontWeight.w700);
  return {
    'root': const TextStyle(color: yInk, backgroundColor: yCream2),
    'keyword': keyword,
    'selector-tag': keyword,
    'literal': keyword,
    'type': TextStyle(color: subdued, fontWeight: FontWeight.w700),
    'built_in': TextStyle(color: subdued),
    'title': strong,
    'name': strong,
    'string': calm,
    'attr': warm,
    'attribute': warm,
    'number': warm,
    'regexp': warm,
    'meta': TextStyle(color: yMuted),
    'comment': muted,
    'quote': muted,
    'variable': TextStyle(color: yInk2),
    'params': TextStyle(color: yInk2),
    'symbol': warm,
    'bullet': warm,
    'section': strong,
    'tag': TextStyle(color: primary),
  };
}

Color _accentTone(
  Color accent, {
  double hueShift = 0,
  double saturationShift = 0,
  double lightnessShift = 0,
}) {
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withHue((hsl.hue + hueShift) % 360)
      .withSaturation((hsl.saturation + saturationShift).clamp(0.24, 0.88))
      .withLightness((hsl.lightness + lightnessShift).clamp(0.24, 0.58))
      .toColor();
}

Color _accentMix(Color accent, Color target, double amount) {
  return Color.lerp(accent, target, amount) ?? accent;
}

class _YuliImageBlockPreview extends StatelessWidget {
  final Key previewKey;
  final String url;
  final double width;
  final String align;

  const _YuliImageBlockPreview({
    required this.previewKey,
    required this.url,
    required this.width,
    required this.align,
  });

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 64;
    final safeMaxWidth = availableWidth.clamp(80.0, 1200.0).toDouble();
    final safeWidth = width.clamp(80.0, safeMaxWidth).toDouble();
    final previewAlignment = switch (align) {
      'right' => Alignment.centerRight,
      'left' => Alignment.centerLeft,
      _ => Alignment.center,
    };
    return Align(
      alignment: previewAlignment,
      child: SizedBox(
        key: previewKey,
        width: safeWidth,
        child: _YuliImageBlockContent(url: url),
      ),
    );
  }
}

class _YuliImageBlockContent extends StatelessWidget {
  final String url;

  const _YuliImageBlockContent({required this.url});

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return const _YuliImageBlockPlaceholder(
        icon: YuLiIcons.image,
        label: 'SIN IMAGEN',
      );
    }
    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
      return Image.network(
        trimmedUrl,
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) => const _YuliImageBlockPlaceholder(
              icon: YuLiIcons.imageOff,
              label: 'IMAGEN NO DISPONIBLE',
            ),
      );
    }

    final file = File(trimmedUrl);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.contain);
    }

    return _YuliImageBlockPlaceholder(
      icon: YuLiIcons.image,
      label: trimmedUrl.split(RegExp(r'[\\/]+')).last,
    );
  }
}

class _YuliImageBlockPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;

  const _YuliImageBlockPlaceholder({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      color: yCream2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: yMuted),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: yMono(size: 10, color: yMuted, tracking: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YuliInlineEditorButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback? onTap;

  const _YuliInlineEditorButton({
    required this.label,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? yCream2 : color,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(
            size: 11,
            weight: FontWeight.w700,
            color: onTap == null ? yMuted : foreground,
          ),
        ),
      ),
    );
  }
}

class _YuliTableAxisButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _YuliTableAxisButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    ),
  );
}

class _YuliLatexBlockComponentBuilder extends BlockComponentBuilder {
  final EditorState editorState;
  final Color accent;

  _YuliLatexBlockComponentBuilder({
    required this.editorState,
    required this.accent,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _YuliLatexBlockComponentWidget(
      key: node.key,
      node: node,
      editorState: editorState,
      accent: accent,
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) =>
          node.delta == null &&
          node.children.isEmpty &&
          node.attributes[yuliLatexBlockContent] is String;
}

class _YuliLatexBlockComponentWidget extends BlockComponentStatefulWidget {
  final EditorState editorState;
  final Color accent;

  const _YuliLatexBlockComponentWidget({
    super.key,
    required super.node,
    required this.editorState,
    required this.accent,
  }) : super(configuration: const BlockComponentConfiguration());

  @override
  State<_YuliLatexBlockComponentWidget> createState() =>
      _YuliLatexBlockComponentWidgetState();
}

class _YuliLatexBlockComponentWidgetState
    extends State<_YuliLatexBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  final _contentKey = GlobalKey();

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final formula = node.attributes[yuliLatexBlockContent] as String? ?? '';
    final align = node.attributes[blockComponentAlign] as String?;
    final alignment = switch (align) {
      'left' => Alignment.centerLeft,
      'right' => Alignment.centerRight,
      _ => Alignment.center,
    };
    Widget child = Container(
      key: _contentKey,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      alignment: alignment,
      child:
          formula.trim().isEmpty
              ? Text(
                'LATEX VACIO',
                style: yMono(size: 11, color: yMuted, tracking: 0.8),
              )
              : Math.tex(
                formula.replaceAll('\\\\', '\\'),
                mathStyle: MathStyle.display,
                textStyle: yBody(size: 20, color: yInk),
                onErrorFallback:
                    (_) => Text(
                      formula,
                      style: yMono(size: 13, color: yMuted, tracking: 0),
                    ),
              ),
    );
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: widget.editorState.selectionNotifier,
      remoteSelection: widget.editorState.remoteSelections,
      blockColor: widget.editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );
    return child;
  }

  @override
  Position start() => Position(path: node.path, offset: 0);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is RenderBox) return Offset.zero & box.size;
    return Rect.zero;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is RenderBox) return [Offset.zero & box.size];
    return const [];
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) return null;
    return Offset.zero & box.size;
  }

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox?.localToGlobal(offset) ?? offset;

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;
}

class _YuliCodeBlockComponentBuilder extends BlockComponentBuilder {
  _YuliCodeBlockComponentBuilder({required super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ParagraphBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;
}
