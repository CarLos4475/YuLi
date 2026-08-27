import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/note.dart' show NoteKind;
import '../../../domain/services/ai_assistant.dart';
import 'ai_chat_session.dart';
import 'pin_dialog.dart';

class AiChatMenuResult {
  final AiChatSettings settings;
  final bool summarize;

  const AiChatMenuResult({required this.settings, this.summarize = false});
}

class AiChatSettingsDialog extends ConsumerStatefulWidget {
  final AiChatSettings initial;
  final Color accent;
  final bool canSummarize;
  final NoteKind hostKind;

  const AiChatSettingsDialog({
    super.key,
    required this.initial,
    required this.accent,
    required this.canSummarize,
    this.hostKind = NoteKind.block,
  });

  @override
  ConsumerState<AiChatSettingsDialog> createState() =>
      _AiChatSettingsDialogState();
}

class _AiChatSettingsDialogState extends ConsumerState<AiChatSettingsDialog> {
  late AiChatSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _set(AiChatSettings value) => setState(() => _draft = value);

  void _finish({bool summarize = false}) {
    Navigator.pop(
      context,
      AiChatMenuResult(settings: _draft, summarize: summarize),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PinDialogShell(
      icon: YuLiIcons.slidersHorizontal,
      title: 'CHAT Y CONSUMO',
      accent: widget.accent,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          PinGhostButton(label: 'CERRAR', onTap: () => Navigator.pop(context)),
          const SizedBox(width: 8),
          PinPrimaryButton(
            label: 'APLICAR',
            icon: YuLiIcons.check,
            accent: widget.accent,
            onTap: _finish,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _impactLegend(),
          const SizedBox(height: 18),
          _sectionLabel('ACCIÓN'),
          _summaryAction(),
          const SizedBox(height: 18),
          _sectionLabel('PERFIL'),
          Row(
            children: [
              Expanded(
                child: _profileButton(
                  'AHORRO',
                  AiChatProfile.savings,
                  const AiChatSettings.savings(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _profileButton(
                  'EQUILIBRADO',
                  AiChatProfile.balanced,
                  const AiChatSettings.balanced(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _profileButton(
                  'COMPLETO',
                  AiChatProfile.complete,
                  const AiChatSettings.complete(),
                  highImpact: true,
                ),
              ),
            ],
          ),
          if (_draft.profile == AiChatProfile.custom) ...[
            const SizedBox(height: 7),
            Text(
              'PERSONALIZADO',
              textAlign: TextAlign.center,
              style: yMono(
                size: 9,
                weight: FontWeight.w800,
                tracking: 1.1,
                color: widget.accent,
              ),
            ),
          ],
          const SizedBox(height: 7),
          _helperText(_profileDetail),
          const SizedBox(height: 18),
          _sectionLabel('MODELO'),
          Row(
            children: [
              Expanded(
                child: _choiceCard(
                  label: 'FLASH',
                  detail: 'Rápido y económico.',
                  selected: _draft.model == AiModel.flash,
                  onTap: () => _set(_draft.copyWith(model: AiModel.flash)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _choiceCard(
                  label: 'PRO',
                  detail: 'Más capaz y costoso.',
                  selected: _draft.model == AiModel.pro,
                  highImpact: true,
                  onTap: () => _set(_draft.copyWith(model: AiModel.pro)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _helperText(_modelDetail),
          const SizedBox(height: 18),
          _sectionLabel('LONGITUD DE RESPUESTA'),
          _threeChoices(
            values: AiResponseLength.values,
            selected: _draft.responseLength,
            label:
                (value) => switch (value) {
                  AiResponseLength.brief => 'BREVE',
                  AiResponseLength.normal => 'NORMAL',
                  AiResponseLength.detailed => 'DETALLADA',
                },
            onTap: (value) => _set(_draft.copyWith(responseLength: value)),
            highImpact: (value) => value == AiResponseLength.detailed,
          ),
          const SizedBox(height: 7),
          _helperText(_responseLengthDetail),
          const SizedBox(height: 18),
          _sectionLabel('CUÁNTO RECORDAR'),
          _threeChoices(
            values: AiHistoryDepth.values,
            selected: _draft.historyDepth,
            label:
                (value) => switch (value) {
                  AiHistoryDepth.recent => 'RECIENTE',
                  AiHistoryDepth.normal => 'NORMAL',
                  AiHistoryDepth.full => 'TODO',
                },
            onTap: (value) => _set(_draft.copyWith(historyDepth: value)),
            highImpact: (value) => value == AiHistoryDepth.full,
          ),
          const SizedBox(height: 7),
          _helperText(_historyDetail),
          const SizedBox(height: 18),
          _sectionLabel('CONTEXTO Y FUNCIONES'),
          _toggle(
            icon: YuLiIcons.fileText,
            title: _hostContextTitle,
            detail: _hostContextDetail,
            value: _draft.useNoteContext,
            highImpact: true,
            onChanged: (value) => _set(_draft.copyWith(useNoteContext: value)),
          ),
          _toggle(
            icon: YuLiIcons.link,
            title: 'BUSCAR CONTENIDO RELACIONADO',
            detail: 'Añade fragmentos de notas y enlaces vinculados.',
            value: _draft.useRelatedSources,
            highImpact: true,
            onChanged:
                (value) => _set(_draft.copyWith(useRelatedSources: value)),
          ),
          _toggle(
            icon: YuLiIcons.listChecks,
            title: 'CONSULTAR TAREAS Y PROYECTOS',
            detail:
                'Puede revisar Fight y Lab. Una consulta puede usar llamadas extra.',
            value: _draft.useTools,
            highImpact: true,
            onChanged: (value) => _set(_draft.copyWith(useTools: value)),
          ),
          _toggle(
            icon: YuLiIcons.sparkles,
            title: 'RESPUESTAS INTERACTIVAS',
            detail: 'Permite quizzes, tarjetas, pasos y ejemplos visuales.',
            value: _draft.useInteractiveReplies,
            onChanged:
                (value) => _set(_draft.copyWith(useInteractiveReplies: value)),
          ),
          _toggle(
            icon: YuLiIcons.brain,
            title: 'USAR RECUERDOS GUARDADOS',
            detail: 'Usa preferencias y datos que aceptaste guardar.',
            value: _draft.useMemory,
            onChanged: (value) => _set(_draft.copyWith(useMemory: value)),
          ),
          _toggle(
            icon: YuLiIcons.squareCheck,
            title: 'PREPARAR ACCIONES',
            detail: 'Propone tareas o tarjetas y siempre pide confirmación.',
            value: _draft.useActionDrafts,
            onChanged: (value) => _set(_draft.copyWith(useActionDrafts: value)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: yCream2,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Text(
              'Las reglas de YuLi siempre se envían. El contexto y las funciones sólo se añaden cuando están activados. Mantenerlos estables ayuda a reutilizar la caché.',
              style: yBody(size: 11, weight: FontWeight.w600, color: yInk),
            ),
          ),
        ],
      ),
    );
  }

  String get _profileDetail => switch (_draft.profile) {
    AiChatProfile.savings =>
      'Usa menos contexto y funciones para reducir el consumo.',
    AiChatProfile.balanced =>
      'Equilibra contexto, calidad y consumo para el uso diario.',
    AiChatProfile.complete =>
      'Usa más contexto y funciones para obtener respuestas más completas.',
    AiChatProfile.custom =>
      'Conserva exactamente la combinación de opciones que elegiste.',
  };

  String get _modelDetail => switch (_draft.model) {
    AiModel.flash =>
      'Prioriza velocidad y menor consumo para consultas cotidianas.',
    AiModel.pro =>
      'Prioriza capacidad para tareas complejas y puede consumir más.',
  };

  String get _responseLengthDetail => switch (_draft.responseLength) {
    AiResponseLength.brief => 'Genera respuestas cortas con el menor consumo.',
    AiResponseLength.normal =>
      'Da el detalle suficiente con un consumo equilibrado.',
    AiResponseLength.detailed =>
      'Genera respuestas amplias y puede consumir bastante más.',
  };

  String get _historyDetail => switch (_draft.historyDepth) {
    AiHistoryDepth.recent =>
      'Recuerda los últimos 2 intercambios y reduce el contexto enviado.',
    AiHistoryDepth.normal =>
      'Recuerda los últimos 4 intercambios para mantener más continuidad.',
    AiHistoryDepth.full =>
      'Recuerda todo el chat; las conversaciones largas consumen más contexto.',
  };

  String get _hostContextTitle => switch (widget.hostKind) {
    NoteKind.block => 'CONTEXTO DE ESTA NOTA',
    NoteKind.whiteboard => 'CONTEXTO DE ESTA PIZARRA',
    NoteKind.notebook => 'CONTEXTO DE ESTE CUADERNO',
  };

  String get _hostContextDetail => switch (widget.hostKind) {
    NoteKind.block =>
      'Envía el texto de esta nota. Si no cambia, normalmente se reutiliza desde caché.',
    NoteKind.whiteboard =>
      'Usa el contexto preparado para esta pizarra; no convierte los trazos en texto.',
    NoteKind.notebook =>
      'Usa el contexto preparado para este cuaderno; no convierte los trazos en texto.',
  };

  Widget _helperText(String text) =>
      Text(text, key: ValueKey(text), style: yBody(size: 11, color: yMuted));

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: yMono(
        size: 10,
        weight: FontWeight.w800,
        tracking: 1.3,
        color: yInk,
      ),
    ),
  );

  Widget _impactLegend() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(
      color: yCream2,
      border: Border.all(color: yBorderStrong, width: yLineThin),
    ),
    child: Row(
      children: [
        Container(width: 9, height: 9, color: widget.accent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'EL CUADRADO MARCA OPCIONES QUE PUEDEN AUMENTAR MUCHO EL GASTO',
            style: yMono(
              size: 8.5,
              weight: FontWeight.w800,
              tracking: 0.5,
              color: yInk,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _summaryAction() {
    final enabled = widget.canSummarize;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _finish(summarize: true) : null,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(
            color: enabled ? yBorderStrong : yBorderSoft,
            width: yLineThin,
          ),
        ),
        child: Row(
          children: [
            Icon(
              YuLiIcons.textQuote,
              size: 16,
              color: enabled ? widget.accent : yMuted,
            ),
            const SizedBox(width: 9),
            Text(
              'RESUMIR EL CHAT',
              style: yMono(
                size: 11,
                weight: FontWeight.w800,
                tracking: 0.8,
                color: enabled ? yInk : yMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileButton(
    String label,
    AiChatProfile profile,
    AiChatSettings value, {
    bool highImpact = false,
  }) {
    final selected = _draft.profile == profile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _set(value),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? widget.accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (highImpact) ...[
                _impactSquare(inverted: selected),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: yMono(
                  size: 9,
                  weight: FontWeight.w800,
                  tracking: 0.6,
                  color: selected ? yCream : yInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceCard({
    required String label,
    required String detail,
    required bool selected,
    required VoidCallback onTap,
    bool highImpact = false,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? widget.accent : yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highImpact) ...[
                _impactSquare(inverted: selected),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: yMono(
                  size: 11,
                  weight: FontWeight.w800,
                  tracking: 1.0,
                  color: selected ? yCream : yInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: yBody(size: 10, color: selected ? yCream : yMuted),
          ),
        ],
      ),
    ),
  );

  Widget _threeChoices<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) label,
    required ValueChanged<T> onTap,
    bool Function(T value)? highImpact,
  }) => Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            key: ValueKey(values[i]),
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(values[i]),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: values[i] == selected ? widget.accent : yCream,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (highImpact?.call(values[i]) ?? false) ...[
                    _impactSquare(inverted: values[i] == selected),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label(values[i]),
                    style: yMono(
                      size: 9,
                      weight: FontWeight.w800,
                      tracking: 0.6,
                      color: values[i] == selected ? yCream : yInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _toggle({
    required IconData icon,
    required String title,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool highImpact = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
        decoration: BoxDecoration(
          color: value ? widget.accent.withValues(alpha: 0.10) : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: value ? widget.accent : yMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w800,
                            tracking: 0.5,
                            color: yInk,
                          ),
                        ),
                      ),
                      if (highImpact) ...[
                        const SizedBox(width: 6),
                        _impactChip(active: value),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(detail, style: yBody(size: 10.5, color: yMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? widget.accent : yCream,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child:
                  value
                      ? const Icon(YuLiIcons.check, size: 13, color: yCream)
                      : null,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _impactSquare({bool inverted = false}) =>
      Container(width: 8, height: 8, color: inverted ? yCream : widget.accent);

  Widget _impactChip({required bool active}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: BoxDecoration(
      color: active ? widget.accent : yCream2,
      border: Border.all(color: yBorderStrong, width: yLineThin),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _impactSquare(inverted: active),
        const SizedBox(width: 4),
        Text(
          'MÁS GASTO',
          style: yMono(
            size: 7.5,
            weight: FontWeight.w800,
            tracking: 0.4,
            color: active ? yCream : yInk,
          ),
        ),
      ],
    ),
  );
}
