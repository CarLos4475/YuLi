import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/lab_space_providers.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/kanban_column.dart';
import '../../../domain/services/ai_assistant.dart';
import '../flight/note_block_widgets.dart'
    show NoteMarkdownPreview, fixMarkdownTables;
import '../flight/ai_chat_sheet.dart' show showLabChat;

// ─── YuLi · LAB — one-shot AI actions for a space ──────────────────────────
// (Chat about the space is phase 2; this same sheet will host it later.)

enum _LabAction { generate, summarize, chat }

/// Open the "YuLi · LAB" action panel. One-shot actions run with the caller's
/// [context]/[ref] (which outlive the sheet) after it pops with a choice.
Future<void> showLabAiSheet(
    BuildContext context, WidgetRef ref, LabSpace space) async {
  final hasKey = await ref.read(aiKeyStoreProvider).hasKey();
  if (!context.mounted) return;
  if (!hasKey) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Configura tu API key de DeepSeek en Ajustes'),
        duration: Duration(seconds: 3)));
    return;
  }
  final action = await showModalBottomSheet<_LabAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _LabAiSheet(space: space),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _LabAction.generate:
      await _generateCards(context, ref, space);
    case _LabAction.summarize:
      await _summarizeBoard(context, ref, space);
    case _LabAction.chat:
      await showLabChat(
        context,
        ref,
        spaceId: space.id,
        boardLabel: space.name,
        accent: space.accentColor,
        buildContext: () async {
          final cols = await ref.read(kanbanColumnsProvider(space.id).future);
          final cards =
              await ref.read(kanbanCardsBySpaceProvider(space.id).future);
          return _serializeBoard(space, cols, cards);
        },
      );
  }
}

class _LabAiSheet extends StatelessWidget {
  final LabSpace space;
  const _LabAiSheet({required this.space});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 10, height: 10, color: space.accentColor),
              const SizedBox(width: 8),
              Text('YuLi · LAB',
                  style: yMono(
                      size: 12,
                      weight: FontWeight.w700,
                      tracking: 1.6,
                      color: yInk)),
              const Spacer(),
              Flexible(
                child: Text(space.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: yMono(size: 10, color: yMuted, tracking: 1)),
              ),
            ]),
            const SizedBox(height: 10),
            Text('// ACCIONES SOBRE EL PROYECTO',
                style: yMono(
                    size: 10,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yMuted)),
            const SizedBox(height: 12),
            _action(Icons.auto_awesome, 'Generar tarjetas',
                'Desglosa un objetivo en tarjetas (a Backlog)',
                () => Navigator.of(context).pop(_LabAction.generate)),
            const SizedBox(height: 8),
            _action(Icons.notes, 'Resumir / triage',
                'Resume el avance y qué sigue',
                () => Navigator.of(context).pop(_LabAction.summarize)),
            const SizedBox(height: 8),
            _action(Icons.forum, 'Chat del proyecto',
                'Conversa con el board como contexto',
                () => Navigator.of(context).pop(_LabAction.chat)),
          ],
        ),
      ),
    );
  }

  Widget _action(
      IconData icon, String label, String sub, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: yCream,
          border: Border.all(color: yInk, width: yLineMid),
          boxShadow: const [BoxShadow(color: yInk, offset: Offset(3, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: space.accentColor,
                border: Border.all(color: yInk, width: yLineMid),
              ),
              child: Icon(icon, color: yCream, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          ySans(size: 15, weight: FontWeight.w700, color: yInk)),
                  Text(sub, style: yBody(size: 12, color: yMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Generate cards ─────────────────────────────────────────────────────────

Future<void> _generateCards(
    BuildContext context, WidgetRef ref, LabSpace space) async {
  final ctrl = TextEditingController();
  final prompt = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text('Generar tarjetas',
          style: ySans(size: 18, weight: FontWeight.w700)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(
            hintText: '¿Qué proyecto/objetivo desgloso en tarjetas?'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Generar')),
      ],
    ),
  );
  if (prompt == null || prompt.trim().isEmpty || !context.mounted) return;

  final limiter = ref.read(aiUsageLimiterProvider);
  if (!await limiter.canSend()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Límite diario de IA alcanzado.'),
        duration: Duration(seconds: 2)));
    return;
  }
  if (!context.mounted) return;

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  await limiter.record();
  final today = DateTime.now();
  final todayStr = _iso(today);
  final window = (space.startDate != null && space.dueDate != null)
      ? ' El proyecto va del ${_iso(space.startDate!)} al ${_iso(space.dueDate!)}.'
      : '';
  final buf = StringBuffer();
  String? err;
  try {
    await for (final tok in ref.read(aiAssistantProvider).streamReply([
      AiMessage(
          AiRole.system,
          'Eres un planificador de proyectos. Desglosa lo que pida el usuario '
          'en tarjetas accionables de un tablero Kanban. Responde SOLO con una '
          'tarjeta por línea, con este formato EXACTO:\n'
          'título :: prioridad :: inicio :: fin\n'
          '- prioridad ∈ {none, low, medium, high}\n'
          '- inicio y fin en formato AAAA-MM-DD (deja el campo vacío si no '
          'aplica, pero conserva los ::)\n'
          '- sin numerar, sin viñetas, sin texto adicional, máximo 12 tarjetas.\n'
          'Hoy es $todayStr.$window'),
      AiMessage(AiRole.user, prompt.trim()),
    ], model: AiModel.flash)) {
      buf.write(tok);
    }
  } catch (e) {
    err = '$e';
  }
  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return;
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)));
    return;
  }
  final proposals = _parseProposals(buf.toString());
  if (proposals.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No pude generar tarjetas.'),
        duration: Duration(seconds: 2)));
    return;
  }
  final columns = await ref.read(kanbanColumnsProvider(space.id).future);
  if (!context.mounted || columns.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LabCardReviewSheet(
        space: space, columns: columns, proposals: proposals),
  );
}

List<_CardProposal> _parseProposals(String raw) {
  final out = <_CardProposal>[];
  for (final line in raw.split('\n')) {
    final s = line.trim();
    if (s.isEmpty || !s.contains('::')) continue;
    final parts = s.split('::').map((p) => p.trim()).toList();
    var title = parts.isNotEmpty ? parts[0] : '';
    title = title.replaceFirst(RegExp(r'^\s*([-*•]|\d+[.)])\s*'), '').trim();
    if (title.isEmpty) continue;
    final pr = parts.length > 1 ? _parsePriority(parts[1]) : CardPriority.none;
    final start = parts.length > 2 ? DateTime.tryParse(parts[2]) : null;
    final due = parts.length > 3 ? DateTime.tryParse(parts[3]) : null;
    out.add(_CardProposal(
        title: title, priority: pr, startDate: start, dueDate: due));
    if (out.length >= 12) break;
  }
  return out;
}

CardPriority _parsePriority(String s) {
  switch (s.toLowerCase().trim()) {
    case 'low':
    case 'baja':
      return CardPriority.low;
    case 'medium':
    case 'media':
      return CardPriority.medium;
    case 'high':
    case 'alta':
      return CardPriority.high;
    default:
      return CardPriority.none;
  }
}

// ─── Summarize / triage ─────────────────────────────────────────────────────

Future<void> _summarizeBoard(
    BuildContext context, WidgetRef ref, LabSpace space) async {
  final limiter = ref.read(aiUsageLimiterProvider);
  if (!await limiter.canSend()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Límite diario de IA alcanzado.'),
        duration: Duration(seconds: 2)));
    return;
  }
  final columns = await ref.read(kanbanColumnsProvider(space.id).future);
  final cards = await ref.read(kanbanCardsBySpaceProvider(space.id).future);
  if (!context.mounted) return;
  final board = _serializeBoard(space, columns, cards);
  if (board.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El tablero está vacío.'),
        duration: Duration(seconds: 2)));
    return;
  }
  if (!context.mounted) return;

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  await limiter.record();
  final buf = StringBuffer();
  String? err;
  try {
    await for (final tok in ref.read(aiAssistantProvider).streamReply([
      const AiMessage(
          AiRole.system,
          'Eres un asistente de gestión de proyectos. Te paso el estado de un '
          'tablero Kanban. Devuelve en markdown: un resumen breve del avance, '
          'qué está atorado o vencido, y 2-4 sugerencias de qué hacer a '
          'continuación. Sé conciso y directo. No inventes tarjetas que no '
          'estén en el tablero.'),
      AiMessage(AiRole.user, board),
    ], model: AiModel.flash)) {
      buf.write(tok);
    }
  } catch (e) {
    err = '$e';
  }
  if (navigator.canPop()) navigator.pop();
  if (!context.mounted) return;
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 3)));
    return;
  }
  final summary = buf.toString().trim();
  if (summary.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _SummaryDialog(text: summary, accent: space.accentColor),
  );
}

String _serializeBoard(
    LabSpace space, List<KanbanColumn> columns, List<KanbanCard> cards) {
  final buf = StringBuffer();
  buf.writeln('# Proyecto: ${space.name}');
  if (space.startDate != null || space.dueDate != null) {
    buf.writeln(
        'Rango: ${space.startDate != null ? _iso(space.startDate!) : '—'} → '
        '${space.dueDate != null ? _iso(space.dueDate!) : '—'}');
  }
  buf.writeln('Hoy: ${_iso(DateTime.now())}\n');
  for (final col in columns) {
    final colCards = cards.where((c) => c.columnId == col.id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    buf.writeln('## ${col.name} (${colCards.length})');
    if (colCards.isEmpty) {
      buf.writeln('(vacía)');
    } else {
      for (final c in colCards) {
        final bits = <String>[];
        if (c.priority != CardPriority.none) {
          bits.add('prioridad ${c.priority.toDbString()}');
        }
        if (c.dueDate != null) bits.add('vence ${_iso(c.dueDate!)}');
        if (c.originTaskDoneAt != null) bits.add('hecha');
        final meta = bits.isEmpty ? '' : ' — ${bits.join(', ')}';
        buf.writeln('- ${cleanMention(c.title)}$meta');
      }
    }
    buf.writeln();
  }
  return buf.toString().trim();
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ─── Models / dialogs ───────────────────────────────────────────────────────

class _CardProposal {
  String title;
  CardPriority priority;
  DateTime? startDate;
  DateTime? dueDate;
  bool include = true;
  _CardProposal({
    required this.title,
    this.priority = CardPriority.none,
    this.startDate,
    this.dueDate,
  });
}

class _SummaryDialog extends StatelessWidget {
  final String text;
  final Color accent;
  const _SummaryDialog({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: yCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        decoration:
            BoxDecoration(border: Border.all(color: yInk, width: yLineHeavy)),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(width: 8, height: 8, color: accent),
              const SizedBox(width: 8),
              Text('RESUMEN / TRIAGE',
                  style: yMono(
                      size: 11,
                      weight: FontWeight.w700,
                      tracking: 1.4,
                      color: yInk)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, size: 18, color: yInk),
              ),
            ]),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: NoteMarkdownPreview(data: fixMarkdownTables(text)),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.of(context).pop();
              },
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  border: Border.all(color: yInk, width: yLineMid),
                ),
                child: Text('COPIAR',
                    style: yMono(
                        size: 12,
                        weight: FontWeight.w700,
                        tracking: 1.2,
                        color: yCream)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Review sheet (edit proposals → create in Backlog) ──────────────────────

class _LabCardReviewSheet extends ConsumerStatefulWidget {
  final LabSpace space;
  final List<KanbanColumn> columns;
  final List<_CardProposal> proposals;
  const _LabCardReviewSheet({
    required this.space,
    required this.columns,
    required this.proposals,
  });

  @override
  ConsumerState<_LabCardReviewSheet> createState() =>
      _LabCardReviewSheetState();
}

class _LabCardReviewSheetState extends ConsumerState<_LabCardReviewSheet> {
  late final List<_CardProposal> _items;
  late final List<TextEditingController> _ctrls;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = widget.proposals;
    _ctrls =
        _items.map((p) => TextEditingController(text: p.title)).toList();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  KanbanColumn get _backlog => widget.columns.firstWhere(
        (c) => c.name.toLowerCase() == 'backlog',
        orElse: () => widget.columns.first,
      );

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(kanbanCardRepositoryProvider);
    final col = _backlog;
    var created = 0;
    for (int i = 0; i < _items.length; i++) {
      final p = _items[i];
      if (!p.include) continue;
      final title = _ctrls[i].text.trim();
      if (title.isEmpty) continue;
      await repo.create(
        labSpaceId: widget.space.id,
        columnId: col.id,
        title: title,
        priority: p.priority,
        dueDate: p.dueDate,
        startDate: p.startDate,
      );
      created++;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$created tarjeta(s) creada(s) en ${col.name}'),
        duration: const Duration(seconds: 2)));
  }

  Future<void> _pickDate(int i, {required bool start}) async {
    final p = _items[i];
    final initial = (start ? p.startDate : p.dueDate) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          dialogTheme: DialogThemeData(backgroundColor: paperColor(ctx)),
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: inkColor(ctx), onPrimary: paperColor(ctx)),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    setState(() {
      if (start) {
        p.startDate = DateTime(date.year, date.month, date.day);
      } else {
        p.dueDate = DateTime(date.year, date.month, date.day);
      }
    });
  }

  void _cyclePriority(int i) {
    final order = [
      CardPriority.none,
      CardPriority.low,
      CardPriority.medium,
      CardPriority.high
    ];
    setState(() {
      final cur = order.indexOf(_items[i].priority);
      _items[i].priority = order[(cur + 1) % order.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _items.where((p) => p.include).length;
    return Container(
      decoration: const BoxDecoration(
        color: yCream,
        border: Border(top: BorderSide(color: yInk, width: yLineHeavy)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('REVISAR TARJETAS → ${_backlog.name.toUpperCase()}',
                style: yMono(
                    size: 11,
                    weight: FontWeight.w700,
                    tracking: 1.4,
                    color: yInk)),
            const SizedBox(height: 4),
            Text('Edita, ajusta fechas/prioridad y desmarca las que no quieras.',
                style: yBody(size: 12, color: yMuted)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (_, i) => _row(i),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: n == 0 || _busy ? null : _create,
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: n == 0 ? yCream2 : widget.space.accentColor,
                  border: Border.all(color: yInk, width: yLineMid),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: yCream))
                    : Text('CREAR $n',
                        style: yMono(
                            size: 12,
                            weight: FontWeight.w700,
                            tracking: 1.2,
                            color: n == 0 ? yMuted : yCream)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(int i) {
    final p = _items[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: p.include ? yCream : yCream2,
        border: Border.all(color: yInk, width: yLineThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => p.include = !p.include),
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.include ? yInk : yCream,
                    border: Border.all(color: yInk, width: yLineThin),
                  ),
                  child: p.include
                      ? const Text('✓',
                          style: TextStyle(
                              fontSize: 12,
                              color: yCream,
                              height: 1.0,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrls[i],
                  style: yBody(size: 14, weight: FontWeight.w600, color: yInk),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(_priorityLabel(p.priority), _priorityColor(p.priority),
                  () => _cyclePriority(i)),
              _chip(
                  p.startDate == null
                      ? '+ inicio'
                      : 'inicio ${_short(p.startDate!)}',
                  yCream,
                  () => _pickDate(i, start: true)),
              _chip(
                  p.dueDate == null ? '+ due' : 'due ${_short(p.dueDate!)}',
                  yCream,
                  () => _pickDate(i, start: false)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color bg, VoidCallback onTap) {
    final dark = bg.computeLuminance() < 0.5;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: yInk, width: 1.5),
        ),
        child: Text(label,
            style: yMono(
                size: 10,
                weight: FontWeight.w700,
                tracking: 0.8,
                color: dark ? yCream : yInk)),
      ),
    );
  }

  String _priorityLabel(CardPriority p) => switch (p) {
        CardPriority.none => 'prioridad —',
        CardPriority.low => 'baja',
        CardPriority.medium => 'media',
        CardPriority.high => 'alta',
      };

  // Matches labPriorityColor (board/timeline/calendar). "none" stays cream so
  // the empty-priority chip reads as neutral.
  Color _priorityColor(CardPriority p) => switch (p) {
        CardPriority.none => yCream,
        CardPriority.low => yLab,
        CardPriority.medium => yAmber,
        CardPriority.high => yFight,
      };

  String _short(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
