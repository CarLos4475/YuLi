# YuLi · Resumen de sesión · 25-may-2026

Rediseño completo del frontend de YuLi siguiendo el sistema brutalista
"Command Triptych" (V1) entregado por Claude Design. Cada fase compiló con
`flutter analyze` limpio (0 errores).

## Setup

- Flutter 3.44.0 instalado en `~/development/flutter`
- Target principal: Android tablet landscape 1280×820
- Tokens centralizados: `lib/presentation/widgets/yuli_design.dart`
- Stack DB: drift + sqlite3_flutter_libs (sin cambios de stack)
- Schema bumps: v10 → v11 (note_blocks) → v12 (Notes.kind) → v13 (KanbanColumns.isTerminal)

## Fases entregadas

### Home View (V1 Command Triptych)
- `home_screen.dart` reescrito como 3 pilares (FIGHT/FLIGHT/LAB) que vacían
  contenido del modo correspondiente
- Header strip 96px con greeting + tiempo + fecha + bloque negro YuLi (Li
  en ámbar) + gear de settings
- LAB pillar con multi-space scroll, stage label derivado de fechas,
  progress bar achurada en tiempo (no porcentaje manual), próxima clase
  agregada de todos los spaces activos
- Phone fallback: stack vertical

### Mode views (FIGHT / FLIGHT / LAB)
- `ModeHeader` + `YuliBottomNav` 68px (reemplaza `ModeSwitch` viejo)
- FIGHT: 3 buckets HOY | AYER | VENCIDAS con CapturaBar (FIGHT/ prefix +
  red + button), mention popup @folder
- VENCIDAS bucket usa `archived_failed` con grace period 24h antes de
  trash (no migración DB)
- FLIGHT: toolbar (+NUEVA / ORDEN / FILTRO / view toggle / search ⌘K),
  folder cards w/ 3 recent notes preview, EDITADA HACE Xh, scope de
  linked labs, pinning via SharedPreferences
- Folder detail: hero header con color stripe, notas grid 3-col
  saturadas, TAREAS PENDIENTES strip
- LAB: tabs EN PROCESO / PAUSADOS / COMPLETADOS / ARCHIVO. Space card
  con top stripe, stage badge, due, days-left urgent ≤7d, stacked
  distribution bar, stats abiertas/vencidas/hechas, capability chips
  toggleables (lectura de `labTabsProvider`)
- `LabSpaceStatus.paused` añadido al enum (compat forward)

### Note editor (P1-P6)
- DB migration: nueva tabla `note_blocks(id, note_id, position, type,
  payload JSON, timestamps)`. Legacy wipe (single-user)
- `NoteBlock` sealed class con subtipos Text / Math / Heading / Bullets /
  Tareas / Drawing
- `NoteBlockActions` helper: crea tasks reales heredando @folder,
  toggle done global, link a kanban (origin_task_id), delete dialog
  "unlink vs hard-delete"
- Editor reescrito: ReorderableListView de bloques w/ drag handle ⋮⋮,
  autosave per-block (2s debounce + flush en blur)
- 4 icon actions: ✓ save / ◉ image / ∞ link-lab / PDF
- Drawing toolbar rediseñado: 6 colores fijos, 3 sizes, lock scroll,
  undo/redo, clear con confirm, **palm rejection** (PointerDeviceKind
  filter stylus/invertedStylus)
- Propagation chips ↳NOTA / →SPACENAME en FIGHT bucket y FLIGHT folder
  TAREAS strip (`taskPropagationProvider`)

### Note variants (P7-P9)
- `Notes.kind` enum block | whiteboard
- New-note picker dialog antes de create
- `WhiteboardEditorScreen`: InteractiveViewer pan+zoom 0.3x-4x, canvas
  10000×10000 con grid dotted, toolbar idéntica a drawing block + palm
  rejection + SNAP toggle
- `ShapeRecognizer`: line / circle / ellipse / rectangle / triangle /
  arrow. Algoritmos: regresión lineal, varianza radial, Douglas-Peucker,
  fit elipse por bbox
- Hold-end trigger Apple-Notes-style: timer 800ms reset en cada
  pointer-move; si pointer sigue down → detect → replace stroke +
  HapticFeedback.lightImpact
- Whiteboard link-to-lab: mismo flujo de kanban_card con sourceNoteId,
  navigation kind-aware

### Space detail (P10-P14)
- `kanban_columns.isTerminal` BOOL (schema v13). Migration set
  Entregado/Vencido a terminal por default
- SpaceFrame chrome: header brutalist (back + name flight + scope chip +
  date chip + 4 icon btns con bg color), tab strip mono labels + ✕
  closable + "+" preset picker
- Kanban column: color stripe top + DONE chip si isTerminal + ⋯ menu
- `_ColumnManagePopover`: rename / mover izq | der / toggle terminal /
  delete. GhostColumn brutalist
- AddCard footer mono "+ AÑADIR TAREA"
- Horario/Timeline/Calendario tabs refrescados con `ViewHead` + NavBtn +
  HeadBtn. Lógica intacta
- Card detail sheet: drag handle ink + kicker mono + título grande + 3
  sheet icons (save/preview/close) + "// ESTA TAREA APARECE EN" chips
  derivados (Kanban col, Calendario fecha, Timeline fecha, FIGHT origen,
  FLIGHT nota) + footer eliminar underline + autoguardado mono

## Cifras

- Commits en branch `horario`:
  - `bbf5a29` OVERHAUL VISTAS DE HOME
  - `8620b87` Fixes a ciegas
  - `01a30b4` OVERHAUL TOTAL A LAS NOTAS
  - `fedc476` Pizarra infinita + variant picker + lab link
  - (este resumen + space redesign)

- `flutter analyze`: **0 errors**, 27 lints pre-existentes en código no
  tocado (note_editor legacy, calendar_tab, timeline_tab, etc.)

## Pendientes para device

Cuando se baje el repo en casa:

1. `dart run build_runner build` para regenerar `.g.dart`
2. Instalar Android SDK (Android Studio) si no está
3. `flutter doctor --android-licenses`
4. `flutter run -d <android-device>`

Pruebas críticas:
- Home pillars tablet → tabs mode → bottom nav
- FIGHT 3 buckets swipe + long-press send to lab
- FLIGHT folder con notas grid + tareas strip
- Nueva nota → picker → block editor / pizarra
- Pizarra: dibujar círculo + hold pen 800ms → snap
- LAB space → tabs (kanban con popover ⋯, terminal toggle)
- Kanban card → detail sheet con "aparece en" chips

## Decisiones registradas

- Storage VENCIDAS = `archived_failed` con grace 24h (no migración)
- Pinning folders/notes = SharedPreferences (no migración)
- Folder scope = nombres de spaces linkeados (m:n existente)
- Math display = bloque separado; inline LaTeX deferred
- Drawing toolbar palm rejection ON por default
- Shape recognition SNAP toggle ON por default
- Whiteboard pan+zoom via InteractiveViewer + lock toggle para dibujar
- Terminal column = explicit boolean + UI toggle (no heurística nombre)
