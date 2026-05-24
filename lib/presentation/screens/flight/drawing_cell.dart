import 'package:flutter/material.dart';
import '../../theme/app_tokens.dart';
import 'note_cell_model.dart';

const _colors = [
  Color(0xFF111111),
  Color(0xFFE02B2B),
  Color(0xFF2D4B8E),
  Color(0xFF3D6B4F),
  Color(0xFFC17F3A),
  Color(0xFF6B2D8E),
];

const _widths = [1.5, 3.0, 6.0];

class DrawingCell extends StatefulWidget {
  final DrawingData data;
  final ValueChanged<DrawingData> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDrawStart;
  final VoidCallback onDrawEnd;
  final ValueChanged<bool> onScrollLockChanged;
  final Widget? header;

  const DrawingCell({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onDelete,
    required this.onDrawStart,
    required this.onDrawEnd,
    required this.onScrollLockChanged,
    this.header,
  });

  @override
  State<DrawingCell> createState() => _DrawingCellState();
}

class _DrawingCellState extends State<DrawingCell> {
  late DrawingData _data;
  Color _color = const Color(0xFF111111);
  double _strokeW = 2.0;
  bool _erasing = false;
  bool _locked = false;
  final List<DrawingStroke> _undoStack = [];
  DrawingStroke? _active;

  @override
  void initState() {
    super.initState();
    _data = widget.data;
  }

  void _panStart(DragStartDetails d) {
    widget.onDrawStart();
    if (_erasing) {
      _eraseNear(d.localPosition);
      return;
    }
    setState(() {
      _active = DrawingStroke(
        colorValue: _color.toARGB32(),
        strokeWidth: _strokeW,
        points: [
          [d.localPosition.dx, d.localPosition.dy]
        ],
      );
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_erasing) {
      _eraseNear(d.localPosition);
      return;
    }
    if (_active == null) return;
    setState(() {
      _active!.points.add([d.localPosition.dx, d.localPosition.dy]);
    });
  }

  void _panEnd(DragEndDetails _) {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: inkGray.withAlpha(60),
            border: Border.all(color: inkColor(context), width: borderWidth),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.header != null) widget.header!,
              _buildToolbar(context),
            ],
          ),
        ),
        _buildCanvas(context),
        _buildResizeHandle(context),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolBtn(
              context,
              icon: _locked ? Icons.lock : Icons.lock_open,
              active: _locked,
              onTap: () {
                setState(() => _locked = !_locked);
                widget.onScrollLockChanged(_locked);
              },
            ),
            _divider(),
            _toolBtn(
              context,
              icon: Icons.edit_outlined,
              active: !_erasing,
              onTap: () => setState(() => _erasing = false),
            ),
            const SizedBox(width: 4),
            _toolBtn(
              context,
              icon: Icons.auto_fix_normal,
              active: _erasing,
              onTap: () => setState(() => _erasing = true),
            ),
            _divider(),
            for (final c in _colors) ...[
              _colorBtn(context, c),
              const SizedBox(width: 3),
            ],
            _divider(),
            for (final w in _widths) ...[
              _widthBtn(context, w),
              const SizedBox(width: 3),
            ],
            _divider(),
            _toolBtn(
              context,
              icon: Icons.undo,
              active: false,
              enabled: _data.strokes.isNotEmpty,
              onTap: _undo,
            ),
            const SizedBox(width: 4),
            _toolBtn(
              context,
              icon: Icons.redo,
              active: false,
              enabled: _undoStack.isNotEmpty,
              onTap: _redo,
            ),
            const SizedBox(width: 8),
            _toolBtn(
              context,
              icon: Icons.delete_outline,
              active: false,
              onTap: widget.onDelete,
            ),
          ],
          ),
        ),
      );
    }

  Widget _buildCanvas(BuildContext context) {
    return GestureDetector(
      onPanStart: _locked ? _panStart : null,
      onPanUpdate: _locked ? _panUpdate : null,
      onPanEnd: _locked ? _panEnd : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _data.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            left: BorderSide(color: accentLab, width: 3),
            right: BorderSide(color: accentLab, width: 3),
          ),
        ),
        child: _locked
            ? ClipRect(
                child: CustomPaint(
                  painter: _StrokePainter(
                    strokes: _data.strokes,
                    active: _active,
                  ),
                  size: Size.infinite,
                ),
              )
            : Stack(
                children: [
                  ClipRect(
                    child: CustomPaint(
                      painter: _StrokePainter(
                        strokes: _data.strokes,
                        active: _active,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Bloquear scroll para dibujar',
                        style: bodyS.copyWith(
                          color: inkGray.withAlpha(120),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildResizeHandle(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: inkGray.withAlpha(60),
        border: Border.all(color: inkColor(context), width: borderWidth),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _data.height = (_data.height - 60).clamp(120.0, 1200.0);
                _cropStrokes();
              });
              widget.onChanged(_data);
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                border: Border.all(color: inkColor(context), width: borderWidth),
              ),
              child: Icon(Icons.remove, size: 16, color: inkColor(context)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                final prev = _data.height;
                _data.height = (_data.height + d.delta.dy).clamp(120.0, 1200.0);
                if (_data.height < prev) _cropStrokes();
              });
              widget.onChanged(_data);
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                border: Border.all(color: inkColor(context), width: borderWidth),
              ),
              child: Icon(Icons.swap_vert, size: 18, color: inkColor(context)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _data.height = (_data.height + 60).clamp(120.0, 1200.0);
              });
              widget.onChanged(_data);
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                border: Border.all(color: inkColor(context), width: borderWidth),
              ),
              child: Icon(Icons.add, size: 16, color: inkColor(context)),
            ),
          ),
        ],
      ),
    );
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
    if (prevInside) {
      result.add(points[0]);
    }
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
      color: inkGray.withAlpha(40),
    );
  }

  Widget _toolBtn(
    BuildContext context, {
    required IconData icon,
    required bool active,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: active ? inkColor(context) : Colors.transparent,
          border: Border.all(
            color: enabled ? inkColor(context) : inkGray.withAlpha(50),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active
              ? paperColor(context)
              : enabled
                  ? inkColor(context)
                  : inkGray.withAlpha(50),
        ),
      ),
    );
  }

  Widget _colorBtn(BuildContext context, Color c) {
    final sel = _color.toARGB32() == c.toARGB32() && !_erasing;
    return GestureDetector(
      onTap: () => setState(() {
        _color = c;
        _erasing = false;
      }),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: c,
          border: Border.all(
            color: sel ? inkColor(context) : Colors.transparent,
            width: sel ? 2.5 : 0,
          ),
        ),
      ),
    );
  }

  Widget _widthBtn(BuildContext context, double w) {
    final sel = _strokeW == w;
    return GestureDetector(
      onTap: () => setState(() => _strokeW = w),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border.all(
            color: sel ? accentFlight : inkGray.withAlpha(50),
            width: sel ? 2 : 1,
          ),
        ),
        child: Center(
          child: Container(
            width: (w * 2.5).clamp(4.0, 16.0),
            height: (w * 2.5).clamp(4.0, 16.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: inkColor(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

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
