import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';
import 'color_picker.dart'
    show SavedColorsPrefs, ColorPickerPopup, kPenBaseColors;
import 'shape_recognizer.dart' show ShapeKind;
import 'stroke_width_picker.dart'
    show StrokeWidthPrefs, kStrokeWidthMin, kStrokeWidthMax;

/// Floating, edge-docked mini-palettes that the user can summon over the
/// canvas as quick-access shortcuts (own colors / widths / favorite shapes /
/// undo-redo). They keep their OWN colors & widths — independent from the main
/// toolbar's per-tool memory — seeded once from the toolbar on first open.
enum FloatingPaletteKind { colors, shapes, widths, undoRedo }

enum PaletteEdge { left, right }

/// Curated favorite shapes for the floating shapes palette (the ones the shape
/// menu also offers, minus arrow duplicates).
const List<ShapeKind> kFloatingShapeFavorites = [
  ShapeKind.line,
  ShapeKind.arrow,
  ShapeKind.rectangle,
  ShapeKind.ellipse,
  ShapeKind.star,
];

const Map<FloatingPaletteKind, PaletteEdge> _defaultEdge = {
  FloatingPaletteKind.colors: PaletteEdge.right,
  FloatingPaletteKind.shapes: PaletteEdge.right,
  FloatingPaletteKind.widths: PaletteEdge.left,
  FloatingPaletteKind.undoRedo: PaletteEdge.left,
};

const Map<FloatingPaletteKind, double> _defaultVFrac = {
  FloatingPaletteKind.colors: 0.06,
  FloatingPaletteKind.shapes: 0.46,
  FloatingPaletteKind.widths: 0.06,
  FloatingPaletteKind.undoRedo: 0.74,
};

// ─── State + persistence ────────────────────────────────────────────────────

class FloatingPalettesController extends ChangeNotifier {
  final Set<FloatingPaletteKind> open;
  final Map<FloatingPaletteKind, PaletteEdge> _edge;
  final Map<FloatingPaletteKind, double> _vFrac;
  List<Color> colors;
  List<double> widths;

  static const int _maxColors = 24;
  static const int _maxWidths = 16;

  FloatingPalettesController._({
    required this.open,
    required Map<FloatingPaletteKind, PaletteEdge> edge,
    required Map<FloatingPaletteKind, double> vFrac,
    required this.colors,
    required this.widths,
  })  : _edge = edge,
        _vFrac = vFrac;

  static const _kOpen = 'fp_open_v1';
  static const _kEdge = 'fp_edge_v1';
  static const _kVFrac = 'fp_vfrac_v1';
  static const _kColors = 'fp_colors_v1';
  static const _kWidths = 'fp_widths_v1';

  PaletteEdge edgeOf(FloatingPaletteKind k) =>
      _edge[k] ?? _defaultEdge[k] ?? PaletteEdge.right;

  double vFracOf(FloatingPaletteKind k) =>
      _vFrac[k] ?? _defaultVFrac[k] ?? 0.1;

  static Future<FloatingPalettesController> load() async {
    final p = await SharedPreferences.getInstance();

    final open = <FloatingPaletteKind>{};
    final rawOpen = p.getString(_kOpen);
    if (rawOpen != null) {
      try {
        for (final n in (jsonDecode(rawOpen) as List)) {
          final k = FloatingPaletteKind.values
              .where((e) => e.name == n)
              .cast<FloatingPaletteKind?>()
              .firstWhere((_) => true, orElse: () => null);
          if (k != null) open.add(k);
        }
      } catch (_) {}
    }

    final edge = <FloatingPaletteKind, PaletteEdge>{};
    final rawEdge = p.getString(_kEdge);
    if (rawEdge != null) {
      try {
        (jsonDecode(rawEdge) as Map).forEach((key, v) {
          final k = FloatingPaletteKind.values
              .where((e) => e.name == key)
              .cast<FloatingPaletteKind?>()
              .firstWhere((_) => true, orElse: () => null);
          if (k != null) {
            edge[k] = v == 'left' ? PaletteEdge.left : PaletteEdge.right;
          }
        });
      } catch (_) {}
    }

    final vFrac = <FloatingPaletteKind, double>{};
    final rawV = p.getString(_kVFrac);
    if (rawV != null) {
      try {
        (jsonDecode(rawV) as Map).forEach((key, v) {
          final k = FloatingPaletteKind.values
              .where((e) => e.name == key)
              .cast<FloatingPaletteKind?>()
              .firstWhere((_) => true, orElse: () => null);
          if (k != null && v is num) {
            vFrac[k] = v.toDouble().clamp(0.0, 1.0);
          }
        });
      } catch (_) {}
    }

    // Colors/widths: own lists. Seeded once from the main toolbar (favorites /
    // recent widths) the first time, then independent.
    List<Color> colors;
    final rawColors = p.getString(_kColors);
    if (rawColors != null) {
      colors = _decodeColors(rawColors);
    } else {
      final seed = await SavedColorsPrefs.load();
      colors = seed.isNotEmpty
          ? seed.take(_maxColors).toList()
          : kPenBaseColors.take(5).toList();
    }

    List<double> widths;
    final rawWidths = p.getString(_kWidths);
    if (rawWidths != null) {
      widths = _decodeWidths(rawWidths);
    } else {
      widths = (await StrokeWidthPrefs.load()).take(_maxWidths).toList();
    }

    return FloatingPalettesController._(
      open: open,
      edge: edge,
      vFrac: vFrac,
      colors: colors,
      widths: widths,
    );
  }

  static List<Color> _decodeColors(String raw) {
    try {
      return (jsonDecode(raw) as List).whereType<int>().map(Color.new).toList();
    } catch (_) {
      return const [];
    }
  }

  static List<double> _decodeWidths(String raw) {
    try {
      return (jsonDecode(raw) as List)
          .whereType<num>()
          .map((n) => n.toDouble().clamp(kStrokeWidthMin, kStrokeWidthMax))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool isOpen(FloatingPaletteKind k) => open.contains(k);

  void toggle(FloatingPaletteKind k) {
    if (!open.remove(k)) open.add(k);
    notifyListeners();
    _persistLayout();
  }

  void close(FloatingPaletteKind k) {
    if (open.remove(k)) {
      notifyListeners();
      _persistLayout();
    }
  }

  void setDock(FloatingPaletteKind k, PaletteEdge edge, double vFrac) {
    _edge[k] = edge;
    _vFrac[k] = vFrac.clamp(0.0, 1.0);
    notifyListeners();
    _persistLayout();
  }

  void addColor(Color c) {
    final v = c.toARGB32();
    colors = [
      Color(v),
      ...colors.where((x) => x.toARGB32() != v),
    ].take(_maxColors).toList();
    notifyListeners();
    _persistColors();
  }

  void removeColor(Color c) {
    final v = c.toARGB32();
    colors = colors.where((x) => x.toARGB32() != v).toList();
    notifyListeners();
    _persistColors();
  }

  void addWidth(double w) {
    final v = w.clamp(kStrokeWidthMin, kStrokeWidthMax);
    widths = [
      v,
      ...widths.where((x) => (x - v).abs() >= 0.25),
    ]..sort();
    if (widths.length > _maxWidths) widths = widths.take(_maxWidths).toList();
    notifyListeners();
    _persistWidths();
  }

  void removeWidth(double w) {
    widths = widths.where((x) => (x - w).abs() >= 0.25).toList();
    notifyListeners();
    _persistWidths();
  }

  Future<void> _persistLayout() async {
    final p = await SharedPreferences.getInstance();
    p.setString(_kOpen, jsonEncode(open.map((e) => e.name).toList()));
    p.setString(
      _kEdge,
      jsonEncode({for (final e in _edge.entries) e.key.name: e.value.name}),
    );
    p.setString(
      _kVFrac,
      jsonEncode({for (final e in _vFrac.entries) e.key.name: e.value}),
    );
  }

  Future<void> _persistColors() async {
    (await SharedPreferences.getInstance()).setString(
      _kColors,
      jsonEncode(colors.map((c) => c.toARGB32()).toList()),
    );
  }

  Future<void> _persistWidths() async {
    (await SharedPreferences.getInstance())
        .setString(_kWidths, jsonEncode(widths));
  }
}

// ─── The floating layer ──────────────────────────────────────────────────────

const double _paletteWidth = 56;
const double _chip = 40;
const double _gap = 6;
const double _gridPad = 6;
const double _gripH = 16;
const double _edgeMargin = 8;

class FloatingPalettesLayer extends StatefulWidget {
  final FloatingPalettesController controller;
  final Color accent;
  final Color activeColor;
  final double activeWidth;
  final ValueChanged<Color> onPickColor;
  final ValueChanged<double> onPickWidth;
  final ValueChanged<ShapeKind> onInsertShape;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;

  /// Starts the editor's eyedropper; the sampled color is added to this
  /// palette's own list (the editor wires that via the controller).
  final VoidCallback? onEyedropper;

  /// When true the palettes slide off toward their docked edge (used while the
  /// eyedropper is active) and slide back in when it clears.
  final bool hidden;

  const FloatingPalettesLayer({
    super.key,
    required this.controller,
    required this.accent,
    required this.activeColor,
    required this.activeWidth,
    required this.onPickColor,
    required this.onPickWidth,
    required this.onInsertShape,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    this.onEyedropper,
    this.hidden = false,
  });

  @override
  State<FloatingPalettesLayer> createState() => _FloatingPalettesLayerState();
}

class _FloatingPalettesLayerState extends State<FloatingPalettesLayer> {
  final GlobalKey _layerKey = GlobalKey();
  Size _avail = Size.zero;

  FloatingPaletteKind? _dragging;
  Offset _dragTopLeft = Offset.zero;
  Offset _grabOffset = Offset.zero;

  FloatingPalettesController get _c => widget.controller;

  Offset _toLocal(Offset global) {
    final box = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  int _itemCount(FloatingPaletteKind k) {
    switch (k) {
      case FloatingPaletteKind.colors:
        return _c.colors.length + 1; // + config chip
      case FloatingPaletteKind.widths:
        return _c.widths.length + 1;
      case FloatingPaletteKind.shapes:
        return kFloatingShapeFavorites.length;
      case FloatingPaletteKind.undoRedo:
        return 2;
    }
  }

  static const int _maxVisibleChips = 8;

  double _itemsHeight(FloatingPaletteKind k) {
    final n = _itemCount(k);
    return n * _chip + (n > 0 ? (n - 1) * _gap : 0);
  }

  /// Items scroll past this — keeps a long palette on screen (the whole point of
  /// raising the color/width limits) instead of running off the bottom edge.
  double _maxItemsHeight() {
    final byChips = _maxVisibleChips * _chip + (_maxVisibleChips - 1) * _gap;
    final byScreen = _avail.height * 0.62;
    if (byScreen <= 0) return byChips;
    return byChips < byScreen ? byChips : byScreen;
  }

  double _cappedItems(FloatingPaletteKind k) {
    final ih = _itemsHeight(k);
    final mx = _maxItemsHeight();
    return ih < mx ? ih : mx;
  }

  double _estHeight(FloatingPaletteKind k) =>
      _gridPad * 2 + _gripH + _gap + _cappedItems(k);

  Offset _dockTopLeft(FloatingPaletteKind k, double hEst) {
    final edge = _c.edgeOf(k);
    final x = edge == PaletteEdge.left
        ? _edgeMargin
        : _avail.width - _paletteWidth - _edgeMargin;
    final maxTop = (_avail.height - hEst - _edgeMargin).clamp(_edgeMargin, double.infinity);
    final top = (_c.vFracOf(k) * (maxTop - _edgeMargin) + _edgeMargin)
        .clamp(_edgeMargin, maxTop);
    return Offset(x, top);
  }

  void _onDragStart(FloatingPaletteKind k, LongPressStartDetails d, Offset dockTL) {
    final local = _toLocal(d.globalPosition);
    setState(() {
      _dragging = k;
      _grabOffset = local - dockTL;
      _dragTopLeft = dockTL;
    });
    HapticFeedback.selectionClick();
  }

  void _onDragMove(LongPressMoveUpdateDetails d) {
    setState(() => _dragTopLeft = _toLocal(d.globalPosition) - _grabOffset);
  }

  void _onDragEnd(FloatingPaletteKind k, double hEst) {
    final centerX = _dragTopLeft.dx + _paletteWidth / 2;
    final edge = centerX < _avail.width / 2 ? PaletteEdge.left : PaletteEdge.right;
    final maxTop = (_avail.height - hEst - _edgeMargin).clamp(_edgeMargin, double.infinity);
    final span = (maxTop - _edgeMargin).clamp(1.0, double.infinity);
    final vFrac = ((_dragTopLeft.dy - _edgeMargin) / span).clamp(0.0, 1.0);
    _c.setDock(k, edge, vFrac);
    setState(() => _dragging = null);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: _layerKey,
      builder: (context, constraints) {
        _avail = Size(constraints.maxWidth, constraints.maxHeight);
        return IgnorePointer(
          ignoring: widget.hidden,
          // Own compositor layer: a palette drag (setState here) repaints inside
          // this boundary only — never bubbling to the shared overlay (pins,
          // cursors) or forcing the canvas to recomposite. Pin-parity.
          child: RepaintBoundary(
            child: Stack(
              children: [
                if (_dragging != null && !widget.hidden) ..._magnetHints(),
                for (final k in FloatingPaletteKind.values)
                  _buildDockedPalette(k),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _magnetHints() {
    final centerX = _dragTopLeft.dx + _paletteWidth / 2;
    final targetLeft = centerX < _avail.width / 2;
    Widget bar(bool left) => Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              width: _paletteWidth + _edgeMargin * 2,
              color: widget.accent.withValues(
                alpha: (left == targetLeft) ? 0.16 : 0.04,
              ),
            ),
          ),
        );
    return [bar(true), bar(false)];
  }

  Widget _buildDockedPalette(FloatingPaletteKind k) {
    final hEst = _estHeight(k);
    final isDrag = _dragging == k;
    final docked = _dockTopLeft(k, hEst);
    final isOpen = _c.isOpen(k);
    Offset tl;
    if (isDrag) {
      tl = _dragTopLeft;
    } else if (widget.hidden || !isOpen) {
      final offX = _c.edgeOf(k) == PaletteEdge.left
          ? -(_paletteWidth + 24)
          : _avail.width + 24;
      tl = Offset(offX, docked.dy);
    } else {
      tl = docked;
    }
    return AnimatedPositioned(
      key: ValueKey(k),
      duration: isDrag ? Duration.zero : const Duration(milliseconds: 260),
      curve: widget.hidden || !isOpen
          ? Curves.easeInCubic
          : Curves.easeOutBack,
      left: tl.dx,
      top: tl.dy,
      child: IgnorePointer(
        ignoring: !isOpen || widget.hidden,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onLongPressStart: (d) => _onDragStart(k, d, _dockTopLeft(k, hEst)),
          onLongPressMoveUpdate: _onDragMove,
          onLongPressEnd: (_) => _onDragEnd(k, hEst),
          child: AnimatedScale(
            scale: isDrag ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: _PaletteCard(
              kind: k,
              dragging: isDrag,
              maxItemsHeight: _cappedItems(k),
              controller: _c,
              accent: widget.accent,
              activeColor: widget.activeColor,
              activeWidth: widget.activeWidth,
              onPickColor: widget.onPickColor,
              onPickWidth: widget.onPickWidth,
              onInsertShape: widget.onInsertShape,
              onUndo: widget.onUndo,
              onRedo: widget.onRedo,
              canUndo: widget.canUndo,
              canRedo: widget.canRedo,
              onEyedropper: widget.onEyedropper,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── A single palette card ───────────────────────────────────────────────────

class _PaletteCard extends StatelessWidget {
  final FloatingPaletteKind kind;
  final bool dragging;
  final double maxItemsHeight;
  final FloatingPalettesController controller;
  final Color accent;
  final Color activeColor;
  final double activeWidth;
  final ValueChanged<Color> onPickColor;
  final ValueChanged<double> onPickWidth;
  final ValueChanged<ShapeKind> onInsertShape;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onEyedropper;

  const _PaletteCard({
    required this.kind,
    required this.dragging,
    required this.maxItemsHeight,
    required this.controller,
    required this.accent,
    required this.activeColor,
    required this.activeWidth,
    required this.onPickColor,
    required this.onPickWidth,
    required this.onInsertShape,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    this.onEyedropper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _paletteWidth,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(
          color: yBorderStrong,
          width: dragging ? yLineMid : yLineThin,
        ),
        boxShadow: [
          BoxShadow(
            color: yBorderStrong,
            offset: dragging ? const Offset(4, 4) : const Offset(2, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(_gridPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grip(context),
          const SizedBox(height: _gap),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxItemsHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _items(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grip(BuildContext context) {
    return SizedBox(
      height: _gripH,
      child: Row(
        children: [
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.close(kind),
            child: Icon(YuLiIcons.close, size: 14, color: yMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _items(BuildContext context) {
    switch (kind) {
      case FloatingPaletteKind.colors:
        return _colorItems(context);
      case FloatingPaletteKind.widths:
        return _widthItems(context);
      case FloatingPaletteKind.shapes:
        return _shapeItems();
      case FloatingPaletteKind.undoRedo:
        return _undoRedoItems();
    }
  }

  List<Widget> _spaced(List<Widget> items) {
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i < items.length - 1) out.add(const SizedBox(height: _gap));
    }
    return out;
  }

  List<Widget> _colorItems(BuildContext context) {
    final sel = activeColor.toARGB32();
    final items = <Widget>[
      for (final c in controller.colors)
        _chipBox(
          selected: c.toARGB32() == sel,
          onTap: () => onPickColor(c),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c,
              border: Border.all(color: yBorderStrong, width: 1.2),
            ),
          ),
        ),
      _chipBox(
        selected: false,
        onTap: () => _openColorsConfig(context),
        child: Icon(YuLiIcons.plus, size: 16, color: yInk),
      ),
    ];
    return _spaced(items);
  }

  List<Widget> _widthItems(BuildContext context) {
    final items = <Widget>[
      for (final w in controller.widths)
        _chipBox(
          selected: (w - activeWidth).abs() < 0.25,
          onTap: () => onPickWidth(w),
          child: Center(
            child: Container(
              width: w.clamp(2.0, 22.0),
              height: w.clamp(2.0, 22.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (w - activeWidth).abs() < 0.25 ? yCream : yInk,
              ),
            ),
          ),
        ),
      _chipBox(
        selected: false,
        onTap: () => _openWidthsConfig(context),
        child: Icon(YuLiIcons.plus, size: 16, color: yInk),
      ),
    ];
    return _spaced(items);
  }

  List<Widget> _shapeItems() {
    return _spaced([
      for (final s in kFloatingShapeFavorites)
        _chipBox(
          selected: false,
          onTap: () => onInsertShape(s),
          child: Icon(_shapeIcon(s), size: 18, color: yInk),
        ),
    ]);
  }

  List<Widget> _undoRedoItems() {
    return _spaced([
      _chipBox(
        selected: false,
        enabled: canUndo,
        onTap: onUndo,
        child: Icon(YuLiIcons.undo, size: 17,
            color: canUndo ? yInk : yMuted.withValues(alpha: 0.4)),
      ),
      _chipBox(
        selected: false,
        enabled: canRedo,
        onTap: onRedo,
        child: Icon(YuLiIcons.redo, size: 17,
            color: canRedo ? yInk : yMuted.withValues(alpha: 0.4)),
      ),
    ]);
  }

  Widget _chipBox({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    bool enabled = true,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: _chip,
        height: _chip,
        decoration: BoxDecoration(
          color: selected ? accent : yCream,
          border: Border.all(
            color: yBorderStrong,
            width: selected ? 2.5 : yLineThin,
          ),
        ),
        child: child,
      ),
    );
  }

  IconData _shapeIcon(ShapeKind s) {
    switch (s) {
      case ShapeKind.rectangle:
        return YuLiIcons.square;
      case ShapeKind.ellipse:
      case ShapeKind.circle:
        return YuLiIcons.circle;
      case ShapeKind.triangle:
        return YuLiIcons.triangle;
      case ShapeKind.star:
      case ShapeKind.pentagram:
        return YuLiIcons.star;
      case ShapeKind.line:
        return YuLiIcons.minus;
      case ShapeKind.arrow:
        return YuLiIcons.arrowRight;
    }
  }

  void _openColorsConfig(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColorsConfigSheet(
        controller: controller,
        accent: accent,
        activeColor: activeColor,
        onEyedropper: onEyedropper,
      ),
    );
  }

  void _openWidthsConfig(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WidthsConfigSheet(
        controller: controller,
        accent: accent,
        activeWidth: activeWidth,
      ),
    );
  }
}

// ─── Config sheets (manage each palette's own list) ──────────────────────────

class _ColorsConfigSheet extends StatefulWidget {
  final FloatingPalettesController controller;
  final Color accent;
  final Color activeColor;
  final VoidCallback? onEyedropper;

  const _ColorsConfigSheet({
    required this.controller,
    required this.accent,
    required this.activeColor,
    this.onEyedropper,
  });

  @override
  State<_ColorsConfigSheet> createState() => _ColorsConfigSheetState();
}

class _ColorsConfigSheetState extends State<_ColorsConfigSheet> {
  Future<void> _openPicker(BuildContext context) async {
    final wantEyedropper = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PalettePickerSheet(
        controller: widget.controller,
        accent: widget.accent,
        initial: widget.activeColor,
        onAdded: () => setState(() {}),
      ),
    );
    if (wantEyedropper == true && mounted) _startEyedropper();
  }

  void _startEyedropper() {
    // Close this config sheet, then hand off to the editor's loupe.
    Navigator.of(context).pop();
    widget.onEyedropper?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return _sheetShell(
      title: 'PALETA DE COLORES',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _sheetAction(
                  icon: YuLiIcons.plus,
                  label: 'COLOR ACTUAL',
                  primary: true,
                  accent: widget.accent,
                  onTap: () => setState(() => c.addColor(widget.activeColor)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sheetAction(
                  icon: YuLiIcons.slidersHorizontal,
                  label: 'ELEGIR…',
                  accent: widget.accent,
                  onTap: () => _openPicker(context),
                ),
              ),
            ],
          ),
          if (widget.onEyedropper != null) ...[
            const SizedBox(height: 8),
            _sheetAction(
              icon: YuLiIcons.palette,
              label: 'GOTERO (TOMAR DEL LIENZO)',
              accent: widget.accent,
              onTap: _startEyedropper,
            ),
          ],
          const SizedBox(height: 12),
          Text('TOCA PARA QUITAR',
              style: yMono(size: 9, weight: FontWeight.w700, tracking: 1.4, color: yMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final col in c.colors)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => c.removeColor(col)),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: col,
                      border: Border.all(color: yBorderStrong, width: yLineThin),
                    ),
                    child: Icon(YuLiIcons.close, size: 15, color: yCream),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PalettePickerSheet extends StatefulWidget {
  final FloatingPalettesController controller;
  final Color accent;
  final Color initial;
  final VoidCallback onAdded;

  const _PalettePickerSheet({
    required this.controller,
    required this.accent,
    required this.initial,
    required this.onAdded,
  });

  @override
  State<_PalettePickerSheet> createState() => _PalettePickerSheetState();
}

class _PalettePickerSheetState extends State<_PalettePickerSheet> {
  late Color _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  void _add() {
    widget.controller.addColor(_current);
    widget.onAdded();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPickerPopup(
                currentColor: _current,
                recentColors: widget.controller.colors,
                savedColors: const [],
                quickColors: widget.controller.colors,
                quickLabel: 'EN LA PALETA',
                onPreview: (c) => setState(() => _current = c),
                onCommit: (c) => setState(() => _current = c),
                onStar: (c) {
                  widget.controller.addColor(c);
                  widget.onAdded();
                },
                onEyedropper: () => Navigator.of(context).pop(true),
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 320,
                child: _sheetAction(
                  icon: YuLiIcons.plus,
                  label: 'AGREGAR A LA PALETA',
                  primary: true,
                  accent: widget.accent,
                  onTap: _add,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidthsConfigSheet extends StatefulWidget {
  final FloatingPalettesController controller;
  final Color accent;
  final double activeWidth;

  const _WidthsConfigSheet({
    required this.controller,
    required this.accent,
    required this.activeWidth,
  });

  @override
  State<_WidthsConfigSheet> createState() => _WidthsConfigSheetState();
}

class _WidthsConfigSheetState extends State<_WidthsConfigSheet> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.activeWidth.clamp(kStrokeWidthMin, kStrokeWidthMax);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return _sheetShell(
      title: 'GROSORES RÁPIDOS',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: _value.clamp(4.0, 30.0),
                height: _value.clamp(4.0, 30.0),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: yInk),
              ),
              const SizedBox(width: 12),
              Text('${_value.toStringAsFixed(_value < 10 ? 1 : 0)} PX',
                  style: yMono(size: 12, weight: FontWeight.w700, tracking: 1.2, color: yInk)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: yInk,
              inactiveTrackColor: yInk.withValues(alpha: 0.2),
              thumbColor: widget.accent,
              overlayColor: widget.accent.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              trackShape: const RectangularSliderTrackShape(),
            ),
            child: Slider(
              value: _value,
              min: kStrokeWidthMin,
              max: kStrokeWidthMax,
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          _sheetAction(
            icon: YuLiIcons.plus,
            label: 'AGREGAR GROSOR',
            primary: true,
            accent: widget.accent,
            onTap: () => setState(() => c.addWidth(_value)),
          ),
          const SizedBox(height: 12),
          Text('TOCA PARA QUITAR',
              style: yMono(size: 9, weight: FontWeight.w700, tracking: 1.4, color: yMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in c.widths)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => c.removeWidth(w)),
                  child: Container(
                    width: 48,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: yCream,
                      border: Border.all(color: yBorderStrong, width: yLineThin),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: w.clamp(2.0, 18.0),
                          height: w.clamp(2.0, 18.0),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: yInk),
                        ),
                        const SizedBox(height: 3),
                        Text(w.toStringAsFixed(w < 10 ? 1 : 0),
                            style: yMono(size: 8, weight: FontWeight.w700, color: yMuted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _sheetShell({required String title, required Widget child}) {
  return SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(3, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: yMono(size: 11, weight: FontWeight.w700, tracking: 1.6, color: yMuted)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

Widget _sheetAction({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  required Color accent,
  bool primary = false,
}) {
  final fg = primary ? yCream : yInk;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary ? accent : yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 8),
          Text(label,
              style: yMono(
                  size: 10, weight: FontWeight.w700, tracking: 1.4, color: fg)),
        ],
      ),
    ),
  );
}
