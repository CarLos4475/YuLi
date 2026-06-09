import 'package:flutter/material.dart';

/// Editor popup that scales/fades/slides in on open and back out on close — the
/// same feel as the floating palettes. Drop-in replacement for the old
/// `if (open) ...[barrier, Positioned(popup)]` blocks: it stays mounted while
/// the close animates and ignores pointers while shut.
///
/// Anchors at the bottom by default (slides up). Pass [top] to anchor near the
/// top instead (slides down) — used by the inline block-note cells whose
/// toolbar sits at the top.
class RevealPopup extends StatefulWidget {
  final bool open;
  final VoidCallback onDismiss;
  final Widget child;
  final double? top;
  final double bottom;
  final double horizontalMargin;

  const RevealPopup({
    super.key,
    required this.open,
    required this.onDismiss,
    required this.child,
    this.top,
    this.bottom = 64,
    this.horizontalMargin = 12,
  });

  @override
  State<RevealPopup> createState() => _RevealPopupState();
}

class _RevealPopupState extends State<RevealPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 170),
      value: widget.open ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(RevealPopup old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) {
      _ctrl.forward();
    } else if (!widget.open && old.open) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromTop = widget.top != null;
    final scaleAlign = fromTop ? Alignment.topCenter : Alignment.bottomCenter;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        if (t == 0) return const SizedBox.shrink();
        final fade = Curves.easeOut.transform(t).clamp(0.0, 1.0);
        final scaleT = Curves.easeOutBack.transform(t);
        final slideT = Curves.easeOutCubic.transform(t);
        final scale = 0.90 + 0.10 * scaleT;
        final dy = (fromTop ? -22.0 : 22.0) * (1 - slideT);
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: !widget.open,
            child: Stack(
              children: [
                if (widget.open)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDismiss,
                    ),
                  ),
                Positioned(
                  left: widget.horizontalMargin,
                  right: widget.horizontalMargin,
                  top: widget.top,
                  bottom: fromTop ? null : widget.bottom,
                  child: Align(
                    alignment: scaleAlign,
                    child: Opacity(
                      opacity: fade,
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Transform.scale(
                          scale: scale,
                          alignment: scaleAlign,
                          child: widget.child,
                        ),
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
