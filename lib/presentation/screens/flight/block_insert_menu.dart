import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
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
      _MenuItem(
        YuLiIcons.table,
        'Tabla',
        panelType: InsertPanelType.table,
      ),
      _MenuItem(YuLiIcons.code, 'Código', panelType: InsertPanelType.code),
      _MenuItem(
        YuLiIcons.textQuote,
        'Cita',
        panelType: InsertPanelType.quote,
      ),
      _MenuItem(YuLiIcons.sigma, 'LaTeX', panelType: InsertPanelType.latex),
      _MenuItem(
        YuLiIcons.image,
        'Imagen',
        panelType: InsertPanelType.image,
      ),
      _MenuItem(YuLiIcons.separatorHorizontal, 'Divisor', syntax: '\n\n---\n\n'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yBorderStrong, width: yLineMid)),
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
                'INSERTAR BLOQUE',
                style: yMono(
                  size: 10,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                itemCount: items.length,
                separatorBuilder:
                    (_, _) => Divider(
                      height: 1,
                      color: yMuted.withValues(alpha: 0.3),
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
                        horizontal: 24,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, size: 20, color: yMuted),
                          const SizedBox(width: 16),
                          Text(item.label, style: yBody(size: 16, color: yInk)),
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
