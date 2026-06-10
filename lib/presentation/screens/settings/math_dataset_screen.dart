import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_tokens.dart';
import '../../theme/lab_icons.dart';

/// Pantalla de etiquetado del dataset de Math OCR (solo debug).
///
/// Recorre los volcados de trazos en `…/files/math_dump/` (ver
/// `_maybeDumpMathStrokes` en `ocr_flow.dart`), muestra el trazo renderizado y
/// el LaTeX que adivinó el modelo, y permite **corregir** la etiqueta. Las
/// muestras corregidas se guardan en `…/files/math_labeled/<id>.json`
/// (`{strokes, latex, guess, verified}`) — eso es lo que se hace `adb pull`
/// para el fine-tune. Los crudos quedan intactos salvo que se Borren.
class MathDatasetScreen extends StatefulWidget {
  const MathDatasetScreen({super.key});

  @override
  State<MathDatasetScreen> createState() => _MathDatasetScreenState();
}

class _DumpSample {
  final File file;
  final String id;
  final String guess;
  final List<List<Offset>> strokes;

  _DumpSample({
    required this.file,
    required this.id,
    required this.guess,
    required this.strokes,
  });
}

class _MathDatasetScreenState extends State<MathDatasetScreen> {
  /// Meta de muestras etiquetadas antes de lanzar el fine-tune.
  static const _fineTuneGoal = 200;

  final _ctrl = TextEditingController();
  List<_DumpSample> _samples = [];
  int _index = 0;
  bool _loading = true;
  int _labeledTotal = 0;
  Directory? _labeledDir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) {
        setState(() => _loading = false);
        return;
      }
      final dumpDir = Directory('${base.path}/math_dump');
      final labeledDir = Directory('${base.path}/math_labeled');
      if (!await labeledDir.exists()) await labeledDir.create(recursive: true);
      _labeledDir = labeledDir;

      final labeledTotal =
          labeledDir.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.json'),
          ).length;

      final samples = <_DumpSample>[];
      if (await dumpDir.exists()) {
        final files =
            dumpDir.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.json'),
            ).toList()..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          try {
            final id = f.uri.pathSegments.last.replaceAll('.json', '');
            // ya etiquetado → no lo mostramos
            if (await File('${labeledDir.path}/$id.json').exists()) continue;
            final json = jsonDecode(await f.readAsString()) as Map;
            samples.add(
              _DumpSample(
                file: f,
                id: id,
                guess: (json['latex'] as String?) ?? '',
                strokes: _parseStrokes(json['strokes']),
              ),
            );
          } catch (_) {
            // dump corrupto → lo ignoramos
          }
        }
      }
      setState(() {
        _samples = samples;
        _index = 0;
        _labeledTotal = labeledTotal;
        _loading = false;
      });
      _syncFieldToCurrent();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<List<Offset>> _parseStrokes(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (s is List)
          [
            for (final p in s)
              if (p is List && p.length >= 2)
                Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
    ];
  }

  /// Precarga el campo con el guess del modelo (la lista solo tiene pendientes).
  void _syncFieldToCurrent() {
    if (_samples.isEmpty) {
      _ctrl.clear();
      return;
    }
    setState(() => _ctrl.text = _samples[_index].guess);
  }

  void _go(int delta) {
    if (_samples.isEmpty) return;
    final next = (_index + delta).clamp(0, _samples.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
    _syncFieldToCurrent();
  }

  Future<void> _save() async {
    if (_samples.isEmpty || _labeledDir == null) return;
    final s = _samples[_index];
    final latex = _ctrl.text.trim();
    if (latex.isEmpty) return;
    final payload = {
      'id': s.id,
      'latex': latex,
      'guess': s.guess,
      'verified': true,
      'strokes': [
        for (final stroke in s.strokes)
          [
            for (final p in stroke) [p.dx, p.dy],
          ],
      ],
    };
    await File(
      '${_labeledDir!.path}/${s.id}.json',
    ).writeAsString(jsonEncode(payload));
    // etiquetado → fuera de la lista de pendientes; quedamos en la siguiente.
    setState(() {
      _labeledTotal++;
      _samples.removeAt(_index);
      if (_index >= _samples.length) _index = math.max(0, _samples.length - 1);
    });
    _syncFieldToCurrent();
  }

  /// Junta TODAS las etiquetas en un único `.jsonl` (una muestra por línea) y
  /// lo manda por el Share sheet → sobrevive a desinstalar la app. Cada export
  /// es una foto completa; el conteo va en el nombre para no perder el más grande.
  Future<void> _export() async {
    final dir = _labeledDir;
    final messenger = ScaffoldMessenger.of(context);
    if (dir == null) return;
    final files =
        dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.json'),
        ).toList()..sort((a, b) => a.path.compareTo(b.path));
    final buffer = StringBuffer();
    var count = 0;
    for (final f in files) {
      try {
        final obj = jsonDecode(await f.readAsString());
        buffer.writeln(jsonEncode(obj)); // compacta a una sola línea
        count++;
      } catch (_) {
        // etiqueta corrupta → la saltamos
      }
    }
    if (count == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay etiquetas que exportar todavía.')),
      );
      return;
    }
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/yuli_math_${count}labels_$stamp.jsonl');
    await out.writeAsString(buffer.toString());
    await Share.shareXFiles([
      XFile(out.path),
    ], text: 'YuLi · dataset math OCR · $count etiquetas');
  }

  Future<void> _deleteRaw() async {
    if (_samples.isEmpty) return;
    final s = _samples[_index];
    try {
      if (await s.file.exists()) await s.file.delete();
      final labeledFile = File('${_labeledDir!.path}/${s.id}.json');
      if (await labeledFile.exists()) await labeledFile.delete();
    } catch (_) {}
    setState(() {
      _samples.removeAt(_index);
      if (_index >= _samples.length) _index = math.max(0, _samples.length - 1);
    });
    _syncFieldToCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final ink = inkColor(context);
    final paper = paperColor(context);
    final total = _samples.length;

    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── HEADER ──
            Container(
              color: ink,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(YuLiIcons.arrowLeft, size: 20, color: paper),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DATASET MATH',
                    style: labelBold.copyWith(
                      color: paper,
                      letterSpacing: 1.5,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (!_loading) ...[
                    Text(
                      '$_labeledTotal/$_fineTuneGoal ✓',
                      style: mono.copyWith(
                        color: paper,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _labeledTotal > 0 ? _export : null,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          YuLiIcons.share,
                          size: 20,
                          color: _labeledTotal > 0 ? paper : inkGray,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(height: borderWidthHeavy, color: ink),
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : total == 0
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Sin trazos recolectados todavía.\n\nUsa el botón MATH '
                            'en tus apuntes (build debug) y volverán a aparecer aquí '
                            'para etiquetar.',
                            textAlign: TextAlign.center,
                            style: bodyM.copyWith(color: inkGray),
                          ),
                        ),
                      )
                      : _buildEditor(ink, paper),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(Color ink, Color paper) {
    final s = _samples[_index];
    final latex = _ctrl.text.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // navegación + contador
        Row(
          children: [
            _navBtn(YuLiIcons.chevronLeft, _index > 0, () => _go(-1)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: paper,
                  border: Border.all(color: ink, width: borderWidth),
                ),
                child: Text(
                  'PENDIENTE ${_index + 1} / ${_samples.length}',
                  style: labelBold.copyWith(
                    color: ink,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _navBtn(
              YuLiIcons.chevronRight,
              _index < _samples.length - 1,
              () => _go(1),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── TRAZO RENDERIZADO ──
        _label('TRAZO', ink),
        const SizedBox(height: 6),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ink, width: borderWidth),
          ),
          child: CustomPaint(
            painter: _StrokePainter(s.strokes),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 16),

        // ── GUESS DEL MODELO ──
        _label('MODELO DIJO', ink),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: paper,
            border: Border.all(color: inkGray, width: borderWidth),
          ),
          child: SelectableText(
            s.guess.isEmpty ? '(vacío)' : s.guess,
            style: mono.copyWith(color: inkGray, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),

        // ── LATEX CORRECTO (editable) ──
        _label('LATEX CORRECTO', ink),
        const SizedBox(height: 6),
        TextField(
          controller: _ctrl,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          style: mono.copyWith(color: ink, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ink, width: borderWidth),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ink, width: borderWidth),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: ink, width: borderWidth),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── PREVIEW RENDERIZADO ──
        _label('PREVIEW', ink),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ink, width: borderWidth),
          ),
          child: Center(
            child:
                latex.isEmpty
                    ? Text('(vacío)', style: bodyS.copyWith(color: inkGray))
                    : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Math.tex(
                        latex,
                        mathStyle: MathStyle.display,
                        textStyle: const TextStyle(
                          color: Colors.black,
                          fontSize: 26,
                        ),
                        onErrorFallback:
                            (err) => Text(
                              'NO RENDERIZABLE',
                              style: mono.copyWith(
                                color: accentFight,
                                fontSize: 12,
                              ),
                            ),
                      ),
                    ),
          ),
        ),
        const SizedBox(height: 20),

        // ── ACCIONES ──
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _actionBtn(
                'GUARDAR',
                accentJournal,
                paperLight,
                _save,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionBtn('SALTAR', paper, ink, () => _go(1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _actionBtn('BORRAR CRUDO', paper, accentFight, _deleteRaw),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _label(String text, Color ink) => Text(
    text,
    style: labelBold.copyWith(
      color: ink.withAlpha(160),
      fontSize: 10,
      letterSpacing: 1.2,
    ),
  );

  Widget _navBtn(IconData icon, bool enabled, VoidCallback onTap) {
    final ink = inkColor(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: paperColor(context),
          border: Border.all(color: enabled ? ink : inkGray, width: borderWidth),
        ),
        child: Icon(icon, size: 18, color: enabled ? ink : inkGray),
      ),
    );
  }

  Widget _actionBtn(
    String label,
    Color bg,
    Color fg,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: inkColor(context), width: borderWidth),
        ),
        child: Text(
          label,
          style: labelBold.copyWith(
            color: fg,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Pinta los trazos (negro sobre blanco) escalados a la caja, igual que los ve
/// el reconocedor — sin normalizar a tensor, solo para revisión visual.
class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final s in strokes) {
      for (final p in s) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    if (minX == double.infinity) return;

    const pad = 14.0;
    final bw = math.max(maxX - minX, 1.0);
    final bh = math.max(maxY - minY, 1.0);
    final scale = math.min(
      (size.width - 2 * pad) / bw,
      (size.height - 2 * pad) / bh,
    );
    final ox = (size.width - bw * scale) / 2 - minX * scale;
    final oy = (size.height - bh * scale) / 2 - minY * scale;
    Offset t(Offset p) => Offset(p.dx * scale + ox, p.dy * scale + oy);

    final paint =
        Paint()
          ..color = Colors.black
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = Colors.black;

    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(t(s.first), 1.5, dot);
        continue;
      }
      final path = Path()..moveTo(t(s.first).dx, t(s.first).dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(t(s[i]).dx, t(s[i]).dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => old.strokes != strokes;
}
