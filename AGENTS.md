# AGENTS — YuLi

## Codegraph Policy

Prefer `codegraph` when the task benefits from semantic search, symbol lookup, architecture discovery, or impact analysis. The project is already initialized (native backend, better-sqlite3).

Do NOT use codegraph when simple file reads or grep are sufficient.

Do NOT install, reinitialize, or reconfigure codegraph unless explicitly asked.

## Coding Conventions

- **No comments** unless the WHY is non-obvious.
- **No `await`** on async returns that already return a future.
- Wildcard params: `(_, _)` (Dart 3+ wildcards).
- Color hex: `'#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}'`.
- Soft delete: `deleted_at` / `trashed_at` columns. Hard delete after 7 days.
- `borderRadius: 0` on everything. No exceptions.
- All UI visible text must start with uppercase. No exceptions.
- Always consider tablet layout and keyboard handling in every view.
- Analyze reusable components before implementing any new view.

## Persistence Rules

- Riverpod NEVER imports Drift directly. Only Repository interfaces.
- Tables use `@DataClassName('XxxRow')` to avoid collision with domain models.
- `expires_at` is computed in Dart: `DateTime.now().add(Duration(hours: 48))`.
- No `Color.value` — use `Color.toARGB32()` (Flutter 3.27+).
- No `CardTheme` — use `CardThemeData`.
- No `dialogBackgroundColor` — use `DialogThemeData`.
- Manual providers only — no Riverpod generator (`@riverpod`).
- SQLite schema is designed to be PostgreSQL-compatible (future Supabase).

## Persistent Context Files

| File | Purpose |
|---|---|
| `ARCHITECTURE.md` | High-level system architecture, stack, folder structure |
| `DECISIONS.md` | Important technical decisions with reasoning |
| `KNOWN_ISSUES.md` | Persistent bugs, framework pitfalls, edge cases |
| `MEMORY.md` | Índice de todos los archivos de contexto |
| `user_profile.md` | Perfil del usuario (idioma, expertise, preferencias) |
| `feedback_workflow.md` | Regla "explica antes de codear" en bugs complejos |
| `feedback_style.md` | Estilo de comunicación (español, conciso) |

## Startup (LEER ANTES DE CUALQUIER COSA)

1. Leer `user_profile.md` — saber quién es el usuario y cómo comunicarse.
2. Leer `feedback_workflow.md` y `feedback_style.md` — saber cómo interactuar.
3. Leer `ARCHITECTURE.md` — entender stack, capas, carpetas.
4. Leer `DECISIONS.md` — entender por qué se hicieron las cosas.
5. Leer `KNOWN_ISSUES.md` — evitar reintroducir bugs conocidos.

## Maintenance Rules for Future Agents

- **Prune stale information** regularly. Prefer deleting over accumulating.
- Keep files small, signal-dense, and curated.
- **Avoid duplication** across files. If something belongs in one place, don't repeat it elsewhere.
- **Do not store** temporary debugging context, conversation logs, or long brainstorming notes.
- Treat these markdown files as **long-term memory infrastructure**, not logs.
- If you find outdated or irrelevant content, delete or archive it.
- If you add a new persistent convention, update the appropriate file.
- When in doubt, err on the side of less text.
