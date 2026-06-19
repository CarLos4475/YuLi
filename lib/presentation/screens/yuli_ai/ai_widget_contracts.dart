import 'dart:convert';

enum AiWidgetSurface { yuli, flight }

enum AiWidgetPolicy { study, appData, appWrite, memory }

class AiWidgetSpec {
  final String type;
  final int version;
  final String description;
  final List<String> triggerKeywords;
  final AiWidgetPolicy policy;
  final String promptContract;

  const AiWidgetSpec({
    required this.type,
    required this.version,
    required this.description,
    required this.triggerKeywords,
    required this.policy,
    required this.promptContract,
  });

  String get promptDoc =>
      '<widget_spec id="${type.toLowerCase()}_v$version">\n'
      '$description\n'
      '$promptContract\n'
      '</widget_spec>';
}

class AiWidgetRetriever {
  const AiWidgetRetriever();

  List<AiWidgetSpec> retrieve(
    String query, {
    required AiWidgetSurface surface,
    int k = 3,
  }) {
    final q = _normalize(query);
    final explicitApp = _explicitAppIntent(q);
    final scored = <({AiWidgetSpec spec, int score})>[];
    for (final spec in kAiWidgetSpecs) {
      if (surface == AiWidgetSurface.flight &&
          _needsExplicitIntent(spec.policy) &&
          !explicitApp) {
        continue;
      }
      final score = spec.triggerKeywords.fold<int>(0, (sum, keyword) {
        final key = _normalize(keyword);
        if (q == key) return sum + 4;
        if (q.contains(key)) return sum + 3;
        if (q.split(' ').any((part) => part.startsWith(key))) return sum + 1;
        return sum;
      });
      if (score > 0) scored.add((spec: spec, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.spec.type.compareTo(b.spec.type);
    });
    return scored.take(k).map((e) => e.spec).toList();
  }

  bool _needsExplicitIntent(AiWidgetPolicy policy) =>
      policy == AiWidgetPolicy.appData || policy == AiWidgetPolicy.appWrite;

  bool _explicitAppIntent(String q) {
    const keys = [
      'fight',
      'lab',
      'kanban',
      'tarea',
      'pendiente',
      'recordatorio',
      'proyecto',
      'card',
      'tarjeta',
      'tarjeta lab',
      'card lab',
      'crea',
      'crear tarea',
      'crea una tarea',
      'guardame',
      'guarda',
      'guardar memoria',
      'guarda eso',
      'memoria',
      'recuerdame',
      'memoriza',
    ];
    return keys.any((key) => q.contains(_normalize(key)));
  }
}

sealed class AiWidgetPart {
  const AiWidgetPart();
}

class AiWidgetTextPart extends AiWidgetPart {
  final String text;

  const AiWidgetTextPart(this.text);
}

class AiWidgetBlockPart extends AiWidgetPart {
  final String type;
  final int version;
  final Map<String, dynamic> data;
  final String raw;

  const AiWidgetBlockPart({
    required this.type,
    required this.version,
    required this.data,
    required this.raw,
  });
}

class AiWidgetParser {
  static final RegExp _block = RegExp(
    r'<!--YULI_WIDGET:([A-Z_]+)\s+v=(\d+)\s*([\s\S]*?)-->',
    multiLine: true,
  );
  static final RegExp _bareBlock = RegExp(
    r'(?:```[a-zA-Z]*\s*)?YULI_WIDGET:([A-Z_]+)\s+v=(\d+)\s*([\s\S]*?)(?:```|$)',
    multiLine: true,
  );

  static List<AiWidgetPart> parse(String text) {
    final normalized = _normalizeBareBlocks(text);
    final parts = <AiWidgetPart>[];
    var cursor = 0;
    for (final match in _block.allMatches(normalized)) {
      if (match.start > cursor) {
        parts.add(AiWidgetTextPart(normalized.substring(cursor, match.start)));
      }
      final raw = match.group(0) ?? '';
      final type = match.group(1) ?? '';
      final version = int.tryParse(match.group(2) ?? '') ?? 1;
      final body = (match.group(3) ?? '').trim();
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          parts.add(
            AiWidgetBlockPart(
              type: type,
              version: version,
              data: decoded,
              raw: raw,
            ),
          );
        } else {
          parts.add(AiWidgetTextPart(raw));
        }
      } catch (_) {
        parts.add(AiWidgetTextPart(raw));
      }
      cursor = match.end;
    }
    if (cursor < normalized.length) {
      parts.add(AiWidgetTextPart(normalized.substring(cursor)));
    }
    return parts.where((part) {
      if (part is AiWidgetTextPart) return part.text.trim().isNotEmpty;
      return true;
    }).toList();
  }

  static bool hasWidgets(String text) =>
      parse(text).any((part) => part is AiWidgetBlockPart);

  static bool isStreamingWidgetDraft(String text) =>
      text.contains('<!--YULI_WIDGET:') ||
      RegExp(r'YULI_WIDGET:[A-Z_]+\s+v=\d+').hasMatch(text);

  static String stripStreamingWidgetDraft(String text) {
    final htmlStart = text.indexOf('<!--YULI_WIDGET:');
    final bareStart =
        RegExp(
          r'(?:```[a-zA-Z]*\s*)?YULI_WIDGET:[A-Z_]+\s+v=\d+',
        ).firstMatch(text)?.start;
    final starts = [
      if (htmlStart >= 0) htmlStart,
      if (bareStart != null) bareStart,
    ];
    if (starts.isEmpty) return text;
    starts.sort();
    return text.substring(0, starts.first).trimRight();
  }

  static String _normalizeBareBlocks(String text) {
    if (_block.hasMatch(text)) return text;
    if (text.contains('<!--YULI_WIDGET')) return text;
    return text.replaceAllMapped(_bareBlock, (match) {
      final type = match.group(1) ?? '';
      final version = match.group(2) ?? '1';
      final body = (match.group(3) ?? '').trim();
      final json = _extractJsonObject(body);
      if (json == null) return match.group(0) ?? '';
      return '<!--YULI_WIDGET:$type v=$version\n$json\n-->';
    });
  }

  static String? _extractJsonObject(String body) {
    final start = body.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < body.length; i++) {
      final ch = body[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return body.substring(start, i + 1);
      }
    }
    return null;
  }
}

const List<AiWidgetSpec> kAiWidgetSpecs = [
  AiWidgetSpec(
    type: 'CONCEPT_CARD',
    version: 1,
    description: 'Destaca un concepto clave dentro de una explicación.',
    triggerKeywords: [
      'explica',
      'explicame',
      'concepto',
      'definicion',
      'idea clave',
      'que es',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para reforzar visualmente una definición o idea central.
Formato estricto:
<!--YULI_WIDGET:CONCEPT_CARD v=1
{"title":"Derivada","definition":"Mide cómo cambia una función en un punto.","keyIdea":"Es la pendiente instantánea.","example":"Si f(x) es posición, f'(x) es velocidad."}
-->''',
  ),
  AiWidgetSpec(
    type: 'STEPS',
    version: 1,
    description: 'Renderiza pasos visuales para un método o proceso.',
    triggerKeywords: [
      'paso',
      'pasos',
      'proceso',
      'metodo',
      'resolver',
      'como se hace',
      'procedimiento',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para explicar procesos, métodos o resolución paso a paso.
Formato estricto:
<!--YULI_WIDGET:STEPS v=1
{"title":"Método rápido","items":[{"label":"Identifica la función","detail":"Mira qué regla aplica."},{"label":"Deriva","detail":"Aplica la regla correspondiente."}]}
-->''',
  ),
  AiWidgetSpec(
    type: 'COMPARISON',
    version: 1,
    description: 'Renderiza una comparación visual entre dos ideas.',
    triggerKeywords: [
      'compara',
      'comparar',
      'diferencia',
      'diferencias',
      'versus',
      'vs',
      'tabla',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para comparar dos conceptos, opciones o enfoques.
Formato estricto:
<!--YULI_WIDGET:COMPARISON v=1
{"title":"Derivada vs Integral","leftLabel":"Derivada","rightLabel":"Integral","rows":[{"left":"Cambio instantáneo","right":"Acumulación"},{"left":"Pendiente","right":"Área"}]}
-->''',
  ),
  AiWidgetSpec(
    type: 'FLASHCARDS',
    version: 1,
    description: 'Renderiza tarjetas de repaso girables.',
    triggerKeywords: [
      'flashcard',
      'flashcards',
      'tarjetas',
      'repaso',
      'memorizar',
      'estudiar',
      'examen',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para crear tarjetas de repaso. Mantén cada tarjeta breve.
Formato estricto:
<!--YULI_WIDGET:FLASHCARDS v=1
{"title":"Repaso rápido","cards":[{"front":"¿Qué mide la derivada?","back":"Cambio instantáneo o pendiente en un punto."},{"front":"¿Qué mide la integral?","back":"Acumulación o área bajo la curva."}]}
-->''',
  ),
  AiWidgetSpec(
    type: 'CHECKLIST',
    version: 1,
    description: 'Renderiza una checklist visual no persistente.',
    triggerKeywords: [
      'checklist',
      'lista',
      'plan',
      'preparar',
      'pendientes de estudio',
      'tareas de estudio',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para planes, preparación o listas accionables dentro del chat. No crea tareas reales.
Formato estricto:
<!--YULI_WIDGET:CHECKLIST v=1
{"title":"Plan de estudio","items":[{"label":"Repasar fórmulas","checked":false},{"label":"Resolver 3 ejercicios","checked":false}]}
-->''',
  ),
  AiWidgetSpec(
    type: 'QUIZ',
    version: 1,
    description: 'Renderiza una pregunta interactiva de opción múltiple.',
    triggerKeywords: [
      'quiz',
      'examen',
      'pregunta',
      'opcion multiple',
      'prueba',
      'repasar',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget cuando el usuario pida practicar, repasar o contestar una pregunta interactiva.
Formato estricto:
<!--YULI_WIDGET:QUIZ v=1
{"question":"Pregunta","options":[{"id":"a","label":"Opción A"},{"id":"b","label":"Opción B"}],"answer":"a","explanation":"Explicación breve."}
-->
No pongas nada después del bloque si la respuesta principal es el quiz.''',
  ),
  AiWidgetSpec(
    type: 'OPTIONS',
    version: 1,
    description: 'Renderiza opciones elegibles cuando el usuario debe escoger.',
    triggerKeywords: [
      'opcion',
      'elige',
      'escoger',
      'prefieres',
      'cual',
      'alternativas',
    ],
    policy: AiWidgetPolicy.study,
    promptContract: '''
Usa este widget para decisiones o selección de caminos.
Formato estricto:
<!--YULI_WIDGET:OPTIONS v=1
{"title":"Elige una opción","options":[{"id":"a","label":"Primera","message":"Elijo la primera"},{"id":"b","label":"Segunda","message":"Elijo la segunda"}]}
-->
Cada opción debe tener label visible y puede tener message para enviarlo al chat.''',
  ),
  AiWidgetSpec(
    type: 'TASK_LIST',
    version: 1,
    description: 'Renderiza tareas reales consultadas desde tools de Fight.',
    triggerKeywords: [
      'tarea',
      'pendiente',
      'fight',
      'hoy',
      'vencida',
      'recordatorio',
    ],
    policy: AiWidgetPolicy.appData,
    promptContract: '''
Usa este widget solo con tareas que vengan de una herramienta o contexto real.
Formato estricto:
<!--YULI_WIDGET:TASK_LIST v=1
{"title":"Pendientes de hoy","items":[{"id":1,"content":"Tarea","status":"pending","folder":{"id":2,"name":"Cálculo","color":"#2D4B8E"},"due":"2026-06-20T23:59:59"}]}
-->
No inventes ids, carpetas ni fechas.''',
  ),
  AiWidgetSpec(
    type: 'TASK_DRAFT',
    version: 1,
    description: 'Propone crear una tarea editable antes de guardarla.',
    triggerKeywords: [
      'crea',
      'crear',
      'crear tarea',
      'crea una tarea',
      'nueva tarea',
      'añade tarea',
      'anota tarea',
      'agrega tarea',
      'haz task',
      'recordarme',
      'recuerdame',
      'tengo que',
    ],
    policy: AiWidgetPolicy.appWrite,
    promptContract: '''
Usa este widget cuando el usuario pida convertir algo en tarea nueva. Esto NO crea la tarea por tu cuenta: solo propone un borrador y la app pedirá confirmación.
Formato estricto:
<!--YULI_WIDGET:TASK_DRAFT v=1
{"content":"Hacer tarea","folder":{"id":2,"name":"Cálculo","color":"#2D4B8E"},"dueDate":"2026-06-20","duePrecision":"date","reminderPreset":"before_1d","temporaryMemory":{"scope":"folder:2","text":"Tiene tarea mañana.","expiresAt":"2026-06-21T23:59:59"}}
-->
Si no conoces folderId real, omite id y manda solo name. Si no conoces una fecha exacta, omite dueDate. Usa solo lo que el usuario pidió o lo que esté claro por contexto.''',
  ),
  AiWidgetSpec(
    type: 'LAB_CARD_DRAFT',
    version: 1,
    description: 'Propone crear una tarjeta Lab editable antes de guardarla.',
    triggerKeywords: [
      'lab',
      'kanban',
      'tarjeta',
      'card',
      'crear tarjeta',
      'crea una tarjeta',
      'manda a lab',
      'proyecto',
    ],
    policy: AiWidgetPolicy.appWrite,
    promptContract: '''
Usa este widget cuando el usuario pida crear una tarjeta nueva de Lab. Esto NO crea la tarjeta por tu cuenta: solo propone un borrador y la app pedirá confirmación.
Formato estricto:
<!--YULI_WIDGET:LAB_CARD_DRAFT v=1
{"title":"Investigar APIs REST","space":"Hello","column":"Backlog","description":"Leer documentación de Flask y FastAPI","priority":"medium","dueDate":"2026-06-26T19:00:00","reminderPreset":"before_1d"}
-->
No digas que la tarjeta ya fue creada. Di que es un borrador confirmable. No uses columnas terminales o vencidas.''',
  ),
  AiWidgetSpec(
    type: 'MEMORY_SUGGESTION',
    version: 1,
    description: 'Propone guardar recuerdos del usuario con confirmación.',
    triggerKeywords: [
      'me llamo',
      'mi nombre es',
      'soy ',
      'recuerda',
      'guarda',
      'guardar',
      'guarda eso',
      'guardame',
      'memoria',
      'memoriza',
      'prefiero',
      'me gusta',
      'no me gusta',
      'estoy estudiando',
      'estudio',
      'mi carrera',
      'mi materia',
      'mi examen',
      'estudio',
    ],
    policy: AiWidgetPolicy.memory,
    promptContract: '''
Usa este widget por iniciativa cuando el usuario diga una afirmación explícita y estable sobre sí mismo: nombre, preferencia, materia, carrera, objetivo de estudio o contexto personal útil. No guardes inferencias. Si el usuario dice "guarda eso" o "guarda eso como memoria", toma la afirmación explícita relevante del turno anterior inmediato.
Formato estricto:
<!--YULI_WIDGET:MEMORY_SUGGESTION v=1
{"title":"Guardar memoria","items":[{"key":"name","label":"Nombre","value":"Dylan","scope":"global","expiresAt":null}]}
-->
No guardes datos sensibles ni temporales sin expiresAt.''',
  ),
];

String aiWidgetPrompt(
  List<AiWidgetSpec> specs, {
  required AiWidgetSurface surface,
}) {
  if (specs.isEmpty) return '';
  final mode =
      surface == AiWidgetSurface.yuli
          ? 'Estás en YuLi AI global: puedes proponer widgets y acciones de forma proactiva cuando ayuden.'
          : 'Estás en el chat de una nota Flight: usa proactivamente widgets de estudio/nota y sugerencias de memoria cuando el usuario afirme algo explícito sobre sí mismo; para Fight o Lab espera petición explícita o confirmación.';
  return 'Tienes contratos de widgets renderizables. Puedes intercalar markdown '
      'normal y uno o varios widgets cuando eso haga la explicación más clara. '
      'Si usas uno, respeta el JSON '
      'exacto dentro de <!--YULI_WIDGET:TYPE v=1 ...-->. No inventes datos reales '
      'existentes: tareas, proyectos y cards existentes deben venir de tools o '
      'contexto. Si el usuario pide crear una tarea o tarjeta nueva, puedes '
      'proponer TASK_DRAFT o LAB_CARD_DRAFT con los datos pedidos; la app '
      'pedirá confirmación. $mode\n\n'
      '${specs.map((s) => s.promptDoc).join('\n\n')}';
}

String _normalize(String value) {
  final lower = value.toLowerCase();
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final idx = from.indexOf(char);
    buf.write(idx >= 0 ? to[idx] : char);
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
