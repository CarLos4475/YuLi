# ONLINE_FEATURES — YuLi

Discusión y roadmap de features **online opcionales**. NO incluye la sync con Supabase (eso es lo último, se hará cuando la versión offline esté lista para producción).

## Principios (innegociables)

- **Opt-in, nunca dependencia.** Todo lo online se dispara explícitamente y nunca bloquea un flujo core. Sin conexión, la app funciona igual; la feature se desactiva con gracia.
- **Resultado persistido local** (Drift/SQLite): se calcula una vez y queda disponible offline para siempre.
- **Sin cuentas ni backend en v1**: el usuario pone su **propia API key** (secure storage local).
- **Privacidad explícita.** Distinguir on-device (sigue siendo offline) de nube (el contenido sale a terceros).
- **Aislamiento de capas.** Servicios detrás de interfaces en `domain/services/`, implementación en `data/services/`, expuestos por providers Riverpod. La UI/Riverpod nunca ve la llamada de red directa. Borrable sin tocar el core.
- **Escalado a producción:** v1 = key personal directo a la API. Si algún día hay múltiples usuarios, la key NO puede ir embebida (es extraíble) → se necesitará un proxy backend (que probablemente converge con el backend de Supabase). Diseñar la interfaz de servicio para que el *transporte* (directo vs proxy) sea intercambiable sin tocar a los callers.

## v1 — OCR (Tinta → texto) [scope CONGELADO]

Arrancamos por OCR. La capa IA (v2) queda **scopeada pero diferida** hasta que OCR esté sólido.
La unión entre ambas es "texto como contexto": OCR, nota markdown o texto tecleado son
intercambiables como entrada de la IA. La **sheet de texto reconocido** (ver abajo) es la
superficie canónica de la que la IA leerá después.

**Tecnología:** `google_mlkit_digital_ink_recognition` (on-device). Modelo de idioma se baja
una vez (default español); offline después. Ventaja: `DrawingStroke.points` ya son listas de
puntos → conversión directa a `Ink`/`StrokePoint`.

**Qué se reconoce:** solo escritura (`pen`, `fountainPen`). Excluye `isShape`, resaltador,
imágenes y task blocks.

**TEXTO, no matemáticas.** ML Kit es un reconocedor de *palabras/prosa*, NO de notación
matemática: una Σ, integral, fracción, exponentes/subíndices salen MAL por diseño (mapea el trazo
a la letra/símbolo más cercano; no da LaTeX). No es afinable — es la herramienta equivocada para
mate. Decisiones:
- v1 reconoce **texto** y punto. La **sheet editable** es la red de seguridad para correcciones.
- **Aviso "parece no-texto":** tras reconocer, si la confianza es baja / el resultado pinta
  no-textual (mucho símbolo no alfanumérico, tokens muy cortos), mostrar un hint suave: "esto
  parece matemáticas/dibujo — el modo Matemáticas llega después", en vez de devolver basura.
  (Nota honesta: es un hint por baja confianza, NO un clasificador de mate fiable; eso es difícil.)
- **Dejar la BASE lista para el motor de matemáticas** (recordatorio): la interfaz de
  reconocimiento se diseña con la idea de un *modo*/segundo motor. El camino de mate (futuro) es
  **manuscrito → LaTeX** (motor específico tipo Mathpix, nube) → **celda Math** (que ya existe en
  la app). Ver "Mate manuscrito → LaTeX" en Parqueado; conecta directo aquí.

**Fuente de trazos:** selección con **lasso** (reusa `selectedIndices`) en ambos editores;
en **cuaderno** además "página completa". Pizarra (infinita): solo por lasso.

**UX — acción + sheet intermedia (editable):**
- Acción "→ Texto" en el toolbar del lasso cuando la selección tiene trazos de escritura.
- Abre una **sheet "TEXTO RECONOCIDO"** con el texto en un **campo editable** (no solo lectura):
  permite corregir errores de OCR, **copiar fragmentos a mano** (selección nativa) y **copiar
  todo** (botón). Misma sheet servirá de contexto para la IA más adelante (`[Preguntar a IA]`).
- Acciones en la sheet v1: **[Copiar todo]** y **[Enviar a nota FLIGHT]** (crea/añade a una nota
  markdown). En el canvas NO hay bloque de texto nativo, por eso el destino es portapapeles/nota.
- Candidatos alternativos de ML Kit: opcional (chips), no v1.

**Persistencia:** **efímero on-demand** en v1 — no se guarda el texto atado a los trazos. La
búsqueda en manuscrito queda para la fase de búsqueda semántica.

**Arquitectura:** `domain/services/ink_recognizer.dart` (interfaz) + `data/services/
mlkit_ink_recognizer.dart` (impl) + provider Riverpod (feature-flag = modelo descargado).
Gestión del modelo de idioma en una pantalla de ajustes.

**No-goals v1:** capa IA, motor de matemáticas/LaTeX (solo se deja la base/seam para el modo
futuro), bloque de texto editable en el canvas, auto-indexado para búsqueda.

## v2 — Asistente IA: CHAT (solo conversación) [scope CONGELADO]

**v2 es chat READ-ONLY: la IA habla, tú lees y copias. NO escribe en la app.** Toda capacidad de
que la IA *edite* (crear tareas, insertar/reemplazar celdas, poner título) se va a **v3**. Así v2
queda chica, segura y shippeable, y v3 es puramente aditivo (botones de "aplicar" sobre el chat),
sin recodeo.

**Proveedor:** **DeepSeek** por defecto (API OpenAI-compatible). Interfaz provider-agnóstica para
poder añadir Claude/OpenAI después (Claude es mejor pero más caro → opción futura). Key en secure
storage.

**Modelos por tarea (costo):** **DeepSeek V4 Flash** para lo barato (título, traducir corto);
**DeepSeek V4 Pro** para razonar (resumir, limpiar/reescribir, extraer tareas, preguntar libre).

**Forma del panel: CHAT (multi-turno) efímero y SIEMPRE anclado.**
- Multi-turno: recuerda lo anterior; puedes repreguntar ("más corto", "ahora en inglés"). Salida
  en **streaming** (SSE estilo OpenAI).
- **Efímero:** la conversación vive mientras estás en la vista de la nota; se borra al salir de
  esa nota.
- **Siempre anclado a un contexto** antes del primer mensaje (la IA nunca opera a ciegas):
  - Abierto desde `[Preguntar a IA]` (sheet de OCR / celda / nota) → el ancla es ese texto, ya cargado.
  - Abierto en frío desde el panel → recuadro obligatorio "¿De qué es esto?" (ej. "Proceso de
    Markov"); ese texto queda como **ancla fija** que persiste toda la sesión.
- Las **acciones** (resumir, limpiar, extraer tareas, título, traducir, preguntar libre) son
  **botones de atajo** que mandan un mensaje plantilla dentro del chat. En v2 el resultado solo se
  **lee y se copia** (botón **Copiar** por respuesta — es portapapeles, no edita la app).
- **Costo:** el historial acumula tokens → recortar conversaciones largas.

**Cómo le llega el contexto:** la IA NO lee trazos; lee texto. La **sheet de OCR** tiene un botón
`[Preguntar a IA]` que pasa su texto (ya corregido) como ancla inicial. Otros orígenes: una celda
de nota, toda la nota (celdas de texto concatenadas), o el ancla "¿De qué es esto?" en frío.
(Las notas de FLIGHT son por **celdas** — text/math/bullets/tareas/drawing —; en v2 eso solo
importa para *leer* el contexto: una celda o toda la nota unida.)

**Transporte:** key directa en v2 → **proxy** en producción (mismo backend futuro), sin tocar callers.

**Flags:** sin key → feature oculta; sin red → deshabilitada con mensaje.

**Arquitectura:** `domain/services/ai_assistant.dart` (interfaz, streaming) +
`data/services/deepseek_assistant.dart` (impl OpenAI-compatible) + provider Riverpod
(flag = key presente). Panel de chat único reusable desde FLIGHT / sheet de OCR / canvas.

**No-goals v2:** que la IA escriba/edite cualquier cosa (→ v3), proxy/backend de producción, tags,
sugerir carpeta, historial persistido, otros proveedores implementados (interfaz lista, solo
DeepSeek en v2).

## v3 — Acciones que editan (la IA aplica cambios) [parqueado]

Aditivo sobre el chat de v2: cada respuesta del chat gana **botones de "aplicar"**. Siempre
explícito, nunca en silencio; deshacible vía el editor de celdas. Las notas son por celdas, así que
aplicar opera a nivel celda.

- **Extraer tareas → FIGHT** (la estrella, se enchufa con OCR): de la respuesta saca tareas →
  **checklist de revisión** (toggle/editar) → crea `Task`s (pending, `expiresAt` hoy, `folderId` de
  la nota) **enlazadas a la nota**. Reusa el flujo de creación existente. Requiere parsing
  estructurado de la lista.
- **Resumir → nueva celda** de texto en la nota.
- **Limpiar / reescribir → reemplaza la celda** seleccionada (o el texto en la sheet de OCR).
- **Sugerir título → set `note.title`** (sin tags, sin carpeta).
- Integración con el **deshacer** del editor de celdas.

## Parqueado (retomar después — interesante)

- **Bloque de texto editable en el canvas:** un nuevo tipo de objeto de texto sobre cuaderno/
  pizarra (con edición + lasso). Vale la pena (sería un 3er destino del OCR: insertar el texto
  reconocido en el lienzo), pero fuera de la v1 de OCR. Requiere nuevo tipo de objeto + edición.
- **Captura de URLs:** pegar un link → importar como nota markdown limpia (readability) o tarjeta enriquecida (Open Graph). Buen flujo de captura. Nube (fetch).
- **Búsqueda semántica del segundo cerebro:** embeddings + vector guardado en SQLite; buscar/preguntar por significado, no por palabras exactas. La apuesta grande; la de más trabajo (indexado + re-index incremental). Se conecta con guardar el texto OCR de los manuscritos.
- **Mate manuscrito → LaTeX** (Mathpix u on-device): es el "modo Matemáticas" que v1-OCR deja
  apuntado. Manuscrito → LaTeX → **celda Math** (ya existe, usa `flutter_math_fork`). Se enchufa en
  el mismo seam de reconocimiento que el texto (selector Texto / Matemáticas).
- **Voz → texto** para captura rápida en FIGHT (on-device).
