import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/reminder_preset.dart';
import '../../../domain/models/task.dart';
import '../../providers/database_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../flight/note_block_widgets.dart'
    show NoteMarkdownPreview, fixMarkdownTables;
import 'ai_widget_contracts.dart';

const _kUserMemoryKey = 'yuli_user_memory_v1';

class AiWidgetRenderer extends ConsumerWidget {
  final String text;
  final Color accent;
  final AiWidgetSurface surface;
  final void Function(String message)? onSendMessage;

  const AiWidgetRenderer({
    super.key,
    required this.text,
    required this.accent,
    required this.surface,
    this.onSendMessage,
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
      );
    }
    if (part is! AiWidgetBlockPart) return const SizedBox.shrink();
    return switch (part.type) {
      'CONCEPT_CARD' => _ConceptCardWidget(data: part.data, accent: accent),
      'STEPS' => _StepsWidget(data: part.data, accent: accent),
      'COMPARISON' => _ComparisonWidget(data: part.data, accent: accent),
      'FLASHCARDS' => _FlashcardsWidget(data: part.data, accent: accent),
      'CHECKLIST' => _ChecklistWidget(data: part.data, accent: accent),
      'QUIZ' => _QuizWidget(data: part.data, accent: accent),
      'OPTIONS' => _OptionsWidget(
        data: part.data,
        accent: accent,
        onSendMessage: onSendMessage,
      ),
      'TASK_LIST' => _TaskListWidget(data: part.data),
      'TASK_DRAFT' => _TaskDraftWidget(data: part.data),
      'LAB_CARD_DRAFT' => _LabCardDraftWidget(data: part.data),
      'MEMORY_SUGGESTION' => _MemorySuggestionWidget(
        data: part.data,
        accent: accent,
      ),
      _ => _UnknownWidget(type: part.type, accent: accent),
    };
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
          Text(
            _sentence(title),
            style: ySans(size: 20, weight: FontWeight.w900, color: yInk),
          ),
          if (definition.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _sentence(definition),
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

  const _StepsWidget({required this.data, required this.accent});

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
          Text(
            _sentence(title),
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            _StepRow(index: i + 1, data: items[i], accent: accent),
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

  const _StepRow({
    required this.index,
    required this.data,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final label = _string(data['label'], 'Paso $index');
    final detail = _string(data['detail'], '');
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
                Text(
                  _sentence(label),
                  style: yBody(size: 14, weight: FontWeight.w900, color: yInk),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _sentence(detail),
                    style: yBody(size: 13, color: yInk2, height: 1.3),
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
          Text(
            _sentence(title),
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
                    pale: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _CompareCell(text: _string(row['right'], ''))),
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
  final bool pale;

  const _CompareCell({required this.text, this.pale = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      decoration: BoxDecoration(
        color: pale ? yCream2 : yCream,
        border: Border.all(color: yBorderStrong, width: yLineThin),
      ),
      child: Text(
        _sentence(text),
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

  @override
  Widget build(BuildContext context) {
    final title = _string(widget.data['title'], 'Tarjetas');
    final cards = _list(widget.data['cards']);
    return _WidgetFrame(
      title: 'Flashcards',
      icon: YuLiIcons.bookOpen,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(title),
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < cards.length; i++) ...[
            _flashcard(i, cards[i]),
            if (i != cards.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _flashcard(int index, Map<String, dynamic> data) {
    final flipped = _flipped.contains(index);
    final front = _string(data['front'], 'Pregunta');
    final back = _string(data['back'], 'Respuesta');
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
            Text(
              _sentence(flipped ? back : front),
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
    return _WidgetFrame(
      title: 'Checklist',
      icon: YuLiIcons.squareCheck,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(title),
            style: ySans(size: 18, weight: FontWeight.w900, color: yInk),
          ),
          const SizedBox(height: 10),
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
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
        decoration: BoxDecoration(
          color: active ? widget.accent.withValues(alpha: 0.14) : yCream2,
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
              child: Text(
                _sentence(label),
                style: yBody(
                  size: 14,
                  weight: FontWeight.w800,
                  color: yInk,
                ).copyWith(
                  decoration: active ? TextDecoration.lineThrough : null,
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
    final question = _string(widget.data['question'], 'Pregunta');
    final answer = _string(widget.data['answer'], '');
    final explanation = _string(widget.data['explanation'], '');
    final options = _list(widget.data['options']);
    return _WidgetFrame(
      title: 'Quiz',
      icon: YuLiIcons.listChecks,
      accent: widget.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _sentence(question),
            style: ySans(size: 18, weight: FontWeight.w800, color: yInk),
          ),
          const SizedBox(height: 12),
          for (final option in options) ...[
            _quizOption(option, answer),
            const SizedBox(height: 8),
          ],
          if (_selected != null && explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            _StatusStrip(
              color: _selected == answer ? yLab : yFight,
              text: _selected == answer ? 'Correcto' : 'Revisa la explicación',
            ),
            const SizedBox(height: 8),
            Text(
              _sentence(explanation),
              style: yBody(size: 13, color: yInk2, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quizOption(Map<String, dynamic> option, String answer) {
    final id = _string(option['id'], '');
    final label = _string(option['label'], id.toUpperCase());
    final selected = _selected == id;
    final correct = selected && id == answer;
    final wrong = selected && id != answer;
    final color = correct ? yLab : (wrong ? yFight : widget.accent);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _selected = id);
        HapticFeedback.selectionClick();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: selected ? color : yCream,
          border: Border.all(color: yBorderStrong, width: yLineThin),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? yCream : color,
                border: Border.all(color: yBorderStrong, width: yLineThin),
              ),
              child: Text(
                id.toUpperCase(),
                style: yMono(
                  size: 11,
                  weight: FontWeight.w800,
                  color: selected ? yInk : yCream,
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
                  color: selected ? yCream : yInk,
                ),
              ),
            ),
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

  const _TaskDraftWidget({required this.data});

  @override
  ConsumerState<_TaskDraftWidget> createState() => _TaskDraftWidgetState();
}

class _TaskDraftWidgetState extends ConsumerState<_TaskDraftWidget> {
  late String _content = _string(widget.data['content'], 'Nueva tarea');
  bool _memoryEnabled = true;
  bool _busy = false;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    final folder = _map(widget.data['folder']);
    final due = _string(widget.data['dueDate'], '');
    final reminder = _string(widget.data['reminderPreset'], '');
    final memory = _map(widget.data['temporaryMemory']);
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
              if (folder != null)
                _FolderBadge(folder: folder, fallback: yFight),
              if (due.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.calendar,
                  label: 'Fecha ${_formatDateLabel(due)}',
                  color: yFight,
                ),
              if (reminder.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.bell,
                  label: _reminderLabel(reminder),
                  color: yFight,
                ),
            ],
          ),
          if (memory != null) ...[
            const SizedBox(height: 12),
            _ToggleRow(
              active: _memoryEnabled,
              label: 'Guardar recuerdo temporal',
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
    final ctrl = TextEditingController(text: _content);
    final next = await showDialog<String>(
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
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    style: yBody(size: 15, color: yInk),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                    ),
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
                          onTap: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
    ctrl.dispose();
    if (next == null || next.isEmpty) return;
    setState(() => _content = next);
  }

  Future<void> _create() async {
    if (_content.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final due = _parseDueDate(
        _string(widget.data['dueDate'], ''),
        _string(widget.data['duePrecision'], ''),
      );
      final preset = _parseReminder(_string(widget.data['reminderPreset'], ''));
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
      final memory = _map(widget.data['temporaryMemory']);
      if (_memoryEnabled && memory != null) {
        await _saveMemory(memory, linkedTaskId: task.id);
      }
      if (!mounted) return;
      setState(() => _created = true);
      _snack(context, 'Tarea creada');
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo crear la tarea');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int?> _resolveFolderId() async {
    final folder = _map(widget.data['folder']);
    if (folder == null) return null;
    final id = _int(folder['id']);
    if (id != null &&
        await ref.read(folderRepositoryProvider).getById(id) != null) {
      return id;
    }
    final name = _string(folder['name'], '').toLowerCase().trim();
    if (name.isEmpty) return null;
    final folders = await ref.read(folderRepositoryProvider).getActive();
    return folders
        .where((f) => f.name.toLowerCase().trim() == name)
        .firstOrNull
        ?.id;
  }
}

class _LabCardDraftWidget extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;

  const _LabCardDraftWidget({required this.data});

  @override
  ConsumerState<_LabCardDraftWidget> createState() =>
      _LabCardDraftWidgetState();
}

class _LabCardDraftWidgetState extends ConsumerState<_LabCardDraftWidget> {
  late String _title = _string(
    widget.data['title'] ?? widget.data['content'],
    'Nueva tarjeta',
  );
  bool _busy = false;
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    final description = _string(widget.data['description'], '');
    final space = _spaceName();
    final column = _string(widget.data['column'], '');
    final due = _string(widget.data['dueDate'], '');
    final reminder = _string(widget.data['reminderPreset'], '');
    final priority = _string(widget.data['priority'], '');
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
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _sentence(description),
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
              if (column.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.kanban,
                  label: 'Columna $column',
                  color: yLab,
                ),
              if (priority.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.triangleAlert,
                  label: 'Prioridad ${_priorityLabel(priority)}',
                  color: yLab,
                ),
              if (due.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.calendar,
                  label: 'Fecha ${_formatDateLabel(due)}',
                  color: yLab,
                ),
              if (reminder.isNotEmpty)
                _MiniBadge(
                  icon: YuLiIcons.bell,
                  label: _reminderLabel(reminder),
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
    final raw = widget.data['space'];
    final map = _map(raw);
    if (map != null) return _string(map['name'], '');
    return _string(raw, '');
  }

  Future<void> _edit() async {
    final ctrl = TextEditingController(text: _title);
    final next = await showDialog<String>(
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
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    style: yBody(size: 15, color: yInk),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: yBorderStrong,
                          width: yLineMid,
                        ),
                      ),
                    ),
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
                          onTap: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
    ctrl.dispose();
    if (next == null || next.isEmpty) return;
    setState(() => _title = next);
  }

  Future<void> _create() async {
    if (_title.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final space = await _resolveSpace();
      if (space == null) {
        if (mounted) _snack(context, 'No encontré el proyecto Lab');
        return;
      }
      final column = await _resolveColumn(space.id);
      if (column == null) {
        if (mounted) _snack(context, 'No encontré una columna válida');
        return;
      }
      final due = _parseDueDate(
        _string(widget.data['dueDate'], ''),
        _string(widget.data['duePrecision'], ''),
      );
      final preset = _parseReminder(_string(widget.data['reminderPreset'], ''));
      await ref
          .read(kanbanCardRepositoryProvider)
          .create(
            labSpaceId: space.id,
            columnId: column.id,
            title: _title.trim(),
            description: _nullableString(widget.data['description']),
            priority: _parsePriority(_string(widget.data['priority'], '')),
            dueDate: due,
            remindAt:
                preset == null ? null : reminderTimeForPreset(preset, due),
            reminderPreset: preset,
          );
      if (!mounted) return;
      setState(() => _created = true);
      _snack(context, 'Tarjeta creada');
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo crear la tarjeta');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LabSpace?> _resolveSpace() async {
    final raw = widget.data['space'];
    final map = _map(raw);
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
    final wanted = _string(widget.data['column'], '').toLowerCase().trim();
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

  const _MemorySuggestionWidget({required this.data, required this.accent});

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
        await _saveMemory(items[index]);
      }
    }
    if (!mounted) return;
    setState(() => _saved = true);
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
                Text(
                  _sentence(text),
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

Future<void> _saveMemory(Map<String, dynamic> item, {int? linkedTaskId}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kUserMemoryKey);
  final existing =
      raw == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(raw) as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
  final record = {
    'key': _string(item['key'], 'memory'),
    'label': _string(item['label'], _string(item['key'], 'Memoria')),
    'value': _string(item['value'] ?? item['text'], ''),
    'scope': _string(item['scope'], 'global'),
    'expiresAt': item['expiresAt'],
    'createdAt': DateTime.now().toIso8601String(),
    if (linkedTaskId != null) 'linkedTaskId': linkedTaskId,
  };
  if (_string(record['value'], '').isEmpty) return;
  existing.removeWhere(
    (m) =>
        m['key'] == record['key'] &&
        m['scope'] == record['scope'] &&
        m['value'] == record['value'],
  );
  existing.add(record);
  await prefs.setString(_kUserMemoryKey, jsonEncode(existing));
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

Color? _parseColor(String raw) {
  final clean = raw.replaceAll('#', '').trim();
  if (clean.length != 6 && clean.length != 8) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(clean.length == 6 ? (0xFF000000 | value) : value);
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
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

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(_sentence(message)),
      duration: const Duration(seconds: 2),
    ),
  );
}
