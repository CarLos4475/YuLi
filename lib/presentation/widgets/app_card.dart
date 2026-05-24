import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  final double? borderThickness;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Offset? shadowOffset;

  const AppCard({
    super.key,
    required this.child,
    this.borderColor,
    this.borderThickness,
    this.backgroundColor,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.shadowOffset,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? inkColor(context);
    final effectiveBorderThickness = borderThickness ?? borderWidth;
    final effectiveBackground = backgroundColor ?? cardBackground(context);
    final effectiveShadow = shadowOffset;

    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: effectiveBackground,
        border: Border.all(
          color: effectiveBorderColor,
          width: effectiveBorderThickness,
        ),
        boxShadow: effectiveShadow != null
            ? [
                BoxShadow(
                  color: effectiveBorderColor,
                  offset: effectiveShadow,
                  blurRadius: shadowBlurRadius,
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      );
    }

    return card;
  }
}
