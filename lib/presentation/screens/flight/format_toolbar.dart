import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';

class FormatToolbar extends StatelessWidget {
  final TextEditingController? controller;
  final VoidCallback? onOpenInsertMenu;

  const FormatToolbar({super.key, this.controller, this.onOpenInsertMenu});

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
    final wrapped = '::: $align\n$selected\n:::';
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
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _FmtBtn(label: 'B', onTap: () => _wrap('**', '**')),
          const SizedBox(width: 4),
          _FmtBtn(label: 'I', onTap: () => _wrap('*', '*')),
          const SizedBox(width: 4),
          _FmtBtn(label: 'S', onTap: () => _wrap('~~', '~~')),
          const SizedBox(width: 4),
          _FmtBtn(label: '`', onTap: () => _wrap('`', '`')),
          const SizedBox(width: 4),
          _FmtBtn(label: r'$', onTap: () => _wrap(r'$', r'$')),
          const SizedBox(width: 8),
          _AlignBtn(icon: Icons.format_align_left, onTap: () => _wrapAlign('left')),
          const SizedBox(width: 4),
          _AlignBtn(icon: Icons.format_align_center, onTap: () => _wrapAlign('center')),
          const SizedBox(width: 4),
          _AlignBtn(icon: Icons.format_align_right, onTap: () => _wrapAlign('right')),
          const Spacer(),
          if (onOpenInsertMenu != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenInsertMenu,
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: yFlight,
                  border: Border.all(color: yInk, width: 1.5),
                ),
                child: Text('+',
                    style: yMono(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yCream,
                      tracking: 0,
                    )),
              ),
            ),
        ],
      ),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FmtBtn({required this.label, required this.onTap});

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
          color: yCream,
          border: Border.all(color: yInk, width: 1.5),
        ),
        child: Text(
          label,
          style: yBody(size: 13, weight: FontWeight.w700, color: yInk),
        ),
      ),
    );
  }
}

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _AlignBtn({required this.icon, required this.onTap});

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
          border: Border.all(color: yInk, width: 1.5),
        ),
        child: Icon(icon, size: 14, color: yInk),
      ),
    );
  }
}
