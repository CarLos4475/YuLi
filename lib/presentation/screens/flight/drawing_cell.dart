import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import 'note_cell_model.dart';

const _baseColors = <Color>[
  yInk,
  yFight,
  yFlight,
  yLab,
  yAmber,
  yAmber2,
];

const _widths = [3.0, 6.0, 10.0];

class DrawingCell extends StatefulWidget {
  final DrawingData data;
  final ValueChanged<DrawingData> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDrawStart;
  final VoidCallback onDrawEnd;
  final ValueChanged<bool> onScrollLockChanged;
  final Color? accent;
  final Widget? header;

  const DrawingCell({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
    required this.onDrawStart,
    required this.onDrawEnd,
    required this.onScrollLockChanged,
    this.accent,
    this.header,
  });

  @override
  State<DrawingCell> createState() => _DrawingCellState();
}

class _DrawingCellState extends State<DrawingCell> {
  late DrawingData _data;
  late List<Color> _palette;
  Color _color = yInk;
  double _strokeW = 3.0;
  bool _erasing = false;
  bool _locked = false;
  bool _palmRejection = true;
  final List<DrawingStroke> _undoStack = [];
  DrawingStroke? _active;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
    _palette = _buildPalette();
  }

  @override
  void didUpdateWidget(covariant DrawingCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accent != widget.accent) {
      setState(() => _palette = _buildPalette());
    }
  }

  List<Color> _buildPalette() {
    if (widget.accent == null) return _baseColors;
    return [..._baseColors.sublist(0, 5), widget.accent!];
  }

  bool _shouldAcceptPointer(PointerDeviceKind kind) {
    if (!_palmRejection) return true;
    return kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  void _start(Offset pos) {
    widget.onDrawStart();
    if (_erasing) {
      _eraseNear(pos);
      return;
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        points: [
          [pos.dx, pos.dy]
        ],
      );
    });
  }

  void _move(Offset pos) {
    if (_erasing) {
      _eraseNear(pos);
      return;
    }
    if (_active == null) return;
    setState(() {
      _active!.points.add([pos.dx, pos.dy]);
    });
  }

  void _end() {
    widget.onDrawEnd();
    if (_active == null) return;
    _active!.points.removeWhere(
        (p) => p.length < 2 || !p[0].isFinite || !p[1].isFinite);
    if (_active!.points.isEmpty) {
      _active = null;
      return;
    }
    setState(() {
      _data.strokes.add(_active!);
      _active = null;
      _undoStack.clear();
    });
    widget.onChanged(_data);
  }

  void _eraseNear(Offset pos) {
    const r2 = 20.0 * 20.0;
    final before = _data.strokes.length;
    _data.strokes.removeWhere((s) {
      for (final p in s.points) {
        final dx = p[0] - pos.dx;
        final dy = p[1] - pos.dy;
        if (dx * dx + dy * dy < r2) return true;
      }
      return false;
    });
    if (_data.strokes.length != before) {
      setState(() {});
      widget.onChanged(_data);
    }
  }

  void _undo() {
    if (_data.strokes.isEmpty) return;
    setState(() => _undoStack.add(_data.strokes.removeLast()));
    widget.onChanged(_data);
  }

  void _redo() {
    if (_undoStack.isEmpty) return;
    setState(() => _data.strokes.add(_undoStack.removeLast()));
    widget.onChanged(_data);
  }

  void _clearAll() {
    if (_data.strokes.isEmpty && _undoStack.isEmpty) return;
    setState(() {
      _undoStack.addAll(_data.strokes);
      _data.strokes.clear();
    });
    widget.onChanged(_data);
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    widget.onScrollLockChanged(_locked);
  }

  void _togglePalmRejection() {
    setState(() => _palmRejection = !_palmRejection);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yInk, width: yLineMid),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          _buildToolbar(),
          _buildCanvas(),
          _buildResizeStrip(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(bottom: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolBtn(
              icon: _locked ? Icons.lock : Icons.lock_open,
              active: _locked,
              onTap: _toggleLock,
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.edit_outlined,
              active: !_erasing,
              onTap: () => setState(() => _erasing = false),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.auto_fix_high,
              active: _erasing,
              onTap: () => setState(() => _erasing = true),
            ),
            _divider(),
            for (final c in _palette) ...[
              _colorBtn(c),
              const SizedBox(width: 4),
            ],
            _divider(),
            for (final w in _widths) ...[
              _widthBtn(w),
              const SizedBox(width: 4),
            ],
            _divider(),
            _toolBtn(
              icon: Icons.undo,
              active: false,
              enabled: _data.strokes.isNotEmpty,
              onTap: _undo,
            ),
            const SizedBox(width: 4),
            _toolBtn(
              icon: Icons.redo,
              active: false,
              enabled: _undoStack.isNotEmpty,
              onTap: _redo,
            ),
            _divider(),
            _toolBtn(
              icon: Icons.back_hand_outlined,
              active: _palmRejection,
              label: 'PALMA',
              onTap: _togglePalmRejection,
            ),
            const SizedBox(width: 8),
            _toolBtn(
              icon: Icons.delete_outline,
              active: false,
              onTap: _confirmClear,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    if (_data.strokes.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yCream,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('Borrar dibujo',
            style: ySans(size: 18, weight: FontWeight.w700)),
        content: Text('¿Borrar todos los trazos del bloque?',
            style: yBody(size: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) _clearAll();
  }

  Widget _buildCanvas() {
    final canvas = Container(
      height: _data.height,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: yCream,
      ),
      child: ClipRect(
        child: Stack(
          children: [
            CustomPaint(
              painter: _StrokePainter(
                strokes: _data.strokes,
                active: _active,
              ),
              size: Size.infinite,
            ),
            if (!_locked)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'BLOQUEAR SCROLL PARA DIBUJAR',
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yMuted.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!_locked) return canvas;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (!_shouldAcceptPointer(e.kind)) return;
        _start(e.localPosition);
      },
      onPointerMove: (e) {
        if (!_shouldAcceptPointer(e.kind)) return;
        if (_active == null && !_erasing) return;
        _move(e.localPosition);
      },
      onPointerUp: (e) {
        if (!_shouldAcceptPointer(e.kind)) return;
        _end();
      },
      onPointerCancel: (e) {
        if (!_shouldAcceptPointer(e.kind)) return;
        _end();
      },
      child: canvas,
    );
  }

  Widget _buildResizeStrip() {
    return Container(
      decoration: const BoxDecoration(
        color: yCream2,
        border: Border(top: BorderSide(color: yInk, width: yLineThin)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _resizeBtn(Icons.remove, () => _resize(-60)),
          const SizedBox(width: 6),
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                final prev = _data.height;
                _data.height =
                    (_data.height + d.delta.dy).clamp(120.0, 1200.0);
                if (_data.height < prev) _cropStrokes();
              });
              widget.onChanged(_data);
            },
            child: Container(
              width: 36,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: yCream,
                border: Border.all(color: yInk, width: yLineThin),
              ),
              child: const Icon(Icons.swap_vert, size: 14, color: yInk),
            ),
          ),
          const SizedBox(width: 6),
          _resizeBtn(Icons.add, () => _resize(60)),
        ],
      ),
    );
  }

  Widget _resizeBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineThin),
        ),
        child: Icon(icon, size: 14, color: yInk),
      ),
    );
  }

  void _resize(double delta) {
    setState(() {
      final prev = _data.height;
      _data.height = (_data.height + delta).clamp(120.0, 1200.0);
      if (_data.height < prev) _cropStrokes();
    });
    widget.onChanged(_data);
  }

  void _cropStrokes() {
    final h = _data.height;
    final toRemove = <DrawingStroke>[];
    for (final s in _data.strokes) {
      _cropPointsInPlace(s.points, h);
      if (s.points.isEmpty) toRemove.add(s);
    }
    for (final s in toRemove) {
      _data.strokes.remove(s);
    }
    if (_active != null) {
      _cropPointsInPlace(_active!.points, h);
      if (_active!.points.isEmpty) _active = null;
    }
  }

  void _cropPointsInPlace(List<List<double>> points, double h) {
    if (points.isEmpty) return;
    final result = <List<double>>[];
    bool prevInside = points[0][1] <= h;
    if (prevInside) result.add(points[0]);
    for (int i = 1; i < points.length; i++) {
      final currInside = points[i][1] <= h;
      if (prevInside && !currInside) {
        final prev = points[i - 1];
        final curr = points[i];
        final dy = curr[1] - prev[1];
        if (dy.abs() > 0.001) {
          final t = (h - prev[1]) / dy;
          result.add([prev[0] + t * (curr[0] - prev[0]), h]);
        }
      } else if (!prevInside && currInside) {
        final prev = points[i - 1];
        final curr = points[i];
        final dy = curr[1] - prev[1];
        if (dy.abs() > 0.001) {
          final t = (h - prev[1]) / dy;
          result.add([prev[0] + t * (curr[0] - prev[0]), h]);
        }
        result.add(points[i]);
      } else if (currInside) {
        result.add(points[i]);
      }
      prevInside = currInside;
    }
    points
      ..clear()
      ..addAll(result);
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: yInk.withValues(alpha: 0.2),
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required bool active,
    bool enabled = true,
    String? label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: label != null ? 8 : 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? yInk : yCream,
          border: Border.all(
            color: enabled ? yInk : yMuted.withValues(alpha: 0.4),
            width: yLineThin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active
                  ? yCream
                  : enabled
                      ? yInk
                      : yMuted.withValues(alpha: 0.4),
            ),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w700,
                    tracking: 1.2,
                    color: active ? yCream : yInk,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _colorBtn(Color c) {
    final sel = _color.toARGB32() == c.toARGB32() && !_erasing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _color = c;
        _erasing = false;
      }),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c,
          border: Border.all(
            color: yInk,
            width: sel ? 3 : yLineThin,
          ),
        ),
      ),
    );
  }

  Widget _widthBtn(double w) {
    final sel = _strokeW == w;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _strokeW = w),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(
            color: sel ? yInk : yMuted.withValues(alpha: 0.4),
            width: sel ? 2.5 : yLineThin,
          ),
        ),
        child: Container(
          width: w.clamp(3.0, 14.0),
          height: w.clamp(3.0, 14.0),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: yInk,
          ),
        ),
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────

class _StrokePainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? active;

  _StrokePainter({required this.strokes, this.active});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, s);
    }
    if (active != null) _draw(canvas, active!);
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

class DrawingPreviewPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  const DrawingPreviewPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _draw(canvas, s);
    }
  }

  @override
  bool shouldRepaint(DrawingPreviewPainter old) => true;
}

void _draw(Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;

  final paint = Paint()
    ..color = Color(stroke.colorValue)
    ..strokeWidth = stroke.strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  if (stroke.points.length == 1) {
    canvas.drawCircle(
      Offset(stroke.points[0][0], stroke.points[0][1]),
      stroke.strokeWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }

  final path = Path();
  path.moveTo(stroke.points[0][0], stroke.points[0][1]);

  for (int i = 1; i < stroke.points.length - 1; i++) {
    final x0 = stroke.points[i][0];
    final y0 = stroke.points[i][1];
    final x1 = stroke.points[i + 1][0];
    final y1 = stroke.points[i + 1][1];
    path.quadraticBezierTo(x0, y0, (x0 + x1) / 2, (y0 + y1) / 2);
  }

  final last = stroke.points.last;
  path.lineTo(last[0], last[1]);
  canvas.drawPath(path, paint);
}
