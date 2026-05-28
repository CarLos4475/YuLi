# ARCHITECTURE — YuLi

## Stack

| Layer | Technology |
|---|---|
| UI | Flutter + Riverpod 2.x (`flutter_riverpod ^2.x`) |
| Database | Drift ORM + SQLite (`drift ^2.x`, `sqlite3_flutter_libs`) |
| Markdown | `markdown_widget` + `flutter_math_fork` |
| Fonts | Space Grotesk (display), Inter (body) — local TTF in `assets/fonts/` |
| Images | `image_picker` |
| Dates | `intl ^0.19.0` |
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
├── main.dart                  # AppShell, _AppInit startup gate
├── domain/
│   ├── models/                # Pure domain entities (Task, Note, Folder, etc.)
│   └── repositories/          # Abstract interfaces
├── data/
│   ├── local/
│   │   ├── database.dart      # AppDatabase, runExpiryQueries, migrations
│   │   ├── tables/            # 11+ Drift table definitions
│   │   └── daos/              # Data Access Objects
│   └── repositories/local/    # Concrete repository implementations
└── presentation/
    ├── theme/                 # app_tokens.dart — all design tokens
    ├── providers/             # Riverpod providers (database, tasks, notes, etc.)
    ├── screens/
    │   ├── fight/             # Task capture, buckets
    │   ├── flight/            # Notes, folders, editors
    │   └── lab/               # Kanban, calendar, timeline, schedule
    └── widgets/               # Reusable components
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

**Tables:** `tasks`, `folders`, `notes`, `note_images`, `note_versions`, `note_task_links`, `note_blocks`, `lab_spaces`, `kanban_columns`, `kanban_cards`, `space_folder_links`, `onboarding_flags`, `schedule_blocks`, `schedule_settings`, `schedule_week_notes`

**Task lifecycle:**
```
pending → yesterday → archived_failed → trash → hard delete (7 days)
```
Expiry runs in `runExpiryQueries()` at startup. Returns `int` (archived count) for AppBanner.

**Code generation:**
```bash
dart run build_runner build --delete-conflicting-outputs
```
Never edit `.g.dart` files manually.

## Key Integrations

- **Task ↔ Kanban sync:** Completing a task in Fight moves linked card to "Entregado". Moving card to "Entregado" from kanban completes the linked task. Expired tasks move card to "Vencido".
- **Note ↔ Kanban link:** Notes can create kanban cards with `sourceNoteId`. Invisible `<!-- kanban:{card_id} -->` anchor in the markdown.
- **Schedule ↔ Flight:** Schedule blocks can link to Flight folders. `_NextClassBanner` in folder detail shows the next class.
