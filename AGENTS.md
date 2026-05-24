# AGENTS — Segundo Cerebro

## Instrucciones de arranque (LEER ANTES DE HACER CUALQUIER COSA)

1. Leer `CONTEXT.md` completo para entender la arquitectura y decisiones del proyecto.
2. Leer `PROGRESS.md` completo para saber qué está hecho y qué falta.
3. Solo después de leer ambos archivos, continuar con el trabajo.

## Codegraph Policy

Prefer `codegraph` when a task benefits from semantic code search, symbol lookup, architecture discovery, impact analysis, or richer project context. The project is already initialized with a native backend (better-sqlite3).

Do not treat `codegraph` as mandatory when simple file reads or text search are enough.

Do not install, reinstall, initialize, reinitialize, uninitialize, or reconfigure `codegraph` unless the user explicitly asks for it.

## Al finalizar cada sesión

1. Actualizar `PROGRESS.md` con una nueva entrada fechada.
2. Si se tomó alguna decisión técnica que cambie la spec original, actualizar `CONTEXT.md`.

## Premisas irrompibles

- 100% Offline-First. Cero servidores, cero red.
- borderRadius: 0 en absolutamente todo, sin excepciones.
- Riverpod nunca habla directamente con Drift. Siempre a través del Repository.
- El esquema SQLite es compatible con PostgreSQL (futuro Supabase).
- Analizar componentes reutilizables antes de implementar cualquier vista nueva.
- Considerar siempre tablet y manejo de teclado en cada vista.
- Todo texto visible en UI debe comenzar con mayúscula. Sin excepciones.
