import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class AppTag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  final VoidCallback? onTap;

  const AppTag({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? inkColor(context);
    final fgColor = textColor ?? _contrastColor(bgColor);

    Widget tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: bgColor, width: 0),
      ),
      child: Text(
        label,
        style: labelBold.copyWith(color: fgColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: tag,
      );
    }

    return tag;
  }

  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? inkBlack : inkLight;
  }
}
