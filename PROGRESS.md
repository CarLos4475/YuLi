# PROGRESS — YuLi

## Sesión 1 — 2026-05-23

### Completado
- Estructura de carpetas del proyecto (`data/`, `domain/`, `presentation/`, `assets/fonts/`)
- Archivos de continuidad: `AGENTS.md`, `CONTEXT.md`, `PROGRESS.md`
- `pubspec.yaml` actualizado con todas las dependencias (Drift, Riverpod, markdown_widget, etc.)
- **Phase 2 — Design tokens y componentes:**
  - `lib/presentation/theme/app_tokens.dart` con todos los tokens de color, tipografía y espaciado
  - `AppCard` — contenedor rectangular borde negro, sin borderRadius, parametrizable
  - `AppTag` — bloque rectangular para carpetas, estados, prioridades
  - `AppSectionDivider` — separador tipográfico editorial
  - `AppBanner` — banner con borde izquierdo de acento y acción opcional
  - `AppColumnHeader` — header de columna Kanban
  - `GrainOverlay` — textura grain via CustomPainter (noise Perlin simplificado)
  - `ModeSwitch` — barra de navegación global entre modos
- **Phase 3 — Esquema de base de datos:**
  - 11 tablas Drift definidas en `lib/data/local/tables/`
  - `AppDatabase` en `lib/data/local/database.dart` con `runExpiryQueries()` tipado
  - 5 DAOs: `TasksDao`, `NotesDao`, `FoldersDao`, `LabSpacesDao`, `KanbanDao`
- **Phase 4 — Repository Pattern:**
  - 6 modelos de dominio en `lib/domain/models/`
  - 5 interfaces abstractas en `lib/domain/repositories/`
  - 5 implementaciones locales en `lib/data/repositories/local/`
  - Providers Riverpod: `database_providers`, `task_providers`, `folder_providers`, `note_providers`, `lab_space_providers`
  - `main.dart` actualizado con `ProviderScope`, expiry al arranque y modo enum

- **Phase 5 — Modo FIGHT:** `fight_screen.dart`, `fight_input.dart`, `task_card.dart`
  - Input con autofocus, contador de chars (@ no cuenta), popup de @menciones con carpetas
  - Stream pendientes + sección "DE AYER" + sección "COMPLETADAS HOY"
  - Dismissible: swipe derecha = completar (fade out + háptico), swipe izquierda = rescatar (solo yesterday)
  - Respeta `MediaQuery.disableAnimations`
- **Phase 6 — Modo FLIGHT:** `flight_screen.dart`, `folder_detail_screen.dart`, `note_editor_screen.dart`, `block_insert_menu.dart`, `format_toolbar.dart`, `new_folder_dialog.dart`
  - Grid de carpetas con badge de tareas pendientes
  - Editor con dot-grid de fondo (CustomPaint), toggle editar/preview
  - Preview con `markdown_widget`, editor con TextField
  - Autosave cada 2s + guardar al cerrar + versión snapshot
  - Panel deslizante de tareas Fight (DraggableScrollableSheet)
  - BlockInsertMenu con 11 tipos de bloques
- **Phase 7 — Modo LAB:** `lab_screen.dart`, `lab_space_detail_screen.dart`, `kanban_card_tile.dart`, `kanban_card_detail.dart`, `new_lab_space_dialog.dart`
  - Grid de Lab Spaces con status visual diferenciado
  - Kanban board: scroll horizontal de columnas, ReorderableListView por columna
  - DragTarget entre columnas para cross-column drag & drop
  - Card detail como DraggableScrollableSheet (80%): título, selector de columna, prioridad, due date, descripción

- **Phase 8 — Integración cross-modal:**
  - `navigation_provider.dart` — `pendingNoteNavigationProvider` para navegar a nota desde Lab
  - Fight task → Kanban: long-press en `TaskCard` abre `_SendToKanbanSheet` con lista de spaces/columnas. La tarjeta creada guarda `origin_task_id`.
  - "ver nota de origen →" en `KanbanCardDetail` activa el provider y hace pop; `AppShell` escucha y cambia a Flight.
  - Panel Fight en Flight ya estaba implementado en Phase 6 (DraggableScrollableSheet)
- **Phase 9 — Pulido:**
  - `CoachMark` widget reutilizable — lee `onboarding_flags` DB, muestra una sola vez, guarda al dismissar
  - Coachmarks activos: `fight_intro` (input), `fight_at_mention` (popup @), `flight_intro` (grid carpetas), `lab_intro` (grid spaces), `block_insert` (botón + editor)
  - GrainOverlay en headers de Fight, Flight y Lab
  - Dark mode completo: definido en `app_tokens.dart` con `lightTheme()` + `darkTheme()`, sigue preferencia del sistema

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Ejecutar `dart run build_runner build --delete-conflicting-outputs` para generar código Drift
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Decisiones técnicas tomadas
- `@DataClassName('XxxRow')` en todas las tablas Drift para evitar conflicto con modelos de dominio
- Providers Riverpod manuales (sin `riverpod_generator`) para mantener el código explícito
- `AppDatabase` expone `runExpiryQueries()` que retorna `int` (cantidad de tareas archivadas) para decidir si mostrar el AppBanner
- `currentModeProvider` en `database_providers.dart` maneja la navegación entre modos

### Problemas encontrados
- Ninguno en esta sesión

---

## Sesión 2 — 2026-05-23 (Corrección de Cuelgues y Lógica de Expiración)

### Completado
- Se solucionó el cuelgue indefinido (ANR) en la pantalla de carga al iniciar la app en Android. Se cambió `shareAcrossIsolates: true` por `shareAcrossIsolates: false` en `driftDatabase`, evitando el bloqueo del hilo principal por la comunicación entre isolates.
- Se corrigió la consulta de expiración (`runExpiryQueries`) en SQLite. Debido a que Drift almacena los campos `DateTime` como marcas de tiempo Unix (enteros), consultas como `date(created_at)` daban resultados nulos en SQLite. Se agregó el modificador `'unixepoch'` a todas las consultas de comparación de fechas (ej. `date(created_at, 'unixepoch')`).
- Se crearon pruebas unitarias integrales en `test/database_test.dart` para validar en memoria todas las transiciones de fecha de las tareas, comprobando que se archivas, mueven a la papelera y se eliminan correctamente tras los plazos estipulados.
- Se optimizó drásticamente el rendimiento de `GrainOverlay`. Anteriormente, realizaba 12,000 llamadas a `canvas.drawRect` en cada frame, generando millones de asignaciones de objetos y operaciones de números aleatorios en la CPU. Esto saturaba el recolector de basura (GC) y provocaba el cuelgue de buffer en Android (`BLASTBufferQueue: Can't acquire next buffer`). Ahora, el ruido se renderiza a un `ui.Picture` una única vez y se guarda en caché, mientras que un `RepaintBoundary` aísla las actualizaciones de renderizado reduciendo el coste a O(1) con cero asignaciones de memoria por frame.
- Se corrigió un error de layout crítico en la barra de navegación (`ModeSwitch`). Los widgets `_ModeTab` contenían un `Column` sin restricciones que declaraba un `Container` de ancho infinito (`width: double.infinity`) y posteriormente un `Center`, causando que el ancho del tab se expandiera a infinito al renderizarse dentro de un `Row` no constreñido. Esto rompía el paso de diseño (layout pass) en Flutter y dejaba la barra sin dimensiones en la fase de pintura, lanzando excepciones `RenderBox was not laid out` que provocaban bloqueos en el hilo principal. Se simplificó y saneó el diseño implementando la pestaña activa a través de una decoración de borde (`Border`) en el contenedor del tab, auto-ajustándose limpiamente sin desbordamientos de flex.
- Se reemplazó el efecto de ruido/granulado en los headers por fondos de color sólido correspondientes al acento de cada modo (Rojo en Fight, Azul en Flight, Verde en Lab) con texto de alto contraste (inkLight) y un borde inferior separador negro, logrando un aspecto más limpio y premium.
- Se agregó un botón táctil e intuitivo "CAPTURAR" en la barra de captura del modo Fight, deshabilitándose automáticamente si el texto está vacío o excede los 280 caracteres. Esto resuelve el problema de UX donde el teclado virtual de Android no permitía enviar/confirmar tareas debido a que la tecla "Enter" en campos multilínea por defecto inserta saltos de línea (`\n`).
- Se implementó la integración cruzada definitiva entre Fight y Flight: al editar una nota en Flight, abrir el panel de tareas pendientes y hacer tap sobre cualquier tarea, esta se inserta automáticamente en la posición del cursor de la nota como un checklist markdown (`- [ ] tarea`) y se marca como completada de forma inmediata.
- Se convirtió `pendingTasksForFolderProvider` de un `FutureProvider` estático a un `StreamProvider` reactivo. Esto hace que la base de datos envíe actualizaciones en tiempo real y que las tarjetas de carpeta, contadores de badges en Flight y el panel de tareas pendientes se actualicen al instante cuando se captura una tarea en Fight (sin requerir reiniciar la app).
- Se desacopló y modularizó el panel de tareas pendientes creando el componente reutilizable `FightPanel` en `lib/presentation/widgets/fight_panel.dart`.
- Se integró el panel de tareas pendientes en la vista de detalle general de carpetas (`FolderDetailScreen`) mediante un bottomNavigationBar que se muestra únicamente cuando hay tareas pendientes. Al tocar una tarea en esta pantalla general, la tarea se marca como completada directamente.

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Problemas encontrados
- Bloqueo total del event loop de Flutter/Dart por fallas de isolación con `shareAcrossIsolates: true` en entornos Android. Solucionado.
- La base de datos no realizaba transiciones de expiración en arranque debido a la interpretación errónea de SQLite del timestamp numérico como día juliano en vez de unix epoch. Solucionado.
- Sobrecarga masiva de renderizado en `GrainOverlay` (12,000 rects/frame + millones de random allocations/segundo) bloqueando la cola de frames GPU y causando ANR en el dispositivo del usuario al desplegarse el teclado/redimensionar la pantalla. Solucionado.
- Excepciones de renderizado `RenderBox was not laid out` en la barra de navegación (`ModeSwitch`) causadas por constraints de ancho infinito (`double.infinity` + `Center`) dentro de un `Row` flex horizontal. Solucionado.

---

## Sesión 3 — 2026-05-23 (Reactividad de Capturas y Estilizado de Menciones)

### Completado
- Se solucionó la reactivación inicial de carpetas en el modo de captura (FIGHT). Al cargar la pantalla por primera vez, `activeFoldersProvider` no tenía escuchas activos, por lo que retornaba `null` y evitaba que el input reconociera el `@` del autocompletado y guardara la tarea con su `folderId`. Ahora, se observa/escucha `activeFoldersProvider` dentro del widget `FightInput` para mantener el stream caliente desde el arranque.
- Se implementó la persistencia y renderizado inteligente de etiquetas con **split-styling**:
  - En la base de datos se guarda el contenido completo de la tarea con su mención intacta (ej. `"haz lo de @matematicas hoy"`), preservando la referencia original.
  - En la visualización (`TaskCard` en Fight y `PanelTaskTile` en el panel desplegable), se divide el texto dinámicamente; se remueve únicamente el carácter `@` de la mención y se renderiza el nombre de la carpeta (ej. `"matematicas"`) en **negrita y con su color correspondiente**, manteniendo el resto de la frase en su estilo por defecto.
  - En la vista previa de notas (`_MarkdownPreview`), se adaptó un `textGenerator` en `MarkdownGenerator` para interceptar dinámicamente menciones tipo `@nombre_carpeta` y producir un `ConcreteElementNode` con la misma lógica de división de estilos (remoción del `@` y aplicación de negrita + color al nombre del folder).
- Se habilitó la visibilidad permanente del bottom sheet en la vista general de la carpeta (`FolderDetailScreen`), mostrando `— tareas pendientes —` cuando el contador es 0 y `— tareas pendientes (count) —` cuando es mayor a 0, alineando el comportamiento y permitiendo abrir la bandeja en cualquier momento.

---

## Sesión 4 — 2026-05-23 (Soporte LaTeX Completo en Notas y Exclusión de Divisas)

### Completado
- Se implementó el soporte completo para fórmulas LaTeX matemáticas tanto en línea (`$f(x)$`) como en bloque (`$$f(x)$$`).
- Se introdujo `LatexBlockSyntax` (subclase de `BlockSyntax` de `markdown`), que captura correctamente fórmulas de bloque de múltiples líneas (e incluso líneas vacías intermedias) delimitadas por `$$` independientes, impidiendo que el motor de markdown las fragmente en múltiples párrafos.
- Se refinó la expresión regular en `LatexSyntax` a `r'(\$\$(?!\s)([\s\S]+?)(?<!\s)\$\$)|(\$(?!\s)([^$\n]+?)(?<!\s)\$)'` para exigir que los delimitadores no tengan espacios adyacentes a su contenido interno. Esto soluciona los problemas de falsos positivos en oraciones con precios o divisas (por ejemplo: `tengo $10 y $20`, `$10, $20 y $30` o un precio simple como `cuesta $5`), que ahora se muestran como texto normal en lugar de generar errores de renderizado matemático.
- Se agregó el archivo `test/latex_test.dart` con pruebas de integración de widgets para validar la rendering del componente `Math` y asegurar la correcta exclusión de precios de divisa del parser matemático. Todas las pruebas unitarias y de integración pasan con éxito.
- Se solucionó un error de ciclo de vida (`StateError: Cannot use "ref" after the widget was disposed.`) que provocaba el cierre inesperado (cuelgue/crash) de la app al salir de las pantallas de edición (`NoteEditorScreen` y `KanbanCardDetail`). Este error ocurría porque el método `_save()` se invocaba en `dispose()` de forma síncrona pero ejecutaba consultas asíncronas de guardado, lo que causaba que al retornar del primer `await` el widget ya estuviese desmontado e intentar usar `ref.read` fallara. Se resolvió almacenando una referencia en caché al repositorio (`final repository = ref.read(...)`) de forma síncrona antes de los awaits.
- Se implementaron las conexiones cruzadas de integraciones de la **Fase 8 (Flight ➔ Lab)**:
  - **Conversión de Notas a Kanban Cards:** Añadido el botón "vincular a Lab" en el header del editor de notas (`NoteEditorScreen`). Al presionarlo, abre el panel `_SendNoteToKanbanSheet` que despliega los Lab Spaces y sus columnas. Al seleccionar una columna, se crea la tarjeta Kanban apuntando a la nota (`sourceNoteId`) y se inserta automáticamente un ancla invisible en la nota (`<!-- kanban:{id} -->`) forzando el auto-guardado.
  - **Vinculación de Carpetas a Lab Spaces:** Añadido un botón de carpeta en el header del tablero Kanban (`_KanbanHeader` en `LabSpaceDetailScreen`). Al presionarlo, abre la bandeja `_LinkFoldersSheet` para asociar/desasociar carpetas Flight completas a este Lab Space en la tabla `space_folder_links`. Las carpetas vinculadas se muestran dinámicamente como etiquetas de colores debajo del título del space.
  - **Prueba de Integración:** Añadida una prueba unitaria/de integración en `test/latex_test.dart` que valida el guardado en base de datos y mapeo en repositorio de la relación de carpetas vinculadas a espacios y tarjetas Kanban nacidas de apuntes.
- Se implementó la opción de eliminación por pulsación larga (**long-press**) en la galería de carpetas de Flight (`_FolderTile` en `flight_screen.dart`) y en los recuadros de proyectos de Lab (`_SpaceTile` en `lab_screen.dart`). Al mantener presionado un elemento:
  - Se despliega un diálogo de confirmación `AlertDialog` con bordes rectos estrictos (`borderRadius: 0.0`) y colores de contraste.
  - Al confirmar, se invoca de forma segura el método `softDelete` de su correspondiente repositorio (`FolderRepository` o `LabSpaceRepository`), enviándolo a la papelera en base de datos de manera reactiva (desapareciendo inmediatamente de las cuadrículas activas de la interfaz).





