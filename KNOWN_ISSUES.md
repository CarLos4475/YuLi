# KNOWN_ISSUES — YuLi

## Whiteboard shape recognizer — rectangles fail

Rectangles and squares drawn on the whiteboard are not reliably detected by the shape recognizer.

- Circles and triangles work correctly.
- Douglas-Peucker simplification doesn't reduce hand-drawn rectangles to 4 reliable vertices.
- Bounding box fallback is insufficient.
- Affected file: `lib/presentation/screens/flight/shape_recognizer.dart` — `_tryPolygon()`, `_mergeClose()`, `_maxDistToBbox()`.

## GrainOverlay deactivated

`grain_overlay.dart` has `_GrainPainter` declared but unused. The `build()` returns `child` directly. Deactivated because the computation blocked the render thread on non-standard GPUs (Huawei). If reactivating, use `shouldRepaint` returning `false` and consider pre-rendering to an image or using shaders.

