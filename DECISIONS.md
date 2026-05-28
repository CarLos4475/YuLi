# DECISIONS — YuLi

## 2026-05-24 — Task↔Kanban bidirectional sync
When a task is completed in Fight, its linked kanban card moves to "Entregado" with `originTaskDoneAt`. When a card moves to "Entregado", the linked task completes. Moving a card out of "Entregado" clears `originTaskDoneAt`.

## 2026-05-24 — Expiry triggers kanban cascade
When a task transitions `archived_failed → trash`, the linked card moves to "Vencido". On permanent hard delete (7 days), `originTaskId` and `originTaskDoneAt` are cleared from the card.

## 2026-05-24 — `originFolderColor` nullable
Added as nullable int field (schema v9) to preserve Flight folder color on kanban cards for badges. ALTER TABLE on SQLite doesn't apply defaults to existing rows, so nullable avoids migration crashes.

## 2026-05-24 — Schedule lazy settings
Settings are created lazily on first opening the Schedule tab, not at LabSpace creation time. `showSaturday`/`showSunday` are nullable int columns to survive ALTER TABLE on existing databases.

## 2026-05-24 — Schedule overlap algorithm
Greedy lane assignment: each block goes to the first available lane. If all lanes conflict, a new lane is created. Cascade overlap (Google Calendar style) expands blocks 50% beyond their lane when adjacent lanes exist.

## 2026-05-24 — Whiteboard shape recognition
Hold-end trigger (800ms timer, reset on pointer-move, 20px tolerance). Uses Douglas-Peucker simplification + radial variance + line regression across stroke types. Snaps to recognized shape on hold-end with HapticFeedback.

## 2026-05-24 — Drawing palm rejection
Enabled by default. Filters `PointerDeviceKind.stylus` / `invertedStylus`. Finger input won't draw — used for panning via InteractiveViewer.

## 2026-05-24 — `archived_failed` grace period
VENCIDAS bucket uses `archived_failed` status with a 24-hour grace period before moving to trash. No DB migration needed — done via query logic.

## 2026-05-24 — Pinning via SharedPreferences
Folder/note pinning stored in SharedPreferences, not in DB. Avoids schema changes for lightweight preference data.

## 2026-05-24 — Whiteboard pan+zoom
`InteractiveViewer` with 0.3x–4x scale, 10000×10000 canvas. Lock toggle disables pan/zoom for drawing.

## 2026-05-25 — Column terminal toggle
Explicit `isTerminal` boolean on `kanban_columns` (schema v13). "Entregado" and "Vencido" default to terminal. Toggle in column menu, not inferred from name.

## 2026-05-25 — Drawing data as JSON in `note_blocks.payload`
Drawing strokes serialized as JSON array in the `payload` column of `note_blocks`, not in a separate table. Keeps block structure self-contained.

## 2026-05-27 — Note kind = enum in `Notes.kind`
Added `notebook` kind alongside `block` and `whiteboard`. Notebook uses paginated A4 canvas, whiteboard uses infinite scroll. Block is the original markdown-with-blocks editor.
