# YuLi — Contexto para Claude Code

App "Segundo Cerebro" personal. Flutter, 100% offline-first. Spec original: `C:\Users\PC\Downloads\segundo_cerebro_prompt_final.md`

---

## Stack técnico

| Capa | Tecnología |
|------|-----------|
| UI | Flutter + Riverpod 2.x (`flutter_riverpod ^2.5.3`) |
| Base de datos | Drift ORM (`drift ^2.22.0`, `drift_flutter ^0.2.x`) |
| Markdown | `markdown_widget ^2.3.2` + `flutter_math_fork` |
| Fuentes | Space Grotesk (display) + Inter (body) — TTF locales en `assets/fonts/` |
| Imágenes | `image_picker` |
| UUID | `uuid ^4.5.1` |
| Fechas | `intl ^0.19.0` |

**Versión Flutter:** 3.27+ (usa `Color.toARGB32()`, `CardThemeData`, `DialogThemeData`)

---

## Reglas absolutas (no negociables)

1. **`borderRadius: 0` en todo.** Sin excepciones. Ni en diálogos, ni en cards, ni en inputs.
2. **Riverpod nunca importa Drift directamente.** Flujo obligatorio: UI → Provider → Repository interface → LocalRepository (Drift).
3. **Tablas Drift con `@DataClassName('XxxRow')`** para evitar colisión con modelos de dominio (ej: `Task` vs `TaskRow`).
4. **`expires_at` se calcula en Dart**, nunca con modificadores SQLite: `DateTime.now().add(Duration(hours: 48))`.
5. **Sin `Color.value`** — usar `Color.toARGB32()` (Flutter 3.27+).
6. **Sin `CardTheme`** — usar `CardThemeData`.
7. **Sin `dialogBackgroundColor`** — usar `DialogThemeData(backgroundColor: ...)`.
8. **Providers manuales** — no usar Riverpod generator (`@riverpod`).

---

## Arquitectura de capas

```
lib/
├── main.dart                          # AppShell, _AppInit (gating de startup)
├── domain/
│   ├── models/                        # Modelos puros de dominio (sin Drift)
│   │   ├── task.dart                  # Task, TaskStatus
│   │   ├── folder.dart                # Folder
│   │   ├── note.dart                  # Note
│   │   ├── lab_space.dart             # LabSpace, LabSpaceStatus
│   │   ├── kanban_card.dart           # KanbanCard, CardPriority
│   │   └── kanban_column.dart         # KanbanColumn
│   └── repositories/                  # Interfaces abstractas
│       ├── task_repository.dart
│       ├── folder_repository.dart
│       ├── note_repository.dart
│       ├── lab_space_repository.dart
│       └── kanban_card_repository.dart
├── data/
│   ├── local/
│   │   ├── database.dart              # AppDatabase (@DriftDatabase), runExpiryQueries()
│   │   ├── database.g.dart            # GENERADO — no editar
│   │   ├── tables/                    # 11 tablas Drift (XxxTable con @DataClassName('XxxRow'))
│   │   └── daos/                      # 5 DAOs + sus .g.dart generados
│   └── repositories/local/            # Implementaciones concretas de los repos
└── presentation/
    ├── theme/
    │   └── app_tokens.dart            # TODOS los tokens: colores, tipografía, temas
    ├── providers/                     # Riverpod providers
    │   ├── database_providers.dart    # databaseProvider, expiryResultProvider, repos
    │   ├── task_providers.dart
    │   ├── folder_providers.dart
    │   ├── note_providers.dart
    │   ├── lab_space_providers.dart
    │   └── navigation_provider.dart   # pendingNoteNavigationProvider (cross-mode nav)
    ├── screens/
    │   ├── fight/                     # FightScreen, FightInput, TaskCard
    │   ├── flight/                    # FlightScreen, FolderDetailScreen, NoteEditorScreen
    │   └── lab/                       # LabScreen, LabSpaceDetailScreen, KanbanCardDetail
    └── widgets/                       # Componentes reutilizables
        ├── app_tokens.dart            # (en theme/)
        ├── app_banner.dart
        ├── app_card.dart
        ├── app_section_divider.dart
        ├── app_tag.dart
        ├── app_column_header.dart
        ├── coach_mark.dart            # Onboarding one-time tooltips
        ├── grain_overlay.dart         # Textura decorativa (actualmente desactivada — ver nota)
        └── mode_switch.dart           # Bottom nav FIGHT/FLIGHT/LAB
```

---

## Design tokens (`app_tokens.dart`)

```dart
// Colores principales
paperLight = Color(0xFFF5F2EC)   // fondo claro
paperDark  = Color(0xFF0D0D0D)   // fondo oscuro (casi negro)
inkBlack   = Color(0xFF111111)   // texto claro-mode
inkLight   = Color(0xFFF5F2EC)   // texto dark-mode
inkGray    = Color(0xFF888888)   // texto secundario

// Acents por modo
accentFight  = Color(0xFFE02B2B)  // rojo
accentFlight = Color(0xFF2D4B8E)  // azul pizarra
accentLab    = Color(0xFF3D6B4F)  // verde musgo

// Helpers de contexto
paperColor(context)   // paper según brightness
inkColor(context)     // ink según brightness
cardBackground(context)
desaturate(color)     // para tareas completadas

// Tipografía
displayXL / displayL / displayM  → Space Grotesk Bold/ExtraBold
bodyL / bodyM / bodyS            → Inter Regular
labelBold                        → Inter Bold 14px
mono                             → monospace 14px
```

---

## Base de datos

**Tablas:** `tasks`, `folders`, `notes`, `note_images`, `note_versions`, `note_task_links`, `lab_spaces`, `kanban_columns`, `kanban_cards`, `space_folder_links`, `onboarding_flags`

**Ciclo de vida de tareas:**
```
pending → yesterday → archived_failed → trash → (delete permanente 7 días)
```
Ejecutado en `runExpiryQueries()` al iniciar la app. Retorna `int` (tareas archivadas) para el `AppBanner`.

**Conexión:** `driftDatabase(name: 'yuli_db', native: DriftNativeOptions(shareAcrossIsolates: false))`
> Nota: `shareAcrossIsolates: true` causó problemas, se dejó en `false`.

**Código generado:** Los archivos `.g.dart` se generan con:
```bash
dart run build_runner build --delete-conflicting-outputs
```
No editar `.g.dart` manualmente. Si cambias tablas/DAOs, regenerar.

---

## Modos de la app

| Modo | Color | Descripción |
|------|-------|-------------|
| FIGHT | `accentFight` rojo | Captura rápida de tareas (280 chars, `@mención` para carpeta) |
| FLIGHT | `accentFlight` azul | Notas markdown con carpetas |
| LAB | `accentLab` verde | Tablero Kanban por proyecto (LabSpace) |

**Navegación entre modos:** `currentModeProvider` (StateProvider). Navegación cross-mode (Lab→Flight para abrir nota) via `pendingNoteNavigationProvider`.

---

## Flujo de startup

```
main() → WidgetsFlutterBinding.ensureInitialized() → ProviderScope → YuLiApp
  → _AppInit (ConsumerWidget)
    → ref.watch(expiryResultProvider)  ← FutureProvider con timeout 8s y try/catch
      loading: muestra "YuLi" + spinner
      error/data: AppShell(archivedTaskCount)
        → AppShell → Scaffold con bottom nav (ModeSwitch) + _ModeContent
          → FightScreen / FlightScreen / LabScreen
```

---

## Onboarding

`CoachMark` widget: envuelve cualquier widget, muestra tooltip una sola vez.
- Llaves en tabla `onboarding_flags`: `'fight_intro'`, `'flight_intro'`, `'lab_intro'`
- Métodos en `AppDatabase`: `hasSeenOnboarding(key)`, `markOnboardingSeen(key)`

---

## Componentes clave

### `GrainOverlay` (`grain_overlay.dart`)
Actualmente **desactivado** — `build()` retorna `child` directamente. El `_GrainPainter` existe en el archivo pero no se usa. Se desactivó porque el cómputo bloqueaba el render thread en dispositivos con GPU no estándar (Huawei). Si se reactiva, usar con precaución y solo con `shouldRepaint` que retorne `false`.

### `CoachMark` (`coach_mark.dart`)
Overlay posicionado encima del child. Lee `onboarding_flags` DB. Se descarta con tap. Posición: `above` o `below`.

### `TaskCard` (`fight/task_card.dart`)
- Swipe derecha → completar (con animación fade + HapticFeedback)
- Long press → "Enviar a Kanban" (bottom sheet con selector de LabSpace + columna)
- Botón rescate para tareas de ayer

### `NoteEditorScreen` (`flight/note_editor_screen.dart`)
- Autosave cada 2s + save al cerrar
- Toggle edit/preview markdown
- Fondo dot-grid (`_DotGridPainter`) — este SÍ está activo, es más liviano que el grain
- Panel Fight deslizable (bottom sheet) para ver tareas de la carpeta

---

## Pendientes / Issues conocidos

- **GrainOverlay desactivado:** Reactivar con una implementación que no bloquee (pre-render a imagen, o usar shader). La implementación actual en el archivo usa `ui.Picture` como cache pero está desconectada del widget.
- **Tablet layout:** No hay layout adaptativo. En tablets wide (>720px) el contenido se ve en columna única con espacio vacío. `_crossAxisCount()` en grids ya es responsive (2/3/4 cols según ancho), pero las pantallas principales no tienen split-pane.
- **LaTeX:** `flutter_math_fork` instalado pero no integrado en el preview de markdown. Pendiente wiring en `_MarkdownPreview`.
- **Papelera y Configuración:** Los ítems del menú `•••` → "PAPELERA" y "CONFIGURACIÓN" solo hacen `Navigator.pop`. Pantallas no implementadas.
- **`AppBanner` onAction:** En `main.dart`, el botón "ver" del banner de tareas archivadas llama `onAction: () {}` — no implementado.
- **Trash screen:** No hay pantalla de papelera para ver/restaurar tareas eliminadas.

---

## Comandos útiles

```bash
# Analizar código
flutter analyze lib/

# Build debug APK
flutter build apk --debug

# Regenerar código Drift (si cambias tablas o DAOs)
dart run build_runner build --delete-conflicting-outputs

# Run en dispositivo conectado
flutter run

# Build release APK
flutter build apk --release
```

---

## Convenciones de código

- **Sin comentarios** salvo que el WHY sea no obvio.
- **Sin `await` innecesarios** en returns de funciones async.
- Parámetros wildcard: `(_, _)` en lugar de `(_, __)` (Dart 3 wildcards).
- Colores hexadecimales: `'#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}'`
- Soft delete: campos `deleted_at` / `trashed_at`. Hard delete: 7 días después.
