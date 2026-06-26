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
        return Container(
          decoration: const BoxDecoration(
            color: yCream,
            border: Border(
              top: BorderSide(color: yBorderStrong, width: yLineThin),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _FmtBtn(
                  label: 'B',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('**'),
                ),
                const SizedBox(width: 4),
                _FmtBtn(
                  label: 'I',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('*'),
                ),
                const SizedBox(width: 4),
                _FmtBtn(
                  label: 'S',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('~~'),
                ),
                const SizedBox(width: 4),
                _FmtBtn(
                  label: '`',
                  active: false,
                  accent: accent,
                  onTap: () => _wrap('`'),
                ),
                const SizedBox(width: 8),
                _AlignBtn(
                  icon: YuLiIcons.textAlignStart,
                  active: align == 'left',
                  accent: accent,
                  onTap: () => _align('left'),
                ),
                const SizedBox(width: 4),
                _AlignBtn(
                  icon: YuLiIcons.textAlignCenter,
                  active: align == 'center',
                  accent: accent,
                  onTap: () => _align('center'),
                ),
                const SizedBox(width: 4),
                _AlignBtn(
                  icon: YuLiIcons.textAlignEnd,
                  active: align == 'right',
                  accent: accent,
                  onTap: () => _align('right'),
                ),
                const SizedBox(width: 12),
                if (onOpenInsertMenu != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenInsertMenu,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        border: Border.all(color: yBorderStrong, width: 1.5),
                      ),
                      child: Text(
                        '+',
                        style: yMono(
                          size: 14,
                          weight: FontWeight.w700,
                          color: yCream,
                          tracking: 0,
                        ),
                      ),
                    ),
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

class _FmtBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color accent;
  const _FmtBtn({
    required this.label,
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
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: 1.5),
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

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color accent;
  const _AlignBtn({
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
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent : yCream,
          border: Border.all(color: yBorderStrong, width: 1.5),
        ),
        child: Icon(icon, size: 14, color: active ? yCream : yInk),
      ),
    );
  }
}
