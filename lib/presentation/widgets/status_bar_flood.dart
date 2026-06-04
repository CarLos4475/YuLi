import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floods the status-bar inset with [color] (edge-to-edge) and sets matching
/// icon brightness, keeping [child] below the bar. Use as a Scaffold `body`
/// wrapper on screens whose own header colour differs from the cream scaffold
/// background, so the status bar continues seamlessly into the header band
/// instead of leaving a mismatched strip above it.
class StatusBarFlood extends StatelessWidget {
  const StatusBarFlood({
    super.key,
    required this.color,
    required this.child,
    this.leadingColor,
    this.leadingWidth = 8,
  });

  /// The header colour to extend into the status bar.
  final Color color;

  /// The screen body. Should NOT add its own top SafeArea — this widget already
  /// consumes the top inset via the coloured strip.
  final Widget child;

  /// Optional accent sideline that continues up the LEFT edge into the status
  /// bar (e.g. a folder header's colour stripe). Null → plain [color] strip.
  final Color? leadingColor;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final light = color.computeLuminance() > 0.5;
    final leading = leadingColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
        statusBarBrightness: light ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.paddingOf(context).top,
            width: double.infinity,
            child: leading == null
                ? ColoredBox(color: color)
                : Row(
                    // Stretch so the fill (ColoredBox) takes the full strip
                    // height — without it the loose Row height collapses it to
                    // zero and the scaffold cream shows through.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: leadingWidth,
                        child: ColoredBox(color: leading),
                      ),
                      Expanded(child: ColoredBox(color: color)),
                    ],
                  ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
