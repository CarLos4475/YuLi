import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

enum LassoExtraMenuSide { left, right }

class LassoMiniToolbar extends StatefulWidget {
  static const double iconButtonExtent = 24;
  static const double separatorWidth = yLineThin;
  static const double mainHeight = 32;
  static const double extraMenuWidth = 84;
  static const double extraMenuGap = 6;
  static const double extraMenuItemHeight = 32;
  static const double extraMenuHeight =
      extraMenuItemHeight * 3 + separatorWidth * 2;
  static const double extraMenuTotalWidth = extraMenuWidth + extraMenuGap;

  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final ValueChanged<Color> onColorChange;
  final ValueChanged<double> onWidthChange;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback? onPin;
  final VoidCallback? onCrop;
  final VoidCallback? onRecognizeText;
  final VoidCallback? onSendToYuli;
  final VoidCallback? onSendMathToYuli;
  final List<Color> palette;
  final List<double> widths;
  final Color accent;
  final LassoExtraMenuSide extraMenuSide;

  const LassoMiniToolbar({
    super.key,
    required this.onDelete,
    required this.onDuplicate,
    required this.onColorChange,
    required this.onWidthChange,
    required this.onFlipH,
    required this.onFlipV,
    required this.onCopy,
    required this.onCut,
    this.onPin,
    this.onCrop,
    this.onRecognizeText,
    this.onSendToYuli,
    this.onSendMathToYuli,
    required this.palette,
    this.widths = const [3.0, 6.0, 10.0],
    this.accent = yFlight,
    this.extraMenuSide = LassoExtraMenuSide.right,
  });

  static double mainWidth({
    required bool hasCrop,
    required bool hasPin,
    required bool hasExtraMenu,
  }) {
    final widths = <double>[
      if (hasCrop) _labelButtonWidth('RECORTAR'),
      _labelButtonWidth('BORRAR'),
      _labelButtonWidth('DUPLICAR'),
      if (hasPin) _labelButtonWidth('FIJAR'),
      _labelButtonWidth('COLOR'),
      _labelButtonWidth('GROSOR'),
      _labelButtonWidth('H'),
      _labelButtonWidth('V'),
      _labelButtonWidth('COPIAR'),
      _labelButtonWidth('CORTAR'),
      if (hasExtraMenu) iconButtonExtent,
    ];
    return widths.fold(0.0, (sum, w) => sum + w) +
        (widths.length - 1) * separatorWidth;
  }

  static double _labelButtonWidth(String label) =>
      22 + label.length * 6.0 + (label.length <= 1 ? 0 : 4);

  @override
  State<LassoMiniToolbar> createState() => _LassoMiniToolbarState();
}

class _LassoMiniToolbarState extends State<LassoMiniToolbar> {
  bool _showPalette = false;
  bool _showWidths = false;
  bool _showExtraMenu = false;

  @override
  Widget build(BuildContext context) {
    final hasExtraMenu =
        widget.onRecognizeText != null ||
        widget.onSendToYuli != null ||
        widget.onSendMathToYuli != null;
    final toolbar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showPalette)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
              boxShadow: const [
                BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in widget.palette) ...[
                  GestureDetector(
                    onTap: () {
                      widget.onColorChange(c);
                      setState(() => _showPalette = false);
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: c,
                        border: Border.all(color: yBorderStrong, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_showWidths)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: yCream,
              border: Border.all(color: yBorderStrong, width: yLineMid),
              boxShadow: const [
                BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in widget.widths) ...[
                  GestureDetector(
                    onTap: () {
                      widget.onWidthChange(w);
                      setState(() => _showWidths = false);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: yCream,
                        border: Border.all(color: yBorderStrong, width: 1.5),
                      ),
                      child: Container(
                        width: w * 2,
                        height: w * 2,
                        decoration: BoxDecoration(
                          color: yInk,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: yCream,
            border: Border.all(color: yBorderStrong, width: yLineMid),
            boxShadow: const [
              BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onCrop != null) ...[
                _Btn(
                  icon: YuLiIcons.crop,
                  label: 'RECORTAR',
                  tooltip: 'Recortar',
                  onTap: widget.onCrop!,
                ),
                _sep(),
              ],
              _Btn(
                icon: YuLiIcons.trash,
                label: 'BORRAR',
                tooltip: 'Borrar',
                onTap: widget.onDelete,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.copy,
                label: 'DUPLICAR',
                tooltip: 'Duplicar',
                onTap: widget.onDuplicate,
              ),
              _sep(),
              if (widget.onPin != null) ...[
                _Btn(
                  icon: YuLiIcons.pin,
                  label: 'FIJAR',
                  tooltip: 'Fijar',
                  onTap: widget.onPin!,
                ),
                _sep(),
              ],
              _Btn(
                icon: YuLiIcons.palette,
                label: 'COLOR',
                tooltip: 'Color',
                onTap:
                    () => setState(() {
                      _showPalette = !_showPalette;
                      _showWidths = false;
                      _showExtraMenu = false;
                    }),
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.penLine,
                label: 'GROSOR',
                tooltip: 'Grosor',
                onTap:
                    () => setState(() {
                      _showWidths = !_showWidths;
                      _showPalette = false;
                      _showExtraMenu = false;
                    }),
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.flipHorizontal,
                label: 'H',
                tooltip: 'Voltear horizontal',
                onTap: widget.onFlipH,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.flipVertical,
                label: 'V',
                tooltip: 'Voltear vertical',
                onTap: widget.onFlipV,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.copy,
                label: 'COPIAR',
                tooltip: 'Copiar',
                onTap: widget.onCopy,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.scissors,
                label: 'CORTAR',
                tooltip: 'Cortar',
                onTap: widget.onCut,
              ),
              if (hasExtraMenu) ...[
                _sep(),
                _Btn(
                  icon: YuLiIcons.moreHorizontal,
                  tooltip: 'Más',
                  active: _showExtraMenu,
                  accent: widget.accent,
                  onTap:
                      () => setState(() {
                        _showExtraMenu = !_showExtraMenu;
                        _showPalette = false;
                        _showWidths = false;
                      }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (!hasExtraMenu) return toolbar;
    final sideMenu = _ExtraMenuSlot(
      visible: _showExtraMenu && hasExtraMenu,
      side: widget.extraMenuSide,
      child: _ExtraMenu(
        onRecognizeText: widget.onRecognizeText,
        onSendToYuli: widget.onSendToYuli,
        onSendMathToYuli: widget.onSendMathToYuli,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          widget.extraMenuSide == LassoExtraMenuSide.left
              ? [sideMenu, toolbar]
              : [toolbar, sideMenu],
    );
  }

  Widget _sep() => Container(width: yLineThin, height: 28, color: yInk);
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final Color accent;

  const _Btn({
    required this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.accent = yFlight,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width:
              label == null
                  ? LassoMiniToolbar.iconButtonExtent
                  : LassoMiniToolbar._labelButtonWidth(label!),
          height: LassoMiniToolbar.mainHeight,
          alignment: Alignment.center,
          color: active ? accent : yCream,
          child:
              label == null
                  ? Icon(icon, size: 14, color: active ? yCream : yInk)
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 13, color: active ? yCream : yInk),
                      const SizedBox(width: 3),
                      Text(
                        label!,
                        style: yMono(
                          size: 8,
                          weight: FontWeight.w700,
                          tracking: 0.8,
                          color: active ? yCream : yInk,
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

class _ExtraMenuSlot extends StatelessWidget {
  final bool visible;
  final LassoExtraMenuSide side;
  final Widget child;

  const _ExtraMenuSlot({
    required this.visible,
    required this.side,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final gap =
        side == LassoExtraMenuSide.left
            ? const EdgeInsets.only(right: LassoMiniToolbar.extraMenuGap)
            : const EdgeInsets.only(left: LassoMiniToolbar.extraMenuGap);
    return Padding(
      padding: gap,
      child: SizedBox(
        width: LassoMiniToolbar.extraMenuWidth,
        child: visible ? child : const SizedBox.shrink(),
      ),
    );
  }
}

class _ExtraMenu extends StatelessWidget {
  final VoidCallback? onRecognizeText;
  final VoidCallback? onSendToYuli;
  final VoidCallback? onSendMathToYuli;

  const _ExtraMenu({
    required this.onRecognizeText,
    required this.onSendToYuli,
    required this.onSendMathToYuli,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LassoMiniToolbar.extraMenuWidth,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExtraMenuItem(
            icon: YuLiIcons.type,
            label: 'TEXTO',
            onTap: onRecognizeText,
          ),
          _sep(),
          _ExtraMenuItem(
            icon: YuLiIcons.sparkles,
            label: 'YULI',
            onTap: onSendToYuli,
          ),
          _sep(),
          _ExtraMenuItem(
            icon: YuLiIcons.sigma,
            label: 'MATH',
            onTap: onSendMathToYuli,
          ),
        ],
      ),
    );
  }

  Widget _sep() => Container(height: yLineThin, color: yInk);
}

class _ExtraMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ExtraMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: LassoMiniToolbar.extraMenuWidth,
        height: LassoMiniToolbar.extraMenuItemHeight,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: yInk),
              const SizedBox(width: 5),
              Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.0,
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
