import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/folder_providers.dart';
import '../../theme/lab_icons.dart';
import '../../widgets/yuli_design.dart';
import '../../../domain/models/folder.dart';
import '../../../domain/models/kanban_card.dart';
import '../../../domain/models/lab_space.dart';
import '../../../domain/models/task.dart';
import '../../../domain/services/ai_assistant.dart';

// ─── YuLi AI tools (function calling) ────────────────────────────────────────
// v2 is READ-ONLY: the model can consult the user's tasks and lab projects.
// Writes (create/complete/delete) are v3 — adding one is just another entry in
// [_tools] with a handler. Handlers return a compact JSON string (token-cheap).

typedef _ToolHandler =
    Future<String> Function(WidgetRef ref, Map<String, dynamic> args);

class _YuliTool {
  final AiToolDef def;
  final _ToolHandler handler;
  const _YuliTool(this.def, this.handler);
}

/// Tool definitions sent to the model.
List<AiToolDef> get yuliToolDefs => _tools.map((t) => t.def).toList();

/// Execute a tool call and return its JSON result (errors are returned as JSON
/// so the model can recover, never thrown).
Future<String> runYuliTool(WidgetRef ref, AiToolCall call) async {
  final tool = _tools.where((t) => t.def.name == call.name).firstOrNull;
  if (tool == null) {
    return jsonEncode({'error': 'Herramienta desconocida: ${call.name}'});
  }
  try {
    final args =
        call.arguments.trim().isEmpty
            ? <String, dynamic>{}
            : (jsonDecode(call.arguments) as Map).cast<String, dynamic>();
    return await tool.handler(ref, args);
  } catch (e) {
    return jsonEncode({'error': '$e'});
  }
}

// ─── System role addons ─────────────────────────────────────────────────────

/// Appended to the BASE prompt for the dedicated YuLi AI chat: tools are its
/// whole point, so it uses them proactively.
String yuliToolSystem() =>
    'Eres YuLi, el asistente del "segundo cerebro" del usuario (una app de '
    'tareas y proyectos). Puedes consultar de forma interna sus tareas '
    '(FIGHT) y sus proyectos/tableros kanban (LAB). Hazlo con naturalidad '
    'siempre que la pregunta requiera datos reales existentes del usuario; no '
    'inventes tareas existentes, fechas existentes ni proyectos existentes que '
    'no vengan de información validada por YuLi. Si el usuario pide crear una '
    'tarea nueva, NO te niegues: propón un borrador confirmable con los datos '
    'que el usuario dio. No menciones nombres '
    'de herramientas, llamadas internas, tablas, columnas, JSON, IDs ni detalles '
    'técnicos: habla como producto ("tus tareas", "tu proyecto", "lo que hay en '
    'YuLi"). Responde breve y directo, en el idioma del usuario. Hoy es ${_today()}.';

/// Appended in the FLIGHT note chat: same tools, but it must NOT reach for them
/// unless the user explicitly asks about their tasks/projects — its main job is
/// the note.
String flightToolSystem() =>
    'Además de tu rol, puedes consultar internamente las tareas (FIGHT) y '
    'los proyectos kanban (LAB) del usuario. Úsalas SOLO si el usuario lo pide '
    'de forma explícita (p. ej. "¿qué tengo pendiente?", "¿cómo va el proyecto '
    'X?", "crea una tarea"). Para todo lo demás ignóralas y céntrate en la '
    'nota. No inventes datos existentes: si consultas tareas/proyectos reales, '
    'que vengan de información validada por YuLi. Si el usuario pide crear una '
    'tarea nueva, NO la ejecutes tú: propón un borrador confirmable. No menciones '
    'nombres de herramientas, llamadas internas, '
    'tablas, columnas, JSON, IDs ni detalles técnicos: habla como producto. '
    'Hoy es ${_today()}.';

// ─── Tools ──────────────────────────────────────────────────────────────────

final List<_YuliTool> _tools = [
  _YuliTool(
    const AiToolDef(
      name: 'list_tasks',
      description:
          'Lista las tareas del usuario (FIGHT). status: today=pendientes de '
          'hoy, yesterday=de ayer, overdue=vencidas, done=hechas hoy, all=todas.',
      parameters: {
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'enum': ['today', 'yesterday', 'overdue', 'done', 'all'],
            'description': 'Grupo de tareas. Por defecto today.',
          },
          'folder': {
            'type': 'string',
            'description': 'Nombre de carpeta para filtrar (opcional).',
          },
        },
      },
    ),
    _listTasks,
  ),
  _YuliTool(
    const AiToolDef(
      name: 'list_lab_spaces',
      description:
          'Lista los proyectos activos del usuario en LAB con sus fechas y '
          'progreso temporal.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    _listLabSpaces,
  ),
  _YuliTool(
    const AiToolDef(
      name: 'list_cards',
      description:
          'Lista las tarjetas de un proyecto LAB, agrupadas por columna. '
          'Indica el nombre del proyecto en "space".',
      parameters: {
        'type': 'object',
        'properties': {
          'space': {
            'type': 'string',
            'description': 'Nombre del proyecto/space.',
          },
          'column': {
            'type': 'string',
            'description': 'Filtrar por nombre de columna (opcional).',
          },
        },
        'required': ['space'],
      },
    ),
    _listCards,
  ),
];

// ─── Handlers ────────────────────────────────────────────────────────────────

Future<String> _listTasks(WidgetRef ref, Map<String, dynamic> args) async {
  final repo = ref.read(taskRepositoryProvider);
  final status = (args['status'] as String?)?.toLowerCase() ?? 'today';
  final folders = await ref.read(activeFoldersProvider.future);
  final byId = {for (final f in folders) f.id: f.name};

  Future<List<Task>> snap(String s) async => switch (s) {
    'today' => await repo.watchPending().first,
    'yesterday' => await repo.watchYesterday().first,
    'overdue' => await repo.watchVencidas().first,
    'done' => await repo.watchDoneToday().first,
    _ => [
      ...await repo.watchPending().first,
      ...await repo.watchYesterday().first,
      ...await repo.watchVencidas().first,
      ...await repo.watchDoneToday().first,
    ],
  };

  var tasks = await snap(status);

  final folderArg = (args['folder'] as String?)?.trim();
  if (folderArg != null && folderArg.isNotEmpty) {
    final fid = _matchFolder(folders, folderArg)?.id;
    if (fid == null) {
      return jsonEncode({'error': 'No encontré la carpeta "$folderArg".'});
    }
    tasks = tasks.where((t) => t.folderId == fid).toList();
  }

  final items =
      tasks
          .take(60)
          .map(
            (t) => {
              'content': t.content,
              'status': t.status.toDbString(),
              if (t.folderId != null) 'folder': byId[t.folderId],
              if (t.dueDate != null) 'due': _d(t.dueDate),
            },
          )
          .toList();
  return jsonEncode({'status': status, 'count': tasks.length, 'tasks': items});
}

Future<String> _listLabSpaces(WidgetRef ref, Map<String, dynamic> _) async {
  final spaces = await ref.read(labSpaceRepositoryProvider).getActive();
  final now = DateTime.now();
  final items =
      spaces
          .where((s) => s.status == LabSpaceStatus.active)
          .map(
            (s) => {
              'name': s.name,
              if (s.startDate != null) 'start': _d(s.startDate),
              if (s.dueDate != null) 'due': _d(s.dueDate),
              if (s.startDate != null && s.dueDate != null)
                'progress': _progress(s.startDate!, s.dueDate!, now),
            },
          )
          .toList();
  return jsonEncode({'count': items.length, 'spaces': items});
}

Future<String> _listCards(WidgetRef ref, Map<String, dynamic> args) async {
  final name = (args['space'] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    return jsonEncode({'error': 'Falta el nombre del proyecto.'});
  }
  final spaces = await ref.read(labSpaceRepositoryProvider).getActive();
  final space = _matchSpace(spaces, name);
  if (space == null) {
    return jsonEncode({'error': 'No encontré el proyecto "$name".'});
  }
  final labRepo = ref.read(labSpaceRepositoryProvider);
  final cardRepo = ref.read(kanbanCardRepositoryProvider);
  final columns = await labRepo.getColumns(space.id);
  final cards = await cardRepo.watchBySpace(space.id).first;
  final colFilter = (args['column'] as String?)?.trim().toLowerCase();

  final out = <Map<String, dynamic>>[];
  for (final col in columns) {
    if (colFilter != null &&
        colFilter.isNotEmpty &&
        !col.name.toLowerCase().contains(colFilter)) {
      continue;
    }
    final colCards =
        cards.where((c) => c.columnId == col.id).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    out.add({
      'column': col.name,
      'cards':
          colCards
              .map(
                (c) => {
                  'title': c.title,
                  if (c.description != null && c.description!.trim().isNotEmpty)
                    'description': c.description!.trim(),
                  if (c.priority != CardPriority.none)
                    'priority': c.priority.toDbString(),
                  if (c.dueDate != null) 'due': _d(c.dueDate),
                  if (c.originTaskDoneAt != null) 'done': true,
                },
              )
              .toList(),
    });
  }
  return jsonEncode({'space': space.name, 'columns': out});
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Folder? _matchFolder(List<Folder> folders, String q) {
  final ql = q.toLowerCase();
  return folders.where((f) => f.name.toLowerCase() == ql).firstOrNull ??
      folders.where((f) => f.name.toLowerCase().contains(ql)).firstOrNull;
}

LabSpace? _matchSpace(List<LabSpace> spaces, String q) {
  final ql = q.toLowerCase();
  return spaces.where((s) => s.name.toLowerCase() == ql).firstOrNull ??
      spaces.where((s) => s.name.toLowerCase().contains(ql)).firstOrNull;
}

int _progress(DateTime start, DateTime end, DateTime now) {
  if (!end.isAfter(start)) return 0;
  final total = end.difference(start).inMinutes;
  final elapsed = now.difference(start).inMinutes;
  return ((elapsed / total) * 100).clamp(0, 100).round();
}

String _today() => _d(DateTime.now(), dateOnly: true)!;

String? _d(DateTime? dt, {bool dateOnly = false}) {
  if (dt == null) return null;
  final d =
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  if (dateOnly || (dt.hour == 0 && dt.minute == 0)) return d;
  return '$d ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Spinning refresh icon shown while the AI queries tasks/lab data.
class ConsultingIndicator extends StatefulWidget {
  final Color accent;
  const ConsultingIndicator({super.key, required this.accent});
  @override
  State<ConsultingIndicator> createState() => _ConsultingIndicatorState();
}

class _ConsultingIndicatorState extends State<ConsultingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder:
                (_, child) =>
                    Transform.rotate(angle: _ctrl.value * 6.2832, child: child),
            child: Icon(YuLiIcons.refresh, size: 16, color: widget.accent),
          ),
          const SizedBox(width: 10),
          Text('Consultando…', style: yBody(size: 13, color: widget.accent)),
        ],
      ),
    );
  }
}
