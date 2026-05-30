# KNOWN_ISSUES — YuLi

## Resolved: Scribble erase only worked once (sampling-rate bias in `isScribble`)

**Symptoms:** Borrado por garabato funcionaba solo la primera vez que se entraba a la app. Después nunca más — el mismo trazo que antes borraba, ahora se dibujaba como stroke normal.

**Root cause:** `_rawPen` captura todos los eventos de puntero sin filtrar. Con la app "fría" (recién abierta), Flutter entrega ~40 eventos por garabato → `angVar ≈ 0.42`. Con la app "caliente" (event loop a pleno), entrega ~150-200 eventos para el mismo trazo → los segmentos consecutivos miden 2-3px, son casi colineales → `angVar ≈ 0.13`. Como el threshold era `> 0.25`, `isScribble()` retornaba `false` para todos los garabatos excepto el primero.

**Fix (2026-05-29):** Agregado `_resampleTo()` en `note_cell_model.dart` — resampleo por arc-length a 40 puntos fijos antes de calcular varianza angular y densidad de cruces. Esto normaliza la densidad de puntos sin importar cuántos eventos entregue Flutter. La función `isScribble()` es compartida por pizarra, cuaderno y drawing cell.

**Also:** Creado `_doScribbleErase()` en `whiteboard_editor_screen.dart` (el método estaba declarado como llamado pero nunca implementado). Agregado guard `isScribble` en `_tryShapeSnap()` de ambos editores. Limpieza de `_rawPen = []` al final de cada erase.

**Files:**
- `note_cell_model.dart` — `_resampleTo()`, `isScribble()` usa puntos resampleados (40) para angVar/crossings
- `whiteboard_editor_screen.dart` — `_doScribbleErase()`, guard en `_tryShapeSnap`, prioridad en `_onUp`
- `notebook_editor_screen.dart` — guard en `_tryShapeSnap`

**Do not** reintroducir código que use `_rawPen` sin resamplear en `isScribble`.

## Resolved: Notebook lasso — mover selección entre páginas la duplicaba/agrandaba

**Fix (2026-05-29):** `_syncLassoToPages` usaba `s.points.any(p => p[1] >= pageTop && p[1] < pageBottom)` — si un trazo cruzaba dos páginas, se clonaba en ambas. Reescribí la función para asignar cada trazo a UNA sola página según el centroide en Y. Si el centroide cae en un gap, se asigna a la página más cercana.

**File:** `notebook_editor_screen.dart` — `_syncLassoToPages`.

## Resolved: Notebook page jumping to the left on first pan (boundaryMargin + centering conflict)

**Why:** `_applyInitialScroll` centers the page with `dx = (viewportW - 595) / 2`. On wide screens (tablet, landscape), this dx exceeds the horizontal boundary margin (178.5px). On first pan, `InteractiveViewer` clamps the position, snapping the page to the left. Zoom "fixed" it only because scaling changes the effective boundary calculation.

**File:** `lib/presentation/screens/flight/notebook_editor_screen.dart` — `InteractiveViewer` `boundaryMargin`.

**Do not revert** `horizontal: c.maxWidth` back to a fixed multiplier.

## Resolved: Whiteboard shape recognizer — rectangles fail / detected as triangles

**Fix (2026-05-29):** Rewrote `shape_recognizer.dart` around arc-length resampling. `detect()` returns a `RecognizedShape` (kind + points) and runs closed-shape detection even when not perfectly closed.

- **Rectangle** is detected by bbox geometry, not corner count: `_hugFraction > 0.80` (contour hugs the bbox) **and** `_allSidesCovered` (all 4 sides carry ≥5% of points). This is robust for wide/short rectangles whose short sides have too few resampled points to yield 4 corners (which previously misfired as triangles), while rejecting triangles (one side touched only by a vertex) and circles (arcs bow inward, hug ≈ 0.68).
- **Triangle / rotated rect** fall back to turning-angle corner detection with non-max suppression (`_dominantCorners`): 3 corners → triangle, 4 right-ish corners → rectangle (axis-aligned bbox if upright, else the quad).
- **Circle** uses centroid + relaxed spread (<0.18); ellipse via bbox fit.

**Rendering:** recognized shapes carry `DrawingStroke.isShape` and render as crisp straight polylines (`buildStrokePath` in `drawing_engine.dart`) — the freehand quadratic smoothing turns polygons into a "teardrop" blob. `lasso_painter.dart` path builders honor `isShape` too, otherwise the lasso highlight shows the blob.

## GrainOverlay deactivated

`grain_overlay.dart` has `_GrainPainter` declared but unused. The `build()` returns `child` directly. Deactivated because the computation blocked the render thread on non-standard GPUs (Huawei). If reactivating, use `shouldRepaint` returning `false` and consider pre-rendering to an image or using shaders.

