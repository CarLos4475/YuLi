# KNOWN_ISSUES — YuLi

## Resolved: Notebook page jumping to the left on first pan (boundaryMargin + centering conflict)

**Fix:** Change `boundaryMargin` from `horizontal: kNotebookPageWidth * 0.3` to `horizontal: c.maxWidth`.

**Why:** `_applyInitialScroll` centers the page with `dx = (viewportW - 595) / 2`. On wide screens (tablet, landscape), this dx exceeds the horizontal boundary margin (178.5px). On first pan, `InteractiveViewer` clamps the position, snapping the page to the left. Zoom "fixed" it only because scaling changes the effective boundary calculation.

**File:** `lib/presentation/screens/flight/notebook_editor_screen.dart` — `InteractiveViewer` `boundaryMargin`.

**Do not revert** `horizontal: c.maxWidth` back to a fixed multiplier.

## Whiteboard shape recognizer — rectangles fail

Rectangles and squares drawn on the whiteboard are not reliably detected by the shape recognizer.

- Circles and triangles work correctly.
- Douglas-Peucker simplification doesn't reduce hand-drawn rectangles to 4 reliable vertices.
- Bounding box fallback is insufficient.
- Affected file: `lib/presentation/screens/flight/shape_recognizer.dart` — `_tryPolygon()`, `_mergeClose()`, `_maxDistToBbox()`.

## GrainOverlay deactivated

`grain_overlay.dart` has `_GrainPainter` declared but unused. The `build()` returns `child` directly. Deactivated because the computation blocked the render thread on non-standard GPUs (Huawei). If reactivating, use `shouldRepaint` returning `false` and consider pre-rendering to an image or using shaders.

