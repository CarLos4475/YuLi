import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_tokens.dart';
import '../providers/database_providers.dart';

/// Wraps [child] and shows a one-time coachmark overlay.
/// Reads [flagKey] from onboarding_flags; if not seen, shows the tooltip.
class CoachMark extends ConsumerStatefulWidget {
  final String flagKey;
  final String message;
  final Widget child;
  final CoachMarkPosition position;

  const CoachMark({
    super.key,
    required this.flagKey,
    required this.message,
    required this.child,
    this.position = CoachMarkPosition.below,
  });

  @override
  ConsumerState<CoachMark> createState() => _CoachMarkState();
}

enum CoachMarkPosition { above, below }

class _CoachMarkState extends ConsumerState<CoachMark> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final db = ref.read(databaseProvider);
    final seen = await db.hasSeenOnboarding(widget.flagKey);
    if (!seen && mounted) setState(() => _visible = true);
  }

  Future<void> _dismiss() async {
    setState(() => _visible = false);
    await ref.read(databaseProvider).markOnboardingSeen(widget.flagKey);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_visible)
          Positioned(
            top: widget.position == CoachMarkPosition.below ? null : null,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: false,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: inkColor(context),
                    boxShadow: [
                      BoxShadow(
                        color: paperColor(context),
                        offset: shadowOffset,
                        blurRadius: shadowBlurRadius,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.message,
                          style: bodyS.copyWith(color: paperColor(context)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ok',
                        style: labelBold.copyWith(color: paperColor(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
