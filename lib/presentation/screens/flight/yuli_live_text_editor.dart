import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/database_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/repositories/note_block_repository.dart';
import 'yuli_code_language_picker.dart';
import 'yuli_markdown_commands.dart';
import 'yuli_markdown_document.dart';
import 'yuli_note_image_importer.dart';

typedef YuliEditorFocusChanged =
    void Function(EditorState? editorState, FocusNode? focusNode);

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
  return style;
}

class YuliLiveTextEditor extends ConsumerStatefulWidget {
  final TextBlock block;
  final Color accent;
  final YuliEditorFocusChanged? onFocusChanged;
  final bool autofocus;
  final Future<String?> Function()? debugPickImagePath;

  const YuliLiveTextEditor({
    super.key,
    required this.block,
    required this.accent,
    this.onFocusChanged,
    this.autofocus = false,
    this.debugPickImagePath,
  });

  @override
  ConsumerState<YuliLiveTextEditor> createState() => _YuliLiveTextEditorState();
}

class _YuliLiveTextEditorState extends ConsumerState<YuliLiveTextEditor> {
  late final EditorState _editorState;
  late final EditorScrollController _scrollController;
  late final FocusNode _focusNode;
  late final NoteBlockRepository _repository;
  StreamSubscription<EditorTransactionValue>? _transactionSubscription;
  Timer? _saveTimer;
  bool _pendingSave = false;
  bool _focused = false;
  bool? _reportedActive;
  bool _syncingStyles = false;
  bool _styleSyncScheduled = false;
  bool _selectionRefreshScheduled = false;
  bool _snappingMarkdownMarkerSelection = false;
  String? _lastCollapsedSelectionPath;
  int? _lastCollapsedSelectionOffset;
  final Set<String> _editingTables = {};
  final Set<String> _editingImages = {};
  final Set<String> _editingLatex = {};
  final Set<String> _editingCode = {};

  @override
  void initState() {
    super.initState();
    _editorState = EditorState(
      document: YuliMarkdownDocument.decode(widget.block.markdown),
    );
    _applyInitialLiveStyles();
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
        _scheduleLiveStyleSync();
        _pendingSave = true;
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(seconds: 2), _persist);
      }
    });
  }

  @override
  void didUpdateWidget(YuliLiveTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_pendingSave) {
      _persist();
    }
    _transactionSubscription?.cancel();
    _editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _scrollController.dispose();
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
    if (_focused && mounted) setState(() => _focused = false);
    if (_pendingSave) _persist();
  }

  void _onSelectionChanged() {
    if (_snapHiddenMarkdownMarkerSelection()) return;
    if (_selectionRefreshScheduled) return;
    _selectionRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionRefreshScheduled = false;
      if (!mounted) return;
      final active = _editorState.selection != null;
      setState(() => _focused = active);
      if (_reportedActive != active) {
        _reportedActive = active;
        widget.onFocusChanged?.call(
          active ? _editorState : null,
          active ? _focusNode : null,
        );
      }
    });
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
  }

  bool _containsInlineLatex(String source) {
    return RegExp(
      r'(?<![\\$])\$(?![$\s])([^$\n]*[^$\s\n][^$\n]*)\$(?!\$)',
    ).hasMatch(source);
  }

  void _applyInitialLiveStyles() {
    for (final node in _editorState.document.root.children) {
      final delta = node.delta;
      if (delta == null ||
          node.type == yuliCodeBlockType ||
          node.type == yuliLatexBlockType) {
        continue;
      }
      node.updateAttributes({
        blockComponentDelta:
            buildLiveMarkdownDelta(delta.toPlainText()).toJson(),
      });
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
        final safeWidth = (width?.toDouble() ?? 320.0).clamp(160.0, 520.0);
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
      if (node.type == yuliLatexBlockType) continue;
      final delta = node.delta;
      if (delta == null || node.type == yuliCodeBlockType) continue;
      final styled = buildLiveMarkdownDelta(delta.toPlainText());
      if (jsonEncode(styled.toJson()) == jsonEncode(delta.toJson())) continue;
      transaction.updateNode(node, {blockComponentDelta: styled.toJson()});
      changed = true;
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

  Future<void> _persist() async {
    _saveTimer?.cancel();
    _pendingSave = false;
    final markdown = YuliMarkdownDocument.encode(_editorState.document);
    await _repository.updatePayload(widget.block.id, {'md': markdown});
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

  Future<void> _saveCode(Node node, String language, String code) async {
    final transaction =
        _editorState.transaction
          ..updateNode(node, {
            blockComponentDelta:
                (Delta()..insert(code.replaceAll('\r\n', '\n'))).toJson(),
            'language': yuliNormalizeCodeLanguage(language),
          })
          ..afterSelection = Selection.single(
            path: node.path,
            startOffset: 0,
            endOffset: 1,
          );
    await _editorState.apply(transaction);
    if (!mounted) return;
    setState(() => _editingCode.remove(_nodeKey(node)));
    _focusNode.requestFocus();
  }

  Node? _selectedTableCell(Node tableNode) {
    final selection = _editorState.selection?.normalized;
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

  void _mutateTable(
    Node node, {
    required TableDirection direction,
    required bool add,
  }) {
    final rows = (node.attributes[TableBlockKeys.rowsLen] as num).toInt();
    final cols = (node.attributes[TableBlockKeys.colsLen] as num).toInt();
    final selectedRow = _selectedTableRow(node).clamp(0, rows - 1);
    final selectedCol = _selectedTableCol(node).clamp(0, cols - 1);
    if (direction == TableDirection.row) {
      final position = add ? selectedRow + 1 : selectedRow;
      if (add) {
        TableActions.add(node, position, _editorState, direction);
      } else {
        TableActions.delete(node, position, _editorState, direction);
      }
    } else {
      final position = add ? selectedCol + 1 : selectedCol;
      if (add) {
        TableActions.add(node, position, _editorState, direction);
      } else {
        TableActions.delete(node, position, _editorState, direction);
      }
    }
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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
            ImageBlockKeys.width: width.clamp(160.0, 520.0),
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
    setState(() => _editingImages.remove(_nodeKey(node)));
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
        menuBuilder:
            (node, editorState, position, direction, _, _) =>
                _YuliTableAxisControls(
                  accent: widget.accent,
                  canDelete:
                      direction == TableDirection.col
                          ? (node.attributes[TableBlockKeys.colsLen] as num) > 1
                          : (node.attributes[TableBlockKeys.rowsLen] as num) >
                              1,
                  onAdd:
                      () => TableActions.add(
                        node,
                        position + 1,
                        editorState,
                        direction,
                      ),
                  onDelete:
                      () => TableActions.delete(
                        node,
                        position,
                        editorState,
                        direction,
                      ),
                ),
        tableStyle: TableStyle(
          colWidth: 140,
          rowHeight: 44,
          borderWidth: yLineThin,
          borderColor: yBorderSoft,
          borderHoverColor: widget.accent,
          addIcon: Icon(YuLiIcons.plus, size: 18, color: widget.accent),
          handlerIcon: const Icon(
            YuLiIcons.gripVertical,
            size: 16,
            color: yMuted,
          ),
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
        recognizer: base.recognizer,
        mouseCursor: base.mouseCursor,
        semanticsLabel: base.semanticsLabel,
        locale: base.locale,
        spellOut: base.spellOut,
        style: style,
      );
    }

    Widget blockWrapper(
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
          final active = _isNodeActive(node);
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
            return Stack(
              alignment: Alignment.center,
              children: [
                child!,
                if (!active)
                  IgnorePointer(
                    child: Container(height: yLineThin, color: widget.accent),
                  ),
              ],
            );
          }
          Widget result = child!;
          if (node.type == yuliCodeBlockType) {
            final editing = _editingCode.contains(key);
            final code = node.delta?.toPlainText() ?? '';
            return _YuliAtomicFrame(
              key: ValueKey('yuli_atomic_code_${node.path.join('_')}'),
              accent: widget.accent,
              selected: active,
              editing: editing,
              label: 'CODIGO',
              interceptContent: !editing,
              onSelect: () => _selectAtomicNode(node),
              actions: [
                if (!editing)
                  _YuliAtomicAction(
                    label: 'EDITAR',
                    icon: YuLiIcons.pencil,
                    onTap: () {
                      setState(() => _editingCode.add(key));
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
                      ? _YuliCodeInlineEditor(
                        initialCode: code,
                        initialLanguage:
                            node.attributes['language'] as String? ?? '',
                        accent: widget.accent,
                        onCancel: () {
                          setState(() => _editingCode.remove(key));
                          _selectAtomicNode(node);
                        },
                        onSave:
                            (language, value) =>
                                _saveCode(node, language, value),
                      )
                      : _YuliCodePreview(
                        code: code,
                        language: node.attributes['language'] as String? ?? '',
                        accent: widget.accent,
                      ),
            );
          }
          if (node.type == TableBlockKeys.type) {
            final editing = _editingTables.contains(key);
            final rows =
                (node.attributes[TableBlockKeys.rowsLen] as num).toInt();
            final cols =
                (node.attributes[TableBlockKeys.colsLen] as num).toInt();
            final align = node.attributes[blockComponentAlign] as String?;
            final alignment = switch (align) {
              'center' => Alignment.center,
              'right' => Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
            final maxWidth = MediaQuery.sizeOf(context).width - 64;
            final width = (TableNode(node: node).tableWidth + 40).clamp(
              0,
              maxWidth,
            );
            result = Align(
              alignment: alignment,
              child: SizedBox(width: width.toDouble(), child: result),
            );
            return _YuliAtomicFrame(
              key: ValueKey('yuli_atomic_table_${node.path.join('_')}'),
              accent: widget.accent,
              selected: active,
              editing: editing,
              label: 'TABLA',
              interceptContent: !editing,
              onSelect: () => _selectAtomicNode(node),
              actions: [
                _YuliAtomicAction(
                  label: editing ? 'TERMINAR' : 'EDITAR CELDAS',
                  icon: editing ? YuLiIcons.check : YuLiIcons.pencil,
                  onTap: () {
                    if (editing) {
                      setState(() => _editingTables.remove(key));
                      _selectAtomicNode(node);
                    } else {
                      setState(() => _editingTables.add(key));
                    }
                  },
                ),
                _YuliAtomicAction(
                  label: 'FILA +',
                  icon: YuLiIcons.plus,
                  onTap:
                      () => _mutateTable(
                        node,
                        direction: TableDirection.row,
                        add: true,
                      ),
                ),
                _YuliAtomicAction(
                  label: 'FILA -',
                  icon: YuLiIcons.minus,
                  enabled: rows > 1,
                  onTap:
                      () => _mutateTable(
                        node,
                        direction: TableDirection.row,
                        add: false,
                      ),
                ),
                _YuliAtomicAction(
                  label: 'COL +',
                  icon: YuLiIcons.plus,
                  onTap:
                      () => _mutateTable(
                        node,
                        direction: TableDirection.col,
                        add: true,
                      ),
                ),
                _YuliAtomicAction(
                  label: 'COL -',
                  icon: YuLiIcons.minus,
                  enabled: cols > 1,
                  onTap:
                      () => _mutateTable(
                        node,
                        direction: TableDirection.col,
                        add: false,
                      ),
                ),
              ],
              child: result,
            );
          }
          if (node.type == ImageBlockKeys.type) {
            final editing = _editingImages.contains(key);
            return _YuliAtomicFrame(
              key: ValueKey('yuli_atomic_image_${node.path.join('_')}'),
              accent: widget.accent,
              selected: active,
              editing: editing,
              label: 'IMAGEN',
              interceptContent: !editing,
              onSelect: () => _selectAtomicNode(node),
              actions: [
                if (!editing)
                  _YuliAtomicAction(
                    label: 'EDITAR',
                    icon: YuLiIcons.pencil,
                    onTap: () {
                      setState(() => _editingImages.add(key));
                    },
                  ),
                if (!editing)
                  _YuliAtomicAction(
                    label: 'IZQ',
                    icon: YuLiIcons.textAlignStart,
                    onTap: () => _setNodeAlignment(node, 'left'),
                  ),
                if (!editing)
                  _YuliAtomicAction(
                    label: 'CENTRO',
                    icon: YuLiIcons.textAlignCenter,
                    onTap: () => _setNodeAlignment(node, 'center'),
                  ),
                if (!editing)
                  _YuliAtomicAction(
                    label: 'DER',
                    icon: YuLiIcons.textAlignEnd,
                    onTap: () => _setNodeAlignment(node, 'right'),
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
                      ? _YuliImageInlineEditor(
                        initialUrl:
                            node.attributes[ImageBlockKeys.url] as String? ??
                            '',
                        initialWidth:
                            (node.attributes[ImageBlockKeys.width] as num?)
                                ?.toDouble() ??
                            320.0,
                        initialAlign:
                            node.attributes[ImageBlockKeys.align] as String? ??
                            'center',
                        accent: widget.accent,
                        onPickImage: _pickImageForInlineEditor,
                        onCancel: () {
                          setState(() => _editingImages.remove(key));
                          _selectAtomicNode(node);
                        },
                        onSave:
                            (url, width, align) => _saveImage(
                              node,
                              url: url,
                              width: width,
                              align: align,
                            ),
                      )
                      : result,
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

    final rootChildren = _editorState.document.root.children;
    final lastNode = rootChildren.isEmpty ? null : rootChildren.last;
    final showContinue =
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        border:
            _focused
                ? Border(
                  left: BorderSide(color: widget.accent, width: yLineMid),
                )
                : null,
      ),
      padding: EdgeInsets.only(left: _focused ? 8 : 0, right: 20),
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
  }
}

class _YuliAtomicAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  const _YuliAtomicAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
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
    final color =
        action.enabled ? (action.destructive ? yFight : accent) : yCream2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action.enabled ? action.onTap : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow: [
            BoxShadow(
              color:
                  action.enabled ? yInk : yBorderSoft.withValues(alpha: 0.55),
              offset: const Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              action.icon,
              size: 13,
              color: action.enabled ? yCream : yMuted,
            ),
            const SizedBox(width: 5),
            Text(
              action.label,
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                color: action.enabled ? yCream : yMuted,
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

class _YuliCodeInlineEditor extends StatefulWidget {
  final String initialCode;
  final String initialLanguage;
  final Color accent;
  final VoidCallback onCancel;
  final void Function(String language, String code) onSave;

  const _YuliCodeInlineEditor({
    required this.initialCode,
    required this.initialLanguage,
    required this.accent,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_YuliCodeInlineEditor> createState() => _YuliCodeInlineEditorState();
}

class _YuliCodeInlineEditorState extends State<_YuliCodeInlineEditor> {
  late final TextEditingController _codeController;
  late String _language;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialCode);
    _language = yuliNormalizeCodeLanguage(widget.initialLanguage);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: yCream2,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YuliCodeLanguagePicker(
            language: _language,
            accent: widget.accent,
            onChanged: (value) => setState(() => _language = value),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _codeController,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            style: yMono(
              size: 13,
              color: yInk,
              tracking: 0,
            ).copyWith(height: 1.45),
            decoration: const InputDecoration(
              hintText: 'CODIGO',
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
                  onTap: () => widget.onSave(_language, _codeController.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YuliImageInlineEditor extends StatefulWidget {
  final String initialUrl;
  final double initialWidth;
  final String initialAlign;
  final Color accent;
  final Future<String?> Function() onPickImage;
  final VoidCallback onCancel;
  final void Function(String url, double width, String align) onSave;

  const _YuliImageInlineEditor({
    required this.initialUrl,
    required this.initialWidth,
    required this.initialAlign,
    required this.accent,
    required this.onPickImage,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_YuliImageInlineEditor> createState() => _YuliImageInlineEditorState();
}

class _YuliImageInlineEditorState extends State<_YuliImageInlineEditor> {
  late String _url;
  late double _width;
  late String _align;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl.trim();
    _width = widget.initialWidth.clamp(160.0, 520.0);
    _align = widget.initialAlign;
  }

  Future<void> _pickImage() async {
    if (_loading) return;
    setState(() => _loading = true);
    final path = await widget.onPickImage();
    if (!mounted) return;
    setState(() {
      if (path != null && path.trim().isNotEmpty) {
        _url = path.trim();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: yCream2,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _YuliImageInlinePreview(url: _url),
          const SizedBox(height: 10),
          _YuliInlineEditorButton(
            label: _url.isEmpty ? 'SELECCIONAR IMAGEN' : 'CAMBIAR IMAGEN',
            color: widget.accent,
            foreground: yCream,
            onTap: _loading ? null : _pickImage,
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'IMPORTANDO...',
                textAlign: TextAlign.center,
                style: yMono(size: 10, color: yMuted, tracking: 0.8),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _YuliInlineEditorChip(
                label: 'PEQUEÑA',
                active: _width <= 220,
                accent: widget.accent,
                onTap: () => setState(() => _width = 180),
              ),
              _YuliInlineEditorChip(
                label: 'MEDIA',
                active: _width > 220 && _width < 430,
                accent: widget.accent,
                onTap: () => setState(() => _width = 320),
              ),
              _YuliInlineEditorChip(
                label: 'GRANDE',
                active: _width >= 430,
                accent: widget.accent,
                onTap: () => setState(() => _width = 520),
              ),
              _YuliInlineEditorChip(
                label: 'IZQ',
                active: _align == 'left',
                accent: widget.accent,
                onTap: () => setState(() => _align = 'left'),
              ),
              _YuliInlineEditorChip(
                label: 'CENTRO',
                active: _align == 'center',
                accent: widget.accent,
                onTap: () => setState(() => _align = 'center'),
              ),
              _YuliInlineEditorChip(
                label: 'DER',
                active: _align == 'right',
                accent: widget.accent,
                onTap: () => setState(() => _align = 'right'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'ANCHO ${_width.round()} PX',
            style: yMono(size: 10, color: yMuted, tracking: 0.7),
          ),
          const SizedBox(height: 10),
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
                      _url.isEmpty || _loading
                          ? null
                          : () => widget.onSave(_url, _width, _align),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YuliImageInlinePreview extends StatelessWidget {
  final String url;

  const _YuliImageInlinePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final file = url.isEmpty ? null : File(url);
    final exists = file?.existsSync() ?? false;
    return Container(
      constraints: const BoxConstraints(minHeight: 96, maxHeight: 180),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      clipBehavior: Clip.hardEdge,
      child:
          url.isEmpty
              ? _YuliImageInlinePlaceholder(
                icon: YuLiIcons.image,
                label: 'Sin imagen seleccionada',
              )
              : exists
              ? Image.file(file!, fit: BoxFit.contain)
              : url.startsWith('http://') || url.startsWith('https://')
              ? Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, _, _) => _YuliImageInlinePlaceholder(
                      icon: YuLiIcons.imageOff,
                      label: 'Imagen no disponible',
                    ),
              )
              : _YuliImageInlinePlaceholder(
                icon: YuLiIcons.image,
                label: url.split(RegExp(r'[\\/]+')).last,
              ),
    );
  }
}

class _YuliImageInlinePlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;

  const _YuliImageInlinePlaceholder({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
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
    );
  }
}

class _YuliInlineEditorChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _YuliInlineEditorChip({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yMono(
            size: 10,
            weight: FontWeight.w700,
            color: active ? yCream : yInk,
            tracking: 0.7,
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

class _YuliTableAxisControls extends StatelessWidget {
  final Color accent;
  final bool canDelete;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  const _YuliTableAxisControls({
    required this.accent,
    required this.canDelete,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _YuliTableAxisButton(
            icon: YuLiIcons.minus,
            color: canDelete ? accent : yMuted,
            onTap: canDelete ? onDelete : null,
          ),
          Container(width: yLineThin, height: 26, color: yBorderStrong),
          _YuliTableAxisButton(
            icon: YuLiIcons.plus,
            color: accent,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _YuliTableAxisButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _YuliTableAxisButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 26,
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
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
