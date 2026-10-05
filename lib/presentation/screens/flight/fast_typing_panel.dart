import 'package:flutter/material.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'ai_chat_visuals.dart';
import 'yuli_block_actions.dart';

class FastTypingPanel extends StatelessWidget {
  final YuliBlockActions actions;
  final Color accent;
  final Future<void> Function() onCorrect;
  final VoidCallback onClose;

  const FastTypingPanel({
    super.key,
    required this.actions,
    required this.accent,
    required this.onCorrect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AiFrostedSurface(
      accent: accent,
      role: AiFrostedSurfaceRole.dialog,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'YuLi Fast Typing',
                  style: ySans(size: 18, weight: FontWeight.w700, color: aiInk),
                ),
              ),
              if (actions.busy) AiThinkingIndicator(accent: accent),
              const SizedBox(width: 8),
              AiSoftIconButton(
                icon: YuLiIcons.close,
                tooltip:
                    actions.busy ? 'Cancelar corrección' : 'Cerrar selección',
                onTap: actions.busy ? actions.cancel : onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            actions.notice ??
                (actions.busy
                    ? 'YuLi está preparando la corrección. Puedes cancelar sin cambiar el texto.'
                    : actions.eligible.isEmpty
                    ? 'Este bloque no contiene texto que se pueda corregir.'
                    : 'Corrige errores de tecleo en este bloque de texto. Se omiten imágenes, código y fórmulas.'),
            style: yBody(size: 12, color: aiMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!actions.busy &&
                  actions.correctionAfter == null &&
                  actions.eligible.isNotEmpty)
                _action('Corregir bloque', YuLiIcons.type, () => onCorrect()),
              if (actions.correctionAfter != null && !actions.busy) ...[
                _action('Aceptar cambios', YuLiIcons.check, () async {
                  await actions.acceptCorrection();
                  if (context.mounted) onClose();
                }),
                _action(
                  'Rechazar cambios',
                  YuLiIcons.close,
                  onClose,
                  primary: false,
                ),
              ],
            ],
          ),
          if (actions.correctionAfter != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AiSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Original', style: yBody(size: 12, color: aiMuted)),
                    const SizedBox(height: 4),
                    SelectableText(
                      actions.correctionBefore ?? '',
                      style: yBody(size: 16, color: aiMuted),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Corregido',
                      style: yBody(
                        size: 12,
                        color: accent,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      actions.correctionAfter ?? '',
                      style: yBody(size: 16, color: aiInk),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = true,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: AiStatusPill(
      label: label,
      icon: icon,
      accent: accent,
      accented: primary,
      onTap: onTap,
    ),
  );
}
