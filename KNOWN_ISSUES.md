# KNOWN_ISSUES — YuLi

## Whiteboard shape recognizer — rectangles fail

Rectangles and squares drawn on the whiteboard are not reliably detected by the shape recognizer.

- Circles and triangles work correctly.
- Douglas-Peucker simplification doesn't reduce hand-drawn rectangles to 4 reliable vertices.
- Bounding box fallback is insufficient.
- Affected file: `lib/presentation/screens/flight/shape_recognizer.dart` — `_tryPolygon()`, `_mergeClose()`, `_maxDistToBbox()`.

## GrainOverlay deactivated

`grain_overlay.dart` has `_GrainPainter` declared but unused. The `build()` returns `child` directly. Deactivated because the computation blocked the render thread on non-standard GPUs (Huawei). If reactivating, use `shouldRepaint` returning `false` and consider pre-rendering to an image or using shaders.

## LaTeX not wired in preview

`flutter_math_fork` is installed but not connected to the markdown preview pipeline. The `_MarkdownPreview` widget doesn't render LaTeX blocks yet.

## Tablet layout incomplete

No adaptive split-pane layout for tablets (>720dp). Grids in content areas are already responsive, but main screens use a single-column layout.

## Trash screen / Settings not implemented

The "PAPELERA" and "CONFIGURACIÓN" menu items in the `•••` menu just call `Navigator.pop()`. The corresponding screens don't exist yet.

## AppBanner onAction not wired

In `main.dart`, the "ver" button on the archived tasks banner calls `onAction: () {}` — no implementation.
