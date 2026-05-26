# YuLi — Pendientes

## Whiteboard: Shape Recognizer (rectángulos/cuadrados)

**Estado:** No funciona correctamente. Al dibujar un rectángulo o cuadrado y hacer hold, se detecta como elipse o no se detecta.

**Contexto:**
- El hold-con-tolerancia (800ms, 20px) funciona bien como trigger
- Círculos se detectan correctamente
- Triángulos se detectan correctamente
- Rectángulos/cuadrados fallan — Douglas-Peucker no simplifica a 4 vértices de forma confiable con trazos a mano alzada
- El fallback por bbox tampoco es suficiente

**Archivos relevantes:**
- `lib/presentation/screens/flight/shape_recognizer.dart` — `_tryPolygon()`, `_mergeClose()`, `_maxDistToBbox()`
- `lib/presentation/screens/flight/whiteboard_editor_screen.dart` — `_tryShapeSnap()`, `_startHoldTimer()`

**Posibles approaches:**
- Usar Hough transform o convex hull + minimum area rectangle en vez de Douglas-Peucker
- Detectar 4 segmentos lineales dominantes y calcular intersecciones
- Checar si el ratio perímetro²/área ≈ 16 (cuadrado) o dentro de rango rectangular
- Usar la varianza de distancia a cada edge del bbox en vez de varianza radial
