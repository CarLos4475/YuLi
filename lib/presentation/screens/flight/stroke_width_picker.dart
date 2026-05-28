import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/yuli_design.dart';

const double kStrokeWidthMin = 0.5;
const double kStrokeWidthMax = 40.0;
const double kStrokeWidthDefault = 3.0;
const int kRecentStrokeWidthsCount = 3;
const String _kPrefsKey = 'recent_stroke_widths_v1';

class StrokeWidthPrefs {
  static Future<List<double>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return const [3.0, 6.0, 10.0];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<num>()
            .map((n) => n.toDouble().clamp(kStrokeWidthMin, kStrokeWidthMax))
            .take(kRecentStrokeWidthsCount)
            .toList();
      }
    } catch (_) {}
    return const [3.0, 6.0, 10.0];
  }

  static Future<void> save(List<double> widths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(widths));
  }

  /// Push [value] to the front, dedupe within 0.25px tolerance, keep ≤N.
  static List<double> push(List<double> current, double value) {
    final v = value.clamp(kStrokeWidthMin, kStrokeWidthMax);
    final out = <double>[v];
    for (final w in current) {
      if ((w - v).abs() < 0.25) continue;
      out.add(w);
      if (out.length >= kRecentStrokeWidthsCount) break;
    }
    return out;
  }
}

class StrokeWidthButton extends StatelessWidget {
  final double currentWidth;
  final bool isOpen;
  final Color accentColor;
  final VoidCallback onTap;

  const StrokeWidthButton({
    super.key,
    required this.currentWidth,
    required this.isOpen,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dotSize = currentWidth.clamp(2.0, 18.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isOpen ? accentColor : yCream,
          border: Border.all(color: yInk, width: isOpen ? 2.5 : yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOpen ? yCream : yInk,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              currentWidth.toStringAsFixed(currentWidth < 10 ? 1 : 0),
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: isOpen ? yCream : yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StrokeWidthPopup extends StatefulWidget {
  final double currentWidth;
  final List<double> recentWidths;
  final Color accentColor;
  final void Function(double) onPreview;
  final void Function(double) onCommit;
  final VoidCallback onClose;

  const StrokeWidthPopup({
    super.key,
    required this.currentWidth,
    required this.recentWidths,
    required this.accentColor,
    required this.onPreview,
    required this.onCommit,
    required this.onClose,
  });

  @override
  State<StrokeWidthPopup> createState() => _StrokeWidthPopupState();
}

class _StrokeWidthPopupState extends State<StrokeWidthPopup> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.currentWidth.clamp(kStrokeWidthMin, kStrokeWidthMax);
  }

  @override
  Widget build(BuildContext context) {
    final previewDot =
        (_value * 1.0).clamp(2.0, 56.0); // visible preview, max 56px

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
        boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('GROSOR',
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  )),
              const Spacer(),
              Text(_value.toStringAsFixed(_value < 10 ? 1 : 0),
                  style: yMono(
                    size: 12,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: yInk,
                  )),
              Text(' PX',
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              border: Border.all(color: yInk, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Container(
              width: previewDot,
              height: previewDot,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: yInk,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: yInk,
              inactiveTrackColor: yInk.withValues(alpha: 0.2),
              thumbColor: widget.accentColor,
              overlayColor: widget.accentColor.withValues(alpha: 0.2),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 9),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: _value,
              min: kStrokeWidthMin,
              max: kStrokeWidthMax,
              onChanged: (v) {
                setState(() => _value = v);
                widget.onPreview(v);
              },
              onChangeEnd: (v) {
                widget.onCommit(v);
              },
            ),
          ),
          const SizedBox(height: 8),
          if (widget.recentWidths.isNotEmpty) ...[
            Text('RECIENTES',
                style: yMono(
                  size: 9,
                  weight: FontWeight.w700,
                  tracking: 1.4,
                  color: yMuted,
                )),
            const SizedBox(height: 6),
            Row(
              children: [
                for (int i = 0; i < widget.recentWidths.length; i++) ...[
                  _RecentChip(
                    width: widget.recentWidths[i],
                    selected: (widget.recentWidths[i] - _value).abs() < 0.25,
                    accentColor: widget.accentColor,
                    onTap: () {
                      setState(() => _value = widget.recentWidths[i]);
                      widget.onPreview(widget.recentWidths[i]);
                      widget.onCommit(widget.recentWidths[i]);
                    },
                  ),
                  if (i < widget.recentWidths.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  final double width;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _RecentChip({
    required this.width,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dot = width.clamp(2.0, 22.0);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accentColor : yCream,
            border: Border.all(
              color: yInk,
              width: selected ? 2.5 : yLineThin,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? yCream : yInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                width.toStringAsFixed(width < 10 ? 1 : 0),
                style: yMono(
                  size: 8,
                  weight: FontWeight.w700,
                  tracking: 1.0,
                  color: selected ? yCream : yMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
