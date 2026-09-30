import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';

class YuliImageResizeFrame extends ConsumerStatefulWidget {
  final double width;
  final double maxWidth;
  final bool selected;
  final Color accent;
  final Widget Function(double width) builder;
  final ValueChanged<double> onResize;

  const YuliImageResizeFrame({
    super.key,
    required this.width,
    required this.maxWidth,
    required this.selected,
    required this.accent,
    required this.builder,
    required this.onResize,
  });

  @override
  ConsumerState<YuliImageResizeFrame> createState() =>
      _YuliImageResizeFrameState();
}

class _YuliImageResizeFrameState extends ConsumerState<YuliImageResizeFrame> {
  double? _draft;
  double? _startX;
  double? _startWidth;
  @override
  Widget build(BuildContext context) {
    final width = (_draft ?? widget.width).clamp(
      80.0,
      widget.maxWidth.clamp(80.0, 1200.0),
    );
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          widget.builder(width),
          if (widget.selected || _draft != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Semantics(
                label: 'Cambiar tamaño de imagen',
                child: Listener(
                  key: const ValueKey('yuli_image_resize'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    _startX = event.position.dx;
                    _startWidth = width;
                    _draft = width;
                  },
                  onPointerMove: (event) {
                    if (_startX == null) return;
                    setState(
                      () =>
                          _draft = (_startWidth! + event.position.dx - _startX!)
                              .clamp(80, widget.maxWidth.clamp(80, 1200)),
                    );
                  },
                  onPointerUp: (_) {
                    widget.onResize(_draft ?? width);
                    setState(() {
                      _draft = null;
                      _startX = null;
                    });
                  },
                  onPointerCancel:
                      (_) => setState(() {
                        _draft = null;
                        _startX = null;
                      }),
                  child: GestureDetector(
                    onPanUpdate: (_) {},
                    child: Container(
                      width: 44,
                      height: 44,
                      color: widget.accent,
                      child: const Icon(
                        YuLiIcons.maximize,
                        color: yCream,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
