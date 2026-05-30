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

## 2026-05-29 — Backgrounds (pattern + color) for whiteboard & notebook
A "FONDO" toolbar button (both editors) opens `BackgroundPopup`: pattern (blank/lined/grid/gridSmall/dotted) + paper color (4 default swatches white/cream/gray/black + "MÁS" reusing `ColorPickerPopup` with a bg-only commit so it doesn't pollute stroke recents). Notebook adds a scope toggle PÁGINA-ACTUAL / TODO-EL-CUADERNO. `DrawingData` gained `background` + `bgColorValue` (serialized `bg`/`bgc`); `DrawingBlock` carries them too (was dropping them on read). **Notebook moved from a single global background to per-page**; new pages inherit the last-applied (`_lastBg`/`_lastBgColor`); the old note-level `rawMarkdown` bg pref is no longer read. Shared `background_paint.dart`: `bgPaper`, `bgMark` (auto-contrast — dark paper → white marks, luminance<0.4), `paintBgPattern`. Painters now fill the paper with the chosen color and tile the pattern. No flip; no warning on dark backgrounds (user relies on per-tool color memory to switch to a light pen).

## 2026-05-29 — Canvas image manipulation + crop (tanda 2)
Lasso now rotates/copies/cuts/pastes/duplicates images alongside strokes (separate `_imageClipboard`; pasted/duplicated images reuse the same file). Image tap-select (finger only) resolves on pointer-**up** if the finger didn't move — selecting on pointer-down was eaten by the InteractiveViewer pan arena (only worked after a prior lasso op). **Crop** (`image_crop_screen.dart`): full-screen modal, box (rectangular adjustable) or lasso (freeform → PNG with transparency); destructive — bakes a new file via `PictureRecorder`/`toImage` (box→JPEG, lasso→PNG), replaces the `CanvasImage.filename` and repositions it by the crop's fractional rect (keeps rotation). Triggered from a `RECORTAR` action shown in the lasso mini-toolbar only when exactly one image (and no strokes) is selected. No image flip (dropped). PDF export of whiteboard/notebook is still a separate unbuilt feature.

## 2026-05-29 — Canvas images (whiteboard + notebook)
Images can be placed on the whiteboard/notebook canvas (not the block `DrawingCell`). `CanvasImage {filename,x,y,w,h,rotation}` lives in `DrawingData.images`, serialized in the block payload (key `i`); `DrawingBlock` carries `imagesJson`. Tracked **only** in the payload (no `note_images` row) — the payload is the source of truth. Files reuse the existing `note_images/{noteId}/` folder; gallery/camera compress via `image_picker` (q80/1920), recent device photos via `photo_manager` + `flutter_image_compress`. Stored by filename only; path rebuilt from note id (survives reinstalls). Decoded to `ui.Image` by `CanvasImageCache` (per-editor, repaints on load) and drawn **behind strokes** (`drawCanvasImage`). Orphan files are reconciled on editor `dispose` (delete files not referenced by any page). Lasso (option A) handles images alongside strokes: select (finger-tap only — stylus never tap-selects images; stylus polygon does enclose them), move, resize, delete; rotate/copy/paste/flip of images is pending (tanda 2), as is PDF export of whiteboard/notebook (no PDF export exists for them yet). New deps: `photo_manager`, `flutter_image_compress` + photo permission in the Android manifest.

## 2026-05-29 — Highlighter + per-tool memory + global drawing prefs
New `DrawTool.highlighter` + `DrawingStroke.isHighlighter` (serialized `hl`). Renders wide/translucent via `BlendMode.multiply` at alpha 0.5 in the shared `drawStroke` (and `lasso_painter` previews) — keeps the ink underneath legible without reordering passes; chosen over a two-pass "behind ink" render to avoid touching ~5 render sites. May switch to two-pass if multiply looks wrong. Highlighter reuses the pen freehand pipeline but skips shape-snap (no hold timer) and scribble-erase. The local `_draw` in `drawing_cell`/`whiteboard` now just delegate to `drawStroke` (single source of truth).

**Per-tool color/width memory:** each colored tool (pen/fountain/highlighter) remembers its own color + width; switching tools saves the outgoing slot and restores the incoming one (`_toolColors`/`_toolWidths` + `_selectTool`). The recent/saved color palette stays shared.

**Global persistence (`drawing_prefs.dart`, SharedPreferences):** these are user/device preferences, not note content, so they're app-wide and shared across all 3 editors — per-tool color/width, stabilizer level, palm rejection, and fill toggle. NOT persisted: active tool and zoom-lock (contextual). Defaults: pen ink/3, fountain ink/2, highlighter amber/20.

## 2026-05-29 — Drawing stroke stabilizer (off by default)
Strokes are raw by default in all 3 editors (no finish-time `smoothPoints`/`_smooth`). A toolbar button (`StabilizerLevel` OFF/BAJO/MEDIO/ALTO in `stroke_stabilizer.dart`) enables a live EMA position filter (`LiveStabilizer`) applied to x/y only — shared by pen and fountain pen. When on, the move-time min-dist downsample is skipped. Per-stroke instance created on pointer-down, nulled on up/cancel.

## 2026-05-29 — Snapshot-based undo/redo
Undo/redo store deep-copied stroke snapshots (`DrawingStroke.clone()`), not just the last-added stroke — so erasing, lasso delete/move/resize/rotate/color/width/cut/paste/duplicate, and clear are all reversible. Continuous gestures (eraser drag, lasso move/resize/rotate) capture one snapshot at gesture-start and commit on gesture-end. Notebook keys snapshots by page `blockId` (`Map<int, List<DrawingStroke>>`) since strokes live per-page; page add/delete/reorder clears both stacks.

## 2026-05-29 — Shape snap: live-adjust + translucent fill
After a shape snaps (hold-to-recognize), the editor enters a live-adjust state instead of committing immediately: the ongoing drag resizes closed shapes (scale around centroid, ratio = pointer-dist / snap-time-dist) or moves the end point of lines/arrows (anchored at the start), committing on pen-up. `_snapKind/_snapBasePoints/_snapCenter/_snapAnchor/_snapRefDist` hold the state in whiteboard + notebook (the block `DrawingCell` has no snap). Closed shapes can be drawn with a GoodNotes-style translucent fill (`DrawingStroke.filled`, color @ 0.22 alpha via `fillStrokeShape` in `drawing_engine.dart`), toggled by a "RELLENO" toolbar button. Shared shape builders (`buildLineShape`, `buildArrowShape`, `scaleShape`, `shapeCentroid`) live in `shape_recognizer.dart`.

Recognized shapes carry `DrawingStroke.isShape` and render as **crisp straight polylines** (`buildStrokePath`), not the freehand quadratic smoothing that turns polygons into a teardrop blob. Both the main painters and `lasso_painter.dart` (highlight/move/resize/rotate previews) honor `isShape`. `filled`/`isShape` are serialized (`fl`/`sh`) and preserved by `clone()`/`copyWith()`.

## 2026-05-29 — Scribble erase resampling fix
`isScribble()` now resamples input points to 40 evenly-spaced arc-length points before computing angular variance and crossing density. This normalises point density regardless of how many raw pointer events Flutter delivers (the event rate varies significantly between "cold" app start and "warm" steady-state). Without this, the same scribble would have `angVar ≈ 0.42` on first use and `angVar ≈ 0.13` afterwards, making detection inconsistent. The resample target (40) was chosen because the first successful scribble had ~40 points.

Also: `_rawPen` is still populated for scribble detection but the density-normalised analysis uses resampled points. Added `_doScribbleErase()` in whiteboard (was missing), scribble guard in `_tryShapeSnap` (both editors), and `_onUp` priority check in whiteboard.

## 2026-05-29 — Background color favorites separated from pen favorites
Background color picker now uses its own `SavedBgColorsPrefs` (key `saved_bg_colors_v1`) instead of sharing `SavedColorsPrefs` (key `saved_pen_colors_v1`). The background picker's star button was a no-op before; now it saves/removes independently. Added `_starBgColor()` in both editors.

## 2026-05-29 — SNAP (lasso grid) removed
The SNAP toggle button (`_snapToGrid`) and its 25px grid snap for lasso move/paste was removed from the whiteboard toolbar. It added UI clutter for a feature that 95%+ of users never use. Hardcoded snap step to 0 in lasso move/paste calls.

## 2026-05-29 — Eraser partial mode + cursor in notebook
Ported partial eraser mode (`EraserMode.partial`) and eraser cursor indicator from whiteboard to notebook. Eraser button now toggles a popup (TRAZO / PRECISO) when already active, icon changes with mode. Cursor widget (`EraserCursor`) positioned outside InteractiveViewer in screen space to avoid transform scaling issues.

## 2026-05-29 — Lasso toolbar position
Adjusted lasso mini-toolbar vertical offset from `bb.top - 64` to `bb.top - 50` in both whiteboard and notebook editors.

## 2026-05-29 — Image panel sort order
Image insert panel now uses `FilterOptionGroup` with `OrderOption(type: createDate, asc: false)` to sort by creation date descending via `PhotoManager.getAssetListPaged`. Previously it fetched the first page unsorted, showing oldest photos first.

## 2026-05-29 — Partial erase: segment subdivision
`splitStrokeByEraser` now subdivides segments that intersect the eraser tip before running the point-erase logic. This fixes partial erasing of shape-snap strokes (rectangles/triangles with only 4-5 vertices) and wide strokes (highlighter). Also changed radius from `radius` alone to `radius + strokeWidth / 2` to match `strokeHitByEraser`.

## 2026-05-29 — Screen-constant lasso/eraser hit areas
Lasso handle hit radius and eraser radius are constant in *screen* pixels: divided by the view scale (`LassoController.hitScale`, set from `_viewScale`) so they don't balloon when zoomed. Eraser uses `strokeHitByEraser` (distance to segment + stroke half-width) for tip-accurate erasing instead of any-vertex-in-radius. Lasso preserves `isFountainPen` and full point components (3rd = baked width) across all transforms.
