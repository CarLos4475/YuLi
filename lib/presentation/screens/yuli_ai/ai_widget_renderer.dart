import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/reminder_preset.dart';
import '../../../domain/models/task.dart';
import '../../providers/database_providers.dart';
import '../../providers/ai_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../flight/note_block_widgets.dart'
    show MarkdownBlockActions, NoteMarkdownPreview, fixMarkdownTables;
import 'ai_widget_contracts.dart';

class AiWidgetRenderer extends ConsumerWidget {
  final String text;
  final Color accent;
  final AiWidgetSurface surface;
  final void Function(String message)? onSendMessage;
  final void Function(String message)? onActionResult;
  final ValueChanged<String>? onCopyBlock;
  final ValueChanged<String>? onPinBlock;
  final int? noteId;

  const AiWidgetRenderer({
    super.key,
    required this.text,
    required this.accent,
    required this.surface,
    this.onSendMessage,
    this.onActionResult,
    this.onCopyBlock,
    this.onPinBlock,
    this.noteId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = AiWidgetParser.parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _part(context, ref, parts[i]),
        ],
      ],
    );
  }

  Widget _part(BuildContext context, WidgetRef ref, AiWidgetPart part) {
    if (part is AiWidgetTextPart) {
      return NoteMarkdownPreview(
        data: fixMarkdownTables(part.text),
        accent: accent,
        onCopyBlock: onCopyBlock,
        onPinBlock: onPinBlock,
      );
    }
    if (part is! AiWidgetBlockPart) return const SizedBox.shrink();
    return switch (part.type) {
      'CONCEPT_CARD' => _ConceptCardWidget(data: part.data, accent: accent),
      'SOLVED_EXAMPLE' => _SolvedExampleWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'STEPS' => _StepsWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'COMPARISON' => _ComparisonWidget(data: part.data, accent: accent),
      'FLASHCARDS' ||
      'FLASHCARD' ||
      'FLASH_CARD' => _FlashcardsWidget(data: part.data, accent: accent),
      'CHECKLIST' => _ChecklistWidget(data: part.data, accent: accent),
      'FORMULA_CARD' => _FormulaCardWidget(
        data: part.data,
        accent: accent,
        onCopyBlock: onCopyBlock,
        onPinBlock: onPinBlock,
      ),
      'MISTAKE_CHECK' => _MistakeCheckWidget(data: part.data, accent: accent),
      'MINI_PROOF' => _MiniProofWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'PRACTICE_SET' => _PracticeSetWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'HINT_LADDER' => _HintLadderWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'VOCAB_CARD' => _VocabCardWidget(data: part.data, accent: accent),
      'TIMELINE' => _TimelineWidget(data: part.data, accent: accent),
      'FLOWCHART' => _FlowchartWidget(data: part.data, accent: accent),
      'CAUSE_EFFECT' ||
      'CAUSEEFFECT' => _CauseEffectWidget(data: part.data, accent: accent),
      'GRAPH_SKETCH' ||
      'GRAPH' ||
      'CHART_SKETCH' => _GraphSketchWidget(data: part.data, accent: accent),
      'MNEMONIC' => _MnemonicWidget(data: part.data, accent: accent),
      'EXAM_RUBRIC' => _ExamRubricWidget(data: part.data, accent: accent),
      'QUIZ' => _QuizWidget(data: part.data, accent: accent),
      'OPTIONS' => _OptionsWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'TASK_LIST' => _TaskListWidget(data: part.data),
      'TASK_DRAFT' => _TaskDraftWidget(
        data: part.data,
        onActionResult: onActionResult,
        noteId: noteId,
      ),
      'LAB_CARD_DRAFT' => _LabCardDraftWidget(
        data: part.data,
        onActionResult: onActionResult,
      ),
      'MEMORY_SUGGESTION' => _MemorySuggestionWidget(
        data: part.data,
        accent: accent,
        onActionResult: onActionResult,
      ),
      _ => _UnknownWidget(type: part.type, accent: accent),
    };
  }
}

class _SolvedExampleWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _SolvedExampleWidget({
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'] ?? data['problem'], 'Ejemplo resuelto');
    final setup = _string(data['setup'] ?? data['given'], '');
    final steps = _list(data['steps']);
    final result = _string(data['result'] ?? data['finalResult'], '');
    final intuition = _string(data['intuition'] ?? data['note'], '');
    return _WidgetFrame(
      title: 'Ejemplo',
      icon: YuLiIcons.box,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 20, weight: FontWeight.w900, color: yInk),
          ),
          if (setup.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.info,
              label: 'Planteamiento',
              text: setup,
              color: accent,
            ),
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 360;
              final gap = twoCols ? 10.0 : 0.0;
              final width =
                  twoCols
                      ? (constraints.maxWidth - gap) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    _SolvedStepCard(
                      index: i + 1,
                      data: steps[i],
                      width: width,
                      accent: accent,
                      onSendMessage: onSendMessage,
                    ),
                ],
              );
            },
          ),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ResultStrip(result: result, accent: accent),
          ],
          if (intuition.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.lightbulb,
              label: 'Intuición',
              text: intuition,
              color: accent,
            ),
          ],
          if (onSendMessage != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniActionButton(
                  label: 'Profundiza',
                  icon: YuLiIcons.search,
                  color: accent,
                  onTap:
                      () => onSendMessage!(
                        'Profundiza este ejemplo resuelto: $title',
                      ),
                ),
                _MiniActionButton(
                  label: 'Más simple',
                  icon: YuLiIcons.listChecks,
                  color: accent,
                  onTap:
                      () => onSendMessage!(
                        'Explícame este ejemplo resuelto más simple: $title',
                      ),
                ),
                _MiniActionButton(
                  label: 'Otro ejemplo',
                  icon: YuLiIcons.box,
                  color: accent,
                  onTap:
                      () => onSendMessage!(
                        'Dame otro ejemplo parecido a este: $title',
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SolvedStepCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> data;
  final double width;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _SolvedStepCard({
    required this.index,
    required this.data,
    required this.width,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'] ?? data['title'], 'Paso $index');
    final detail = _string(data['detail'] ?? data['explanation'], '');
    final formula = _string(data['formula'] ?? data['math'], '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _sendStepQuestion(index, label, detail, onSendMessage),
      child: SizedBox(
        width: width,
        child: Container(
          constraints: const BoxConstraints(minHeight: 130),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
          decoration: BoxDecoration(
            color: yCream2,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      border: Border.all(
                        color: yBorderStrong,
                        width: yLineThin,
                      ),
                    ),
                    child: Text(
                      '$index',
                      style: yMono(
                        size: 11,
                        weight: FontWeight.w900,
                        color: yCream,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _WidgetMarkdownText(
                      label,
                      accent: accent,
                      style: yBody(
                        size: 14,
                        weight: FontWeight.w900,
                        color: yInk,
                      ),
                    ),
                  ),
                  if (onSendMessage != null) ...[
                    const SizedBox(width: 7),
                    _TapHintIcon(accent: accent),
                  ],
                ],
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 9),
                _WidgetMarkdownText(
                  detail,
                  accent: accent,
                  style: yBody(size: 13, color: yInk2, height: 1.35),
                ),
              ],
              if (formula.isNotEmpty) ...[
                const SizedBox(height: 9),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: yCream,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  child: _WidgetMarkdownText(
                    formula,
                    accent: accent,
                    style: yBody(
                      size: 15,
                      weight: FontWeight.w500,
                      color: yInk,
                    ),
                    center: true,
                    formula: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultStrip extends StatelessWidget {
  final String result;
  final Color accent;

  const _ResultStrip({required this.result, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        border: Border.all(color: accent, width: yLineMid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: const Icon(YuLiIcons.star, size: 17, color: yCream),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _WidgetMarkdownText(
              result,
              accent: accent,
              style: yBody(size: 16, weight: FontWeight.w700, color: yInk),
              formula: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _ConceptCardWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Concepto');
    final definition = _string(data['definition'], '');
    final keyIdea = _string(data['keyIdea'], '');
    final example = _string(data['example'], '');
    return _WidgetFrame(
      title: 'Concepto',
      icon: YuLiIcons.lightbulb,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 20, weight: FontWeight.w900, color: yInk),
          ),
          if (definition.isNotEmpty) ...[
            const SizedBox(height: 8),
            _WidgetMarkdownText(
              definition,
              accent: accent,
              style: yBody(size: 14, color: yInk2, height: 1.4),
            ),
          ],
          if (keyIdea.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.sparkles,
              label: 'Idea clave',
              text: keyIdea,
              color: accent,
            ),
          ],
          if (example.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.bookOpen,
              label: 'Ejemplo',
              text: example,
              color: yAmber,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepsWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _StepsWidget({
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Pasos');
    final items = _list(data['items']);
    return _WidgetFrame(
      title: 'Pasos',
      icon: YuLiIcons.listChecks,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            _StepRow(
              index: i + 1,
              data: items[i],
              accent: accent,
              onSendMessage: onSendMessage,
            ),
            if (i != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _StepRow({
    required this.index,
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'], 'Paso $index');
    final detail = _string(data['detail'], '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _sendStepQuestion(index, label, detail, onSendMessage),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                '$index',
                style: yMono(size: 11, weight: FontWeight.w900, color: yCream),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WidgetMarkdownText(
                    label,
                    accent: accent,
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w900,
                      color: yInk,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _WidgetMarkdownText(
                      detail,
                      accent: accent,
                      style: yBody(size: 13, color: yInk2, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            if (onSendMessage != null) ...[
              const SizedBox(width: 7),
              _TapHintIcon(accent: accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparisonWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _ComparisonWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Comparación');
    final left = _string(data['leftLabel'], 'A');
    final right = _string(data['rightLabel'], 'B');
    final rows = _list(data['rows']);
    return _WidgetFrame(
      title: 'Comparación',
      icon: YuLiIcons.scale,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _CompareHeader(label: left, color: accent)),
              const SizedBox(width: 8),
              Expanded(child: _CompareHeader(label: right, color: yAmber)),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CompareCell(
                    text: _string(row['left'], ''),
                    accent: accent,
                    pale: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompareCell(
                    text: _string(row['right'], ''),
                    accent: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _CompareHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _CompareHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Text(
        _sentence(label),
        textAlign: TextAlign.center,
        style: yMono(
          size: 10,
          weight: FontWeight.w900,
          tracking: 0.7,
          color: yCream,
        ),
      ),
    );
  }
}

class _CompareCell extends StatelessWidget {
  final String text;
  final Color accent;
  final bool pale;

  const _CompareCell({
    required this.text,
    required this.accent,
    this.pale = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: pale ? yCream2 : yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: _WidgetMarkdownText(
        text,
        accent: accent,
        style: yBody(size: 13, weight: FontWeight.w700, color: yInk),
      ),
    );
  }
}

class _FlashcardsWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _FlashcardsWidget({required this.data, required this.accent});

  @override
  State<_FlashcardsWidget> createState() => _FlashcardsWidgetState();
}

class _FlashcardsWidgetState extends State<_FlashcardsWidget> {
  final Set<int> _flipped = {};
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Tarjetas');
    final cards = _flashcardItems(widget.data);
    final current = cards.isEmpty ? 0 : _current.clamp(0, cards.length - 1);
    return _WidgetFrame(
      title: 'Flashcards',
      icon: YuLiIcons.bookOpen,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: widget.accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          if (cards.isEmpty)
            _StatusStrip(color: yAmber, text: 'No hay tarjetas disponibles')
          else ...[
            _flashcard(current, cards[current]),
            if (cards.length > 1) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  _FlashcardNavButton(
                    icon: YuLiIcons.chevronLeft,
                    label: 'Tarjeta anterior',
                    accent: widget.accent,
                    enabled: current > 0,
                    onTap: () => setState(() => _current--),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${current + 1} DE ${cards.length}',
                          style: yMono(
                            size: 10,
                            weight: FontWeight.w900,
                            tracking: 1,
                            color: yInk,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _SegmentedProgress(
                          count: cards.length,
                          active: current,
                          accent: widget.accent,
                        ),
                      ],
                    ),
                  ),
                  _FlashcardNavButton(
                    icon: YuLiIcons.chevronRight,
                    label: 'Tarjeta siguiente',
                    accent: widget.accent,
                    enabled: current < cards.length - 1,
                    onTap: () => setState(() => _current++),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _flashcard(int index, Map<String, dynamic> data) {
    final flipped = _flipped.contains(index);
    final front = _string(
      data['front'] ?? data['question'] ?? data['term'] ?? data['prompt'],
      'Pregunta',
    );
    final back = _string(
      data['back'] ?? data['answer'] ?? data['definition'] ?? data['response'],
      'Respuesta',
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          flipped ? _flipped.remove(index) : _flipped.add(index);
        });
        HapticFeedback.selectionClick();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: BoxDecoration(
          color: flipped ? widget.accent : yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow:
              flipped
                  ? const [
                    BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                  ]
                  : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              flipped ? 'Respuesta' : 'Pregunta',
              style: yMono(
                size: 9,
                weight: FontWeight.w900,
                tracking: 1.1,
                color: flipped ? yCream : yMuted,
              ),
            ),
            const SizedBox(height: 6),
            _WidgetMarkdownText(
              flipped ? back : front,
              accent: widget.accent,
              style: yBody(
                size: 14,
                weight: FontWeight.w800,
                color: flipped ? yCream : yInk,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _FlashcardNavButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            enabled
                ? () {
                  onTap();
                  HapticFeedback.selectionClick();
                }
                : null,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? accent : yCream2,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Icon(icon, size: 17, color: enabled ? yCream : yMuted),
        ),
      ),
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  final int count;
  final int active;
  final Color accent;

  const _SegmentedProgress({
    required this.count,
    required this.active,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == active ? 18 : 8,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: i == active ? accent : yMuted.withValues(alpha: 0.35),
          ),
      ],
    );
  }
}

class _ChecklistWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _ChecklistWidget({required this.data, required this.accent});

  @override
  State<_ChecklistWidget> createState() => _ChecklistWidgetState();
}

class _ChecklistWidgetState extends State<_ChecklistWidget> {
  late final Set<int> _checked = _initialChecked();

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Checklist');
    final items = _list(widget.data['items']);
    final completed = _checked.where((index) => index < items.length).length;
    return _WidgetFrame(
      title: 'Checklist',
      icon: YuLiIcons.squareCheck,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: widget.accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 10),
          _ChecklistProgress(
            completed: completed,
            total: items.length,
            accent: widget.accent,
          ),
          if (items.isNotEmpty) const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            _checkRow(i, _string(items[i]['label'], 'Elemento')),
            if (i != items.length - 1) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }

  Widget _checkRow(int index, String label) {
    final active = _checked.contains(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          active ? _checked.remove(index) : _checked.add(index);
        });
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          children: [
            Icon(
              active ? YuLiIcons.squareCheck : YuLiIcons.square,
              size: 18,
              color: active ? widget.accent : yMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _WidgetMarkdownText(
                label,
                accent: widget.accent,
                style: yBody(
                  size: 14,
                  weight: FontWeight.w800,
                  color: active ? yMuted : yInk,
                ).copyWith(
                  decoration:
                      active ? TextDecoration.lineThrough : TextDecoration.none,
                  decorationColor: active ? yMuted : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Set<int> _initialChecked() {
    final items = _list(widget.data['items']);
    return {
      for (var i = 0; i < items.length; i++)
        if (items[i]['checked'] == true) i,
    };
  }
}

class _ChecklistProgress extends StatelessWidget {
  final int completed;
  final int total;
  final Color accent;

  const _ChecklistProgress({
    required this.completed,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                total == 0 ? 'Sin elementos' : '$completed DE $total LISTOS',
                style: yMono(
                  size: 9,
                  weight: FontWeight.w900,
                  tracking: 0.9,
                  color: total > 0 && completed == total ? accent : yMuted,
                ),
              ),
            ),
            if (total > 0)
              Text(
                '${(progress * 100).round()}%',
                style: yMono(size: 9, weight: FontWeight.w900, color: yInk),
              ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 6),
          LayoutBuilder(
            builder:
                (_, constraints) => Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: yCream2,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: math.max(
                      0,
                      (constraints.maxWidth - yLineThin * 2) * progress,
                    ),
                    color: accent,
                  ),
                ),
          ),
        ],
      ],
    );
  }
}

class _FormulaCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final ValueChanged<String>? onCopyBlock;
  final ValueChanged<String>? onPinBlock;

  const _FormulaCardWidget({
    required this.data,
    required this.accent,
    this.onCopyBlock,
    this.onPinBlock,
  });

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Formula');
    final formula = _string(data['formula'] ?? data['math'], '');
    final variables = _list(data['variables']);
    final whenToUse = _string(data['whenToUse'] ?? data['use'], '');
    final example = _string(data['example'], '');
    final cleanFormula = _formulaArtifactContent(formula);
    return _WidgetFrame(
      title: 'Formula',
      icon: YuLiIcons.sigma,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          if (formula.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              decoration: BoxDecoration(
                color: yCream2,
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: _WidgetMarkdownText(
                formula,
                accent: accent,
                style: ySans(size: 18, weight: FontWeight.w500, color: yInk),
                center: true,
                formula: true,
              ),
            ),
            if (cleanFormula.isNotEmpty &&
                (onCopyBlock != null || onPinBlock != null)) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: MarkdownBlockActions(
                  accent: accent,
                  onCopy:
                      onCopyBlock == null
                          ? null
                          : () => onCopyBlock!(cleanFormula),
                  onPin:
                      onPinBlock == null
                          ? null
                          : () => onPinBlock!('\$\$\n$cleanFormula\n\$\$'),
                ),
              ),
            ],
          ],
          if (variables.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variable in variables)
                  _FormulaVariableChip(data: variable, accent: accent),
              ],
            ),
          ],
          if (whenToUse.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.lightbulb,
              label: 'Cuándo usar',
              text: whenToUse,
              color: accent,
            ),
          ],
          if (example.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.box,
              label: 'Ejemplo',
              text: example,
              color: yAmber,
            ),
          ],
        ],
      ),
    );
  }
}

class _FormulaVariableChip extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _FormulaVariableChip({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final symbol = _string(data['symbol'] ?? data['name'], 'x');
    final meaning = _string(data['meaning'] ?? data['label'], '');
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: _WidgetMarkdownText(
              symbol,
              accent: accent,
              style: yMono(size: 10, weight: FontWeight.w900, color: yCream),
            ),
          ),
          if (meaning.isNotEmpty) ...[
            const SizedBox(width: 7),
            Flexible(
              child: _WidgetMarkdownText(
                meaning,
                accent: accent,
                style: yBody(size: 12, weight: FontWeight.w800, color: yInk),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MistakeCheckWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _MistakeCheckWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Errores comunes');
    final items = _list(data['items']);
    return _WidgetFrame(
      title: 'Cuidado',
      icon: YuLiIcons.triangleAlert,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            _MistakeRow(data: items[i], accent: accent),
            if (i != items.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _MistakeRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _MistakeRow({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final mistake = _string(data['mistake'] ?? data['error'], 'Error comun');
    final why = _string(data['why'] ?? data['reason'], '');
    final fix = _string(data['fix'] ?? data['correction'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CalloutLine(
            icon: YuLiIcons.xSquare,
            label: 'Error',
            text: mistake,
            color: yFight,
          ),
          if (why.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CalloutLine(
              icon: YuLiIcons.helpCircle,
              label: 'Por qué',
              text: why,
              color: accent,
            ),
          ],
          if (fix.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CalloutLine(
              icon: YuLiIcons.checkCheck,
              label: 'Corrección',
              text: fix,
              color: yLab,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniProofWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _MiniProofWidget({
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Prueba breve');
    final claim = _string(data['claim'] ?? data['statement'], '');
    final steps = _list(data['steps']);
    final conclusion = _string(data['conclusion'], '');
    return _WidgetFrame(
      title: 'Demostración',
      icon: YuLiIcons.graduationCap,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          if (claim.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.info,
              label: 'Afirmación',
              text: claim,
              color: accent,
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) ...[
            _StepRow(
              index: i + 1,
              data: steps[i],
              accent: accent,
              onSendMessage: onSendMessage,
            ),
            if (i != steps.length - 1) const SizedBox(height: 8),
          ],
          if (conclusion.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ResultStrip(result: conclusion, accent: accent),
          ],
        ],
      ),
    );
  }
}

class _PracticeSetWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _PracticeSetWidget({
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Práctica');
    final items = _list(data['items']);
    return _WidgetFrame(
      title: 'Práctica',
      icon: YuLiIcons.pencil,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            _PracticeItem(
              index: i + 1,
              data: items[i],
              accent: accent,
              onSendMessage: onSendMessage,
            ),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PracticeItem extends ConsumerStatefulWidget {
  final int index;
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _PracticeItem({
    required this.index,
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  ConsumerState<_PracticeItem> createState() => _PracticeItemState();
}

class _PracticeItemState extends ConsumerState<_PracticeItem> {
  bool _showHint = false;

  @override
  Widget build(BuildContext context) {
    final prompt = _string(
      widget.data['prompt'] ?? widget.data['question'],
      'Ejercicio',
    );
    final level = _string(widget.data['level'], '');
    final hint = _string(widget.data['hint'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: Text(
                  '${widget.index}',
                  style: yMono(
                    size: 11,
                    weight: FontWeight.w900,
                    color: yCream,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _WidgetMarkdownText(
                  prompt,
                  accent: widget.accent,
                  style: yBody(size: 14, weight: FontWeight.w900, color: yInk),
                ),
              ),
            ],
          ),
          if (level.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _MiniBadge(
                icon: YuLiIcons.graduationCap,
                label: level,
                color: widget.accent,
              ),
            ),
          ],
          if (_showHint && hint.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.lightbulb,
              label: 'Pista',
              text: hint,
              color: widget.accent,
            ),
          ],
          if (widget.onSendMessage != null || hint.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onSendMessage != null)
                  _MiniActionButton(
                    label: 'Resolver',
                    icon: YuLiIcons.play,
                    color: widget.accent,
                    onTap:
                        () => widget.onSendMessage!(
                          'Resuelve este ejercicio paso a paso: ${_plainWidgetText(prompt)}',
                        ),
                  ),
                if (hint.isNotEmpty)
                  _MiniActionButton(
                    label: _showHint ? 'Ocultar pista' : 'Ver pista',
                    icon: YuLiIcons.lightbulb,
                    color: widget.accent,
                    onTap: () {
                      setState(() => _showHint = !_showHint);
                      HapticFeedback.selectionClick();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HintLadderWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _HintLadderWidget({
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  State<_HintLadderWidget> createState() => _HintLadderWidgetState();
}

class _HintLadderWidgetState extends State<_HintLadderWidget> {
  int _visible = 1;

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Pistas');
    final hints = _list(widget.data['hints']);
    final visible = hints.isEmpty ? 0 : _visible.clamp(0, hints.length);
    return _WidgetFrame(
      title: 'Pistas',
      icon: YuLiIcons.lightbulb,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: widget.accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < visible; i++) ...[
            _HintRow(
              index: i + 1,
              data: hints[i],
              accent: widget.accent,
              onSendMessage: widget.onSendMessage,
            ),
            if (i != visible - 1) const SizedBox(height: 8),
          ],
          if (visible < hints.length) ...[
            const SizedBox(height: 10),
            _ActionButton(
              label: 'Revelar pista',
              icon: YuLiIcons.chevronDown,
              color: widget.accent,
              onTap: () => setState(() => _visible++),
            ),
          ],
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _HintRow({
    required this.index,
    required this.data,
    required this.accent,
    this.onSendMessage,
  });

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'], 'Pista $index');
    final text = _string(data['text'] ?? data['detail'], '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _sendStepQuestion(index, label, text, onSendMessage),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(YuLiIcons.lightbulb, size: 18, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WidgetMarkdownText(
                    label,
                    accent: accent,
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w900,
                      color: yInk,
                    ),
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _WidgetMarkdownText(
                      text,
                      accent: accent,
                      style: yBody(size: 13, color: yInk2, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            if (onSendMessage != null) ...[
              const SizedBox(width: 7),
              _TapHintIcon(accent: accent),
            ],
          ],
        ),
      ),
    );
  }
}

class _VocabCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _VocabCardWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final term = _string(data['term'] ?? data['title'], 'Término');
    final definition = _string(data['definition'], '');
    final example = _string(data['example'], '');
    final counterexample = _string(data['counterexample'], '');
    final mnemonic = _string(data['mnemonic'] ?? data['memory'], '');
    return _WidgetFrame(
      title: 'Vocabulario',
      icon: YuLiIcons.bookOpen,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            term,
            accent: accent,
            style: ySans(size: 21, weight: FontWeight.w900, color: yInk),
          ),
          if (definition.isNotEmpty) ...[
            const SizedBox(height: 9),
            _WidgetMarkdownText(
              definition,
              accent: accent,
              style: yBody(size: 14, color: yInk2, height: 1.4),
            ),
          ],
          if (example.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.check,
              label: 'Ejemplo',
              text: example,
              color: yLab,
            ),
          ],
          if (counterexample.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.xSquare,
              label: 'Contraejemplo',
              text: counterexample,
              color: yFight,
            ),
          ],
          if (mnemonic.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.brain,
              label: 'Mnemotecnia',
              text: mnemonic,
              color: accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _MnemonicWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _MnemonicWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Mnemotecnia');
    final phrase = _string(
      data['mnemonic'] ?? data['phrase'] ?? data['hook'],
      '',
    );
    final meaning = _string(data['meaning'] ?? data['explanation'], '');
    final items =
        _list(data['items']).isNotEmpty
            ? _list(data['items'])
            : _list(data['chunks']);
    return _WidgetFrame(
      title: 'Mnemotecnia',
      icon: YuLiIcons.brain,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          if (phrase.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: _WidgetMarkdownText(
                phrase,
                accent: accent,
                style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
              ),
            ),
          ],
          if (meaning.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.lightbulb,
              label: 'Cómo usarla',
              text: meaning,
              color: accent,
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++) ...[
              _MnemonicChunk(data: items[i], accent: accent),
              if (i != items.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _MnemonicChunk extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _MnemonicChunk({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cue = _string(
      data['cue'] ?? data['letter'] ?? data['label'],
      'Clave',
    );
    final text = _string(data['text'] ?? data['meaning'] ?? data['detail'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 30),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: _WidgetMarkdownText(
              cue,
              accent: accent,
              style: yMono(size: 10, weight: FontWeight.w900, color: yCream),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(width: 9),
            Expanded(
              child: _WidgetMarkdownText(
                text,
                accent: accent,
                style: yBody(size: 13, weight: FontWeight.w800, color: yInk),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _TimelineWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Linea de tiempo');
    final events =
        _list(data['events']).isNotEmpty
            ? _list(data['events'])
            : _list(data['entries']);
    return _WidgetFrame(
      title: 'Timeline',
      icon: YuLiIcons.timeline,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < events.length; i++)
            _TimelineEvent(
              data: events[i],
              accent: accent,
              first: i == 0,
              last: i == events.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final bool first;
  final bool last;

  const _TimelineEvent({
    required this.data,
    required this.accent,
    required this.first,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    final date = _string(data['date'] ?? data['time'], '');
    final name = _string(data['label'] ?? data['name'], '');
    final label = _string(date.isNotEmpty ? date : name, 'Evento');
    final detail = [
      if (date.isNotEmpty && name.isNotEmpty) name,
      _string(data['detail'] ?? data['text'], ''),
    ].where((item) => item.isNotEmpty).join('\n');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 3,
                    color: first ? Colors.transparent : yBorderStrong,
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    border: Border.all(color: yBorderStrong, width: yLineThin),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 3,
                    color: last ? Colors.transparent : yBorderStrong,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 9),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                decoration: BoxDecoration(
                  color: yCream2,
                  border: Border.all(color: yBorderStrong, width: yLineThin),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WidgetMarkdownText(
                      label,
                      accent: accent,
                      style: yMono(
                        size: 11,
                        weight: FontWeight.w900,
                        tracking: 0.8,
                        color: yInk,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _WidgetMarkdownText(
                        detail,
                        accent: accent,
                        style: yBody(size: 12, color: yInk2, height: 1.25),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowchartWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _FlowchartWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Flujo');
    final nodes =
        _list(data['nodes']).isNotEmpty
            ? _list(data['nodes'])
            : _list(data['steps']).isNotEmpty
            ? _list(data['steps'])
            : _list(data['items']);
    return _WidgetFrame(
      title: 'Flujo',
      icon: YuLiIcons.gitGraph,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < nodes.length; i++) ...[
            _FlowNode(index: i + 1, data: nodes[i], accent: accent),
            if (i != nodes.length - 1) ...[
              const SizedBox(height: 8),
              _ArrowDivider(color: accent),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _FlowNode extends StatelessWidget {
  final int index;
  final Map<String, dynamic> data;
  final Color accent;

  const _FlowNode({
    required this.index,
    required this.data,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'] ?? data['title'], 'Paso $index');
    final detail = _string(data['detail'] ?? data['text'] ?? data['body'], '');
    final kind = _string(data['kind'] ?? data['type'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Text(
              '$index',
              style: yMono(size: 11, weight: FontWeight.w900, color: yCream),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _WidgetMarkdownText(
                        label,
                        accent: accent,
                        style: yBody(
                          size: 14,
                          weight: FontWeight.w900,
                          color: yInk,
                        ),
                      ),
                    ),
                    if (kind.isNotEmpty) ...[
                      const SizedBox(width: 7),
                      _MiniBadge(
                        icon: YuLiIcons.gitGraph,
                        label: kind,
                        color: accent,
                      ),
                    ],
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _WidgetMarkdownText(
                    detail,
                    accent: accent,
                    style: yBody(size: 13, color: yInk2, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CauseEffectWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _CauseEffectWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Causa y efecto');
    final cause = _string(
      data['cause'] ?? data['causa'] ?? data['input'],
      _joinTextList(data['causes'] ?? data['causas']),
    );
    final mechanism = _string(
      data['mechanism'] ?? data['bridge'] ?? data['proceso'] ?? data['link'],
      _joinTextList(data['mechanisms'] ?? data['bridges']),
    );
    final effect = _string(
      data['effect'] ?? data['efecto'] ?? data['output'],
      _joinTextList(data['effects'] ?? data['efectos']),
    );
    return _WidgetFrame(
      title: 'Causa efecto',
      icon: YuLiIcons.gitGraph,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          _CauseBox(label: 'Causa', text: cause, color: accent),
          if (mechanism.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArrowDivider(color: accent),
            const SizedBox(height: 8),
            _CauseBox(label: 'Mecanismo', text: mechanism, color: yAmber),
          ],
          if (effect.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ArrowDivider(color: accent),
            const SizedBox(height: 8),
            _CauseBox(label: 'Efecto', text: effect, color: yLab),
          ],
        ],
      ),
    );
  }
}

class _CauseBox extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _CauseBox({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: yMono(
              size: 9,
              weight: FontWeight.w900,
              tracking: 1,
              color: color,
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 5),
            _WidgetMarkdownText(
              text,
              accent: color,
              style: yBody(size: 14, weight: FontWeight.w800, color: yInk),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrowDivider extends StatelessWidget {
  final Color color;

  const _ArrowDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 2, color: yBorderStrong)),
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: const Icon(YuLiIcons.chevronDown, size: 16, color: yCream),
        ),
        Expanded(child: Container(height: 2, color: yBorderStrong)),
      ],
    );
  }
}

class _GraphSketchWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _GraphSketchWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Boceto de gráfica');
    final description = _string(data['description'], '');
    final xLabel = _string(data['xLabel'], 'x');
    final yLabel = _string(data['yLabel'], 'y');
    final features = _list(data['features']);
    return _WidgetFrame(
      title: 'Gráfica',
      icon: YuLiIcons.gitGraph,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          Container(
            height: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: yCream2,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GraphSketchPainter(
                      color: accent,
                      description: '$title $description',
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: _AxisLabel(label: yLabel, accent: accent),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _AxisLabel(label: xLabel, accent: accent),
                ),
              ],
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            _WidgetMarkdownText(
              description,
              accent: accent,
              style: yBody(size: 13, color: yInk2, height: 1.35),
            ),
          ],
          if (features.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final feature in features)
                  _FeaturePill(data: feature, accent: accent),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GraphSketchPainter extends CustomPainter {
  final Color color;
  final String description;

  const _GraphSketchPainter({required this.color, required this.description});

  @override
  void paint(Canvas canvas, Size size) {
    final axis =
        Paint()
          ..color = yBorderStrong
          ..strokeWidth = 2;
    final curve =
        Paint()
          ..color = color
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
    final origin = Offset(20, size.height - 22);
    canvas.drawLine(Offset(origin.dx, 8), origin, axis);
    canvas.drawLine(origin, Offset(size.width - 8, origin.dy), axis);
    final path = _graphPath(size, origin, description.toLowerCase());
    canvas.drawPath(path, curve);
  }

  @override
  bool shouldRepaint(covariant _GraphSketchPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.description != description;
  }
}

Path _graphPath(Size size, Offset origin, String description) {
  final left = origin.dx + 4;
  final right = size.width - 18;
  final top = 16.0;
  final bottom = origin.dy - 7;
  if (description.contains('parábola') ||
      description.contains('parabola') ||
      description.contains('cuadrát')) {
    return Path()
      ..moveTo(left, top + 8)
      ..quadraticBezierTo(size.width * 0.5, bottom, right, top + 8);
  }
  if (description.contains('decrec') ||
      description.contains('negativa') ||
      description.contains('descendente')) {
    return Path()
      ..moveTo(left, top + 8)
      ..lineTo(right, bottom);
  }
  if (description.contains('recta') ||
      description.contains('lineal') ||
      description.contains('pendiente')) {
    return Path()
      ..moveTo(left, bottom)
      ..lineTo(right, top + 8);
  }
  if (description.contains('seno') ||
      description.contains('coseno') ||
      description.contains('ond')) {
    final path = Path()..moveTo(left, size.height * 0.5);
    final width = right - left;
    for (var i = 1; i <= 36; i++) {
      final progress = i / 36;
      path.lineTo(
        left + width * progress,
        size.height * 0.5 - math.sin(progress * math.pi * 2) * 34,
      );
    }
    return path;
  }
  if (description.contains('exponencial')) {
    return Path()
      ..moveTo(left, bottom)
      ..cubicTo(
        size.width * 0.5,
        bottom,
        size.width * 0.72,
        size.height * 0.62,
        right,
        top,
      );
  }
  return Path()
    ..moveTo(left, bottom - 2)
    ..cubicTo(
      size.width * 0.35,
      size.height * 0.85,
      size.width * 0.48,
      size.height * 0.22,
      right,
      size.height * 0.28,
    );
}

class _AxisLabel extends StatelessWidget {
  final String label;
  final Color accent;

  const _AxisLabel({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    final clean = _stripOuterMath(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: accent,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child:
            clean.contains('\\')
                ? Math.tex(
                  clean,
                  mathStyle: MathStyle.text,
                  textStyle: yMono(
                    size: 10,
                    weight: FontWeight.w900,
                    color: yCream,
                  ),
                  onErrorFallback:
                      (_) => Text(
                        _plainWidgetText(label),
                        overflow: TextOverflow.ellipsis,
                        style: yMono(
                          size: 10,
                          weight: FontWeight.w900,
                          color: yCream,
                        ),
                      ),
                )
                : Text(
                  _plainWidgetText(label),
                  overflow: TextOverflow.ellipsis,
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w900,
                    color: yCream,
                  ),
                ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _FeaturePill({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'] ?? data['name'], 'Dato');
    final value = _string(data['value'] ?? data['text'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _sentence(label),
            style: yMono(
              size: 9,
              weight: FontWeight.w900,
              tracking: 0.7,
              color: accent,
            ),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 6),
            _WidgetMarkdownText(
              value,
              accent: accent,
              style: yBody(size: 12, weight: FontWeight.w800, color: yInk),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExamRubricWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _ExamRubricWidget({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Guía de examen');
    final focus = _string(data['focus'], '');
    final criteria = _list(data['criteria']);
    final traps = _list(data['traps']);
    return _WidgetFrame(
      title: 'Examen',
      icon: YuLiIcons.clipboard,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            title,
            accent: accent,
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          if (focus.isNotEmpty) ...[
            const SizedBox(height: 10),
            _CalloutStrip(
              icon: YuLiIcons.star,
              label: 'Enfoque',
              text: focus,
              color: accent,
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < criteria.length; i++) ...[
            _RubricRow(data: criteria[i], accent: accent),
            if (i != criteria.length - 1) const SizedBox(height: 8),
          ],
          if (traps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CalloutStrip(
              icon: YuLiIcons.triangleAlert,
              label: 'Trampas',
              text: traps
                  .map((item) => _string(item['label'] ?? item['text'], ''))
                  .where((item) => item.isNotEmpty)
                  .join('\n'),
              color: yFight,
            ),
          ],
        ],
      ),
    );
  }
}

class _RubricRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _RubricRow({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'] ?? data['criterion'], 'Criterio');
    final weight = _string(data['weight'], '');
    final detail = _string(data['detail'], '');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 42),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Text(
              weight.isEmpty ? 'OK' : weight,
              style: yMono(size: 10, weight: FontWeight.w900, color: yCream),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WidgetMarkdownText(
                  label,
                  accent: accent,
                  style: yBody(size: 14, weight: FontWeight.w900, color: yInk),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _WidgetMarkdownText(
                    detail,
                    accent: accent,
                    style: yBody(size: 13, color: yInk2, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _QuizWidget({required this.data, required this.accent});

  @override
  State<_QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<_QuizWidget> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final question = _string(
      widget.data['question'] ?? widget.data['prompt'] ?? widget.data['title'],
      'Pregunta',
    );
    final options = _quizOptions(widget.data);
    final answer = _normalizeQuizAnswer(
      widget.data['answer'] ??
          widget.data['correctAnswer'] ??
          widget.data['correct'] ??
          widget.data['solution'],
      options,
    );
    final explanation = _string(widget.data['explanation'], '');
    return _WidgetFrame(
      title: 'Quiz',
      icon: YuLiIcons.listChecks,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WidgetMarkdownText(
            question,
            accent: widget.accent,
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final option in options) ...[
              _quizOption(option, answer),
              const SizedBox(height: 8),
            ],
          ] else ...[
            const SizedBox(height: 12),
            _StatusStrip(
              color: yAmber,
              text: 'Faltan opciones para hacerlo interactivo',
            ),
          ],
          if (_selected != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            _StatusStrip(
              color: _selected == answer ? yLab : yFight,
              text: _selected == answer ? 'Correcto' : 'Revisa la explicación',
            ),
            const SizedBox(height: 8),
            _WidgetMarkdownText(
              explanation,
              accent: widget.accent,
              style: yBody(size: 13, color: yInk2, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quizOption(Map<String, dynamic> option, String answer) {
    final id = _string(option['id'] ?? option['key'], '');
    final label = _string(
      option['label'] ?? option['text'] ?? option['value'] ?? option['answer'],
      id.toUpperCase(),
    );
    final selected = _selected == id;
    final answered = _selected != null;
    final correct = answered && id == answer;
    final wrong = selected && id != answer;
    final color = correct ? yLab : (wrong ? yFight : widget.accent);
    final highlighted = correct || wrong;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selected = id);
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: highlighted ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highlighted ? yCream : color,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                id.toUpperCase(),
                style: yMono(
                  size: 11,
                  weight: FontWeight.w800,
                  color: highlighted ? yInk : yCream,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _sentence(label),
                style: yBody(
                  size: 14,
                  weight: FontWeight.w700,
                  color: highlighted ? yCream : yInk,
                ),
              ),
            ),
            if (correct || wrong) ...[
              const SizedBox(width: 8),
              Icon(
                correct ? YuLiIcons.check : YuLiIcons.close,
                size: 18,
                color: yCream,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionsWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onSendMessage;

  const _OptionsWidget({
    required this.data,
    required this.accent,
    required this.onSendMessage,
  });

  @override
  State<_OptionsWidget> createState() => _OptionsWidgetState();
}

class _OptionsWidgetState extends State<_OptionsWidget> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Elige una opción');
    final options = _list(widget.data['options']);
    return _WidgetFrame(
      title: 'Opciones',
      icon: YuLiIcons.sparkles,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(title),
            style: ySans(size: 17, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final option in options) _optionChip(option)],
          ),
        ],
      ),
    );
  }

  Widget _optionChip(Map<String, dynamic> option) {
    final id = _string(option['id'], _string(option['label'], 'opcion'));
    final label = _string(option['label'], id);
    final message = _string(option['message'], label);
    final selected = _selected == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selected = id);
        HapticFeedback.selectionClick();
        widget.onSendMessage?.call(message);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? widget.accent : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow:
              selected
                  ? const [
                    BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                  ]
                  : null,
        ),
        child: Text(
          _sentence(label),
          style: yMono(
            size: 11,
            weight: FontWeight.w800,
            tracking: 0.7,
            color: selected ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

class _TaskListWidget extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TaskListWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = _string(data['title'], 'Tareas');
    final items = _list(data['items']);
    return _WidgetFrame(
      title: 'Fight',
      icon: YuLiIcons.squareCheck,
      accent: yFight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(title),
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'Sin tareas para mostrar',
              style: yBody(size: 13, color: yMuted),
            )
          else
            for (final item in items) ...[
              _TaskRow(data: item),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TaskRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final content = _string(data['content'] ?? data['title'], 'Tarea');
    final due = _string(data['due'] ?? data['dueDate'], '');
    final folder = _map(data['folder']);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: yCream2,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _sentence(content),
            style: yBody(size: 14, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (folder != null)
                _FolderBadge(folder: folder, fallback: yFight),
              if (due.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.clock,
                  label: 'Fecha ${_formatDateLabel(due)}',
                  color: yFight,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskDraftWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String message)? onActionResult;
  final int? noteId;

  const _TaskDraftWidget({
    required this.data,
    this.onActionResult,
    this.noteId,
  });

  @override
  ConsumerState<_TaskDraftWidget> createState() => _TaskDraftWidgetState();
}

class _TaskDraftWidgetState extends ConsumerState<_TaskDraftWidget> {
  late String _content = _string(widget.data['content'], 'Nueva tarea');
  late Map<String, dynamic>? _folder = _map(widget.data['folder']);
  late String _dueDate = _string(widget.data['dueDate'], '');
  late String _duePrecision = _string(widget.data['duePrecision'], '');
  late String _reminderPreset = _string(widget.data['reminderPreset'], '');
  late Map<String, dynamic>? _temporaryMemory = _map(
    widget.data['temporaryMemory'],
  );
  late Map<String, dynamic>? _labLink = _map(widget.data['labLink']);
  bool _memoryEnabled = true;
  bool _busy = false;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    return _WidgetFrame(
      title: 'Crear tarea',
      icon: YuLiIcons.plus,
      accent: yFight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(_content),
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (_folder != null)
                _FolderBadge(folder: _folder!, fallback: yFight),
              if (_dueDate.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.calendar,
                  label: 'Fecha ${_formatDateLabel(_dueDate)}',
                  color: yFight,
                ),
              if (_reminderPreset.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.bell,
                  label: _reminderLabel(_reminderPreset),
                  color: yFight,
                ),
              if (_labLink != null)
                _MiniBadge(
                  icon: YuLiIcons.flaskConical,
                  label: 'Lab ${_labLinkName(_labLink!)}',
                  color: yLab,
                ),
            ],
          ),
          if (_temporaryMemory != null) ...[
            const SizedBox(height: 12),
            _ToggleRow(
              active: _memoryEnabled,
              label: _memoryToggleLabel(_temporaryMemory!),
              color: yFight,
              onTap: () => setState(() => _memoryEnabled = !_memoryEnabled),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: _created ? 'Creada' : 'Crear',
                icon: _created ? YuLiIcons.squareCheck : YuLiIcons.plus,
                color: _created ? yLab : yFight,
                disabled: _busy || _created,
                onTap: _create,
              ),
              _ActionButton(
                label: 'Editar',
                icon: YuLiIcons.pencil,
                color: yInk,
                disabled: _busy || _created,
                onTap: _edit,
                outlined: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final folders = await ref.read(folderRepositoryProvider).getActive();
    final spaces = await ref.read(labSpaceRepositoryProvider).getActive();
    final columnsBySpace = <int, List<KanbanColumn>>{};
    for (final space in spaces) {
      final columns = await ref
          .read(labSpaceRepositoryProvider)
          .getColumns(space.id);
      columnsBySpace[space.id] =
          columns.where((c) => !c.isTerminal && !c.isExpired).toList();
    }
    if (!mounted) return;
    final contentCtrl = TextEditingController(text: _content);
    final folderIdCtrl = TextEditingController(
      text: _string(_folder?['id'], ''),
    );
    final folderNameCtrl = TextEditingController(
      text: _string(_folder?['name'], ''),
    );
    final folderColorCtrl = TextEditingController(
      text: _string(_folder?['color'], ''),
    );
    final dueCtrl = TextEditingController(text: _dueDate);
    final duePrecisionCtrl = TextEditingController(text: _duePrecision);
    final reminderCtrl = TextEditingController(text: _reminderPreset);
    final labSpaceIdCtrl = TextEditingController(
      text: _string(
        _map(_labLink?['space'])?['id'] ?? _labLink?['spaceId'],
        '',
      ),
    );
    final labSpaceNameCtrl = TextEditingController(
      text: _labLink == null ? '' : _labLinkName(_labLink!),
    );
    final labColumnCtrl = TextEditingController(
      text: _string(_labLink?['column'], ''),
    );
    final memoryValueCtrl = TextEditingController(
      text: _string(
        _temporaryMemory?['value'] ?? _temporaryMemory?['text'],
        '',
      ),
    );
    final memoryScopeCtrl = TextEditingController(
      text: _string(_temporaryMemory?['scope'], ''),
    );
    final memoryExpiresCtrl = TextEditingController(
      text: _string(_temporaryMemory?['expiresAt'], ''),
    );
    final next = await showDialog<_TaskDraftEditResult>(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                  maxWidth: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Editar tarea',
                        style: yMono(
                          size: 11,
                          weight: FontWeight.w800,
                          tracking: 1.1,
                          color: yInk,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DraftTextField(
                        controller: contentCtrl,
                        label: 'Contenido',
                        autofocus: true,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: folderNameCtrl,
                              label: 'Folder',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 76,
                            child: _DraftTextField(
                              controller: folderIdCtrl,
                              label: 'Id',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DraftTextField(
                        controller: folderColorCtrl,
                        label: 'Color folder',
                      ),
                      const SizedBox(height: 8),
                      _DraftFolderChoices(
                        folders: folders,
                        idController: folderIdCtrl,
                        nameController: folderNameCtrl,
                        colorController: folderColorCtrl,
                        color: yFight,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: dueCtrl,
                              label: 'Fecha/hora',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: _DraftTextField(
                              controller: duePrecisionCtrl,
                              label: 'Precisión',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DraftDateControls(
                        dateController: dueCtrl,
                        precisionController: duePrecisionCtrl,
                        color: yFight,
                      ),
                      const SizedBox(height: 10),
                      _DraftTextField(
                        controller: reminderCtrl,
                        label: 'Recordatorio',
                      ),
                      const SizedBox(height: 8),
                      _DraftReminderChoices(
                        controller: reminderCtrl,
                        color: yFight,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lab opcional',
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w900,
                          tracking: 1,
                          color: yMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: labSpaceNameCtrl,
                              label: 'Proyecto',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 76,
                            child: _DraftTextField(
                              controller: labSpaceIdCtrl,
                              label: 'Id',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DraftTextField(
                        controller: labColumnCtrl,
                        label: 'Columna',
                      ),
                      const SizedBox(height: 8),
                      _DraftSpaceChoices(
                        spaces: spaces,
                        idController: labSpaceIdCtrl,
                        nameController: labSpaceNameCtrl,
                        color: yLab,
                      ),
                      const SizedBox(height: 8),
                      _DraftColumnChoices(
                        spaceIdController: labSpaceIdCtrl,
                        columnController: labColumnCtrl,
                        columnsBySpace: columnsBySpace,
                        color: yLab,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Memoria opcional',
                        style: yMono(
                          size: 9,
                          weight: FontWeight.w900,
                          tracking: 1,
                          color: yMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DraftTextField(
                        controller: memoryValueCtrl,
                        label: 'Recuerdo',
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: memoryScopeCtrl,
                              label: 'Scope',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DraftTextField(
                              controller: memoryExpiresCtrl,
                              label: 'Expira',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DraftMemoryChoices(
                        scopeController: memoryScopeCtrl,
                        expiresController: memoryExpiresCtrl,
                        color: yFight,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogButton(
                              label: 'Cancelar',
                              onTap: () => Navigator.of(ctx).pop(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DialogButton(
                              label: 'Guardar',
                              color: yFight,
                              onTap:
                                  () => Navigator.of(ctx).pop(
                                    _TaskDraftEditResult(
                                      content: contentCtrl.text.trim(),
                                      folder: _draftFolder(
                                        folderIdCtrl.text,
                                        folderNameCtrl.text,
                                        folderColorCtrl.text,
                                      ),
                                      dueDate: dueCtrl.text.trim(),
                                      duePrecision:
                                          duePrecisionCtrl.text.trim(),
                                      reminderPreset: reminderCtrl.text.trim(),
                                      labLink: _draftLabLink(
                                        labSpaceIdCtrl.text,
                                        labSpaceNameCtrl.text,
                                        labColumnCtrl.text,
                                      ),
                                      temporaryMemory: _draftMemory(
                                        memoryValueCtrl.text,
                                        memoryScopeCtrl.text,
                                        memoryExpiresCtrl.text,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    contentCtrl.dispose();
    folderIdCtrl.dispose();
    folderNameCtrl.dispose();
    folderColorCtrl.dispose();
    dueCtrl.dispose();
    duePrecisionCtrl.dispose();
    reminderCtrl.dispose();
    labSpaceIdCtrl.dispose();
    labSpaceNameCtrl.dispose();
    labColumnCtrl.dispose();
    memoryValueCtrl.dispose();
    memoryScopeCtrl.dispose();
    memoryExpiresCtrl.dispose();
    if (next == null || next.content.isEmpty) return;
    setState(() {
      _content = next.content;
      _folder = next.folder;
      _dueDate = next.dueDate;
      _duePrecision = next.duePrecision;
      _reminderPreset = next.reminderPreset;
      _labLink = next.labLink;
      _temporaryMemory = next.temporaryMemory;
      _memoryEnabled = next.temporaryMemory != null;
    });
  }

  Future<void> _create() async {
    if (_content.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final due = _parseDueDate(_dueDate, _duePrecision);
      final preset = _parseReminder(_reminderPreset);
      final task = await ref
          .read(taskRepositoryProvider)
          .save(
            Task(
              id: 0,
              content: _content.trim(),
              status: TaskStatus.pending,
              folderId: await _resolveFolderId(),
              createdAt: now,
              expiresAt: now.add(const Duration(hours: 48)),
              dueDate: due,
              remindAt:
                  preset == null ? null : reminderTimeForPreset(preset, due),
              reminderPreset: preset,
            ),
          );
      await _linkTaskToCurrentNote(task.id);
      final labResult = await _tryCreateLinkedLabCard(task);
      if (_memoryEnabled && _temporaryMemory != null) {
        await ref
            .read(aiMemoryStoreProvider)
            .saveFromWidgetItem(_temporaryMemory!, linkedTaskId: task.id);
      }
      if (!mounted) return;
      setState(() => _created = true);
      widget.onActionResult?.call(_taskCreatedMessage(task, labResult));
      _snack(context, 'Tarea creada');
    } catch (_) {
      widget.onActionResult?.call(
        'No pude crear la tarea "${_content.trim()}". Revisa los datos e intenta de nuevo.',
      );
      if (mounted) _snack(context, 'No se pudo crear la tarea');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkTaskToCurrentNote(int taskId) async {
    final noteId = widget.noteId;
    if (noteId == null || noteId == 0) return;
    await ref.read(noteRepositoryProvider).linkTask(noteId, taskId);
  }

  String _labLinkName(Map<String, dynamic> labLink) {
    final raw = labLink['space'] ?? labLink['labSpace'] ?? labLink['project'];
    final map = _map(raw);
    return _string(map?['name'] ?? raw ?? labLink['spaceName'], 'Proyecto');
  }

  String _taskCreatedMessage(Task task, _TaskLabLinkResult? labResult) {
    final parts = <String>['Listo, creé la tarea "${task.content}"'];
    final folderName = _string(_folder?['name'], '');
    if (folderName.isNotEmpty) parts.add('en $folderName');
    if (task.dueDate != null) {
      parts.add('para ${_formatDateLabel(task.dueDate!.toIso8601String())}');
    }
    if (task.reminderPreset != null) {
      parts.add(
        'con recordatorio ${_reminderLabel(task.reminderPreset!.toDbString()).toLowerCase()}',
      );
    }
    if (widget.noteId != null && widget.noteId != 0) {
      parts.add('vinculada a esta nota');
    }
    if (labResult != null) parts.add(labResult.message);
    return '${parts.join(', ')}.';
  }

  Future<_TaskLabLinkResult?> _tryCreateLinkedLabCard(Task task) async {
    if (_labLink == null) return null;
    final space = await _resolveLinkedSpace(_labLink!);
    if (space == null) {
      return const _TaskLabLinkResult(
        message: 'pero no pude vincularla a Lab porque no encontré el proyecto',
      );
    }
    final column = await _resolveLinkedColumn(space.id, _labLink!);
    if (column == null) {
      return _TaskLabLinkResult(
        message:
            'pero no pude vincularla a Lab porque ${space.name} no tiene una columna válida',
      );
    }
    final folder = await _resolveFolder();
    final title =
        folder == null
            ? task.content
            : ensureFolderMention(task.content, folder.name);
    await ref
        .read(kanbanCardRepositoryProvider)
        .create(
          labSpaceId: space.id,
          columnId: column.id,
          title: title,
          dueDate: task.dueDate,
          remindAt: task.remindAt,
          reminderPreset: task.reminderPreset,
          sourceNoteId:
              widget.noteId == null || widget.noteId == 0
                  ? null
                  : widget.noteId,
          originTaskId: task.id,
          originFolderColor: folder?.color.toARGB32(),
        );
    return _TaskLabLinkResult(
      message: 'y la vinculé a Lab en ${space.name} > ${column.name}',
    );
  }

  Future<LabSpace?> _resolveLinkedSpace(Map<String, dynamic> labLink) async {
    final raw = labLink['space'] ?? labLink['labSpace'] ?? labLink['project'];
    final map = _map(raw);
    final id = _int(map?['id'] ?? labLink['spaceId'] ?? labLink['labSpaceId']);
    final repo = ref.read(labSpaceRepositoryProvider);
    if (id != null) {
      final found = await repo.getById(id);
      if (found != null) return found;
    }
    final name =
        _string(
          map?['name'] ?? raw ?? labLink['spaceName'],
          '',
        ).toLowerCase().trim();
    if (name.isEmpty) return null;
    final spaces = await repo.getActive();
    return spaces
            .where((s) => s.name.toLowerCase().trim() == name)
            .firstOrNull ??
        spaces.where((s) => s.name.toLowerCase().contains(name)).firstOrNull;
  }

  Future<KanbanColumn?> _resolveLinkedColumn(
    int labSpaceId,
    Map<String, dynamic> labLink,
  ) async {
    final columns = await ref
        .read(labSpaceRepositoryProvider)
        .getColumns(labSpaceId);
    final valid = columns.where((c) => !c.isTerminal && !c.isExpired).toList();
    if (valid.isEmpty) return null;
    final wanted = _string(labLink['column'], '').toLowerCase().trim();
    if (wanted.isNotEmpty) {
      final byName =
          valid.where((c) => c.name.toLowerCase().trim() == wanted).firstOrNull;
      if (byName != null) return byName;
    }
    return valid
            .where((c) => c.name.toLowerCase().trim() == 'backlog')
            .firstOrNull ??
        valid.where((c) => c.isDefault).firstOrNull ??
        valid.first;
  }

  Future<int?> _resolveFolderId() async => (await _resolveFolder())?.id;

  Future<Folder?> _resolveFolder() async {
    if (_folder == null) return null;
    final id = _int(_folder!['id']);
    if (id != null &&
        await ref.read(folderRepositoryProvider).getById(id) != null) {
      return ref.read(folderRepositoryProvider).getById(id);
    }
    final name = _string(_folder!['name'], '').toLowerCase().trim();
    if (name.isEmpty) return null;
    final folders = await ref.read(folderRepositoryProvider).getActive();
    return folders
        .where((f) => f.name.toLowerCase().trim() == name)
        .firstOrNull;
  }
}

class _TaskLabLinkResult {
  final String message;

  const _TaskLabLinkResult({required this.message});
}

class _TaskDraftEditResult {
  final String content;
  final Map<String, dynamic>? folder;
  final String dueDate;
  final String duePrecision;
  final String reminderPreset;
  final Map<String, dynamic>? labLink;
  final Map<String, dynamic>? temporaryMemory;

  const _TaskDraftEditResult({
    required this.content,
    required this.folder,
    required this.dueDate,
    required this.duePrecision,
    required this.reminderPreset,
    required this.labLink,
    required this.temporaryMemory,
  });
}

class _LabCardDraftEditResult {
  final String title;
  final String description;
  final Object? space;
  final String column;
  final String priority;
  final String dueDate;
  final String duePrecision;
  final String reminderPreset;

  const _LabCardDraftEditResult({
    required this.title,
    required this.description,
    required this.space,
    required this.column,
    required this.priority,
    required this.dueDate,
    required this.duePrecision,
    required this.reminderPreset,
  });
}

Map<String, dynamic>? _draftFolder(String id, String name, String color) {
  final folderId = _int(id.trim());
  final folderName = name.trim();
  final folderColor = color.trim();
  if (folderId == null && folderName.isEmpty) return null;
  return {
    if (folderId != null) 'id': folderId,
    if (folderName.isNotEmpty) 'name': folderName,
    if (folderColor.isNotEmpty) 'color': folderColor,
  };
}

Map<String, dynamic>? _draftLabLink(String id, String name, String column) {
  final space = _draftSpace(id, name);
  final col = column.trim();
  if (space == null && col.isEmpty) return null;
  return {if (space != null) 'space': space, if (col.isNotEmpty) 'column': col};
}

Map<String, dynamic>? _draftMemory(
  String value,
  String scope,
  String expiresAt,
) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final cleanScope = scope.trim();
  final cleanExpires = expiresAt.trim();
  return {
    'key': 'memory',
    'label': 'Memoria',
    'value': text,
    'scope': cleanScope.isEmpty ? 'global' : cleanScope,
    if (cleanExpires.isNotEmpty) 'expiresAt': cleanExpires,
  };
}

Map<String, dynamic>? _draftSpace(String id, String name) {
  final spaceId = _int(id.trim());
  final spaceName = name.trim();
  if (spaceId == null && spaceName.isEmpty) return null;
  return {
    if (spaceId != null) 'id': spaceId,
    if (spaceName.isNotEmpty) 'name': spaceName,
  };
}

String _memoryToggleLabel(Map<String, dynamic> memory) {
  final expires = _string(memory['expiresAt'], '');
  if (expires.isEmpty) return 'Guardar memoria';
  return 'Guardar memoria temporal hasta ${_formatDateLabel(expires)}';
}

class _LabCardDraftWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String message)? onActionResult;

  const _LabCardDraftWidget({required this.data, this.onActionResult});

  @override
  ConsumerState<_LabCardDraftWidget> createState() =>
      _LabCardDraftWidgetState();
}

class _LabCardDraftWidgetState extends ConsumerState<_LabCardDraftWidget> {
  late String _title = _string(
    widget.data['title'] ?? widget.data['content'],
    'Nueva tarjeta',
  );
  late String _description = _string(widget.data['description'], '');
  late Object? _space = widget.data['space'];
  late String _column = _string(widget.data['column'], '');
  late String _dueDate = _string(widget.data['dueDate'], '');
  late String _duePrecision = _string(widget.data['duePrecision'], '');
  late String _reminderPreset = _string(widget.data['reminderPreset'], '');
  late String _priority = _string(widget.data['priority'], '');
  bool _busy = false;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    final space = _spaceName();
    return _WidgetFrame(
      title: 'Crear tarjeta',
      icon: YuLiIcons.kanban,
      accent: yLab,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(_title),
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          if (_description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _sentence(_description),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: yBody(size: 13, color: yInk2, height: 1.35),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (space.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.flaskConical,
                  label: 'Proyecto $space',
                  color: yLab,
                ),
              if (_column.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.kanban,
                  label: 'Columna $_column',
                  color: yLab,
                ),
              if (_priority.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.triangleAlert,
                  label: 'Prioridad ${_priorityLabel(_priority)}',
                  color: yLab,
                ),
              if (_dueDate.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.calendar,
                  label: 'Fecha ${_formatDateLabel(_dueDate)}',
                  color: yLab,
                ),
              if (_reminderPreset.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.bell,
                  label: _reminderLabel(_reminderPreset),
                  color: yLab,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: _created ? 'Creada' : 'Crear',
                icon: _created ? YuLiIcons.squareCheck : YuLiIcons.plus,
                color: yLab,
                disabled: _busy || _created,
                onTap: _create,
              ),
              _ActionButton(
                label: 'Editar',
                icon: YuLiIcons.pencil,
                color: yInk,
                disabled: _busy || _created,
                onTap: _edit,
                outlined: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _spaceName() {
    final map = _map(_space);
    if (map != null) return _string(map['name'], '');
    return _string(_space, '');
  }

  Future<void> _edit() async {
    final spaces = await ref.read(labSpaceRepositoryProvider).getActive();
    final columnsBySpace = <int, List<KanbanColumn>>{};
    for (final space in spaces) {
      final columns = await ref
          .read(labSpaceRepositoryProvider)
          .getColumns(space.id);
      columnsBySpace[space.id] =
          columns.where((c) => !c.isTerminal && !c.isExpired).toList();
    }
    if (!mounted) return;
    final titleCtrl = TextEditingController(text: _title);
    final descriptionCtrl = TextEditingController(text: _description);
    final spaceMap = _map(_space);
    final spaceIdCtrl = TextEditingController(
      text: _string(spaceMap?['id'], ''),
    );
    final spaceNameCtrl = TextEditingController(text: _spaceName());
    final columnCtrl = TextEditingController(text: _column);
    final priorityCtrl = TextEditingController(text: _priority);
    final dueCtrl = TextEditingController(text: _dueDate);
    final duePrecisionCtrl = TextEditingController(text: _duePrecision);
    final reminderCtrl = TextEditingController(text: _reminderPreset);
    final next = await showDialog<_LabCardDraftEditResult>(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: yCream,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: yBorderStrong, width: yLineMid),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                  maxWidth: 520,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Editar tarjeta',
                        style: yMono(
                          size: 11,
                          weight: FontWeight.w800,
                          tracking: 1.1,
                          color: yInk,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DraftTextField(
                        controller: titleCtrl,
                        label: 'Título',
                        autofocus: true,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      _DraftTextField(
                        controller: descriptionCtrl,
                        label: 'Descripción',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: spaceNameCtrl,
                              label: 'Proyecto',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 76,
                            child: _DraftTextField(
                              controller: spaceIdCtrl,
                              label: 'Id',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DraftSpaceChoices(
                        spaces: spaces,
                        idController: spaceIdCtrl,
                        nameController: spaceNameCtrl,
                        color: yLab,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: columnCtrl,
                              label: 'Columna',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DraftTextField(
                              controller: priorityCtrl,
                              label: 'Prioridad',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DraftColumnChoices(
                        spaceIdController: spaceIdCtrl,
                        columnController: columnCtrl,
                        columnsBySpace: columnsBySpace,
                        color: yLab,
                      ),
                      const SizedBox(height: 8),
                      _DraftPriorityChoices(
                        controller: priorityCtrl,
                        color: yLab,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _DraftTextField(
                              controller: dueCtrl,
                              label: 'Fecha/hora',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: _DraftTextField(
                              controller: duePrecisionCtrl,
                              label: 'Precisión',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _DraftDateControls(
                        dateController: dueCtrl,
                        precisionController: duePrecisionCtrl,
                        color: yLab,
                      ),
                      const SizedBox(height: 10),
                      _DraftTextField(
                        controller: reminderCtrl,
                        label: 'Recordatorio',
                      ),
                      const SizedBox(height: 8),
                      _DraftReminderChoices(
                        controller: reminderCtrl,
                        color: yLab,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _DialogButton(
                              label: 'Cancelar',
                              onTap: () => Navigator.of(ctx).pop(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DialogButton(
                              label: 'Guardar',
                              color: yLab,
                              onTap:
                                  () => Navigator.of(ctx).pop(
                                    _LabCardDraftEditResult(
                                      title: titleCtrl.text.trim(),
                                      description: descriptionCtrl.text.trim(),
                                      space: _draftSpace(
                                        spaceIdCtrl.text,
                                        spaceNameCtrl.text,
                                      ),
                                      column: columnCtrl.text.trim(),
                                      priority: priorityCtrl.text.trim(),
                                      dueDate: dueCtrl.text.trim(),
                                      duePrecision:
                                          duePrecisionCtrl.text.trim(),
                                      reminderPreset: reminderCtrl.text.trim(),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
    titleCtrl.dispose();
    descriptionCtrl.dispose();
    spaceIdCtrl.dispose();
    spaceNameCtrl.dispose();
    columnCtrl.dispose();
    priorityCtrl.dispose();
    dueCtrl.dispose();
    duePrecisionCtrl.dispose();
    reminderCtrl.dispose();
    if (next == null || next.title.isEmpty) return;
    setState(() {
      _title = next.title;
      _description = next.description;
      _space = next.space;
      _column = next.column;
      _priority = next.priority;
      _dueDate = next.dueDate;
      _duePrecision = next.duePrecision;
      _reminderPreset = next.reminderPreset;
    });
  }

  Future<void> _create() async {
    if (_title.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final space = await _resolveSpace();
      if (space == null) {
        widget.onActionResult?.call(
          'No pude crear la tarjeta "${_title.trim()}" porque no encontré el proyecto Lab.',
        );
        if (mounted) _snack(context, 'No encontré el proyecto Lab');
        return;
      }
      final column = await _resolveColumn(space.id);
      if (column == null) {
        widget.onActionResult?.call(
          'No pude crear la tarjeta "${_title.trim()}" porque no encontré una columna válida.',
        );
        if (mounted) _snack(context, 'No encontré una columna válida');
        return;
      }
      final due = _parseDueDate(_dueDate, _duePrecision);
      final preset = _parseReminder(_reminderPreset);
      await ref
          .read(kanbanCardRepositoryProvider)
          .create(
            labSpaceId: space.id,
            columnId: column.id,
            title: _title.trim(),
            description: _nullableString(_description),
            priority: _parsePriority(_priority),
            dueDate: due,
            remindAt:
                preset == null ? null : reminderTimeForPreset(preset, due),
            reminderPreset: preset,
          );
      if (!mounted) return;
      setState(() => _created = true);
      widget.onActionResult?.call(_cardCreatedMessage(space, column, due));
      _snack(context, 'Tarjeta creada');
    } catch (_) {
      widget.onActionResult?.call(
        'No pude crear la tarjeta "${_title.trim()}". Revisa el proyecto, la columna o la fecha e intenta de nuevo.',
      );
      if (mounted) _snack(context, 'No se pudo crear la tarjeta');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cardCreatedMessage(
    LabSpace space,
    KanbanColumn column,
    DateTime? due,
  ) {
    final parts = <String>[
      'Listo, creé la tarjeta "${_title.trim()}"',
      'en ${space.name}',
      'columna ${column.name}',
    ];
    if (due != null) {
      parts.add('para ${_formatDateLabel(due.toIso8601String())}');
    }
    return '${parts.join(', ')}.';
  }

  Future<LabSpace?> _resolveSpace() async {
    final map = _map(_space);
    final id = _int(map?['id']);
    final repo = ref.read(labSpaceRepositoryProvider);
    if (id != null) {
      final found = await repo.getById(id);
      if (found != null) return found;
    }
    final name = _spaceName().toLowerCase().trim();
    if (name.isEmpty) return null;
    final spaces = await repo.getActive();
    return spaces.where((s) => s.name.toLowerCase().trim() == name).firstOrNull;
  }

  Future<KanbanColumn?> _resolveColumn(int labSpaceId) async {
    final columns = await ref
        .read(labSpaceRepositoryProvider)
        .getColumns(labSpaceId);
    final valid = columns.where((c) => !c.isTerminal && !c.isExpired).toList();
    if (valid.isEmpty) return null;
    final wanted = _column.toLowerCase().trim();
    if (wanted.isNotEmpty) {
      final byName =
          valid.where((c) => c.name.toLowerCase().trim() == wanted).firstOrNull;
      if (byName != null) return byName;
    }
    return valid.where((c) => c.isDefault).firstOrNull ?? valid.first;
  }
}

class _MemorySuggestionWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  final Color accent;
  final void Function(String message)? onActionResult;

  const _MemorySuggestionWidget({
    required this.data,
    required this.accent,
    this.onActionResult,
  });

  @override
  ConsumerState<_MemorySuggestionWidget> createState() =>
      _MemorySuggestionWidgetState();
}

class _MemorySuggestionWidgetState
    extends ConsumerState<_MemorySuggestionWidget> {
  final Set<int> _selected = {};
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final items = _list(widget.data['items']);
    _selected.addAll(List.generate(items.length, (i) => i));
  }

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Guardar memoria');
    final items = _list(widget.data['items']);
    return _WidgetFrame(
      title: 'Memoria',
      icon: YuLiIcons.brain,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(title),
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++) ...[
            _memoryRow(i, items[i]),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          _ActionButton(
            label: _saved ? 'Guardado' : 'Guardar',
            icon: _saved ? YuLiIcons.squareCheck : YuLiIcons.bookmark,
            color: _saved ? yLab : widget.accent,
            disabled: _saved || _selected.isEmpty,
            onTap: () => _save(items),
          ),
        ],
      ),
    );
  }

  Widget _memoryRow(int index, Map<String, dynamic> item) {
    final label = _string(item['label'] ?? item['key'], 'Memoria');
    final value = _string(item['value'], '');
    final active = _selected.contains(index);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          active ? _selected.remove(index) : _selected.add(index);
        });
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: BoxDecoration(
          color: active ? widget.accent.withValues(alpha: 0.14) : yCream2,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              active ? YuLiIcons.squareCheck : YuLiIcons.square,
              size: 18,
              color: active ? widget.accent : yMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sentence(label),
                    style: yMono(
                      size: 10,
                      weight: FontWeight.w800,
                      tracking: 0.8,
                      color: yMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _sentence(value),
                    style: yBody(
                      size: 14,
                      weight: FontWeight.w700,
                      color: yInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(List<Map<String, dynamic>> items) async {
    for (final index in _selected) {
      if (index >= 0 && index < items.length) {
        await ref.read(aiMemoryStoreProvider).saveFromWidgetItem(items[index]);
      }
    }
    if (!mounted) return;
    setState(() => _saved = true);
    widget.onActionResult?.call(
      _selected.length == 1
          ? 'Listo, guardé esa memoria.'
          : 'Listo, guardé ${_selected.length} memorias.',
    );
    _snack(context, 'Memoria guardada');
  }
}

class _UnknownWidget extends StatelessWidget {
  final String type;
  final Color accent;

  const _UnknownWidget({required this.type, required this.accent});

  @override
  Widget build(BuildContext context) {
    return _WidgetFrame(
      title: 'Widget',
      icon: YuLiIcons.info,
      accent: accent,
      child: Text(
        'No pude renderizar $type',
        style: yBody(size: 13, color: yMuted),
      ),
    );
  }
}

class _CalloutLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;

  const _CalloutLine({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: yBorderStrong, width: yLineThin),
          ),
          child: Icon(icon, size: 13, color: yCream),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: yMono(
                  size: 9,
                  weight: FontWeight.w900,
                  tracking: 0.8,
                  color: yMuted,
                ),
              ),
              const SizedBox(height: 3),
              _WidgetMarkdownText(
                text,
                accent: color,
                style: yBody(size: 13, weight: FontWeight.w800, color: yInk),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TapHintIcon extends StatelessWidget {
  final Color accent;

  const _TapHintIcon({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.48,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          border: Border.all(color: accent, width: yLineThin),
        ),
        child: Icon(YuLiIcons.search, size: 12, color: accent),
      ),
    );
  }
}

class _WidgetFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  const _WidgetFrame({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: yCream,
        border: Border.all(color: yBorderStrong, width: yLineMid),
        boxShadow: const [
          BoxShadow(color: yBorderStrong, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: accent,
              border: const Border(
                bottom: BorderSide(color: yBorderStrong, width: yLineMid),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: yCream),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: yMono(
                    size: 10,
                    weight: FontWeight.w800,
                    tracking: 1.2,
                    color: yCream,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _FolderBadge extends StatelessWidget {
  final Map<String, dynamic> folder;
  final Color fallback;

  const _FolderBadge({required this.folder, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(_string(folder['color'], '')) ?? fallback;
    final name = _string(folder['name'], 'Carpeta');
    return _MiniBadge(icon: YuLiIcons.folder, label: name, color: color);
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: yCream),
          const SizedBox(width: 5),
          Text(
            _sentence(label),
            style: yMono(
              size: 9,
              weight: FontWeight.w800,
              tracking: 0.7,
              color: yCream,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalloutStrip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;

  const _CalloutStrip({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: yBorderStrong, width: yLineThin),
            ),
            child: Icon(icon, size: 14, color: yCream),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sentence(label),
                  style: yMono(
                    size: 9,
                    weight: FontWeight.w900,
                    tracking: 1,
                    color: yMuted,
                  ),
                ),
                const SizedBox(height: 4),
                _WidgetMarkdownText(
                  text,
                  accent: color,
                  style: yBody(
                    size: 13,
                    weight: FontWeight.w800,
                    color: yInk,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetMarkdownText extends StatelessWidget {
  final String text;
  final Color accent;
  final TextStyle style;
  final bool center;
  final bool formula;

  const _WidgetMarkdownText(
    this.text, {
    required this.accent,
    required this.style,
    this.center = false,
    this.formula = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = _sentence(_stripWidgetHtml(text));
    final mathy = formula || _containsMathNotation(data);
    final effectiveStyle =
        mathy ? style.copyWith(fontWeight: FontWeight.w500) : style;
    final latexBlock = formula ? _extractLatexBlock(data) : null;
    if (latexBlock != null) {
      final labelStyle = effectiveStyle.copyWith(fontWeight: FontWeight.w700);
      final mathStyle = effectiveStyle.copyWith(fontWeight: FontWeight.w400);
      return Column(
        crossAxisAlignment:
            center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (latexBlock.prefix.isNotEmpty) ...[
            Text(
              latexBlock.prefix,
              textAlign: center ? TextAlign.center : null,
              style: labelStyle,
            ),
            const SizedBox(height: 6),
          ],
          _mathScroll(
            Math.tex(
              latexBlock.latex,
              mathStyle: MathStyle.display,
              textStyle: mathStyle,
              onErrorFallback:
                  (_) => Text(
                    data,
                    textAlign: center ? TextAlign.center : null,
                    style: mathStyle,
                  ),
            ),
            latexBlock.latex,
          ),
          if (latexBlock.suffix.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              latexBlock.suffix,
              textAlign: center ? TextAlign.center : null,
              style: labelStyle,
            ),
          ],
        ],
      );
    }
    final inlineLatex = formula ? _extractInlineLatex(data) : null;
    if (inlineLatex != null) {
      return _mathScroll(
        Math.tex(
          inlineLatex,
          mathStyle: MathStyle.text,
          textStyle: effectiveStyle.copyWith(fontWeight: FontWeight.w400),
          onErrorFallback:
              (_) => Text(
                data,
                textAlign: center ? TextAlign.center : null,
                style: effectiveStyle.copyWith(fontWeight: FontWeight.w400),
              ),
        ),
        inlineLatex,
      );
    }
    if (!_needsMarkdownText(data)) {
      final child = Text(
        data,
        textAlign: center ? TextAlign.center : null,
        style: effectiveStyle,
      );
      return _mathScroll(child, data);
    }
    final markdown = data;
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = IgnorePointer(
          child: NoteMarkdownPreview(
            data: markdown,
            tight: true,
            accent: accent,
            textStyle: effectiveStyle,
          ),
        );
        final wrapped =
            constraints.maxWidth.isFinite
                ? child
                : SizedBox(width: 180, child: child);
        final aligned =
            center
                ? Align(alignment: Alignment.center, child: wrapped)
                : wrapped;
        return _mathScroll(
          aligned,
          data,
          maxWidth: constraints.maxWidth,
          bindWidth: true,
        );
      },
    );
  }

  Widget _mathScroll(
    Widget child,
    String data, {
    double? maxWidth,
    bool bindWidth = false,
  }) {
    if (!formula && !_isLongMath(data)) return child;
    final content =
        bindWidth && maxWidth != null && maxWidth.isFinite
            ? SizedBox(width: maxWidth, child: child)
            : child;
    return ClipRect(
      child: SingleChildScrollView(
        key: const ValueKey('ai_widget_math_scroll'),
        scrollDirection: Axis.horizontal,
        child: content,
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final Color color;
  final String text;

  const _StatusStrip({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color, width: yLineThin),
      ),
      child: Text(
        _sentence(text),
        style: yMono(size: 10, weight: FontWeight.w800, color: yInk),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final bool active;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToggleRow({
    required this.active,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            active ? YuLiIcons.squareCheck : YuLiIcons.square,
            size: 18,
            color: active ? color : yMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _sentence(label),
              style: yBody(size: 13, weight: FontWeight.w700, color: yInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MiniActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Text(
              _sentence(label),
              style: yMono(
                size: 10,
                weight: FontWeight.w900,
                tracking: 0.7,
                color: yInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool disabled;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = !outlined && !disabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: fill ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow:
              fill
                  ? const [
                    BoxShadow(color: yBorderStrong, offset: Offset(3, 3)),
                  ]
                  : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: fill ? yCream : (disabled ? yMuted : color),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: yMono(
                size: 10,
                weight: FontWeight.w800,
                tracking: 0.9,
                color: fill ? yCream : (disabled ? yMuted : yInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _DialogButton({required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final fill = color != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? yCream,
          border: Border.all(color: yBorderStrong, width: yLineMid),
        ),
        child: Text(
          label.toUpperCase(),
          style: yMono(
            size: 11,
            weight: FontWeight.w800,
            tracking: 0.8,
            color: fill ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

class _DraftTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final int maxLines;

  const _DraftTextField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: 1,
      maxLines: maxLines,
      style: yBody(size: 14, color: yInk),
      decoration: InputDecoration(
        labelText: _sentence(label),
        labelStyle: yMono(size: 9, weight: FontWeight.w800, color: yMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yBorderStrong, width: yLineThin),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: yBorderStrong, width: yLineMid),
        ),
      ),
    );
  }
}

class _DraftFolderChoices extends StatefulWidget {
  final List<Folder> folders;
  final TextEditingController idController;
  final TextEditingController nameController;
  final TextEditingController colorController;
  final Color color;

  const _DraftFolderChoices({
    required this.folders,
    required this.idController,
    required this.nameController,
    required this.colorController,
    required this.color,
  });

  @override
  State<_DraftFolderChoices> createState() => _DraftFolderChoicesState();
}

class _DraftFolderChoicesState extends State<_DraftFolderChoices> {
  @override
  void initState() {
    super.initState();
    widget.idController.addListener(_refresh);
    widget.nameController.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.idController.removeListener(_refresh);
    widget.nameController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final selectedId = _int(widget.idController.text);
    return _DraftChipGroup(
      label: 'Folder',
      children: [
        _DraftChip(
          label: 'Sin folder',
          selected: selectedId == null && widget.nameController.text.isEmpty,
          color: widget.color,
          onTap: () {
            widget.idController.clear();
            widget.nameController.clear();
            widget.colorController.clear();
          },
        ),
        for (final folder in widget.folders)
          _DraftChip(
            label: folder.name,
            selected: selectedId == folder.id,
            color: folder.color,
            onTap: () {
              widget.idController.text = '${folder.id}';
              widget.nameController.text = folder.name;
              widget.colorController.text = _colorHex(folder.color);
            },
          ),
      ],
    );
  }
}

class _DraftSpaceChoices extends StatefulWidget {
  final List<LabSpace> spaces;
  final TextEditingController idController;
  final TextEditingController nameController;
  final Color color;

  const _DraftSpaceChoices({
    required this.spaces,
    required this.idController,
    required this.nameController,
    required this.color,
  });

  @override
  State<_DraftSpaceChoices> createState() => _DraftSpaceChoicesState();
}

class _DraftSpaceChoicesState extends State<_DraftSpaceChoices> {
  @override
  void initState() {
    super.initState();
    widget.idController.addListener(_refresh);
    widget.nameController.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.idController.removeListener(_refresh);
    widget.nameController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final selectedId = _int(widget.idController.text);
    return _DraftChipGroup(
      label: 'Proyecto Lab',
      children: [
        _DraftChip(
          label: 'Sin Lab',
          selected: selectedId == null && widget.nameController.text.isEmpty,
          color: widget.color,
          onTap: () {
            widget.idController.clear();
            widget.nameController.clear();
          },
        ),
        for (final space in widget.spaces)
          _DraftChip(
            label: space.name,
            selected: selectedId == space.id,
            color: space.accentColor,
            onTap: () {
              widget.idController.text = '${space.id}';
              widget.nameController.text = space.name;
            },
          ),
      ],
    );
  }
}

class _DraftColumnChoices extends StatefulWidget {
  final TextEditingController spaceIdController;
  final TextEditingController columnController;
  final Map<int, List<KanbanColumn>> columnsBySpace;
  final Color color;

  const _DraftColumnChoices({
    required this.spaceIdController,
    required this.columnController,
    required this.columnsBySpace,
    required this.color,
  });

  @override
  State<_DraftColumnChoices> createState() => _DraftColumnChoicesState();
}

class _DraftColumnChoicesState extends State<_DraftColumnChoices> {
  @override
  void initState() {
    super.initState();
    widget.spaceIdController.addListener(_refresh);
    widget.columnController.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.spaceIdController.removeListener(_refresh);
    widget.columnController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final spaceId = _int(widget.spaceIdController.text);
    final columns = widget.columnsBySpace[spaceId] ?? const <KanbanColumn>[];
    if (columns.isEmpty) return const SizedBox.shrink();
    final selected = widget.columnController.text.toLowerCase().trim();
    return _DraftChipGroup(
      label: 'Columna',
      children: [
        for (final column in columns)
          _DraftChip(
            label: column.name,
            selected: selected == column.name.toLowerCase().trim(),
            color: widget.color,
            onTap: () => widget.columnController.text = column.name,
          ),
      ],
    );
  }
}

class _DraftReminderChoices extends StatelessWidget {
  final TextEditingController controller;
  final Color color;

  const _DraftReminderChoices({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return _DraftValueChoices(
      label: 'Recordatorio',
      controller: controller,
      color: color,
      options: const [
        ('Sin recordatorio', ''),
        ('Al vencer', 'at_due'),
        ('Antes 30 min', 'before_30m'),
        ('Un día antes', 'before_1d'),
      ],
    );
  }
}

class _DraftPriorityChoices extends StatelessWidget {
  final TextEditingController controller;
  final Color color;

  const _DraftPriorityChoices({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return _DraftValueChoices(
      label: 'Prioridad',
      controller: controller,
      color: color,
      options: const [
        ('Normal', ''),
        ('Baja', 'low'),
        ('Media', 'medium'),
        ('Alta', 'high'),
      ],
    );
  }
}

class _DraftMemoryChoices extends StatelessWidget {
  final TextEditingController scopeController;
  final TextEditingController expiresController;
  final Color color;

  const _DraftMemoryChoices({
    required this.scopeController,
    required this.expiresController,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DraftValueChoices(
          label: 'Alcance',
          controller: scopeController,
          color: color,
          options: const [
            ('Global', 'global'),
            ('Folder', 'folder'),
            ('Nota', 'note'),
            ('Temporal', 'temporary'),
          ],
        ),
        const SizedBox(height: 8),
        _DraftChipGroup(
          label: 'Expiración',
          children: [
            _DraftChip(
              label: 'Sin expiración',
              selected: expiresController.text.trim().isEmpty,
              color: color,
              onTap: expiresController.clear,
            ),
            _DraftChip(
              label: 'Mañana',
              selected: false,
              color: color,
              onTap:
                  () =>
                      expiresController.text =
                          DateTime.now()
                              .add(const Duration(days: 1))
                              .toIso8601String(),
            ),
            _DraftChip(
              label: '48 horas',
              selected: false,
              color: color,
              onTap:
                  () =>
                      expiresController.text =
                          DateTime.now()
                              .add(const Duration(hours: 48))
                              .toIso8601String(),
            ),
          ],
        ),
      ],
    );
  }
}

class _DraftValueChoices extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final Color color;
  final List<(String label, String value)> options;

  const _DraftValueChoices({
    required this.label,
    required this.controller,
    required this.color,
    required this.options,
  });

  @override
  State<_DraftValueChoices> createState() => _DraftValueChoicesState();
}

class _DraftValueChoicesState extends State<_DraftValueChoices> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.text.trim();
    return _DraftChipGroup(
      label: widget.label,
      children: [
        for (final option in widget.options)
          _DraftChip(
            label: option.$1,
            selected: selected == option.$2,
            color: widget.color,
            onTap: () => widget.controller.text = option.$2,
          ),
      ],
    );
  }
}

class _DraftDateControls extends StatefulWidget {
  final TextEditingController dateController;
  final TextEditingController precisionController;
  final Color color;

  const _DraftDateControls({
    required this.dateController,
    required this.precisionController,
    required this.color,
  });

  @override
  State<_DraftDateControls> createState() => _DraftDateControlsState();
}

class _DraftDateControlsState extends State<_DraftDateControls> {
  @override
  void initState() {
    super.initState();
    widget.dateController.addListener(_refresh);
    widget.precisionController.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.dateController.removeListener(_refresh);
    widget.precisionController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final due = DateTime.tryParse(widget.dateController.text.trim());
    final label =
        due == null
            ? 'Sin fecha'
            : _formatDateLabel(widget.dateController.text);
    return _DraftChipGroup(
      label: 'Fecha',
      children: [
        _DraftChip(
          label: label,
          selected: due != null,
          color: widget.color,
          onTap: _pickDate,
        ),
        _DraftChip(
          label: 'Sin fecha',
          selected: due == null,
          color: widget.color,
          onTap: () {
            widget.dateController.clear();
            widget.precisionController.clear();
          },
        ),
        _DraftChip(
          label: 'Hoy',
          selected: false,
          color: widget.color,
          onTap: () => _setDate(DateTime.now(), keepTime: false),
        ),
        _DraftChip(
          label: 'Mañana',
          selected: false,
          color: widget.color,
          onTap:
              () => _setDate(
                DateTime.now().add(const Duration(days: 1)),
                keepTime: false,
              ),
        ),
        _DraftChip(
          label: 'Elegir día',
          selected: false,
          color: widget.color,
          onTap: _pickDate,
        ),
        _DraftChip(
          label: 'Elegir hora',
          selected: widget.precisionController.text.trim() == 'datetime',
          color: widget.color,
          onTap: _pickTime,
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final current =
        DateTime.tryParse(widget.dateController.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _setDate(picked, keepTime: widget.precisionController.text == 'datetime');
  }

  Future<void> _pickTime() async {
    final current =
        DateTime.tryParse(widget.dateController.text.trim()) ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    final next = DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
    );
    widget.dateController.text = next.toIso8601String();
    widget.precisionController.text = 'datetime';
  }

  void _setDate(DateTime value, {required bool keepTime}) {
    final current = DateTime.tryParse(widget.dateController.text.trim());
    final next =
        keepTime && current != null
            ? DateTime(
              value.year,
              value.month,
              value.day,
              current.hour,
              current.minute,
            )
            : DateTime(value.year, value.month, value.day);
    widget.dateController.text =
        keepTime
            ? next.toIso8601String()
            : DateFormat('yyyy-MM-dd').format(next);
    widget.precisionController.text = keepTime ? 'datetime' : 'date';
  }
}

class _DraftChipGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _DraftChipGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sentence(label),
          style: yMono(size: 9, weight: FontWeight.w900, color: yMuted),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 7, runSpacing: 7, children: children),
      ],
    );
  }
}

class _DraftChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _DraftChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
          boxShadow:
              selected
                  ? const [
                    BoxShadow(color: yBorderStrong, offset: Offset(2, 2)),
                  ]
                  : null,
        ),
        child: Text(
          _sentence(label),
          style: yMono(
            size: 10,
            weight: FontWeight.w900,
            color: selected ? yCream : yInk,
          ),
        ),
      ),
    );
  }
}

DateTime? _parseDueDate(String raw, String precision) {
  if (raw.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return null;
  if (precision == 'date' || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  }
  return parsed;
}

ReminderPreset? _parseReminder(String raw) => switch (raw) {
  'at_due' => ReminderPreset.atDue,
  'before_30m' => ReminderPreset.before30m,
  'before_1d' => ReminderPreset.before1d,
  _ => null,
};

CardPriority _parsePriority(String raw) => switch (raw.toLowerCase().trim()) {
  'low' || 'baja' => CardPriority.low,
  'medium' || 'media' || 'normal' => CardPriority.medium,
  'high' || 'alta' || 'urgente' => CardPriority.high,
  _ => CardPriority.none,
};

String _priorityLabel(String raw) => switch (_parsePriority(raw)) {
  CardPriority.low => 'Baja',
  CardPriority.medium => 'Media',
  CardPriority.high => 'Alta',
  CardPriority.none => 'Normal',
};

String _reminderLabel(String raw) => switch (raw) {
  'at_due' => 'Al vencer',
  'before_30m' => 'Antes 30 min',
  'before_1d' => 'Un día antes',
  _ => 'Recordatorio',
};

String _formatDateLabel(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final hasTime =
      raw.contains(':') &&
      (parsed.hour != 0 || parsed.minute != 0 || parsed.second != 0);
  return DateFormat(hasTime ? 'd MMM HH:mm' : 'd MMM').format(parsed);
}

class _LatexBlock {
  final String prefix;
  final String latex;
  final String suffix;

  const _LatexBlock({
    required this.prefix,
    required this.latex,
    required this.suffix,
  });
}

String _stripWidgetHtml(String text) {
  return text
      .replaceAll(RegExp(r'</?center>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</?p>', caseSensitive: false), '')
      .trim();
}

_LatexBlock? _extractLatexBlock(String text) {
  final display = RegExp(r'\$\$([\s\S]+?)\$\$').firstMatch(text);
  if (display == null) return null;
  final prefix = text.substring(0, display.start).trim();
  final suffix = text.substring(display.end).trim();
  return _LatexBlock(
    prefix: _trimFormulaLabel(prefix),
    latex: (display.group(1) ?? '').trim(),
    suffix: _trimFormulaLabel(suffix),
  );
}

String? _extractInlineLatex(String text) {
  final match = RegExp(r'^\$([^$]+)\$$').firstMatch(text.trim());
  return match?.group(1)?.trim();
}

String _formulaArtifactContent(String formula) {
  final clean = _sentence(_stripWidgetHtml(formula));
  final block = _extractLatexBlock(clean);
  if (block != null) return block.latex;
  final inline = _extractInlineLatex(clean);
  if (inline != null) return inline;
  return clean.trim();
}

String _trimFormulaLabel(String text) {
  return text.replaceAll(RegExp(r':\s*$'), '').trim();
}

bool _containsMathNotation(String text) =>
    text.contains(r'$') ||
    text.contains(r'\frac') ||
    text.contains(r'\int') ||
    text.contains(r'\lim') ||
    text.contains('∫') ||
    text.contains('∑') ||
    text.contains('√');

bool _isLongMath(String text) =>
    _containsMathNotation(text) && text.length > 42;

void _sendStepQuestion(
  int index,
  String label,
  String detail,
  void Function(String message)? onSendMessage,
) {
  if (onSendMessage == null) return;
  final cleanLabel = _sentence(_plainWidgetText(label));
  final cleanDetail = _plainWidgetText(detail);
  final suffix = cleanDetail.isEmpty ? '' : ' Contexto: $cleanDetail';
  onSendMessage(
    'Explícame con más detalle el paso $index: $cleanLabel.$suffix',
  );
}

Color? _parseColor(String raw) {
  final clean = raw.replaceAll('#', '').trim();
  if (clean.length != 6 && clean.length != 8) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(clean.length == 6 ? (0xFF000000 | value) : value);
}

String _colorHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

List<Map<String, dynamic>> _flashcardItems(Map<String, dynamic> data) {
  final cards =
      _list(data['cards']).isNotEmpty
          ? _list(data['cards'])
          : _list(data['items']).isNotEmpty
          ? _list(data['items'])
          : _list(data['flashcards']);
  if (cards.isNotEmpty) return cards;
  final hasSingle =
      data.containsKey('front') ||
      data.containsKey('back') ||
      data.containsKey('question') ||
      data.containsKey('answer') ||
      data.containsKey('term') ||
      data.containsKey('definition');
  return hasSingle ? [data] : const [];
}

List<Map<String, dynamic>> _quizOptions(Map<String, dynamic> data) {
  final raw =
      data['options'] ??
      data['choices'] ??
      data['answers'] ??
      data['alternatives'] ??
      data['opciones'];
  if (raw is List) {
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final id = String.fromCharCode(97 + i);
      final item = raw[i];
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        map['id'] = _string(map['id'] ?? map['key'], id);
        map['label'] = _string(
          map['label'] ?? map['text'] ?? map['value'] ?? map['answer'],
          id.toUpperCase(),
        );
        result.add(map);
      } else {
        result.add({'id': id, 'label': item.toString()});
      }
    }
    return result;
  }
  if (raw is Map) {
    return raw.entries
        .map(
          (entry) => {
            'id': entry.key.toString().toLowerCase(),
            'label': entry.value.toString(),
          },
        )
        .toList();
  }
  return const [];
}

String _normalizeQuizAnswer(Object? raw, List<Map<String, dynamic>> options) {
  final text = _string(raw, '').toLowerCase().trim();
  if (text.isEmpty) return '';
  if (options.any((option) => _string(option['id'], '') == text)) return text;
  final byLabel = options.firstWhere(
    (option) =>
        _string(option['label'], '').toLowerCase().trim() == text ||
        _string(option['text'], '').toLowerCase().trim() == text,
    orElse: () => const {},
  );
  return _string(byLabel['id'], text);
}

String _joinTextList(Object? value) {
  if (value is! List) return '';
  return value
      .map((item) {
        if (item is Map) {
          return _string(
            item['text'] ?? item['label'] ?? item['detail'] ?? item['value'],
            '',
          );
        }
        return item.toString().trim();
      })
      .where((item) => item.isNotEmpty)
      .join('\n');
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _string(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String _sentence(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

String _plainWidgetText(String text) {
  return text
      .replaceAll(r'$$', '')
      .replaceAll(r'$', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripOuterMath(String text) {
  final trimmed = text.trim();
  final display = RegExp(r'^\$\$([\s\S]+?)\$\$$').firstMatch(trimmed);
  if (display != null) return display.group(1)!.trim();
  final inline = RegExp(r'^\$([^$]+)\$$').firstMatch(trimmed);
  return inline?.group(1)?.trim() ?? trimmed;
}

bool _needsMarkdownText(String text) {
  return text.contains(r'$') ||
      text.contains(r'\(') ||
      text.contains(r'\[') ||
      text.contains('|');
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(_sentence(message)),
      duration: const Duration(seconds: 2),
    ),
  );
}
