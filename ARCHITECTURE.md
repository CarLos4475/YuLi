# ARCHITECTURE — YuLi

## Stack

| Layer | Technology |
|---|---|
| UI | Flutter + Riverpod 2.x (`flutter_riverpod ^2.x`) |
| Database | Drift ORM + SQLite (`drift ^2.x`, `sqlite3_flutter_libs`) |
| Markdown | `markdown_widget` + `flutter_math_fork` |
| Fonts | Space Grotesk (display), Inter (body) — local TTF in `assets/fonts/` |
| Images | `image_picker`, `photo_manager`, `flutter_image_compress` |
| Dates | `intl ^0.19.0` |
| Notifications | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| AI | DeepSeek API (OpenAI-compatible, streaming SSE) + Jina Reader |
| OCR | Google ML Kit Digital Ink Recognition (on-device) |
| PDF Export | `pdf` + `share_plus` |
| Security | `flutter_secure_storage` (API key cifrada) |
| Flutter | 3.27+ (uses `Color.toARGB32()`, `CardThemeData`, `DialogThemeData`) |

## Layer Architecture

```
UI (Flutter Widgets)
    ↓
Riverpod Providers  (lib/presentation/providers/)
    ↓
Repository Interface  (lib/domain/repositories/)
    ↓
LocalRepository (Drift)  (lib/data/repositories/local/)
    ↓
DAO + AppDatabase  (lib/data/local/)
```

**Cardinal rule:** Riverpod NEVER imports Drift directly. Only knows Repository interfaces.

## Folder Structure

```
lib/
├── main.dart                  # ProviderScope → YuLiApp → _AppInit startup gate
├── domain/
│   ├── models/                # Task, Note, NoteBlock, Folder, LabSpace, KanbanCard,
│   │                          # KanbanColumn, Graph, ScheduleBlock, ReminderPreset,
│   │                          # CanvasContextSource, NotificationItem, PageBackground…
│   ├── repositories/          # Abstract interfaces (note, folder, task, kanban, etc.)
│   └── services/              # Contratos (AiAssistant, InkRecognizer, ReminderScheduler)
├── data/
│   ├── local/
│   │   ├── database.dart      # AppDatabase, runExpiryQueries, hardDeleteCascades, migrations
│   │   ├── tables/            # 19 Drift table definitions
│   │   ├── daos/              # Data Access Objects Drift
│   │   └── repositories/      # Concrete local repository implementations
│   └── services/              # DeepSeek Assistant, ML Kit recognizer, reminder coordinator,
│                              # web reader (Jina), context cache, crash logger, image storage
└── presentation/
    ├── theme/                 # app_tokens.dart — todos los tokens de diseño neobrutalista
    ├── providers/             # Riverpod providers (database, tasks, notes, AI, theme, etc.)
    ├── screens/
    │   ├── home/              # Dashboard (triptico Fight/Flight/Lab, progreso, próxima clase)
    │   ├── fight/             # Task capture inline, buckets Hoy/Ayer/Vencidas
    │   ├── flight/            # Note editor (bloques), whiteboard, notebook, OCR, AI chat
    │   ├── lab/               # Kanban, calendar, timeline, schedule, graph, AI, sources
    │   ├── settings/          # Tema, API keys, almacenamiento, crash logs
    │   └── trash/             # Papelera 3 columnas (Flight/Lab/Fight)
    └── widgets/               # Sistema de diseño reutilizable (ModeHeader, YBadge, PillTab, etc.)
```

## App Modes

| Mode | Color | Purpose |
|---|---|---|
| FIGHT | Red (`#E02B2B`) | Quick task capture (280 chars, `@folder` mention) |
| FLIGHT | Blue (`#2D4B8E`) | Markdown notes with folders |
| LAB | Green (`#3D6B4F`) | Kanban board per project (LabSpace) |

Navigation: `currentModeProvider` (StateProvider). Cross-mode navigation via `pendingNoteNavigationProvider` / `pendingFolderNavigationProvider`.

## Startup Flow

```
main() → ProviderScope → YuLiApp → _AppInit
    → ref.watch(expiryResultProvider) — FutureProvider with 8s timeout
        loading: "YuLi" + spinner
        data: AppShell(archivedTaskCount)
    → AppShell → Scaffold + bottom nav → active mode screen
```

## Database

**Tables:** `tasks`, `folders`, `notes`, `note_images`, `note_versions`, `note_task_links`, `note_canvas_links`, `note_blocks`, `lab_spaces`, `kanban_columns`, `kanban_cards`, `space_folder_links`, `space_context_sources`, `onboarding_flags`, `schedule_blocks`, `schedule_settings`, `schedule_week_notes`, `notifications`, `canvas_context_sources` (19 total).

**Task lifecycle:**
```
pending → yesterday → archived_failed → trash → hard delete (7 days)
```
Expiry runs in `runExpiryQueries()` at startup (8 pasos: archivar, vencidas, huérfanos, top 50 notifs, purgar trash). Returns `int` (archived count) for AppBanner.

**Cascadas a nivel app (FK OFF):** `hardDeleteNoteCascade`, `hardDeleteFolderCascade`, `hardDeleteSpaceCascade`, `softDeleteFolderCascade`, `restoreFolderCascade` en `AppDatabase`. Las imágenes en disco las limpia `cleanupOrphanedImages` al arranque (no la BD).

**Code generation:**
```bash
dart run build_runner build --delete-conflicting-outputs
```
Never edit `.g.dart` files manually.

## Key Integrations

- **Task ↔ Kanban sync (`setTaskDone`/`setTaskDoneWith`):** Unico punto bidireccional Fight↔Lab. Completar tarea en Fight mueve card a columna terminal. Mover card a terminal completa la tarea. Reabrir deshace ambos lados y re-sincroniza `dueDate`.
- **Note ↔ Kanban link:** Notes pueden crear cards con `sourceNoteId`. Cards linkean a nota de origen.
- **Note ↔ Task link:** Many-to-many via `note_task_links`.
- **Canvas ↔ Source note link (AI context):** `note_canvas_links` — el OCR redirigido escribe en la nota fuente.
- **Schedule ↔ Flight:** Schedule blocks linkean a carpetas Flight. Widget "Próxima clase" en home y folder detail.
- **AI context system:** `space_context_sources` + `canvas_context_sources` (notas, carpetas, URLs vía Jina Reader). Caché por hash de contenido en `context_cache.dart`.
- **Graph (force-directed):** Conexiones cross-mode visualizadas como grafo. 5 tipos de nodo (space, card, folder, note, task), 3 aristas (structure, bridge, AI). Assembly via `GraphAssembler`, simulación D3-like en `GraphSimulation`.
- **Reminder system:** `ReminderCoordinator` + `LocalReminderScheduler` (flutter_local_notifications). Presets programables, resumen diario, exact reminders. Sincronización con due dates de tasks/cards.
