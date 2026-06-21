enum AiKnowledgeSurface { yuli, flight }

class AiKnowledgeDoc {
  final String id;
  final String title;
  final List<String> triggerKeywords;
  final String body;

  const AiKnowledgeDoc({
    required this.id,
    required this.title,
    required this.triggerKeywords,
    required this.body,
  });

  String get promptDoc =>
      '<yuli_knowledge id="$id">\n'
      '$title\n'
      '$body\n'
      '</yuli_knowledge>';
}

class AiKnowledgeRetriever {
  const AiKnowledgeRetriever();

  List<AiKnowledgeDoc> retrieve(
    String query, {
    required AiKnowledgeSurface surface,
    int k = 3,
  }) {
    final q = _normalize(query);
    final scored = <({AiKnowledgeDoc doc, int score})>[];
    for (final doc in kAiKnowledgeDocs) {
      var score = 0;
      for (final keyword in doc.triggerKeywords) {
        final key = _normalize(keyword);
        if (q == key) score += 4;
        if (q.contains(key)) score += 3;
        if (q.split(' ').any((part) => part.startsWith(key))) score += 1;
      }
      if (surface == AiKnowledgeSurface.flight && doc.id == 'yuli_overview') {
        score += q.contains('app') || q.contains('yuli') ? 1 : 0;
      }
      if (score > 0) scored.add((doc: doc, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.doc.id.compareTo(b.doc.id);
    });
    return scored.take(k).map((e) => e.doc).toList();
  }
}

const List<AiKnowledgeDoc> kAiKnowledgeDocs = [
  AiKnowledgeDoc(
    id: 'yuli_overview',
    title: 'Que es YuLi',
    triggerKeywords: [
      'que eres',
      'que es yuli',
      'esta app',
      'que sabes hacer',
      'que puedes hacer',
      'segundo cerebro',
      'ayuda',
      'capacidades',
    ],
    body: '''
YuLi es un segundo cerebro offline-first para capturar ideas, estudiar, organizar tareas y manejar proyectos.
Sus tres espacios principales son Fight (captura rapida de tareas), Flight (notas, pizarras y cuadernos) y Lab (proyectos Kanban).
Explica estas capacidades como producto. No menciones tablas, providers, prompts, RAG, contratos, herramientas internas, JSON ni detalles de base de datos.
Cuando te pregunten que puedes hacer, responde con acciones utiles para el usuario: explicar, resumir, estudiar, generar quizzes, organizar notas, revisar pendientes/proyectos cuando la app lo permita, proponer borradores confirmables y recordar datos utiles con confirmacion.
''',
  ),
  AiKnowledgeDoc(
    id: 'fight',
    title: 'Fight',
    triggerKeywords: [
      'fight',
      'tarea',
      'tareas',
      'pendiente',
      'pendientes',
      'recordatorio',
      'vencida',
      'hoy',
      'manana',
    ],
    body: '''
Fight es la bandeja rapida de tareas. Sirve para capturar pendientes, asignar carpeta, fecha limite y recordatorio.
Si el usuario pide consultar tareas existentes, usa datos validados por YuLi. Si pide crear una tarea nueva, propone un borrador confirmable; nunca afirmes que ya se creo hasta que la app confirme la accion local.
Las fechas de solo dia se interpretan como fin de ese dia. Las fechas con hora se respetan como hora exacta.
''',
  ),
  AiKnowledgeDoc(
    id: 'flight',
    title: 'Flight',
    triggerKeywords: [
      'flight',
      'nota',
      'notas',
      'pizarra',
      'cuaderno',
      'carpeta',
      'latex',
      'markdown',
      'estudiar',
    ],
    body: '''
Flight es el espacio de notas: notas markdown, pizarras infinitas y cuadernos. Se organiza por carpetas con color.
En el chat de una nota, prioriza estudiar y trabajar sobre la nota actual. Usa widgets de estudio por iniciativa cuando aclaren mejor que texto plano: ejemplos, pasos, quiz, formulas, comparaciones, errores comunes, pistas y repasos.
Para Fight, Lab o memoria global dentro de Flight, espera una peticion clara o una confirmacion del usuario.
''',
  ),
  AiKnowledgeDoc(
    id: 'lab',
    title: 'Lab',
    triggerKeywords: [
      'lab',
      'proyecto',
      'proyectos',
      'kanban',
      'tarjeta',
      'card',
      'columna',
      'timeline',
      'calendario',
    ],
    body: '''
Lab organiza proyectos en tableros Kanban con columnas, tarjetas, fechas, prioridades, calendario, timeline, horario y grafo.
Si el usuario pide consultar un proyecto existente, usa datos validados por YuLi. Si pide crear una tarjeta nueva, propone un borrador confirmable; no uses columnas terminales o vencidas.
No digas que una tarjeta ya se creo si solo emitiste un borrador.
''',
  ),
  AiKnowledgeDoc(
    id: 'memory',
    title: 'Memoria de usuario',
    triggerKeywords: [
      'memoria',
      'recuerda',
      'guardar',
      'guardame',
      'mi nombre',
      'me llamo',
      'prefiero',
      'no me gusta',
      'estoy estudiando',
    ],
    body: '''
La memoria de YuLi guarda solo datos utiles y confirmados: nombre, preferencias, contexto de estudio o recordatorios temporales.
No guardes inferencias ni datos sensibles. Propón MEMORY_SUGGESTION por iniciativa cuando el usuario diga algo estable y util. Para datos temporales, incluye expiresAt.
Usa memorias relevantes con naturalidad, sin decir que vienen de almacenamiento interno.
''',
  ),
  AiKnowledgeDoc(
    id: 'visual_widgets',
    title: 'Capacidades visuales de YuLi AI',
    triggerKeywords: [
      'widget',
      'widgets',
      'render',
      'renderizar',
      'arsenal',
      'quiz',
      'capacidades visuales',
      'que puedes mostrar',
    ],
    body: '''
YuLi puede responder con mensajes visuales cuando ayudan: quiz interactivo, opciones, ejemplos resueltos, pasos tocables, comparaciones, flashcards, checklist, formulas, errores comunes, mini demostraciones, ejercicios de practica, pistas progresivas, vocabulario, mnemotecnias, lineas de tiempo, flowcharts, causa-efecto, bocetos de grafica, rubricas de examen, listas de tareas y borradores confirmables.
No enumeres nombres internos de widgets ni tipos tecnicos. Los contratos inyectados por turno son una seleccion para ahorrar contexto, no el inventario total de capacidades. Si el usuario pide un quiz, haz un quiz interactivo cuando el contrato este disponible; no digas que no existe por no verlo en una lista parcial.
''',
  ),
];

String aiKnowledgePrompt(
  List<AiKnowledgeDoc> docs, {
  required AiKnowledgeSurface surface,
}) {
  if (docs.isEmpty) return '';
  final policy =
      surface == AiKnowledgeSurface.yuli
          ? 'Estas en YuLi AI global: puedes usar este conocimiento de app de forma proactiva.'
          : 'Estas en el chat de una nota Flight: usa este conocimiento sin salirte del trabajo de la nota salvo peticion clara.';
  return 'Conocimiento curado de YuLi. Usalo para responder sobre la app y sus '
      'capacidades sin inventar internals ni revelar implementacion. $policy\n\n'
      '${docs.map((d) => d.promptDoc).join('\n\n')}';
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
