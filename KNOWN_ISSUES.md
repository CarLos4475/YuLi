# KNOWN_ISSUES — YuLi

## Resolved: Notebook page jumping to the left on first pan (boundaryMargin + centering conflict)

**Fix:** Change `boundaryMargin` from `horizontal: kNotebookPageWidth * 0.3` to `horizontal: c.maxWidth`.

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

