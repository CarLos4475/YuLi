import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/note_block.dart';
import '../../../domain/repositories/note_block_repository.dart';
import 'yuli_markdown_commands.dart';
import 'yuli_markdown_document.dart';

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

  const YuliLiveTextEditor({
    super.key,
    required this.block,
    required this.accent,
    this.onFocusChanged,
    this.autofocus = false,
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
    if (_focusNode.hasFocus) return;
    if (_focused && mounted) setState(() => _focused = false);
    if (_pendingSave) _persist();
  }

  void _onSelectionChanged() {
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

  Future<void> _activate() async {
    if (!mounted) return;
    _focusNode.requestFocus();
    await _editorState.updateSelectionWithReason(
      Selection.collapsed(Position(path: const [0])),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  void _applyInitialLiveStyles() {
    for (final node in _editorState.document.root.children) {
      final delta = node.delta;
      if (delta == null || node.type == yuliCodeBlockType) continue;
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
          final text = node.delta?.toPlainText().trimLeft() ?? '';
          final selection = _editorState.selection?.normalized;
          final active =
              selection != null &&
              selection.start.path.equals(node.path) &&
              selection.end.path.equals(node.path);
          if (text.trim() == '---') {
            return Stack(
              alignment: Alignment.center,
              children: [
                child!,
                if (!active)
                  IgnorePointer(
                    child: Container(height: yLineThin, color: yBorderStrong),
                  ),
              ],
            );
          }
          Widget result = child!;
          if (node.type == yuliCodeBlockType) {
            result = Container(
              width: double.infinity,
              color: yCream2,
              child: result,
            );
          }
          if (node.type == TableBlockKeys.type) {
            final align = node.attributes[blockComponentAlign] as String?;
            final alignment = switch (align) {
              'center' => Alignment.center,
              'right' => Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
            final tableChild = result;
            result = LayoutBuilder(
              builder: (context, constraints) {
                final width = (TableNode(node: node).tableWidth + 40).clamp(
                  0,
                  constraints.maxWidth,
                );
                return Align(
                  alignment: alignment,
                  child: SizedBox(width: width.toDouble(), child: tableChild),
                );
              },
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
            ),
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
