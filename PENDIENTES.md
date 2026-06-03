# PENDIENTES — YuLi

Cosas implementadas que faltan **verificar en dispositivo físico** (no se pueden probar en remoto). Cuando confirmes que algo funciona, bórralo de aquí.

---

## ⚡ Optimización de render canvas (calor) — probado en general en TGR, OK

Pizarra/cuaderno optimizados contra el sobrecalentamiento (solo capa `flight`, sin tocar datos/lab): caché de `Path` por-trazo, histéresis de repaint en pan (cuaderno simétrico 0.5, pizarra **predictiva** sesgada a la dirección, `_renderRectFor`), chrome de página cacheado, y el `InteractiveViewer` del cuaderno ya no se reconstruye en pan (#10). El calor bajó mucho y el feeling es bueno en ambos.

**Por si sale algo en una prueba más larga:**
- Pizarra: micro-tirón esperado al **invertir el sentido del pan** de golpe (1 repaint). Si molesta, subir `trail` en `_renderRectFor`.
- Vigilar que en pan/zoom rápido no aparezcan **gaps** de tinta/papel ni **blur**.
- Pendiente NO hecho (#3): `_allVisibleStrokes` clona todo por gesto de **lasso pesado** — solo atacar si esa operación con muchos trazos se siente caliente/lenta.
- Opcional: portar el margen predictivo al cuaderno (lo dejaría aún más frío; hoy va perfecto a 0.5).

---

## ✅ Headless audit validado (no requiere test manual de lógica)

`test/audit_test.dart` ejecuta **14/14** contra BD en memoria. Cubre la parte crítica que no podíamos validar por bloqueos de toolchain (Dev Mode / ATL):

- `KanbanCard.isOverdue` — 7 casos (done, expired column, due con/sin hora, solo-fecha hoy/ayer, sin due).
- Flags de sistema — `create()` siembra los 4 flags; transición de columna centralizada (`_applyColumnTransition`).
- Cross-mode — completar/reabrir card↔task en ambos sentidos; `originTaskDoneAt` y `dueDate` se sellan/limpian correctamente.
- Expiry paso 5 — card completada con due pasado **NO** salta a Vencido; card no-hecha vencida **SÍ** se mueve.
- Cascadas — `hardDeleteNoteCascade`, `hardDeleteFolderCascade`, `hardDeleteSpaceCascade` no dejan huérfanos.

**Consecuencia:** las secciones debajo marcadas con **(lógica validada headless)** solo necesitan que confirmes que la **UI no truene** al ejecutar el flujo; la lógica de datos ya está cubierta.

---

### 🐞→✅ FIX aplicado: error rojo "AiChatSession used after being disposed" al abrir el Chat del proyecto

**Era:** la caja roja al abrir **"Chat del proyecto"** (LAB) — `aiLabSessionProvider` (autoDispose) se desechaba de inmediato porque `showLabChat` solo hacía `ref.read` (no ancla); `initState` luego hacía `addListener` sobre la sesión muerta.
**Fix aplicado:** `ref.watch(aiLabSessionProvider(widget.space.id))` en `LabSpaceDetailScreen.build` (ancla la sesión a la vida de la pantalla, igual que los editores con las notas).
**Verificar:** relanzar → abrir Chat del proyecto → ya NO debe salir el error rojo; abrir/cerrar varias veces; que el chat de proyecto y el de una nota con el mismo id sigan separados.

### 🔔 Recordatorios (notificaciones locales) — branch `feature/reminders`, schema 19 — *lógica validada headless, falta verificar en la TGR*

Feature nueva: notificaciones para tasks (Fight) y cards (Lab) + resumen diario. Instalada y corriendo en la TGR (2026-06-02). `reminder_coordinator_test.dart` cubre programar/cancelar/huérfanos contra BD en memoria. **Falta probar en vivo (mañana):**

- **#1 Disparo con app CERRADA:** pon un recordatorio a +2-3 min (task o card), **cierra la app** (no force-stop), espera → debe llegar la notificación. Tócala → abre la task (Fight) o la card correcta (Lab→espacio→detalle).
- **#2 Recordatorios EXACTOS:** Ajustes → activar "RECORDATORIOS EXACTOS" → debe pedir el permiso especial de Android (Alarmas y recordatorios). Con esto, dispara a la hora exacta aun en reposo (Doze). Sin él, modo inexacto (puede atrasarse).
- **#3 Resumen diario:** activar + fijar hora → a esa hora llega el resumen "Fight: N pendientes… Lab: N cards…".
- **#4 Notificaciones DESACTIVADAS (gotcha Android 12):** la TGR es API 31, no hay diálogo de permiso (es de Android 13+) y vienen **apagadas por defecto**. Verifica: con notifs off, Ajustes muestra **banner rojo "NOTIFICACIONES DESACTIVADAS"** (toca → abre Ajustes del sistema); y al fijar un recordatorio sale **snackbar "ACTIVAR"**. Tras activarlas (ya lo hice por adb una vez), el banner desaparece.
- **#5 Persistencia tras REINICIO:** programa uno futuro, reinicia la tablet → debe seguir disparando (boot receiver reprograma).
- **#6 Optimización de batería (TGR/OEM):** desactivar optimización de batería para YuLi (Ajustes → Batería) y confirmar que la alarma no la mata el sistema.
- **#7 Huérfanos (no truena):** borrar un espacio/folder con cards/tasks que tenían recordatorio → no debe quedar notificación fantasma (cancela en `reconcileAll` al arrancar). Lógica headless ✓, solo confirmar que no truena.
- **#8 Sync con due:** cambiar el due de una task/card con preset (a la hora / 30m antes / 1 día antes) reprograma el recordatorio; completar/mandar a terminal lo cancela; reabrir lo restaura.

⚠️ **Build Android:** requiere `coreLibraryDesugaring` (ya configurado en `android/app/build.gradle.kts`). Sin eso `assembleRelease` falla — `flutter analyze` NO lo detecta.

## Por hacer (NO implementado)

1. **Papelera para cards.** Se borran en duro (tareas/folders/espacios sí tienen soft-delete de 7 días). Feature: esquema (`deleted_at`/`trashed_at` en `kanban_cards`) + UI de recuperación.
2. **Purga de notas trashadas individuales.** No hay paso de expiry que borre notas borradas a mano (sin borrar su folder) → viven en la papelera para siempre. (folder/espacio/tarea sí purgan a 7d.)
3. **`taskIds` histórico en bloques canvas (idea).** Conservar los ids aunque la tarea se borre de FIGHT, como registro histórico. Cambio de arquitectura.
4. **(Futuro) Activar FK + `onDelete`** — ver `KNOWN_ISSUES.md` (hoy las cascadas son a nivel app).

## Implementado hoy — verificar en Android

Cambios de esta sesión sin probar en dispositivo (lógica con test headless donde aplica):

- **#1 Color de folder → cards:** cambiar el color de un folder en Flight actualiza el color de las cards vinculadas a tareas de ese folder.
- **#2 "Backlog" con fallback:** enviar tarea a Lab cae en Backlog o, si no existe, en la **1ª columna no-terminal** (3 archivos Flight). Renombrar Backlog ya no la manda a una columna rara.
- **#4 Label FIN contextual** (detalle card): **VENCIMIENTO** / **ENTREGADO EL** (si hecha) / **VENCIÓ EL** (si vencida).
- **#5 INICIO toggle** "MANUAL" → **"FIJA"** (ya no implica que lo puso el usuario).
- **#6 Reabrir re-sincroniza el due** de la card desde la tarea (headless ✓): completar (FIN→hoy) → reabrir → FIN vuelve al due original de la tarea.
- **#7 OCR `_check`** con try/catch (no truena en plataformas sin ML Kit; no ensucia el crash log en desktop).
- **Flight (auditoría):** quitado código muerto (`parseCells`/`serializeCells`/`NoteCell`/`CellType`); doc en `updatePayload` (reemplaza, no mergea); limpieza de cachés de contexto IA al quitar una fuente.

## Verificación pendiente (dispositivo)

### Crash logger persistente (Ajustes → DIAGNÓSTICO) — *verificado en vivo*

Captura global de errores Dart → `{documentos_app}/diagnostics/crash.log` (rotación ~256 KB) + visor + Compartir + Limpiar. **Verificado en Windows** (captura de error de prueba + un error real de OCR + Compartir abre el diálogo nativo). Falta solo: confirmar **Compartir en Android**. Límite: solo errores **Dart** (los nativos van a logcat). Uso: cuando ocurra un crash → Ajustes → CRASH LOGS → Compartir → mandar el `.log`.

### Imágenes — fuga de archivos arreglada + visor de almacenamiento (Ajustes)

**Bug:** las imágenes son **archivos** en `{documentos_app}/note_images/{noteId}/{uuid}.jpg`; la cascada de borrado solo quitaba las filas `note_images`, **no los .jpg** → fuga al borrar notas/folders.

**Fix:** `cleanupOrphanedImages` — pasada de reconciliación que borra cualquier carpeta `note_images/{id}` sin nota viva. Corre **al arranque** tras el expiry. Limpia las de ahora **y las ya fugadas**.

**Feature (Ajustes → ALMACENAMIENTO):** bloque **IMÁGENES** que muestra el espacio ocupado; al tocarlo abre un **visor in-app** (`ImageStorageScreen`) con grilla de miniaturas + tamaño + a qué nota pertenece. **Solo lectura** en v1.

**Fix (visor decía "no hay" con peso > 0):** el visor leía la tabla `note_images`, pero las imágenes de **canvas/pizarra/cuaderno** se guardan en disco + en el `DrawingData`, NO en esa tabla (solo las inline del editor de notas escriben fila). Ahora el visor **escanea el disco** (`listNoteImageFiles`) → muestra todas, coherente con el peso, ordenadas por tamaño desc. Se eliminó `getAllImages` (tabla) por quedar sin uso.

**Cómo probar:** Ajustes → ALMACENAMIENTO → debe mostrar el tamaño; tocar abre el visor. Borrar una nota con imágenes y relanzar → su carpeta debe desaparecer (el tamaño baja).

### Borrado en cascada a nivel app (huérfanos) — enfoque (a) *(lógica validada headless)*

**Lógica de cascada cubierta por audit.** Solo falta confirmar que los flujos de UI no truenen:

- **#1 Folder:** borrar un folder con notas → las notas desaparecen de Flight y aparecen junto al folder en la papelera; **restaurar el folder** las trae de vuelta. Las tareas del folder siguen en Fight (sin carpeta tras purga).
- **#2 Nota:** borrar permanentemente una nota (papelera) → sus cards vinculadas pierden el badge "NOTA" (no truena al abrirlas).
- **#3 Espacio:** borrar permanentemente un espacio → no quedan columnas/cards/horario huérfanos.
- **#4 Tarea:** al purgarse (7d) ya limpia origin en cards y ahora borra sus `note_task_links`.

**Observación aparte (no tocado):** no hay paso de expiry que purgue **notas** trashadas individualmente → una nota borrada a mano (sin borrar su folder) vive en la papelera para siempre.

### Notificaciones — tope de 50 (anti-acumulación)

El expiry (paso 8) ahora conserva solo las **50 más recientes**. Verificar que sigan apareciendo/limpiándose normal y que no se acumulen indefinidamente.

### Lab — editar título ya no borra la mención @folder

**Cómo probar:** abre una card con `@folder` en el título, edita el texto del título (sin tocar nada más), cierra → el badge `@folder` debe seguir ahí. Si escribes tu propia `@otra` en el título, debe respetarse esa.

### Lab — columnas por flag: renombrar (lo único sin probar en vivo)

El resto (colores, vencida/fin-de-día, transiciones, completar/reabrir, calendario) ya se **verificó en vivo** el 2026-06-01. Falta solo: **renombrar** "Entregado"→"Listo", "Vencido"→"Caducado", "En Proceso"→"Activo" → la automatización debe **seguir funcionando** (va por flag, no por nombre).

### YuLi AI en Lab (one-shot) — generar tarjetas + resumir/triage + chat del proyecto

**Necesita API key DeepSeek en dispositivo.**

- **✦ en el header** del espacio → abre la hoja "YuLi · LAB" con [Generar tarjetas] y [Resumir / triage].
- **Generar tarjetas:** escribe objetivo → IA propone tarjetas → revisión editable (título, prioridad, fechas) → CREAR N en Backlog.
- **Resumir / triage:** diálogo markdown con resumen + botón COPIAR. No debe inventar tarjetas.
- **Chat del proyecto (fase 2):** 3ª acción → chat con board como contexto (barra "TABLERO ▸ [proyecto]", ↻ re-serializa). Verifica: sesión separada de notas con mismo id; ↻ refresca; cambiar board + ↻ resetea hilo.
- Sin key → aviso. Límite diario respetado.

### Lab — rango de fechas por tarjeta + timeline en barras — migración schema 17

**⚠️ Crítico:** `dueDate` quedó intacto (sólo se lee en timeline). Confirmar que completar/mover a Entregado/vencer sigue igual que antes.

- **"En Proceso" = columna del sistema:** mover una card ahí fija **fecha de inicio** automáticamente. Directo a Entregado → inicio = createdAt.
- **Card detail:** sección "// FECHAS" con INICIO (chip + toggle AUTO/MANUAL) y FIN (chip due editable), más línea de rango.
- **Barra multi-día:** card con inicio y fin distintos → rectángulo que se extiende varios días en la timeline.
- **Timeline:** barras por carril, packing por solapamiento. Sin `dueDate` no aparecen.

### Fuentes de contexto MÚLTIPLES (notas + enlaces web) — migración BD schema 16

**Necesita red/dispositivo.**

- **Hoja Fuentes:** botón IA → barra `SINCRONIZADA ▸ N fuentes` (o 🔗 "Fuentes") → abre la hoja. Botones **+ Nota** y **+ Enlace** (URL → fetch Jina → título como label).
- **Multi-nota:** agrega 2-3 notas → chat combina contextos etiquetados.
- **URL:** agrega enlace → debe traer contenido. Pregúntale a la IA sobre la página.
- **↻ por URL (en la hoja):** actualiza esa URL. **↻ global** NO re-fetchea URLs (solo notas locales).
- **Cache:** nota/URL larga (>3000 chars) → primera vez compacta; sal y entra → cache hit. Editar/re-fetch → re-compacta solo esa.
- **OCR:** "Enviar a Yuli" con 1 nota fuente → escribe en ella; con ≥2 → diálogo "¿a qué nota?"; con 0 notas (solo URLs) → ancla puntual.
- Sin red al agregar/refetch URL → aviso claro, usa lo cacheado.

### Exportar canvas a PDF/PNG (pizarra + cuaderno) — NUEVO, sin probar en dispositivo

Módulo aislado del hot-path de render: `canvas_export.dart` re-pinta en frío un `PictureRecorder` reusando `drawStroke`/`drawCanvasImage`/`paintBgPattern` (mismos primitivos que pantalla → fidelidad 1:1). Bloques texto/tarea se rasterizan offscreen (`canvas_block_raster.dart`) montando los MISMOS overlays con `interactive:false` en un `OverlayEntry` fuera de pantalla y capturando su `RepaintBoundary`. Sheets de opciones en `canvas_export_sheet.dart`. Entrada en el "more popup" (⋯) de ambos editores.

- **Pizarra:** ⋯ → EXPORTAR → sheet (TODO / ÁREA, PDF/PNG, incluir tareas). **ÁREA** = recuadro: **1 dedo dibuja, 2 dedos mueven/zoom** (el rect queda anclado en mundo y sigue al pan/zoom); levantar el dedo **NO** exporta — se puede reajustar y se confirma con el botón "EXPORTAR ESTA ÁREA". Usa el mismo `_screenToWorld` del dibujo → coords exactas. **TODO** = bbox automático de todo el contenido (+24px).
- **Cuaderno:** el export vive en el **visor de páginas** (drawer). Botón EXPORTAR en el header → modo selección con **checkbox por página** (elegir 1,2,10… o TODAS) → confirmar → sheet (PDF/PNG; "una página PDF por hoja" si >1; incluir tareas). PNG multi-página = apilado vertical en una sola imagen. PDF multipágina = una hoja A4 (595×842 pt) por página.
- **Verificar en Android:** (1) fidelidad — color de fondo + patrón + trazos (incl. estilográfica/marcador/relleno/figuras) + imágenes + bloques de texto/tarea salen idénticos; (2) bloques rotados no se recortan; (3) toggle de tareas las incluye/excluye; (4) `Share` abre el diálogo nativo y el archivo se abre bien en un visor; (5) selección enorme no revienta memoria (tope 4096px de lado); (6) **que NO haya regresión de calor/render** tras exportar (volver a dibujar sigue fluido). 
- **Miniaturas del drawer del cuaderno arregladas:** `_PageThumbnailPainter` ahora usa `paintBgPattern` + papel/patrón **por página** (`data.background`/`bgColorValue`) + imágenes — antes usaba un fondo hardcodeado y un solo bg global. Verificar que las miniaturas se ven como la página real.
- **`pdf_export.dart` (viejo, editor de notas por celdas) NO se tocó** — sigue para ese editor; el canvas usa el módulo nuevo.

### Cajas de TEXTO en canvas (pizarra + cuaderno)

- **MODO TEXTO:** toca **Texto** (icono notas) → inserta caja Y se queda en modo texto. Tamaño adaptado al zoom.
  - Tocar caja = abre editor markdown dockeado. Arrastrar (1 dedo) = mover. 2 dedos = navegar (zoom/pan).
- **Resize (con el LAZO):** 4 esquinas + 2 lados (izq/der). Arriba/abajo deshabilitado.
  - Esquinas → escala uniforme (letra crece/encoge). Lados izq/der → ancho, texto refluye. NUNCA deforma.
  - Mínimo MUCHO más chico que cajas de tarea.
- **Trazos ENCIMA de la caja:** lápiz sobre caja de texto → tinta encima.
- **Tablas raras de la IA:** si mete tabla mal formada, la caja la repara.
- **Persistencia:** cerrar y reabrir → cajas siguen ahí. Cuaderno multi-página: mover entre páginas reasigna correctamente.
- **Enviar a lienzo (chat):** desde pizarra/cuaderno → "Enviar a lienzo" cierra sheet y aparece caja markdown. En nota normal el botón NO aparece.

### Caja de tareas — resize por esquina y lateral (cuaderno + pizarra)

- **Resize por ESQUINA:** crece/encoge uniforme (caja + texto juntos). Sin deformar. Al soltar queda igual que durante arrastre.
- **Resize LATERAL derecho:** solo ancho, texto refluye.
- **Resize en vivo:** por esquina se ve en tiempo real; por lateral la caja se queda quieta y salta al soltar.
- Probar encoger hasta mínimo (~220×90 px renderizados).
- **Rotar** + redimensionar → coherente.
- **Cerrar y reabrir** → conserva tamaño/escala. Bloques viejos (scale por defecto 1.0) se ven igual.
- Bounding box del lasso ajustado al bloque tras redimensionar.

### v2 / v3 — Asistente IA (chat) — NECESITA TU API KEY

- **Ajustes → ASISTENTE IA (DEEPSEEK)** → pega key → Guardar.
- Streaming, chips (Resumir/Limpiar/Extraer tareas/Título/Traducir), toggle FLASH/PRO, Copiar, "N hoy" + bloqueo a 150.
- **Markdown real** en respuestas (negritas, listas, código, tablas, LaTeX).
- **Persistencia:** cierra sheet y reabre → conversación sigue. Sal de nota/pizarra/cuaderno y vuelve → mensajes descartados, pero **contexto/ancla persiste por nota**.
- **Contexto:** chip "CONTEXTO" → editar/reemplazar/limpiar. OCR/IA desde otra nota → pregunta Añadir/Reemplazar.
- **Auto-compactación:** contexto largo (>3000 chars) → compacta 1 vez, aviso "✦ Compacté…" + botón DESHACER.

**v3 — Acciones que editan:**
- **Copiar** (portapapeles).
- **Rehacer** → descarta esa respuesta y regenera el turno (descarta las de abajo).
- **Guardar en nota** → selector carpeta/nota → añade celda de texto al final o crea nueva.
- **Extraer tareas → FIGHT** → REVISAR TAREAS (checkbox + editable) → CREAR N → tareas en FIGHT enlazadas a la nota.
- **Sugerir título** → en editor de notas, quick-action "Título" pide 3 → popup elegir + editar → aplica a `note.title`.
- **Retry con backoff** → fallos transitorios reintentan 2× con "⟳ Reintentando…". Errores permanentes no reintentan.

### OCR v1 — a futuro (NO bloquea)

- Elegir idioma del modelo (hoy fijo español `es`).
- Modo Matemáticas (Σ, integrales, etc.): `InkRecognitionMode.math` reservado; Mathpix eliminado. Por decidir on-device u otro proveedor.

### Persistencia de tareas en bloques canvas (idea a explorar luego)

Que los bloques de tareas en canvas conserven sus `taskIds` aunque la tarea se borre de FIGHT, funcionando como "registro histórico". Requiere cambio de arquitectura — mejor revisarlo con calma.

---

## 📋 Resumen — qué testear manualmente (dispositivo)

| # | Qué | Dónde / Cómo | Riesgo si falla |
|---|-----|--------------|-----------------|
| 1 | Chat del proyecto sin crash | LAB → ✦ → Chat | Rojo en pantalla |
| 2 | Imágenes: GC limpia + visor muestra tamaño | Ajustes → ALMACENAMIENTO → borrar nota con imgs → relanzar | Fuga de disco |
| 3 | Cascadas UI: papelera folder/nota/espacio y restore | Flight/LAB → borrar → papelera → restaurar/purgar | Huérfanos / crash |
| 5 | Notificaciones no se acumulan >50 | Usar app varios días / forzar expiry | OOM de notificaciones |
| 🔔 | Recordatorios: disparo app cerrada, exactos, resumen, banner notifs-off, reboot, batería, huérfanos | Fight/Lab → fijar recordatorio; Ajustes → toggles | No dispara / fantasma / crash |
| 6 | Editar título no pierde @folder | LAB → card con @folder → editar título | Badge desaparece |
| 9 | Columnas por flag: **renombrar** no rompe (resto verificado en vivo) | LAB → renombrar Entregado/Vencido/En Proceso → probar flujos | Automatización muerta |
| 16 | Pendientes implementados hoy (#1 color folder, #2 backlog fallback, #4/#5 labels, #6 reabrir due, #7 OCR) | ver sección "Implementado hoy" | Regresión |
| 10 | YuLi AI Lab: generar, triage, chat proyecto | LAB → ✦ → acciones | Sin red / key inválida |
| 11 | Timeline barras + rango fechas | LAB → timeline → barras multi-día; card detail → fechas | Render roto |
| 12 | Fuentes múltiples: notas + URLs + cache + OCR | Canvas/pizarra/cuaderno → IA → Fuentes | Contexto stale / sin red |
| 13 | Cajas de texto canvas: modo, resize, tinta encima, persistencia | Pizarra/cuaderno → Texto → crear/editar/mover/resize | Perdida de datos / crash |
| 14 | Caja tareas canvas: resize esquina/lateral, rotar, persistir | Pizarra/cuaderno → lasso → resize tarea | Deforme / bounding box mal |
| 15 | IA v2/v3: chat, contexto, guardar, extraer tareas, título | Notas/pizarra/cuaderno → IA → acciones | Pérdida de mensajes / no edita |

Borra de arriba lo que confirmes. Si algo falla, avísame con el paso exacto.
