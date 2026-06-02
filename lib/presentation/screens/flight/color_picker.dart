import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/yuli_design.dart';
import 'note_cell_model.dart';

const int kRecentColorsCount = 5;
const int kSavedColorsCount = 5;
const String _kRecentsKey = 'recent_pen_colors_v1';
const String _kSavedKey = 'saved_pen_colors_v1';
const String _kBgSavedKey = 'saved_bg_colors_v1';

/// Base palette shared across pen tools. Adding a folder/space accent is the
/// caller's job (see `buildPenPalette`).
const List<Color> kPenBaseColors = <Color>[
  yInk,
  yFight,
  yFlight,
  yLab,
  yAmber,
  yAmber2,
];

List<Color> buildPenPalette(Color? accent) {
  if (accent == null) return kPenBaseColors;
  return [...kPenBaseColors.sublist(0, 5), accent];
}

/// Hit-test a list of strokes at [pos]; returns the topmost stroke's color
/// whose path passes within [tolerance] + half its strokeWidth of the point.
/// Newer strokes (later in the list) win.
Color? sampleStrokeColorAt(
  List<DrawingStroke> strokes,
  Offset pos, {
  double tolerance = 6.0,
}) {
  for (int i = strokes.length - 1; i >= 0; i--) {
    final s = strokes[i];
    if (s.points.isEmpty) continue;
    final hitR = (s.strokeWidth / 2) + tolerance;
    final hitR2 = hitR * hitR;
    final pts = s.points;
    for (int j = 0; j < pts.length; j++) {
      final p = pts[j];
      if (p.length < 2) continue;
      final dx = p[0] - pos.dx;
      final dy = p[1] - pos.dy;
      if (dx * dx + dy * dy < hitR2) return Color(s.colorValue);
      if (j == 0) continue;
      final q = pts[j - 1];
      if (q.length < 2) continue;
      if (_distanceToSegment2(pos.dx, pos.dy, q[0], q[1], p[0], p[1]) < hitR2) {
        return Color(s.colorValue);
      }
    }
  }
  return null;
}

double _distanceToSegment2(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-6) {
    final ex = px - ax;
    final ey = py - ay;
    return ex * ex + ey * ey;
  }
  final t = ((px - ax) * dx + (py - ay) * dy) / len2;
  final tt = t.clamp(0.0, 1.0);
  final cx = ax + tt * dx;
  final cy = ay + tt * dy;
  final ex = px - cx;
  final ey = py - cy;
  return ex * ex + ey * ey;
}

abstract class _ColorListPrefs {
  static Future<List<Color>> _load(String key, int max) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.whereType<int>().map((v) => Color(v)).take(max).toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> _save(String key, List<Color> colors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(colors.map((c) => c.toARGB32()).toList()),
    );
  }

  static List<Color> _push(List<Color> current, Color color, int max) {
    final v = color.toARGB32();
    final out = <Color>[Color(v)];
    for (final c in current) {
      if (c.toARGB32() == v) continue;
      out.add(c);
      if (out.length >= max) break;
    }
    return out;
  }
}

/// Auto-updated on every pen color change. Most-recent-first, max 5.
class ColorPalettePrefs {
  static Future<List<Color>> load() =>
      _ColorListPrefs._load(_kRecentsKey, kRecentColorsCount);

  static Future<void> save(List<Color> colors) =>
      _ColorListPrefs._save(_kRecentsKey, colors);

  static List<Color> push(List<Color> current, Color color) =>
      _ColorListPrefs._push(current, color, kRecentColorsCount);
}

/// User-curated favorites, opt-in via the star button in the advanced view.
/// Prepend on save, oldest evicted when count > 5.
class SavedColorsPrefs {
  static Future<List<Color>> load() =>
      _ColorListPrefs._load(_kSavedKey, kSavedColorsCount);

  static Future<void> save(List<Color> colors) =>
      _ColorListPrefs._save(_kSavedKey, colors);

  static List<Color> push(List<Color> current, Color color) =>
      _ColorListPrefs._push(current, color, kSavedColorsCount);

  static List<Color> remove(List<Color> current, Color color) {
    final v = color.toARGB32();
    return current.where((c) => c.toARGB32() != v).toList();
  }
}

/// Same as [SavedColorsPrefs] but for background/fondo colors — independent
/// from the pen-tool favorites.
class SavedBgColorsPrefs {
  static Future<List<Color>> load() =>
      _ColorListPrefs._load(_kBgSavedKey, kSavedColorsCount);

  static Future<void> save(List<Color> colors) =>
      _ColorListPrefs._save(_kBgSavedKey, colors);

  static List<Color> push(List<Color> current, Color color) =>
      _ColorListPrefs._push(current, color, kSavedColorsCount);

  static List<Color> remove(List<Color> current, Color color) {
    final v = color.toARGB32();
    return current.where((c) => c.toARGB32() != v).toList();
  }
}

// ─── Toolbar pieces ──────────────────────────────────────────────────────────

class ColorButton extends StatelessWidget {
  final Color currentColor;
  final bool isOpen;
  final VoidCallback onTap;

  const ColorButton({
    super.key,
    required this.currentColor,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(
            color: yBorderStrong,
            width: isOpen ? 2.5 : yLineThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: currentColor,
                border: Border.all(color: yBorderStrong, width: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
              color: yInk,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline strip of starred colors shown beside the [ColorButton].
class SavedColorsStrip extends StatelessWidget {
  final List<Color> savedColors;
  final Color currentColor;
  final void Function(Color) onPick;

  const SavedColorsStrip({
    super.key,
    required this.savedColors,
    required this.currentColor,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final selectedArgb = currentColor.toARGB32();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < savedColors.length; i++) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onPick(savedColors[i]),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: savedColors[i],
                border: Border.all(
                  color:
                      savedColors[i].toARGB32() == selectedArgb ? yCream : yBorderStrong,
                  width:
                      savedColors[i].toARGB32() == selectedArgb ? 3 : yLineThin,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}

// ─── Popup ───────────────────────────────────────────────────────────────────

class ColorPickerPopup extends StatefulWidget {
  final Color currentColor;
  final List<Color> recentColors;
  final List<Color> savedColors;

  /// Optional override for the quick-pick row (and its label). Used by the
  /// background picker to show favorites instead of (pen) recents.
  final List<Color>? quickColors;
  final String quickLabel;
  final void Function(Color) onPreview;
  final void Function(Color) onCommit;
  final void Function(Color) onStar;
  final VoidCallback onEyedropper;
  final VoidCallback onClose;

  const ColorPickerPopup({
    super.key,
    required this.currentColor,
    required this.recentColors,
    required this.savedColors,
    this.quickColors,
    this.quickLabel = 'RECIENTES',
    required this.onPreview,
    required this.onCommit,
    required this.onStar,
    required this.onEyedropper,
    required this.onClose,
  });

  @override
  State<ColorPickerPopup> createState() => _ColorPickerPopupState();
}

class _ColorPickerPopupState extends State<ColorPickerPopup> {
  bool _advanced = false;
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.currentColor);
  }

  void _commitHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onPreview(hsv.toColor());
  }

  void _finalizeHsv() {
    widget.onCommit(_hsv.toColor());
  }

  bool _isStarred() {
    final v = widget.currentColor.toARGB32();
    return widget.savedColors.any((c) => c.toARGB32() == v);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: _advanced ? _buildAdvanced() : _buildCompact(),
    );
  }

  Widget _buildCompact() {
    final selectedArgb = widget.currentColor.toARGB32();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'COLOR',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
            const Spacer(),
            Container(
              width: 32,
              height: 18,
              decoration: BoxDecoration(
                color: widget.currentColor,
                border: Border.all(color: yBorderStrong, width: 1.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          widget.quickLabel,
          style: yMono(
            size: 9,
            weight: FontWeight.w700,
            tracking: 1.4,
            color: yMuted,
          ),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (_) {
            final quick = widget.quickColors ?? widget.recentColors;
            return Row(
              children: [
                for (int i = 0; i < kRecentColorsCount; i++) ...[
                  Expanded(
                    child:
                        i < quick.length
                            ? _SwatchTile(
                              color: quick[i],
                              selected: quick[i].toARGB32() == selectedArgb,
                              onTap: () {
                                widget.onPreview(quick[i]);
                                widget.onCommit(quick[i]);
                              },
                            )
                            : const _EmptySwatch(),
                  ),
                  if (i < kRecentColorsCount - 1) const SizedBox(width: 6),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionBtn(
                icon: Icons.colorize,
                label: 'GOTERO',
                onTap: widget.onEyedropper,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ActionBtn(
                icon: Icons.tune,
                label: 'PERSONALIZADO',
                primary: true,
                onTap: () => setState(() => _advanced = true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvanced() {
    final starred = _isStarred();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _advanced = false),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: yCream,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: const Icon(Icons.arrow_back, size: 14, color: yInk),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'COLOR PERSONALIZADO',
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: yMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onStar(_hsv.toColor()),
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: starred ? yAmber2 : yCream,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: Icon(
                  starred ? Icons.star : Icons.star_border,
                  size: 16,
                  color: yInk,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SVPicker(
                  hsv: _hsv,
                  onChange: _commitHsv,
                  onEnd: _finalizeHsv,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 28,
                child: _HuePicker(
                  hue: _hsv.hue,
                  onChange: (h) => _commitHsv(_hsv.withHue(h)),
                  onEnd: _finalizeHsv,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                border: Border.all(color: yBorderStrong, width: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HexInput(
                color: _hsv.toColor(),
                onCommit: (c) {
                  setState(() => _hsv = HSVColor.fromColor(c));
                  widget.onPreview(c);
                  widget.onCommit(c);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SwatchTile extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchTile({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: selected ? yCream : yBorderStrong,
            width: selected ? 3 : yLineThin,
          ),
        ),
        child:
            selected
                ? Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(color: yBorderStrong, width: 1.5),
                  ),
                )
                : null,
      ),
    );
  }
}

class _EmptySwatch extends StatelessWidget {
  const _EmptySwatch();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(
          color: yMuted.withValues(alpha: 0.5),
          width: yLineThin,
        ),
      ),
      child: Center(
        child: Text(
          '·',
          style: yMono(size: 16, color: yMuted.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? yInk : yCream;
    final fg = primary ? yCream : yInk;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.4,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── HSV controls ────────────────────────────────────────────────────────────

class _SVPicker extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChange;
  final VoidCallback onEnd;

  const _SVPicker({
    required this.hsv,
    required this.onChange,
    required this.onEnd,
  });

  void _update(BuildContext context, Offset localPos, Size size) {
    final s = (localPos.dx / size.width).clamp(0.0, 1.0);
    final v = (1.0 - localPos.dy / size.height).clamp(0.0, 1.0);
    onChange(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _update(context, d.localPosition, size),
          onPanUpdate: (d) => _update(context, d.localPosition, size),
          onPanEnd: (_) => onEnd(),
          onTapDown: (d) => _update(context, d.localPosition, size),
          onTapUp: (_) => onEnd(),
          child: CustomPaint(
            painter: _SVPainter(hue: hsv.hue, s: hsv.saturation, v: hsv.value),
            size: size,
          ),
        );
      },
    );
  }
}

class _SVPainter extends CustomPainter {
  final double hue;
  final double s;
  final double v;
  _SVPainter({required this.hue, required this.s, required this.v});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final base =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.white, hueColor],
          ).createShader(rect);
    canvas.drawRect(rect, base);
    final overlay =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(rect);
    canvas.drawRect(rect, overlay);

    final cx = s * size.width;
    final cy = (1 - v) * size.height;
    final ringOuter =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white;
    final ringInner =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black;
    canvas.drawCircle(Offset(cx, cy), 9, ringOuter);
    canvas.drawCircle(Offset(cx, cy), 9, ringInner);

    final border =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = yInk;
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(_SVPainter old) =>
      old.hue != hue || old.s != s || old.v != v;
}

class _HuePicker extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChange;
  final VoidCallback onEnd;

  const _HuePicker({
    required this.hue,
    required this.onChange,
    required this.onEnd,
  });

  void _update(double localY, double height) {
    final h = (localY / height).clamp(0.0, 1.0) * 360.0;
    onChange(h);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _update(d.localPosition.dy, c.maxHeight),
          onPanUpdate: (d) => _update(d.localPosition.dy, c.maxHeight),
          onPanEnd: (_) => onEnd(),
          onTapDown: (d) => _update(d.localPosition.dy, c.maxHeight),
          onTapUp: (_) => onEnd(),
          child: CustomPaint(
            painter: _HuePainter(hue: hue),
            size: Size(c.maxWidth, c.maxHeight),
          ),
        );
      },
    );
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = <Color>[
      for (int i = 0; i <= 360; i += 60)
        HSVColor.fromAHSV(1, i.toDouble() % 360, 1, 1).toColor(),
    ];
    final p =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(rect);
    canvas.drawRect(rect, p);

    final border =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = yInk;
    canvas.drawRect(rect, border);

    final y = (hue / 360.0) * size.height;
    final marker =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white;
    final markerInner =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black;
    final m = Rect.fromLTWH(-2, y - 4, size.width + 4, 8);
    canvas.drawRect(m, marker);
    canvas.drawRect(m, markerInner);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

class _HexInput extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onCommit;

  const _HexInput({required this.color, required this.onCommit});

  @override
  State<_HexInput> createState() => _HexInputState();
}

class _HexInputState extends State<_HexInput> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _hex(widget.color));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _HexInput old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _hex(old.color) != _hex(widget.color)) {
      _ctrl.text = _hex(widget.color);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _tryCommit();
  }

  String _hex(Color c) {
    final argb = c.toARGB32();
    return (argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
  }

  void _tryCommit() {
    final raw = _ctrl.text.trim().replaceAll('#', '');
    if (raw.length != 6) {
      _ctrl.text = _hex(widget.color);
      return;
    }
    final parsed = int.tryParse(raw, radix: 16);
    if (parsed == null) {
      _ctrl.text = _hex(widget.color);
      return;
    }
    widget.onCommit(Color(0xFF000000 | parsed));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        children: [
          Text(
            '#',
            style: yMono(
              size: 12,
              weight: FontWeight.w700,
              tracking: 0.5,
              color: yMuted,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              cursorColor: yInk,
              cursorWidth: 1.5,
              cursorOpacityAnimates: false,
              showCursor: true,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              ],
              onSubmitted: (_) => _tryCommit(),
              onEditingComplete: _tryCommit,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
              style: yMono(
                size: 12,
                weight: FontWeight.w700,
                tracking: 1.0,
                color: yInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
