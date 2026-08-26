import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import 'yuli_markdown_commands.dart';
import 'yuli_markdown_document.dart';

class FormatToolbar extends StatelessWidget {
  final EditorState? editorState;
  final VoidCallback? onOpenInsertMenu;
  final VoidCallback? onRequestFocus;
  final Color accent;

  const FormatToolbar({
    super.key,
    this.editorState,
    this.onOpenInsertMenu,
    this.onRequestFocus,
    this.accent = yFlight,
  });

  void _wrap(String marker) {
    final state = editorState;
    if (state == null) return;
    onRequestFocus?.call();
    wrapMarkdownSelection(state, marker);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onRequestFocus?.call();
    });
  }

  void _line(String prefix, {RegExp? removePattern, bool replaceLine = false}) {
    final state = editorState;
    if (state == null) return;
    onRequestFocus?.call();
    applyMarkdownLinePrefix(
      state,
      prefix,
      removePattern: removePattern,
      replaceLine: replaceLine,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onRequestFocus?.call();
    });
  }

  Future<void> _align(String align) async {
    final state = editorState;
    final selection = state?.selection;
    if (state == null || selection == null) return;
    onRequestFocus?.call();
    setPreferredMarkdownAlignment(state, align);
    final targets = <Node>{};
    for (final node in state.getNodesInSelection(selection)) {
      targets.add(_alignmentTarget(node));
    }
    final direct = state.getNodeAtPath(selection.start.path);
    if (direct != null) targets.add(_alignmentTarget(direct));
    final transaction = state.transaction;
    for (final node in targets) {
      transaction.updateNode(node, {
        if (node.type == ImageBlockKeys.type)
          ImageBlockKeys.align: align
        else
          blockComponentAlign: align == 'left' ? null : align,
      });
    }
    transaction.afterSelection = selection;
    await state.apply(transaction);
    if (state.selection != selection) {
      await state.updateSelectionWithReason(
        selection,
        reason: SelectionUpdateReason.uiEvent,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onRequestFocus?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = editorState;
    if (state == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Selection?>(
      valueListenable: state.selectionNotifier,
      builder: (context, selection, _) {
        String activeAlign() {
          if (selection == null) return preferredMarkdownAlignment(state);
          final nodes = state.getNodesInSelection(selection).toList();
          final direct = state.getNodeAtPath(selection.start.path);
          if (direct != null && !nodes.contains(direct)) nodes.add(direct);
          if (nodes.isEmpty) return preferredMarkdownAlignment(state);
          final values =
              nodes
                  .map(_alignmentTarget)
                  .map(
                    (node) =>
                        node.type == ImageBlockKeys.type
                            ? node.attributes[ImageBlockKeys.align] ?? 'center'
                            : node.attributes[blockComponentAlign] ?? 'left',
                  )
                  .toSet();
          return values.length == 1
              ? values.first as String
              : preferredMarkdownAlignment(state);
        }

        final align = activeAlign();
        final blockPrefix = RegExp(
          r'^(#{1,6}\s+|>\s?|(?:[-+*]|\d+[.)])\s+|[-+*]\s+\[[ xX]\]\s+)',
        );
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow: const [
              BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _TextToolBtn(
                  label: 'H1',
                  active: false,
                  accent: accent,
                  onTap: () => _line('# ', removePattern: blockPrefix),
                ),
                _sep(),
                _TextToolBtn(
                  label: 'H2',
                  active: false,
                  accent: accent,
                  onTap: () => _line('## ', removePattern: blockPrefix),
                ),
                _sep(),
                _TextToolBtn(
                  label: 'H3',
                  active: false,
                  accent: accent,
                  onTap: () => _line('### ', removePattern: blockPrefix),
                ),
                _groupGap(),
                _TextToolBtn(
                  label: 'B',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('**'),
                ),
                _sep(),
                _TextToolBtn(
                  label: 'I',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('*'),
                ),
                _sep(),
                _TextToolBtn(
                  label: 'S',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('~~'),
                ),
                _sep(),
                _IconToolBtn(
                  icon: YuLiIcons.highlighter,
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('=='),
                ),
                _sep(),
                _TextToolBtn(
                  label: '`',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('`'),
                ),
                _groupGap(),
                _TextToolBtn(
                  label: '>',
                  active: false,
                  accent: accent,
                  onTap: () => _line('> ', removePattern: blockPrefix),
                ),
                _sep(),
                _TextToolBtn(
                  label: '-',
                  active: false,
                  accent: accent,
                  onTap: () => _line('- ', removePattern: blockPrefix),
                ),
                _sep(),
                _TextToolBtn(
                  label: '[ ]',
                  active: false,
                  accent: accent,
                  onTap: () => _line('- [ ] ', removePattern: blockPrefix),
                ),
                _sep(),
                _TextToolBtn(
                  label: '---',
                  active: false,
                  accent: accent,
                  wide: true,
                  onTap: () => _line('---', replaceLine: true),
                ),
                _groupGap(),
                _IconToolBtn(
                  icon: YuLiIcons.textAlignStart,
                  active: align == 'left',
                  accent: accent,
                  onTap: () => _align('left'),
                ),
                _sep(),
                _IconToolBtn(
                  icon: YuLiIcons.textAlignCenter,
                  active: align == 'center',
                  accent: accent,
                  onTap: () => _align('center'),
                ),
                _sep(),
                _IconToolBtn(
                  icon: YuLiIcons.textAlignEnd,
                  active: align == 'right',
                  accent: accent,
                  onTap: () => _align('right'),
                ),
                _groupGap(),
                if (onOpenInsertMenu != null)
                  _TextToolBtn(
                    label: '+',
                    active: true,
                    accent: accent,
                    onTap: onOpenInsertMenu!,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Node _alignmentTarget(Node node) {
  final original = node;
  var current = node;
  while (current.parent != null) {
    if (current.type == ImageBlockKeys.type ||
        current.type == TableBlockKeys.type ||
        current.type == yuliLatexBlockType) {
      return current;
    }
    current = current.parent!;
  }
  return original;
}

Widget _sep() => Container(width: yLineThin, height: 28, color: yBorderStrong);

Widget _groupGap() => const SizedBox(width: 12);

class _TextToolBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color accent;
  final bool wide;
  const _TextToolBtn({
    required this.label,
    required this.onTap,
    required this.active,
    required this.accent,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: wide ? 50 : 38,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Text(
          label,
          style: yBody(
            size: 13,
            weight: FontWeight.w700,
            color: active ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

class _IconToolBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color accent;
  const _IconToolBtn({
    required this.icon,
    required this.onTap,
    required this.active,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 38,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Icon(icon, size: 14, color: active ? yCream : yInk),
      ),
    );
  }
}
