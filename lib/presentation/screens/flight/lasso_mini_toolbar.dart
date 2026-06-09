import 'package:flutter/material.dart';
import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

class LassoMiniToolbar extends StatefulWidget {
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final ValueChanged<Color> onColorChange;
  final ValueChanged<double> onWidthChange;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback? onCrop; // only when a single image is selected
  final VoidCallback? onRecognizeText; // only when selection has handwriting
  final VoidCallback? onSendToYuli; // only when selection can become AI context
  final VoidCallback? onSendMathToYuli;
  final List<Color> palette;
  final List<double> widths;

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
    this.onCrop,
    this.onRecognizeText,
    this.onSendToYuli,
    this.onSendMathToYuli,
    required this.palette,
    this.widths = const [3.0, 6.0, 10.0],
  });

  @override
  State<LassoMiniToolbar> createState() => _LassoMiniToolbarState();
}

class _LassoMiniToolbarState extends State<LassoMiniToolbar> {
  bool _showPalette = false;
  bool _showWidths = false;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              if (widget.onRecognizeText != null) ...[
                _Btn(
                  icon: YuLiIcons.type,
                  label: 'TEXTO',
                  onTap: widget.onRecognizeText!,
                ),
                _sep(),
              ],
              if (widget.onSendToYuli != null) ...[
                _Btn(
                  icon: YuLiIcons.sparkles,
                  label: 'YULI',
                  onTap: widget.onSendToYuli!,
                ),
                _sep(),
              ],
              if (widget.onSendMathToYuli != null) ...[
                _Btn(
                  icon: YuLiIcons.sigma,
                  label: 'MATH',
                  onTap: widget.onSendMathToYuli!,
                ),
                _sep(),
              ],
              if (widget.onCrop != null) ...[
                _Btn(
                  icon: YuLiIcons.crop,
                  label: 'RECORTAR',
                  onTap: widget.onCrop!,
                ),
                _sep(),
              ],
              _Btn(
                icon: YuLiIcons.trash,
                label: 'BORRAR',
                onTap: widget.onDelete,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.copy,
                label: 'DUPLICAR',
                onTap: widget.onDuplicate,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.palette,
                label: 'COLOR',
                onTap:
                    () => setState(() {
                      _showPalette = !_showPalette;
                      _showWidths = false;
                    }),
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.penLine,
                label: 'GROSOR',
                onTap:
                    () => setState(() {
                      _showWidths = !_showWidths;
                      _showPalette = false;
                    }),
              ),
              _sep(),
              _Btn(icon: YuLiIcons.flipHorizontal, label: 'H', onTap: widget.onFlipH),
              _sep(),
              _Btn(
                icon: YuLiIcons.flipVertical,
                label: 'V',
                onTap: widget.onFlipV,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.copy,
                label: 'COPIAR',
                onTap: widget.onCopy,
              ),
              _sep(),
              _Btn(
                icon: YuLiIcons.scissors,
                label: 'CORTAR',
                onTap: widget.onCut,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sep() => Container(width: yLineThin, height: 28, color: yInk);
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Btn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: yInk),
            const SizedBox(width: 4),
            Text(
              label,
              style: yMono(
                size: 9,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
