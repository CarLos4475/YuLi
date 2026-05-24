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
- Ninguno en esta sesión

---

## Sesión 10 — 2026-05-23 (Cierre de Sesión)

### Completado
- Véase Sesiones 5–9 para el trabajo realizado hoy (rediseño brutalista de Home, Settings, Tab Bar, exportación a PDF).

### Pendiente
- **Pulir exportación a PDF:** la implementación actual es funcional pero mínima. Se requiere:
  - Preservar formato markdown real (negritas, listas, headers) en vez de strippear todo a texto plano.
  - Soporte para imágenes incrustadas en la nota.
  - Soporte para ecuaciones LaTeX (renderizado o fallback a texto).
  - Mejor manejo de saltos de página y márgenes.
  - Posible selección de formato adicional (txt, markdown raw).
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter).
- Pruebas en dispositivo real (Android/iOS).
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview.

### Problemas encontrados
- `share_plus` requiere reinstalación limpie de la app (`flutter clean` + desinstalar APK + `flutter run`) porque contiene código nativo Android que no se inyecta con Hot Restart.

---

## Sesión 6 — 2026-05-23 (Pantalla de Ajustes y Selector de Tema)

### Completado
- Se agregó `shared_preferences: ^2.3.2` a `pubspec.yaml` para persistencia de preferencias locales.
- Se creó `lib/presentation/providers/theme_provider.dart`:
  - `ThemeModeNotifier` que lee/escribe `ThemeMode` (light/dark/system) en `SharedPreferences` bajo la clave `theme_mode`.
  - `themeModeProvider` expuesto como `StateNotifierProvider<ThemeModeNotifier, ThemeMode>`.
  - `initThemeModeOverride()` para inicializar el provider con el valor almacenado antes del primer frame.
- Se creó `lib/presentation/screens/settings/settings_screen.dart` con estilo brutalista:
  - Header sólido `inkColor` con título "AJUSTES" en mayúsculas y flecha de regreso.
  - Sección "APARIENCIA" con tres opciones de tema: Claro, Oscuro, Sistema.
  - Indicador de selección como cuadrado sólido rojo (`accentFight`) o cuadrado vacío con borde.
  - Sección "INFO" con filas de versión y modo (Offline-first).
  - Bordes inferiores finos para separar filas. Sin borderRadius.
- Se actualizó `lib/main.dart`:
  - `main()` ahora es `async`, inicializa `SharedPreferences` y pasa el override al `ProviderScope`.
  - `YuLiApp` convertido a `ConsumerWidget` para observar `themeModeProvider` y pasar el valor a `MaterialApp.themeMode`.
- Se agregó botón de ajustes (`Icons.settings`) en la esquina superior derecha del header monolito de `home_screen.dart`, navegando a `SettingsScreen` con `MaterialPageRoute`.

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Problemas encontrados
- Ninguno en esta sesión

---

## Sesión 7 — 2026-05-23 (Rediseño de la Tab Bar Inferior)

### Completado
- Se rediseñó `lib/presentation/widgets/mode_switch.dart`:
  - `ModeSwitch` ahora usa `mainAxisSize: MainAxisSize.max` para ocupar todo el ancho disponible.
  - Los tres tabs de modo (FIGHT, FLIGHT, LAB) están envueltos en `Expanded`, distribuyendo el espacio restante de forma equitativa entre ellos.
  - El botón overflow (`•••`) tiene ancho fijo de 48px y está siempre pegado a la derecha, alineado con el botón de retroceso (`<`).
  - Se agregaron separadores verticales finos (`Container(width: 1, height: 28, color: inkGray.withAlpha(60))`) entre cada tab y entre el último tab y el overflow.
  - Se unificó la altura de todos los elementos a 56px para coherencia visual.
  - El overflow menu ahora también incluye el acceso a "CONFIGURACIÓN" (`SettingsScreen`), corrigiendo la ruta que antes era un no-op.

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Problemas encontrados
- Ninguno en esta sesión

---

## Sesión 8 — 2026-05-23 (Rediseño Brutalista de Ajustes)

### Completado
- Se reescribió `settings_screen.dart` con estilo brutalista puro:
  - Header monolito sólido `inkColor` con flecha de regreso y título "AJUSTES" en blanco.
  - Separador `AppSectionDivider` editorial para las secciones `TEMA` e `INFO`.
  - Tres bloques de tema lado a lado (`CLARO`, `OSCURO`, `SISTEMA`), cada uno con color de fondo sólido propio (`paperLight`, `paperDark`, `accentFlight`), texto de alto contraste, borde negro de 2px y sombra sólida offset (3,3).
  - Indicador de selección como **checkbox cuadrado** con borde negro: cuando está activo muestra un cuadrado rojo sólido (`accentFight`) en el interior; vacío cuando no.
  - Dos bloques de info lado a lado (`VERSIÓN` en ocre, `MODO` en verde), mismos bordes y sombras, labels en mayúsculas pequeñas y valores grandes en `displayM`.
  - Bloque de marca final (`YuLi / Segundo Cerebro`) de color negro sólido con texto blanco, borde y sombra.
  - Sin `AppBar`; todo el layout es un `ListView` dentro de `SafeArea` sin padding externo. Sin borderRadius en ningún elemento.

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Problemas encontrados
- Ninguno en esta sesión

---

## Sesión 9 — 2026-05-23 (Exportar Notas a PDF)

### Completado
- Se agregaron dependencias `pdf: ^3.10.8` y `share_plus: ^10.0.0` a `pubspec.yaml`.
- Se creó `lib/presentation/utils/pdf_export.dart` con función `exportNoteToPdf`:
  - Genera un PDF A4 con título en mayúsculas, línea separadora negra y contenido de la nota en texto plano.
  - Limpia el markdown básico (`#*_[\]()!-`) para producir texto legible.
  - Guarda el PDF en directorio temporal con nombre sanitizado basado en el título de la nota.
  - Lanza la hoja de compartir nativa del sistema (`Share.shareXFiles`).
- Se agregó botón cuadrado de exportar PDF en `NoteEditorScreen`:
  - Color de fondo `accentJournal` (ocre), borde negro de 2px, sombra sólida offset (3,3).
  - Icono `Icons.picture_as_pdf` en blanco, tamaño 16px.
  - Ubicado en el header junto a los botones de guardar, preview y vincular a Lab.

### Pendiente
- Descargar y agregar fuentes TTF a `assets/fonts/` (Space Grotesk + Inter)
- Pruebas en dispositivo real (Android/iOS)
- Futura **Phase opcional:** LaTeX real via `flutter_math_fork` integrado en `markdown_widget` preview

### Problemas encontrados
- Ninguno en esta sesión

