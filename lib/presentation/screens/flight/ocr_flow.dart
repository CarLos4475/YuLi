import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ink_recognizer_provider.dart';
import '../../providers/math_ocr_provider.dart';
import '../../../domain/services/ink_recognizer.dart';
import 'ai_chat_sheet.dart';
import 'ocr_result_sheet.dart';
import 'ocr_send_to_note.dart';
import 'yuli_context_sheet.dart';

/// End-to-end OCR flow shared by every ink surface (whiteboard / notebook /
/// drawing cell): show a spinner, download the language model on first use,
/// recognize the [strokes] (world/page coords — only relative geometry matters)
/// and open the editable result sheet. [folderId] enables the "Enviar a nota"
/// action; pass null to hide it (e.g. when there's no host folder).
Future<void> runOcrFlow(
  BuildContext context,
  WidgetRef ref,
  List<List<Offset>> strokes, {
  required Color accent,
  int? folderId,
  int? noteId,
}) async {
  if (strokes.isEmpty) return;

  final candidates = await _recognizeTextCandidates(context, ref, strokes);
  if (candidates == null || !context.mounted) return;

  final text = candidates.isEmpty ? '' : candidates.first.text;
  showOcrResultSheet(
    context,
    text: text,
    looksNonTextual: ocrLooksNonTextual(text),
    accent: accent,
    onSendToNote: folderId == null
        ? null
        : (t) => sendTextToNote(context, ref, t,
            defaultFolderId: folderId, accent: accent),
  );
}

Future<void> runOcrToYuliFlow(
  BuildContext context,
  WidgetRef ref,
  List<List<Offset>> strokes, {
  required Color accent,
  required int noteId,
}) async {
  if (strokes.isEmpty) return;

  final candidates = await _recognizeTextCandidates(context, ref, strokes);
  if (candidates == null || !context.mounted) return;

  final text = candidates.isEmpty ? '' : candidates.first.text.trim();
  if (text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('NO SE RECONOCIÓ TEXTO PARA YULI'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  showYuliContextSheet(
    context,
    contextText: text,
    accent: accent,
    onSend: (t) => showAiChat(
      context,
      ref,
      noteId: noteId,
      newContext: t,
      accent: accent,
    ),
    onAsk: (t) => showAiChat(
      context,
      ref,
      noteId: noteId,
      prefillMessage: t,
      accent: accent,
    ),
  );
}

Future<void> runMathToYuliFlow(
  BuildContext context,
  WidgetRef ref,
  List<List<Offset>> strokes, {
  required Color accent,
  required int noteId,
}) async {
  if (strokes.isEmpty) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  String? error;
  String latex = '';
  try {
    final dataUri = await _renderStrokesDataUri(strokes);
    latex = await ref.read(mathOcrServiceProvider).recognizeImageDataUri(dataUri);
  } catch (e) {
    error = 'ERROR MATH OCR: $e';
  }

  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return;

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 3)),
    );
    return;
  }

  final contextText = _displayMath(latex);
  showYuliContextSheet(
    context,
    contextText: contextText,
    accent: accent,
    onSend: (t) => showAiChat(
      context,
      ref,
      noteId: noteId,
      newContext: t,
      accent: accent,
    ),
    onAsk: (t) => showAiChat(
      context,
      ref,
      noteId: noteId,
      prefillMessage: t,
      accent: accent,
    ),
  );
}

Future<List<InkCandidate>?> _recognizeTextCandidates(
  BuildContext context,
  WidgetRef ref,
  List<List<Offset>> strokes,
) async {
  final recognizer = ref.read(inkRecognizerProvider);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  String? error;
  List<InkCandidate> candidates = const [];
  try {
    if (!await recognizer.isModelReady(kInkDefaultLang)) {
      final ok = await recognizer.downloadModel(kInkDefaultLang);
      if (!ok) error = 'No se pudo descargar el modelo de idioma.';
    }
    if (error == null) {
      candidates = await recognizer.recognize(strokes, langTag: kInkDefaultLang);
    }
  } catch (e) {
    error = 'Error al reconocer: $e';
  }

  if (navigator.canPop()) navigator.pop(); // close spinner
  if (!context.mounted) return null;

  if (error != null) {
    messenger.showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 3)));
    return null;
  }

  return candidates;
}

/// Heuristic (NOT a real math classifier): flag results that are empty or
/// mostly non-letters/digits, to hint "this looks like math/drawing".
bool ocrLooksNonTextual(String t) {
  final s = t.trim();
  if (s.isEmpty) return true;
  final letters = RegExp(r'[\p{L}\p{N}]', unicode: true).allMatches(s).length;
  return letters / s.length < 0.5;
}

String _displayMath(String latex) {
  final s = latex.trim();
  if (s.startsWith(r'$$') && s.endsWith(r'$$')) return s;
  return '\$\$\n$s\n\$\$';
}

Future<String> _renderStrokesDataUri(List<List<Offset>> strokes) async {
  final points = strokes.expand((s) => s).toList();
  if (points.isEmpty) throw const FormatException('Sin trazos.');

  var left = points.first.dx;
  var right = points.first.dx;
  var top = points.first.dy;
  var bottom = points.first.dy;
  for (final p in points) {
    left = math.min(left, p.dx);
    right = math.max(right, p.dx);
    top = math.min(top, p.dy);
    bottom = math.max(bottom, p.dy);
  }

  const padding = 32.0;
  final sourceW = math.max(1.0, right - left);
  final sourceH = math.max(1.0, bottom - top);
  final scale = math.min(3.0, 1400.0 / math.max(sourceW, sourceH));
  final width = ((sourceW + padding * 2) * scale).ceil();
  final height = ((sourceH + padding * 2) * scale).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  canvas
    ..scale(scale)
    ..translate(-left + padding, -top + padding);

  final paint = Paint()
    ..color = Colors.black
    ..strokeWidth = 4 / scale
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, 2 / scale, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (int i = 1; i < stroke.length; i++) {
      path.lineTo(stroke[i].dx, stroke[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw const FormatException('No se pudo renderizar.');
  return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
}
