import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';
import 'block_insert_panels.dart';

class BlockInsertMenu extends StatelessWidget {
  final void Function(String syntax) onDirectInsert;
  final void Function(InsertPanelType type) onOpenPanel;

  const BlockInsertMenu({
    super.key,
    required this.onDirectInsert,
    required this.onOpenPanel,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(Icons.table_chart_outlined, 'Tabla',
          panelType: InsertPanelType.table),
      _MenuItem(Icons.code, 'Código', panelType: InsertPanelType.code),
      _MenuItem(Icons.format_quote_outlined, 'Cita',
          panelType: InsertPanelType.quote),
      _MenuItem(Icons.functions, 'LaTeX', panelType: InsertPanelType.latex),
      _MenuItem(Icons.image_outlined, 'Imagen',
          panelType: InsertPanelType.image),
      _MenuItem(Icons.horizontal_rule, 'Divisor', syntax: '\n\n---\n\n'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: paperColor(context),
        border: Border(
          top: BorderSide(color: inkColor(context), width: borderWidthHeavy),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Insertar bloque',
                style: labelBold.copyWith(color: inkGray),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: inkGray.withAlpha(40),
                  indent: 24,
                  endIndent: 24,
                ),
                itemBuilder: (_, i) {
                  final item = items[i];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(context);
                      if (item.syntax != null) {
                        onDirectInsert(item.syntax!);
                      } else if (item.panelType != null) {
                        onOpenPanel(item.panelType!);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      child: Row(
                        children: [
                          Icon(item.icon, size: 20, color: inkGray),
                          const SizedBox(width: 16),
                          Text(
                            item.label,
                            style: bodyM.copyWith(color: inkColor(context)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String? syntax;
  final InsertPanelType? panelType;
  const _MenuItem(this.icon, this.label, {this.syntax, this.panelType});
}
