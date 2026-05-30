import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../widgets/yuli_design.dart';

/// Result of a crop: the baked file (temp) plus the cropped region expressed as
/// fractions [0..1] of the source image, so the caller can reposition/resize
/// the on-canvas image to keep the kept region in place.
class CropResult {
  final File file;
  final double fracLeft;
  final double fracTop;
  final double fracW;
  final double fracH;
  CropResult(this.file, this.fracLeft, this.fracTop, this.fracW, this.fracH);
}

/// Full-screen destructive crop: rectangular box or freeform lasso (PNG with
/// transparency). Returns a [CropResult] via Navigator.pop, or null on cancel.
class ImageCropScreen extends StatefulWidget {
  final String sourcePath;
  final Color accent;
  const ImageCropScreen({
    super.key,
    required this.sourcePath,
    required this.accent,
  });

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  ui.Image? _image;
  bool _lasso = false;
  bool _busy = false;

  Rect _displayRect = Rect.zero; // where the image is drawn on screen
  Rect? _box; // crop box in screen coords
  final List<Offset> _lassoPts = []; // screen coords
  int _handle = -1; // 0..3 corners, 4 = move whole box

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.sourcePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _layout(Size area) {
    final img = _image!;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final scale = (area.width / iw).clamp(0.0, area.height / ih);
    final w = iw * scale;
    final h = ih * scale;
    final left = (area.width - w) / 2;
    final top = (area.height - h) / 2;
    _displayRect = Rect.fromLTWH(left, top, w, h);
    _box ??= Rect.fromLTWH(
      left + w * 0.1,
      top + h * 0.1,
      w * 0.8,
      h * 0.8,
    );
  }

  // ─── Box gestures ──────────────────────────────────────────────────────

  void _boxDown(Offset pos) {
    final b = _box!;
    final corners = [b.topLeft, b.topRight, b.bottomRight, b.bottomLeft];
    _handle = -1;
    for (int i = 0; i < 4; i++) {
      if ((pos - corners[i]).distance < 28) {
        _handle = i;
        return;
      }
    }
    if (b.contains(pos)) _handle = 4;
  }

  void _boxMove(Offset delta, Offset pos) {
    if (_handle < 0) return;
    var b = _box!;
    if (_handle == 4) {
      b = b.shift(delta);
    } else {
      var l = b.left, t = b.top, r = b.right, bo = b.bottom;
      switch (_handle) {
        case 0:
          l = pos.dx;
          t = pos.dy;
        case 1:
          r = pos.dx;
          t = pos.dy;
        case 2:
          r = pos.dx;
          bo = pos.dy;
        case 3:
          l = pos.dx;
          bo = pos.dy;
      }
      b = Rect.fromLTRB(
        l.clamp(_displayRect.left, r - 30),
        t.clamp(_displayRect.top, bo - 30),
        r.clamp(l + 30, _displayRect.right),
        bo.clamp(t + 30, _displayRect.bottom),
      );
    }
    // Keep inside the image.
    final dr = _displayRect;
    final dx = b.left < dr.left
        ? dr.left - b.left
        : (b.right > dr.right ? dr.right - b.right : 0.0);
    final dy = b.top < dr.top
        ? dr.top - b.top
        : (b.bottom > dr.bottom ? dr.bottom - b.bottom : 0.0);
    setState(() => _box = b.shift(Offset(dx, dy)));
  }

  // ─── Bake ──────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_image == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = _lasso ? await _bakeLasso() : await _bakeBox();
      if (result != null && mounted) Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double get _scale => _displayRect.width / _image!.width;

  Offset _toImage(Offset screen) => Offset(
        (screen.dx - _displayRect.left) / _scale,
        (screen.dy - _displayRect.top) / _scale,
      );

  Future<CropResult?> _bakeBox() async {
    if (_box == null) return null;
    final img = _image!;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final tl = _toImage(_box!.topLeft);
    final br = _toImage(_box!.bottomRight);
    final src = Rect.fromLTRB(
      tl.dx.clamp(0.0, iw),
      tl.dy.clamp(0.0, ih),
      br.dx.clamp(0.0, iw),
      br.dy.clamp(0.0, ih),
    );
    final cw = src.width.round();
    final ch = src.height.round();
    if (cw < 2 || ch < 2) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        Paint()..filterQuality = FilterQuality.high);
    final out = await recorder.endRecording().toImage(cw, ch);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (png == null) return null;

    // No transparency in a box crop → compress to JPEG.
    final jpg = await FlutterImageCompress.compressWithList(
      png.buffer.asUint8List(),
      quality: 85,
      format: CompressFormat.jpeg,
    );
    final file = await _writeTemp(jpg, 'jpg');
    return CropResult(
        file, src.left / iw, src.top / ih, src.width / iw, src.height / ih);
  }

  Future<CropResult?> _bakeLasso() async {
    if (_lassoPts.length < 3) return null;
    final img = _image!;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();

    final path = Path();
    final first = _toImage(_lassoPts.first);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < _lassoPts.length; i++) {
      final pt = _toImage(_lassoPts[i]);
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();

    var b = path.getBounds();
    b = Rect.fromLTRB(
      b.left.clamp(0.0, iw),
      b.top.clamp(0.0, ih),
      b.right.clamp(0.0, iw),
      b.bottom.clamp(0.0, ih),
    );
    final cw = b.width.round();
    final ch = b.height.round();
    if (cw < 2 || ch < 2) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(-b.left, -b.top);
    canvas.clipPath(path);
    canvas.drawImage(img, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    final out = await recorder.endRecording().toImage(cw, ch);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (png == null) return null;

    final file = await _writeTemp(png.buffer.asUint8List(), 'png');
    return CropResult(
        file, b.left / iw, b.top / ih, b.width / iw, b.height / ih);
  }

  Future<File> _writeTemp(Uint8List bytes, String ext) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${const Uuid().v4()}.$ext'));
    await file.writeAsBytes(bytes);
    return file;
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _image == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : LayoutBuilder(builder: (_, c) {
                      _layout(Size(c.maxWidth, c.maxHeight));
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          if (_lasso) {
                            setState(() {
                              _lassoPts
                                ..clear()
                                ..add(d.localPosition);
                            });
                          } else {
                            _boxDown(d.localPosition);
                          }
                        },
                        onPanUpdate: (d) {
                          if (_lasso) {
                            setState(() => _lassoPts.add(d.localPosition));
                          } else {
                            _boxMove(d.delta, d.localPosition);
                          }
                        },
                        child: CustomPaint(
                          size: Size(c.maxWidth, c.maxHeight),
                          painter: _CropPainter(
                            image: _image!,
                            displayRect: _displayRect,
                            box: _lasso ? null : _box,
                            lasso: _lasso ? _lassoPts : null,
                            accent: widget.accent,
                          ),
                        ),
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          _barBtn('CANCELAR', () => Navigator.pop(context)),
          const Spacer(),
          _modeBtn('CAJA', !_lasso, () => setState(() => _lasso = false)),
          const SizedBox(width: 6),
          _modeBtn('LAZO', _lasso, () {
            setState(() {
              _lasso = true;
              _lassoPts.clear();
            });
          }),
          const Spacer(),
          _barBtn(_busy ? '...' : 'RECORTAR', _busy ? null : _confirm,
              filled: true),
        ],
      ),
    );
  }

  Widget _modeBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? widget.accent : Colors.transparent,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Text(label,
            style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: Colors.white)),
      ),
    );
  }

  Widget _barBtn(String label, VoidCallback? onTap, {bool filled = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? widget.accent : Colors.transparent,
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Text(label,
            style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 1.2,
                color: Colors.white)),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect displayRect;
  final Rect? box;
  final List<Offset>? lasso;
  final Color accent;

  _CropPainter({
    required this.image,
    required this.displayRect,
    required this.box,
    required this.lasso,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, displayRect, Paint());

    final dim = Paint()..color = const Color(0x99000000);
    final clear = Path()..addRect(Offset.zero & size);

    if (box != null) {
      clear.addRect(box!);
      clear.fillType = PathFillType.evenOdd;
      canvas.drawPath(clear, dim);
      // Box outline + corner handles.
      canvas.drawRect(
        box!,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final hp = Paint()..color = accent;
      for (final c in [
        box!.topLeft,
        box!.topRight,
        box!.bottomRight,
        box!.bottomLeft
      ]) {
        canvas.drawRect(Rect.fromCenter(center: c, width: 14, height: 14), hp);
      }
    } else if (lasso != null && lasso!.length >= 2) {
      final path = Path()..moveTo(lasso!.first.dx, lasso!.first.dy);
      for (int i = 1; i < lasso!.length; i++) {
        path.lineTo(lasso![i].dx, lasso![i].dy);
      }
      path.close();
      clear.addPath(path, Offset.zero);
      clear.fillType = PathFillType.evenOdd;
      canvas.drawPath(clear, dim);
      canvas.drawPath(
        path,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawRect(Offset.zero & size, dim);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
