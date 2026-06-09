import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/lab_icons.dart';

class AppColumnHeader extends StatelessWidget {
  final String title;
  final Color accentColor;
  final int? cardCount;
  final VoidCallback? onDelete;

  const AppColumnHeader({
    super.key,
    required this.title,
    required this.accentColor,
    this.cardCount,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: accentColor, width: borderWidthHeavy),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: labelBold.copyWith(color: inkColor(context)),
            ),
          ),
          if (cardCount != null)
            Text(
              '$cardCount',
              style: mono.copyWith(color: inkGray),
            ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(YuLiIcons.close, size: 14, color: inkGray.withAlpha(120)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
