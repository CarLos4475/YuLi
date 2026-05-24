import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

class AppSectionDivider extends StatelessWidget {
  final String label;
  final Color? lineColor;
  final EdgeInsetsGeometry? padding;

  const AppSectionDivider({
    super.key,
    required this.label,
    this.lineColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final color = lineColor ?? inkGray;

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: color,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: bodyS.copyWith(color: color, letterSpacing: 1.5),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
