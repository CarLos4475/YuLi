import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/ink_recognizer_provider.dart';
import '../../providers/math_recognizer_provider.dart';
import '../../providers/database_providers.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/services/ink_recognizer.dart';
import '../../../domain/services/math_recognizer.dart';
import '../../../domain/models/note_block.dart';
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
    onSendToNote:
        folderId == null
            ? null
            : (t) => sendTextToNote(
              context,
              ref,
              t,
              defaultFolderId: folderId,
              accent: accent,
            ),
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
    onSend: (t) => _sendOcrContextToYuli(context, ref, noteId, accent, t),
    onAsk:
        (t) => showAiChat(
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

  final mathResult = await _recognizeMathDraft(context, ref, strokes);
  if (!context.mounted) return;

  String dirty = mathResult.latex.trim();
  if (dirty.isEmpty || mathResult.isFallback) {
    final candidates = await _recognizeTextCandidates(context, ref, strokes);
    if (candidates == null || !context.mounted) return;
    dirty = candidates.isEmpty ? dirty : candidates.first.text.trim();
  }

  final contextText = _displayMath(dirty);
  showYuliContextSheet(
    context,
    contextText: contextText,
    accent: accent,
    onSend: (t) => _sendOcrContextToYuli(context, ref, noteId, accent, t),
    onAsk:
        (t) => showAiChat(
          context,
          ref,
          noteId: noteId,
          prefillMessage: t,
          accent: accent,
        ),
  );
}

Future<MathRecognitionResult> _recognizeMathDraft(
  BuildContext context,
  WidgetRef ref,
  List<List<Offset>> strokes,
) async {
  try {
    final result = await ref.read(mathRecognizerProvider).recognize(strokes);
    await _maybeDumpMathStrokes(strokes, result.latex); // datos fine-tune (debug)
    return result;
  } catch (e, stackTrace) {
    await _maybeDumpMathStrokes(strokes, 'ERROR: $e'); // datos fine-tune (debug)
    debugPrint('MATH OCR LOCAL FALLBACK: $e');
    debugPrintStack(stackTrace: stackTrace);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MATH LOCAL FALLÓ: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    return const MathRecognitionResult(latex: '', isFallback: true);
  }
}

// Recolección de datos para el fine-tune del modelo (SOLO debug): vuelca los
// trazos EXACTOS que ve el recognizer + el latex producido a JSON en el
// almacenamiento externo de la app, para juntar caligrafía propia y reentrenar.
// Pull: adb pull /storage/emulated/0/Android/data/com.carlos.yuli.yuli/files/math_dump
Future<void> _maybeDumpMathStrokes(
  List<List<Offset>> strokes,
  String latex,
) async {
  if (!kDebugMode) return;
  try {
    final base = await getExternalStorageDirectory();
    if (base == null) return;
    final dir = Directory('${base.path}/math_dump');
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'latex': latex,
      'strokes': [
        for (final stroke in strokes)
          [
            for (final p in stroke) [p.dx, p.dy],
          ],
      ],
    };
    final file = File('${dir.path}/math_$stamp.json');
    await file.writeAsString(jsonEncode(payload));
    debugPrint('MATH DUMP -> ${file.path} latex="$latex"');
  } catch (e) {
    debugPrint('MATH DUMP error: $e');
  }
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
      candidates = await recognizer.recognize(
        strokes,
        langTag: kInkDefaultLang,
      );
    }
  } catch (e) {
    error = 'Error al reconocer: $e';
  }

  if (navigator.canPop()) navigator.pop(); // close spinner
  if (!context.mounted) return null;

  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(error), duration: const Duration(seconds: 3)),
    );
    return null;
  }

  return candidates;
}

/// Send OCR text to the chat as context. If [noteId] is a canvas with linked
/// NOTE sources, the text is appended as a TextBlock to one of them (asking
/// which when there are several) and the chat resyncs — keeping the note as the
/// source of truth. With no note source, it's pushed as a one-off anchor.
Future<void> _sendOcrContextToYuli(
  BuildContext context,
  WidgetRef ref,
  int noteId,
  Color accent,
  String text,
) async {
  final sources = await ref
      .read(noteRepositoryProvider)
      .getContextSources(noteId);
  final noteSources =
      sources.where((s) => s.isNote && s.noteId != null).toList();
  if (!context.mounted) return;
  if (noteSources.isEmpty) {
    showAiChat(context, ref, noteId: noteId, newContext: text, accent: accent);
    return;
  }
  int target;
  if (noteSources.length == 1) {
    target = noteSources.first.noteId!;
  } else {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: yCream,
              border: Border(
                top: BorderSide(color: yBorderStrong, width: yLineHeavy),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '¿A QUÉ NOTA ENVÍO EL TEXTO?',
                    style: yMono(
                      size: 11,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final s in noteSources)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(s.noteId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: yBorderStrong,
                              width: yLineThin,
                            ),
                          ),
                        ),
                        child: Text(
                          (s.label?.trim().isEmpty ?? true)
                              ? 'Nota'
                              : s.label!.trim(),
                          style: ySans(
                            size: 14,
                            weight: FontWeight.w700,
                            color: yInk,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
    if (picked == null) return;
    target = picked;
  }
  await ref
      .read(noteBlockRepositoryProvider)
      .insertAtEnd(target, NoteBlockType.text, payload: {'md': text});
  if (!context.mounted) return;
  showAiChat(context, ref, noteId: noteId, accent: accent);
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
