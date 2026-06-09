import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/yuli_design.dart';
import '../../theme/lab_icons.dart';

/// Read the composited pixel color at viewport point [p] from a raster snapshot
/// (`RepaintBoundary.toImage` → rawRgba). [p] is in logical viewport pixels;
/// the snapshot is in device pixels, hence [dpr].
Color? sampleSnapshotColor(
  ByteData bytes,
  int imgW,
  int imgH,
  double dpr,
  Offset p,
) {
  final px = (p.dx * dpr).round().clamp(0, imgW - 1);
  final py = (p.dy * dpr).round().clamp(0, imgH - 1);
  final o = (py * imgW + px) * 4;
  if (o < 0 || o + 3 >= bytes.lengthInBytes) return null;
  final r = bytes.getUint8(o);
  final g = bytes.getUint8(o + 1);
  final b = bytes.getUint8(o + 2);
  // Sample reads as opaque ink on the paper — the canvas is never transparent.
  return Color.fromARGB(255, r, g, b);
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

/// Square neobrutalist magnifier. Header shows the sampled color + hex; the body
/// shows a crisp (pixelated) zoom of [image] centred on [sample] with a
/// crosshair marking the exact sampled pixel.
class ColorLoupe extends StatelessWidget {
  final ui.Image image;
  final double dpr;
  final Offset sample;
  final Color color;
  final double size;
  final double zoom;

  const ColorLoupe({
    super.key,
    required this.image,
    required this.dpr,
    required this.sample,
    required this.color,
    this.size = 132,
    this.zoom = 9,
  });

  @override
  Widget build(BuildContext context) {
    const headerH = 28.0;
    return Container(
      width: size,
      height: size + headerH,
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(3, 3))],
      ),
      child: Column(
        children: [
          SizedBox(
            height: headerH,
            child: Row(
              children: [
                Container(
                  width: headerH,
                  height: headerH,
                  decoration: BoxDecoration(
                    color: color,
                    border: const Border(
                      right: BorderSide(color: yBorderStrong, width: yLineThin),
                      bottom: BorderSide(color: yBorderStrong, width: yLineThin),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hex(color),
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w700,
                      tracking: 1.0,
                      color: yInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRect(
              child: CustomPaint(
                painter: _LoupePainter(
                  image: image,
                  dpr: dpr,
                  sample: sample,
                  zoom: zoom,
                ),
                size: Size(size, size),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoupePainter extends CustomPainter {
  final ui.Image image;
  final double dpr;
  final Offset sample;
  final double zoom;

  _LoupePainter({
    required this.image,
    required this.dpr,
    required this.sample,
    required this.zoom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = sample.dx * dpr;
    final cy = sample.dy * dpr;
    final srcW = (size.width / zoom) * dpr;
    final srcH = (size.height / zoom) * dpr;
    final src = Rect.fromCenter(
      center: Offset(cx, cy),
      width: srcW,
      height: srcH,
    );
    final dst = Offset.zero & size;
    // Crisp, pixelated zoom so individual strokes/pixels read clearly.
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );

    final c = Offset(size.width / 2, size.height / 2);
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = yInk;
    const r = 9.0;
    for (final p in [white, ink]) {
      canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
      canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    }
  }

  @override
  bool shouldRepaint(_LoupePainter old) =>
      old.sample != sample || old.image != image || old.zoom != zoom;
}

/// Floating ✕ / ✓ bar shown under the loupe.
class LoupeActionBar extends StatelessWidget {
  final Color accent;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const LoupeActionBar({
    super.key,
    required this.accent,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [BoxShadow(color: yBorderStrong, offset: Offset(3, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(YuLiIcons.close, yCream, onCancel),
          Container(width: yLineThin, height: 40, color: yBorderStrong),
          _btn(YuLiIcons.check, accent, onConfirm),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, Color bg, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 40,
        alignment: Alignment.center,
        color: bg,
        child: Icon(icon, size: 18, color: bg == yCream ? yInk : yCream),
      ),
    );
  }
}
