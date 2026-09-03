import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/note.dart' show NoteKind;
import '../../../domain/services/ai_assistant.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import 'ai_chat_session.dart';
import 'ai_chat_visuals.dart';

class AiChatMenuResult {
  final AiChatSettings settings;
  final bool summarize;
  final bool clearConversation;

  const AiChatMenuResult({
    required this.settings,
    this.summarize = false,
    this.clearConversation = false,
  });
}

class AiChatSettingsDialog extends ConsumerStatefulWidget {
  final AiChatSettings initial;
  final Color accent;
  final bool canSummarize;
  final bool canClearConversation;
  final NoteKind hostKind;

  const AiChatSettingsDialog({
    super.key,
    required this.initial,
    required this.accent,
    required this.canSummarize,
    this.canClearConversation = false,
    this.hostKind = NoteKind.block,
  });

  @override
  ConsumerState<AiChatSettingsDialog> createState() =>
      _AiChatSettingsDialogState();
}

class _AiChatSettingsDialogState extends ConsumerState<AiChatSettingsDialog> {
  late AiChatSettings _draft;
  bool _capabilitiesOpen = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _capabilitiesOpen =
        _draft.useDeepReasoning ||
        _draft.useInteractiveReplies ||
        _draft.useMemory ||
        _draft.useActionDrafts;
  }

  void _set(AiChatSettings value) => setState(() => _draft = value);

  void _finish({bool summarize = false, bool clearConversation = false}) =>
      Navigator.pop(
        context,
        AiChatMenuResult(
          settings: _draft,
          summarize: summarize,
          clearConversation: clearConversation,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 590,
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        child: AiFrostedSurface(
          accent: widget.accent,
          role: AiFrostedSurfaceRole.dialog,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _impactLegend(),
                      if (widget.canSummarize ||
                          widget.canClearConversation) ...[
                        const SizedBox(height: 10),
                        _conversationActions(),
                      ],
                      const SizedBox(height: 18),
                      _sectionLabel('PERFIL'),
                      _profiles(),
                      const SizedBox(height: 7),
                      _helperText(_profileDetail),
                      const SizedBox(height: 18),
                      _sectionLabel('RESPUESTA'),
                      _responseCard(),
                      const SizedBox(height: 18),
                      _sectionLabel('MEMORIA DE LA CONVERSACIÓN'),
                      _historyCard(),
                      const SizedBox(height: 18),
                      _sectionLabel('CONTEXTO'),
                      _contextCard(),
                      const SizedBox(height: 12),
                      _capabilities(),
                      const SizedBox(height: 12),
                      _cacheNote(),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            YuLiIcons.slidersHorizontal,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHAT Y CONSUMO',
                style: ySans(size: 18, weight: FontWeight.w700, color: aiInk),
              ),
              const SizedBox(height: 2),
              Text(
                'Elige qué necesita YuLi antes de enviar.',
                style: yBody(size: 11.5, color: aiMuted),
              ),
            ],
          ),
        ),
        AiSoftIconButton(
          icon: YuLiIcons.close,
          tooltip: 'Cerrar',
          onTap: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.32),
      border: const Border(top: BorderSide(color: aiHairline)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              'CERRAR',
              style: yBody(size: 12, weight: FontWeight.w700, color: aiMuted),
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: widget.accent,
              borderRadius: BorderRadius.circular(21),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(YuLiIcons.check, size: 16, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  'APLICAR',
                  style: yBody(
                    size: 12,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _profiles() => Row(
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
  );

  Widget _responseCard() => AiSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _subLabel('Modelo'),
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
        const SizedBox(height: 16),
        _subLabel('Longitud'),
        _threeChoices<AiResponseLength>(
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
      ],
    ),
  );

  Widget _historyCard() => AiSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _threeChoices<AiHistoryDepth>(
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
        const SizedBox(height: 12),
        _divider(),
        _toggle(
          icon: YuLiIcons.image,
          title: 'RECORDAR IMÁGENES',
          detail:
              'Vuelve a enviar las imágenes del historial con Flash. Es más cómodo, pero puede aumentar mucho el gasto.',
          value: _draft.includeImagesInHistory,
          highImpact: true,
          onChanged:
              (value) => _set(_draft.copyWith(includeImagesInHistory: value)),
        ),
        if (_draft.model == AiModel.pro)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 12, 12),
            child: Text(
              'Pro no admite imágenes por el momento. La opción se aplicará al volver a Flash.',
              style: yBody(size: 10.5, color: aiMuted),
            ),
          ),
      ],
    ),
  );

  Widget _contextCard() => AiSectionCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        _toggle(
          icon: YuLiIcons.fileText,
          title: _hostContextTitle,
          detail: _hostContextDetail,
          value: _draft.useNoteContext,
          highImpact: true,
          onChanged: (value) => _set(_draft.copyWith(useNoteContext: value)),
        ),
        _divider(),
        _toggle(
          icon: YuLiIcons.link,
          title: 'BUSCAR CONTENIDO RELACIONADO',
          detail: 'Añade fragmentos de notas y enlaces vinculados.',
          value: _draft.useRelatedSources,
          highImpact: true,
          onChanged: (value) => _set(_draft.copyWith(useRelatedSources: value)),
        ),
        _divider(),
        _toggle(
          icon: YuLiIcons.listChecks,
          title: 'CONSULTAR TAREAS Y PROYECTOS',
          detail:
              'Puede revisar Fight y Lab. Una consulta puede usar llamadas extra.',
          value: _draft.useTools,
          highImpact: true,
          onChanged: (value) => _set(_draft.copyWith(useTools: value)),
        ),
      ],
    ),
  );

  Widget _capabilities() => AiSectionCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _capabilitiesOpen = !_capabilitiesOpen),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                Icon(YuLiIcons.sparkles, size: 17, color: widget.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FUNCIONES ADICIONALES',
                        style: yBody(
                          size: 11.5,
                          weight: FontWeight.w800,
                          color: aiInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _capabilitiesSummary,
                        style: yBody(size: 10.5, color: aiMuted),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _capabilitiesOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    YuLiIcons.chevronDown,
                    size: 17,
                    color: aiMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child:
              _capabilitiesOpen
                  ? Column(
                    children: [
                      _divider(),
                      _toggle(
                        icon: YuLiIcons.lightbulb,
                        title: 'RAZONAMIENTO PROFUNDO',
                        detail:
                            'Dedica más tokens a problemas difíciles antes de responder. Actívalo sólo cuando realmente necesites más análisis.',
                        value: _draft.useDeepReasoning,
                        highImpact: true,
                        onChanged:
                            (value) =>
                                _set(_draft.copyWith(useDeepReasoning: value)),
                      ),
                      _divider(),
                      _toggle(
                        icon: YuLiIcons.sparkles,
                        title: 'RESPUESTAS INTERACTIVAS',
                        detail:
                            'Permite quizzes, tarjetas, pasos y ejemplos visuales.',
                        value: _draft.useInteractiveReplies,
                        onChanged:
                            (value) => _set(
                              _draft.copyWith(useInteractiveReplies: value),
                            ),
                      ),
                      _divider(),
                      _toggle(
                        icon: YuLiIcons.brain,
                        title: 'USAR RECUERDOS GUARDADOS',
                        detail:
                            'Usa preferencias y datos que aceptaste guardar.',
                        value: _draft.useMemory,
                        onChanged:
                            (value) => _set(_draft.copyWith(useMemory: value)),
                      ),
                      _divider(),
                      _toggle(
                        icon: YuLiIcons.squareCheck,
                        title: 'PREPARAR ACCIONES',
                        detail:
                            'Propone tareas o tarjetas y siempre pide confirmación.',
                        value: _draft.useActionDrafts,
                        onChanged:
                            (value) =>
                                _set(_draft.copyWith(useActionDrafts: value)),
                      ),
                    ],
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    ),
  );

  String get _capabilitiesSummary {
    final active =
        [
          _draft.useDeepReasoning,
          _draft.useInteractiveReplies,
          _draft.useMemory,
          _draft.useActionDrafts,
        ].where((value) => value).length;
    return active == 0
        ? 'Todo desactivado'
        : active == 1
        ? '1 función activa'
        : '$active funciones activas';
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
      Text(text, key: ValueKey(text), style: yBody(size: 11, color: aiMuted));

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      label,
      style: yBody(size: 11, weight: FontWeight.w800, color: aiInk),
    ),
  );

  Widget _subLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: yBody(size: 11, weight: FontWeight.w700, color: aiMuted),
    ),
  );

  Widget _impactLegend() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: widget.accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: widget.accent.withValues(alpha: 0.16)),
    ),
    child: Row(
      children: [
        _impactSquare(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'EL CUADRADO MARCA OPCIONES QUE PUEDEN AUMENTAR MUCHO EL GASTO',
            style: yBody(size: 9.5, weight: FontWeight.w700, color: aiInk),
          ),
        ),
      ],
    ),
  );

  Widget _conversationActions() => LayoutBuilder(
    builder: (context, constraints) {
      final summarize = _conversationAction(
        icon: YuLiIcons.textQuote,
        label: 'RESUMIR EL CHAT',
        onTap: () => _finish(summarize: true),
      );
      final clear = _conversationAction(
        icon: YuLiIcons.trash,
        label: 'LIMPIAR CONVERSACIÓN',
        onTap: () => _finish(clearConversation: true),
      );
      if (constraints.maxWidth < 430) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canSummarize) summarize,
            if (widget.canSummarize && widget.canClearConversation)
              const SizedBox(height: 8),
            if (widget.canClearConversation) clear,
          ],
        );
      }
      return Row(
        children: [
          if (widget.canSummarize) Expanded(child: summarize),
          if (widget.canSummarize && widget.canClearConversation)
            const SizedBox(width: 8),
          if (widget.canClearConversation) Expanded(child: clear),
        ],
      );
    },
  );

  Widget _conversationAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aiHairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: widget.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: yBody(size: 10.5, weight: FontWeight.w800, color: aiInk),
            ),
          ),
          const Icon(YuLiIcons.arrowRight, size: 15, color: aiMuted),
        ],
      ),
    ),
  );

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected ? widget.accent : Colors.white.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: selected ? widget.accent : aiHairline),
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
                style: yBody(
                  size: 9.5,
                  weight: FontWeight.w800,
                  color: selected ? Colors.white : aiInk,
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
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            selected
                ? widget.accent.withValues(alpha: 0.11)
                : Colors.white.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? widget.accent.withValues(alpha: 0.38) : aiHairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highImpact) ...[_impactSquare(), const SizedBox(width: 5)],
              Text(
                label,
                style: yBody(
                  size: 11,
                  weight: FontWeight.w800,
                  color: selected ? widget.accent : aiInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(detail, style: yBody(size: 10, color: aiMuted)),
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    values[i] == selected
                        ? widget.accent
                        : Colors.white.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: values[i] == selected ? widget.accent : aiHairline,
                ),
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
                    style: yBody(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: values[i] == selected ? Colors.white : aiInk,
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
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  value ? widget.accent.withValues(alpha: 0.11) : aiPaperSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 16, color: value ? widget.accent : aiMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: yBody(
                          size: 10.5,
                          weight: FontWeight.w800,
                          color: aiInk,
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
                Text(detail, style: yBody(size: 10.5, color: aiMuted)),
              ],
            ),
          ),
          const SizedBox(width: 9),
          AiSoftToggle(value: value, accent: widget.accent),
        ],
      ),
    ),
  );

  Widget _cacheNote() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: aiHairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(YuLiIcons.info, size: 16, color: widget.accent),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Las reglas de YuLi siempre se envían. El contexto y las funciones sólo se añaden cuando están activados. Mantenerlos estables ayuda a reutilizar la caché.',
            style: yBody(size: 10.5, weight: FontWeight.w600, color: aiMuted),
          ),
        ),
      ],
    ),
  );

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: aiHairline, indent: 56);

  Widget _impactSquare({bool inverted = false}) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: inverted ? Colors.white : widget.accent,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _impactChip({required bool active}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: active ? widget.accent.withValues(alpha: 0.11) : aiPaperSoft,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _impactSquare(),
        const SizedBox(width: 4),
        Text(
          'MÁS GASTO',
          style: yBody(
            size: 7.5,
            weight: FontWeight.w800,
            color: active ? widget.accent : aiMuted,
          ),
        ),
      ],
    ),
  );
}
