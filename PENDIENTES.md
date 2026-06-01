# PENDIENTES — YuLi

Cosas implementadas que faltan **verificar en dispositivo físico** (no se pueden probar en remoto). Cuando confirmes que algo funciona, bórralo de aquí.

---

## Verificación pendiente

### YuLi AI en Lab (one-shot) — generar tarjetas + resumir/triage

**Qué se implementó:** hoja **YuLi · LAB** desde el botón ✦ en el header del espacio. Dos acciones one-shot (sin chat persistente; el chat es fase 2 y se sumará a esta misma hoja).

**Cómo probar (en dispositivo, necesita API key DeepSeek):**
- **✦ en el header** del espacio → abre la hoja "YuLi · LAB" con [Generar tarjetas] y [Resumir / triage].
- **Generar tarjetas:** escribe un objetivo/prompt → la IA propone tarjetas → **vista de revisión**: por tarjeta editas **título**, ciclas **prioridad** (chip), y ajustas **inicio/due** (date-pickers); desmarcas las que no quieras → **CREAR N** → se crean **todas en Backlog** con sus fechas. Verifica que aparezcan en el kanban y, si pusiste fechas, como barras en la timeline.
- **Resumir / triage:** serializa el board (columnas + tarjetas + prioridad/due/hecha) → **diálogo markdown** (mismo render que el chat) con resumen + atorados + siguientes pasos, con botón **COPIAR**. No debe inventar tarjetas.
- **Sin key** → avisa ir a Ajustes. **Límite diario** respetado (cada acción cuenta 1 request). **Sin red / error** → aviso claro.

### Lab — rango de fechas por tarjeta + timeline en barras (base para IA-Lab) — migración schema 17

**Qué se implementó:** `KanbanCard.startDate` nullable (campo nuevo, Lab-only). La timeline pasa de **puntos** a **barras**: cada tarjeta con `dueDate` se dibuja como una barra de `(startDate ?? createdAt) → dueDate`, con **packing por carriles** (barras que se solapan se apilan en filas). Ancho de día **uniforme** (barra = duración). En el detalle de tarjeta hay un toggle **AUTO / MANUAL** para el inicio.

**⚠️ Crítico verificar (no debe romperse cross-mode):** `dueDate` quedó **intacto** — sigue volviéndose fecha de acabado al pasar a "Entregado", sigue sincronizando con FIGHT y con la expiry. Solo se **lee** en la timeline. Confirmar que completar una tarjeta / moverla a Entregado / vencerla sigue igual que antes.

**Cómo probar (migra al primer arranque, agrega la columna `start_date`):**
- **"En Proceso" = columna del sistema:** mover una card a **En Proceso** debe fijar su **fecha de inicio** (= ahora) automáticamente, si no tenía. Si la card va **directo a Entregado** (sin pasar por En Proceso), el inicio = **agregado** (createdAt). Verifica con drag y con cambio de columna desde el detalle.
- **Card detail:** sección "// FECHAS" con **INICIO** (chip: fecha manual / "agregado · dd/mm" en auto, + toggle AUTO/MANUAL) y **FIN** (chip due, toca para editar), más una línea "rango timeline: dd/mm → dd/mm".
- **Barra multi-día:** una card con inicio y fin distintos debe verse como un **rectángulo que se extiende varios días** en la timeline (no un punto).
- **Timeline:** las tarjetas con due aparecen como **barras** del inicio al due. Auto → la barra arranca en la fecha de creación. Manual → arranca en la fecha elegida. Barras que coinciden en el tiempo se apilan en filas dentro del carril (columna). Tarjetas sin `dueDate` no aparecen (igual que antes).
- **Cross-mode:** completar/mover a Entregado/vencer una tarjeta → el `dueDate` y la sync con FIGHT deben comportarse **idéntico** a antes del cambio.

### Fuentes de contexto MÚLTIPLES (notas + enlaces web) — NUEVO, migración BD schema 16

**Qué se implementó:** generaliza el link Nota↔Canvas a **N fuentes** de dos tipos: notas `block` internas y **URLs externas** (leídas con Jina Reader → markdown). Tabla unificada `canvas_context_sources`. Compactación **por fuente, cacheada** (cada nota/URL larga se compacta 1 vez y se reusa). Migración copia los links viejos como fuentes `note`.

**Cómo probar (en dispositivo) — migra al primer arranque:**
- **Hoja Fuentes:** botón IA → barra `SINCRONIZADA ▸ N fuentes` (o 🔗 "Fuentes" si no hay) → abre la hoja. Botones **+ Nota** (notas de la carpeta) y **+ Enlace** (campo URL → fetch Jina → agrega con el **título de la página** como label).
- **Multi-nota:** agrega 2-3 notas → el chat combina sus contextos (etiquetados, separados por `---`).
- **URL:** agrega un enlace → debe traer el contenido (verifica que el título salga bien). Pregúntale a la IA sobre la página.
- **↻ por URL (en la hoja):** actualiza esa URL (re-fetch). El **↻ global** de la barra **NO** re-fetchea URLs (solo re-lee notas locales) — verifica que no dispare red.
- **Cache:** agrega una nota/URL larga (>3000 chars) → primera vez compacta (1 request); sal y entra → no re-compacta (cache hit). Editar la nota / re-fetch la URL → re-compacta solo esa.
- **OCR:** "Enviar a Yuli" con 1 nota fuente → escribe en ella; con ≥2 notas → **diálogo "¿a qué nota?"**; con 0 notas (solo URLs) → ancla puntual.
- **Quitar fuente / sin red:** quitar desde la hoja; sin conexión al agregar/refetch URL → aviso claro, usa lo cacheado.
- **Jina key (Ajustes):** funciona sin key (free); sección "JINA READER KEY (OPCIONAL)" para subir límites.
- **Notas normales (block):** sin cambios (no aparece 🔗 ni badge).

### Sincronización Nota ↔ Canvas (link único) — REEMPLAZADO por multi-fuente (arriba); ignorar

**Qué se implementó:** un canvas (pizarra/cuaderno) puede **vincularse** a una nota `block` fuente; el contexto del chat IA se toma de esa nota. Lo existente (import manual, OCR→contexto, ancla manual) sigue igual cuando NO hay link. La gestión del link vive **dentro del chat** (reactivo vía `canvasSourceNoteIdProvider`).

**Cómo probar (en dispositivo) — al primer arranque corre la migración (crea `note_canvas_links`):**
- **Vincular:** en un canvas, abre el chat IA → si no hay ancla, en el gate aparece **VINCULAR NOTA FUENTE**; si ya hay ancla, el icono 🔗 en la barra CONTEXTO. Elige una nota de la carpeta → la barra cambia a **`SINCRONIZADA ▸ [título] · hace Xmin`**.
- **Sync:** edita la nota fuente (sal del canvas → nota → edita → vuelve) y reabre el chat → el contexto se actualiza. El botón **↻** re-sincroniza sin reabrir.
- **Badge:** con link activo, el botón IA (✦) muestra un **cuadrito accent que parpadea duro** (600ms) en ambos headers (colapsado y expandido), pizarra y cuaderno.
- **OCR redirigido:** con link, lasso → "Enviar a Yuli" debe **agregar un bloque de texto a la nota fuente** (no al ancla) y abrir el chat ya sincronizado. "Preguntar a Yuli" sigue prellenando el input.
- **Desvincular:** desde la barra (icono link-off) → el ancla queda **congelada** (control manual vuelve), el badge se apaga.
- **Defensa:** borra la nota fuente → al reabrir el chat del canvas, se **auto-desvincula** (no truena).
- **Notas normales (block):** sin cambios — no aparece 🔗 ni "Vincular" ni badge.

### Cajas de TEXTO en canvas (pizarra + cuaderno) — suelo fértil para v3

**Qué se implementó:** nuevo `CanvasTextBlock` (markdown) que se renderiza con el MISMO motor que las celdas de texto de notas (`NoteMarkdownPreview`) → se ve idéntico a una nota. Botón **Texto** (icono notas) en el toolbar de pizarra/cuaderno. Serializado en `DrawingData['tx']` (bloques viejos sin la clave → lista vacía, no rompe).

**Cómo probar (en dispositivo):**
- **MODO TEXTO:** toca **Texto** (icono notas) → inserta una caja Y **se queda en modo texto** (el botón queda activo). El tamaño de inserción **se adapta al zoom** (~240px en pantalla; el user hace zoom para escribir).
  - En modo texto: **tocar la caja en cualquier zona = abre el editor** (markdown dockeado sobre el teclado). **Arrastrar (1 dedo) = mover** la caja. **2 dedos = navegar** (zoom/pan). 1 dedo en vacío no hace pan (reservado para mover cajas).
  - GUARDAR → se renderiza igual que una nota (mismo motor).
- **Resize (con el LAZO):** 4 esquinas + 2 lados (izq/der). **Arriba/abajo deshabilitado** (no se dibujan ni responden esos handles).
  - **Esquinas** → escala uniforme (letra crece/encoge). **Lados izq/der** → ancho, texto refluye. NUNCA deforma.
  - **Mínimo MUCHO más chico** que las cajas de tarea (40px world) — probar encoger bastante estando con zoom.
- **Trazos ENCIMA de la caja:** dibuja con lápiz sobre una caja de texto → la tinta debe quedar **encima** (no detrás). (Las cajas de tarea siguen encima de los trazos.)
- **Tablas raras de la IA:** si la IA mete una tabla con `|---|` mal formado, la caja la **repara** (misma protección que el chat) y NO truena.
- **Persistencia:** cerrar y reabrir la pizarra/cuaderno → las cajas **siguen ahí** (bug arreglado: `DrawingBlock.textBlocksJson`). Cuaderno multi-página: mover entre páginas reasigna por `_syncLassoToPages`.
- **Enviar a lienzo (chat):** chat IA desde **pizarra/cuaderno** → en una respuesta, **Enviar a lienzo** → cierra el sheet y aparece la caja con la respuesta (markdown crudo). Idéntica a la del chat. En una **nota normal** el botón NO aparece.
- **Espacio blanco arriba:** se redujo el padding de la caja; verificar que el texto arranca cerca del borde (el padding top de headings del markdown puede dejar algo — avisar si molesta).

### 2. Caja de tareas — resize por esquina y lateral (cuaderno + pizarra)

**Qué se cambió:** el bloque ahora tiene un campo `scale`. El contenido se maqueta a ancho `w/scale` y se escala uniforme con `FittedBox(fit: fitWidth)`. Se eliminó el viejo `_heightLocked` + `FittedBox.fill` (deformaba y nunca se activaba porque el lasso muta el bloque in-place).

**Cómo probar (con el lasso, bloque seleccionado):**
- **Resize por ESQUINA:**
  - ✅ Esperado: crece/encoge **uniforme** — la caja Y el **texto** escalan juntos (la letra se hace más grande/chica). Cambia ancho **y alto** a la vez. NO debe deformarse (texto estirado/aplastado).
  - ✅ Al **soltar** debe quedar exactamente como se veía durante el arrastre — **sin** deformarse y **sin** tener que "moverla un poco" para que tome forma.
- **Resize LATERAL derecho:**
  - ✅ Esperado: solo cambia el **ancho**, el texto **refluye** (se reacomoda) al mismo tamaño de letra. (Esto ya funcionaba; confirmar que sigue igual.)
- **Resize en vivo:**
  - ✅ Durante el arrastre por esquina se debe ver el cambio en tiempo real (la caja sigue al lasso). Durante el lateral la caja se queda quieta y salta al reflujo al soltar (comportamiento aceptado).
- Probar **encoger** hasta el mínimo (no debe bajar de ~220×90 px renderizados ni dejar el texto ilegible/cortado).
- **Rotar** + luego redimensionar: que siga coherente.
- **Cerrar y reabrir** el cuaderno/pizarra: el bloque debe conservar su tamaño/escala (se serializa `scale`). Bloques **viejos** (creados antes de este cambio) deben verse igual que antes (scale por defecto 1.0).
- Que el **bounding box del lasso** quede bien ajustado al bloque después de redimensionar (sin franja vacía arriba/abajo).

### v2 — Asistente IA (chat) — branch `ocr` — NECESITA TU API KEY

**Qué se implementó:** base DeepSeek (streaming, OpenAI-compatible) + key cifrada en Ajustes + chat read-only (habla y copias; NO edita → v3). **La conversación vive en una sesión POR NOTA** (provider autoDispose), no en el sheet. Entradas: botón **IA** (✨) en el toolbar de **pizarra/cuaderno** y en el header del **editor de notas**, y **"Preguntar a IA"** desde la sheet de OCR.

**Cómo probar (en dispositivo):**
1. **Ajustes → ASISTENTE IA (DEEPSEEK)** → pega tu API key → **Guardar** ("Configurada ✓"). No sale del dispositivo.
2. Abre el chat (botón IA en pizarra/cuaderno/nota, o desde el lasso/OCR).
   - ✅ Streaming, chips (Resumir/Limpiar/Extraer tareas/Título/Traducir), repreguntar mantiene hilo, toggle FLASH/PRO, Copiar, "N hoy" + bloqueo al llegar a 150.
   - ✅ **La respuesta se renderiza como markdown** (negritas, listas, código, blockquotes, checklists, tablas, LaTeX `$..$`/`$$..$$`) con el mismo renderer de las notas. Durante el streaming se ve texto plano y al terminar "cuaja" a markdown.
   - ✅ **Entradas:** botón IA en header de nota y en header/toolbar de pizarra/cuaderno; desde el lasso: **Enviar a Yuli** (texto OCR → contexto), **Preguntar a Yuli** (OCR → prellena el input, sin tocar el contexto), **Importar nota** (pizarra/cuaderno → elegir otra nota de la carpeta como contexto). Long-press en una nota inyecta su contenido (sin duplicar).
3. **Persistencia (lo que faltaba):**
   - ✅ **Cierra el sheet** y vuelve a abrir IA → la conversación **sigue ahí** (no se pierde).
   - ✅ **Sal de la nota/pizarra/cuaderno** y entra de nuevo → **los mensajes se descartan** (chat limpio) PERO **el contexto/ancla PERSISTE por nota** (sigue ahí, incluso tras reiniciar la app).
4. **Cambiar/añadir contexto (lo que faltaba):**
   - ✅ Toca el chip **"CONTEXTO"** arriba → editor para **editar / reemplazar / limpiar** el ancla.
   - ✅ Con un chat ya con contexto, manda **otro** (OCR de pizarra, o IA desde otra nota) → pregunta **Añadir / Reemplazar**. (Si el contexto entrante es idéntico al actual, no pregunta.)
5. **Sin key** → avisa ir a Ajustes. **Key inválida/sin red/sin saldo** → error claro en el chat.
7. **Rediseño visual (Claude Design, ADN brutalista):** verificar en dispositivo (no probado en remoto):
   - Header **ink** con marca (cuadro + diamante), wordmark "YuLi · IA / ASISTENTE DE NOTAS", **segmentado FLASH|PRO**, **barra de uso** (usado/150) y cerrar.
   - **Barra CONTEXTO ▸** con el texto del ancla + ✎ (editar) + ✕ (quitar).
   - Burbujas con **sombra dura**: usuario (etiqueta TÚ, accent) e IA (marca con **diamante que rota**, etiqueta YULI · IA, markdown).
   - **Saludo** genérico al abrir un chat vacío.
   - **Acciones por respuesta de IA:** Copiar (real), **Guardar en nota / Rehacer / Extraer tareas** (por ahora muestran "disponible en v3").
   - Quick actions con glifos (≡ ☑ A ⇄ ⌫ ❝) bajo "// ACCIONES SOBRE LA NOTA".
   - Todo usa el **accent de la nota** (no azul fijo). Revisar que no haya overflow del header en pantallas angostas.
6. **Auto-compactación del contexto (token-shielding):** carga un contexto largo (>3000 chars; p.ej. varios OCR/notas añadidos) y manda un mensaje → ✅ la IA **compacta** el contexto una vez, aparece el aviso **"✦ Compacté el contexto…"** y un botón **DESHACER** (solo en ese aviso). Deshacer restaura el contexto largo. Editar/añadir contexto vuelve a habilitar la compactación. (No debe poder enviarse otro mensaje mientras compacta.)

### v3 — Acciones que editan (IMPLEMENTADO) — verificar en dispositivo

Botones en cada respuesta de la IA:
- ✅ **Copiar** (portapapeles).
- ✅ **Rehacer** → descarta esa respuesta y regenera el turno (re-envía tu mensaje). Verificar que en una respuesta anterior descarte las de abajo (es "rehacer desde aquí").
- ✅ **Guardar en nota** → abre el selector de carpeta/nota (mismo que OCR): elige nota existente (añade celda de texto al final) o crea nueva. Verifica la celda en la nota.
- ✅ **Extraer tareas → FIGHT** → abre **REVISAR TAREAS** (checkbox + texto editable por línea) → **CREAR N** → tareas en FIGHT (`@carpeta` de la nota) enlazadas a la nota. Verifica que aparezcan en FIGHT y en el bloque de tareas de la nota.
- Probar con respuestas SIN lista (extraer no debe inventar; avisa "no encontré tareas" si no hay).

**v3.1 (IMPLEMENTADO) — verificar en dispositivo:**
- ✅ **Sugerir título** → en el editor de **notas** (no en canvas), la quick-action "Título" pide 3 → **popup elegir + editar** → aplica a `note.title` (y guarda). Verifica que el campo de título se actualice y persista.
- ✅ **Retry con backoff** → en fallos transitorios (sin red / 429 / 5xx) reintenta 2× con backoff, mostrando **"⟳ Reintentando…"** en la burbuja. Solo reintenta si aún no llegó ningún token (no duplica). Errores permanentes (key inválida/sin saldo) no reintentan.
- ❌ **Reemplazar celda** → DROPEADO (con contexto multi-fuente "la celda de origen" ya no aplica; "Guardar en nota" añadiendo cubre el caso).
- ❌ **Proxy para la key** → descartado (app personal, key cifrada local; no se publica).

### OCR v1 — a futuro (verificado en dispositivo, NO bloquea)

OCR v1 funciona en pizarra, cuaderno y celda de dibujo. Quedan para más adelante:
- **Elegir idioma del modelo** (hoy fijo español `es`). Sería un selector en Ajustes + pasar el `langTag` a `runOcrFlow`. La base ya soporta varios idiomas.
- **Modo Matemáticas** (Σ, integrales, etc.): el seam `InkRecognitionMode.math` sigue reservado. Mathpix se **eliminó por completo** (muy caro). Resolver de **otra forma** (por decidir: on-device u otro proveedor). Ver `ONLINE_FEATURES.md`.

### Persistencia de tareas en bloques canvas (sin limpiar IDs huérfanos)

**Idea a explorar luego:** Que los bloques de tareas en canvas (pizarra/cuaderno) conserven sus `taskIds` incluso cuando la tarea se borra de FIGHT (expira, hard delete, etc.). Así el bloque funciona como "registro histórico" de lo que había: las tareas completadas se quedan tachadas, las borradas desaparecen del render actual pero el ID queda como referencia.

**Dificultad:** implica separar el render actual (que depende de `noteLinkedTasksProvider` → solo devuelve tareas vivas) de un render histórico. Haría falta almacenar un snapshot de cada tarea (content, status, doneAt) en el propio bloque al momento del cambio, o consultar la tabla de tareas incluyendo las borradas (que ya no existen tras hard delete de 7 días). Es un cambio de arquitectura — mejor revisarlo con calma.
