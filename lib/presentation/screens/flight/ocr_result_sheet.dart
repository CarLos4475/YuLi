import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/yuli_design.dart';

/// Bottom sheet showing the OCR result. The text is **editable** so the user
/// can fix recognition errors, copy fragments by hand (native selection) or
/// copy everything. This is the canonical "recognized text" surface — the AI
/// (v2) will read its context from here later.
Future<void> showOcrResultSheet(
  BuildContext context, {
  required String text,
  required bool looksNonTextual,
  required Color accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OcrResultSheet(
        text: text, looksNonTextual: looksNonTextual, accent: accent),
  );
}

class _OcrResultSheet extends StatefulWidget {
  final String text;
  final bool looksNonTextual;
  final Color accent;

  const _OcrResultSheet({
    required this.text,
    required this.looksNonTextual,
    required this.accent,
  });

  @override
  State<_OcrResultSheet> createState() => _OcrResultSheetState();
}

class _OcrResultSheetState extends State<_OcrResultSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.text);
  bool _copied = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _ctrl.text));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        decoration: const BoxDecoration(
          color: yCream,
          border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('TEXTO RECONOCIDO',
                      style: yMono(
                          size: 11,
                          weight: FontWeight.w700,
                          tracking: 1.4,
                          color: yInk)),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 20, color: yInk),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.looksNonTextual) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: yFight.withValues(alpha: 0.12),
                    border: Border.all(color: yFight, width: yLineThin),
                  ),
                  child: Text(
                    'Esto parece matemáticas o un dibujo — el reconocimiento de '
                    'texto puede fallar. El modo Matemáticas llega después.',
                    style: yMono(size: 10, tracking: 0.6, color: yInk),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: false,
                  keyboardType: TextInputType.multiline,
                  style: yBody(size: 15, color: yInk),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: yInk, width: yLineMid),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: yInk, width: yLineMid),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: yInk, width: yLineMid),
                    ),
                    hintText: 'Sin texto reconocido',
                    hintStyle: yBody(size: 15, color: yMuted),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _copyAll,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _copied ? yInk : widget.accent,
                    border: Border.all(color: yInk, width: yLineMid),
                  ),
                  child: Text(
                    _copied ? '✓ COPIADO' : 'COPIAR TODO',
                    style: yMono(
                        size: 12,
                        weight: FontWeight.w700,
                        tracking: 1.4,
                        color: yCream),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tip: mantén presionado para seleccionar y copiar un fragmento.',
                style: yMono(size: 9, tracking: 0.4, color: yMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
