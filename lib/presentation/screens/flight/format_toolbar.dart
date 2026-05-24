import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';

class FormatToolbar extends StatelessWidget {
  final TextEditingController? controller;

  const FormatToolbar({super.key, this.controller});

  void _wrap(String before, String after) {
    final ctrl = controller;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final selected = sel.textInside(text);
    final newText = text.replaceRange(
        sel.start, sel.end, '$before$selected$after');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: sel.start + before.length,
        extentOffset: sel.start + before.length + selected.length,
      ),
    );
  }

  void _wrapAlign(String align) {
    final ctrl = controller;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final selected = sel.textInside(text);
    final wrapped = '::: $align\n\n$selected\n\n:::';
    final newText = text.replaceRange(sel.start, sel.end, wrapped);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.start + wrapped.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ToolbarItem(label: 'B', onTap: () => _wrap('**', '**')),
        _ToolbarItem(label: 'I', onTap: () => _wrap('*', '*')),
        _ToolbarItem(label: 'S', onTap: () => _wrap('~~', '~~')),
        _ToolbarItem(label: '`', onTap: () => _wrap('`', '`')),
        _ToolbarItem(label: r'$', onTap: () => _wrap(r'$', r'$')),
        _AlignItem(icon: Icons.format_align_left, onTap: () => _wrapAlign('left')),
        _AlignItem(icon: Icons.format_align_center, onTap: () => _wrapAlign('center')),
        _AlignItem(icon: Icons.format_align_right, onTap: () => _wrapAlign('right')),
      ],
    );
  }
}

class _ToolbarItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ToolbarItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Text(
            label,
            style: labelBold.copyWith(color: inkColor(context)),
          ),
        ),
      ),
    );
  }
}

class _AlignItem extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AlignItem({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 16, color: inkColor(context)),
      ),
    );
  }
}
