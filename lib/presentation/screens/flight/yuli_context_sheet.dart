import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/yuli_design.dart';

Future<void> showYuliContextSheet(
  BuildContext context, {
  required String contextText,
  required Color accent,
  required ValueChanged<String> onSend,
  required ValueChanged<String> onAsk,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _YuliContextSheet(
      contextText: contextText,
      accent: accent,
      onSend: onSend,
      onAsk: onAsk,
    ),
  );
}

class _YuliContextSheet extends StatefulWidget {
  final String contextText;
  final Color accent;
  final ValueChanged<String> onSend;
  final ValueChanged<String> onAsk;

  const _YuliContextSheet({
    required this.contextText,
    required this.accent,
    required this.onSend,
    required this.onAsk,
  });

  @override
  State<_YuliContextSheet> createState() => _YuliContextSheetState();
}

class _YuliContextSheetState extends State<_YuliContextSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.contextText);
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
                  Text('CONTEXTO PARA YULI',
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
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
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
                    hintText: 'CONTEXTO VACÍO',
                    hintStyle: yBody(size: 15, color: yMuted),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final text = _ctrl.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(context).pop();
                        widget.onSend(text);
                      },
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          border: Border.all(color: yInk, width: yLineMid),
                        ),
                        child: Text(
                          'ENVIAR A YULI',
                          style: yMono(
                              size: 11,
                              weight: FontWeight.w700,
                              tracking: 1.2,
                              color: yCream),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final text = _ctrl.text.trim();
                        if (text.isEmpty) return;
                        Navigator.of(context).pop();
                        widget.onAsk(text);
                      },
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: yCream,
                          border:
                              Border.all(color: widget.accent, width: yLineMid),
                        ),
                        child: Text(
                          'PREGUNTAR A YULI',
                          style: yMono(
                              size: 11,
                              weight: FontWeight.w700,
                              tracking: 1.0,
                              color: yInk),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _copyAll,
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _copied ? yInk : yCream,
                    border: Border.all(color: widget.accent, width: yLineMid),
                  ),
                  child: Text(
                    _copied ? 'COPIADO' : 'COPIAR CONTEXTO',
                    style: yMono(
                        size: 11,
                        weight: FontWeight.w700,
                        tracking: 1.2,
                        color: _copied ? yCream : yInk),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
