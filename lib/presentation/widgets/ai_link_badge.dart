import 'dart:async';
import 'package:flutter/material.dart';

import 'yuli_design.dart';

/// Wraps the AI button and overlays a hard-blinking solid square (no fade,
/// brutalist) in the top-right corner when the canvas is linked to a source
/// note. Signals "this canvas's AI context is synced from a note".
class AiLinkBadge extends StatefulWidget {
  final Widget child;
  final bool active;
  final Color color;
  const AiLinkBadge({
    super.key,
    required this.child,
    required this.active,
    required this.color,
  });

  @override
  State<AiLinkBadge> createState() => _AiLinkBadgeState();
}

class _AiLinkBadgeState extends State<AiLinkBadge> {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant AiLinkBadge old) {
    super.didUpdateWidget(old);
    if (widget.active && _timer == null) {
      _start();
    } else if (!widget.active && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _on = true;
    }
  }

  void _start() {
    _on = true;
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_on)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.color,
                border: Border.all(color: yBorderStrong, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
