import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ink_recognizer_provider.dart';
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

  final candidates = await _recognizeTextCandidates(context, ref, strokes);
  if (candidates == null || !context.mounted) return;

  final dirty = candidates.isEmpty ? '' : candidates.first.text.trim();
  final contextText = _displayMath(dirty);
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
  if (s.isEmpty) return '\$\$\n\n\$\$';
  if (s.startsWith(r'$$') && s.endsWith(r'$$')) return s;
  return '\$\$\n$s\n\$\$';
}
