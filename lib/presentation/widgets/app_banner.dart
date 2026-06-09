import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/lab_icons.dart';

class AppBanner extends StatelessWidget {
  final String message;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const AppBanner({
    super.key,
    required this.message,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackground(context),
        border: Border(
          left: BorderSide(color: accentColor, width: borderWidthHeavy),
          top: BorderSide(color: inkColor(context), width: borderWidth),
          bottom: BorderSide(color: inkColor(context), width: borderWidth),
          right: BorderSide(color: inkColor(context), width: borderWidth),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: bodyS.copyWith(color: inkColor(context)),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  actionLabel!,
                  style: labelBold.copyWith(color: accentColor),
                ),
              ),
            ),
          if (onDismiss != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  YuLiIcons.close,
                  size: 16,
                  color: inkGray,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
