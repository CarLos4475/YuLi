import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import 'block_insert_panels.dart';

class BlockInsertMenu extends StatelessWidget {
  final void Function(String syntax) onDirectInsert;
  final void Function(InsertPanelType type) onOpenPanel;
  final Color accent;

  const BlockInsertMenu({
    super.key,
    required this.onDirectInsert,
    required this.onOpenPanel,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(
          top: BorderSide(color: yBorderStrong, width: yLineMid),
          left: BorderSide(color: yBorderStrong, width: yLineMid),
          right: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
        boxShadow: [
          BoxShadow(
            color: yBorderStrong,
            offset: Offset(7, 7),
            blurRadius: 0,
          ),
        ],
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.65,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Insertar bloque',
                          style: ySans(
                            size: 22,
                            weight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: yInk,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'CONTENIDO · MEDIA',
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w700,
                            tracking: 1.6,
                            color: yMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: yBorderStrong.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                children: [
                  _GroupLabel('Contenido'),
                  const SizedBox(height: 6),
                  _BlockTile(
                    icon: YuLiIcons.table,
                    label: 'Tabla',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenPanel(InsertPanelType.table);
                    },
                  ),
                  _BlockTile(
                    icon: YuLiIcons.code,
                    label: 'Codigo',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenPanel(InsertPanelType.code);
                    },
                  ),
                  _BlockTile(
                    icon: YuLiIcons.textQuote,
                    label: 'Cita',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenPanel(InsertPanelType.quote);
                    },
                  ),
                  _BlockTile(
                    icon: YuLiIcons.sigma,
                    label: 'Latex',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenPanel(InsertPanelType.latex);
                    },
                  ),
                  const SizedBox(height: 10),
                  _GroupLabel('Media'),
                  const SizedBox(height: 6),
                  _BlockTile(
                    icon: YuLiIcons.image,
                    label: 'Imagen',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onOpenPanel(InsertPanelType.image);
                    },
                  ),
                  _BlockTile(
                    icon: YuLiIcons.separatorHorizontal,
                    label: 'Divisor',
                    accent: accent,
                    onTap: () {
                      Navigator.pop(context);
                      onDirectInsert('\n\n---\n\n');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      '── ${label.toUpperCase()}',
      style: yMono(
        size: 10,
        weight: FontWeight.w700,
        tracking: 1.6,
        color: yMuted,
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;

  const _BlockTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  border: Border(
                    right: BorderSide(color: yBorderStrong, width: yLineThin),
                  ),
                ),
                child: Icon(icon, size: 18, color: yCream),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: ySans(
                    size: 15,
                    weight: FontWeight.w700,
                    color: yInk,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  YuLiIcons.chevronRight,
                  size: 18,
                  color: yInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
