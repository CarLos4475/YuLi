# Optimización pendiente — Tiempo de entrada vs fluidez en paneo

## Contexto

Actualmente ambos editores (notebook y pizarra) priorizan fluidez en paneo sobre velocidad de entrada: cargan todo el contenido upfront y nunca evictan. Esto elimina el lag durante el gesto pero penaliza el open time, especialmente en notebooks/pizarras densas con muchas páginas o trazos.

El plan de chunks dinámicos para nitidez de paneo requiere que los datos estén en RAM sin sorpresas (sin evicción ni re-decode), por lo que esta decisión es necesaria como base limpia.

## Estado actual de los editores

### Notebook (`notebook_editor_screen.dart`)

- `_loadPages()` decodifica TODAS las páginas secuencialmente al entrar (1 por ciclo de await, sin yield entre ellas).
- `_evictColdPages()` retorna 0 (evicción desactivada).
- `_scheduleDeferredDecode()` / `_decodeMorePages()` existen pero son no-ops porque `_pendingDecode` está vacío.
- `_pendingDecode` se usa solo para recovery en errores de decode.
- `_pageShells` se mantiene actualizado en `_persistPage` para futura rehidratación.
- El batch fetch de strokes (450 por lote con `endOfFrame`) sigue activo en `_decodeData`.

### Pizarra (`whiteboard_editor_screen.dart`)

- `_ensureCanvasBlock()` llama a `_decodeData()` síncrono (todo upfront).
- No tiene sistema de shells/pendingDecode (nunca existió para pizarra).
- `_mergeLoadedStrokeRows`, `_ensureStrokesLoadedForRegion`, `_ensureAllStrokesLoadedForGlobalOp` existen pero solo se ejecutan bajo demanda explícita.

## Problema

Entrar es lento proporcional al contenido total:
- Notebook: O(n páginas × m trazos), con batch fetch que da respiro al UI pero alarga el open.
- Pizarra: O(n trazos), decode síncrono de todos los strokes de una vez.

Una vez dentro: cero lag, cero decode sorpresa, cero evicción.

## Objetivo

Entrar rápido (~300-500ms para notebooks típicos) sin sacrificar fluidez en paneo.

## Solución propuesta — Decode agresivo post-entrada sin evicción

### Cómo funciona

1. **Shells inmediatos** (ya existe en notebook con `_pageShells`, `_pendingDecode`):
   - Al abrir, registrar todas las páginas como shells (metadata sin strokes).
   - Decodificar la página actual + vecinos inmediatos síncrono (primeros ~3 frames).
   - Mostrar UI instantáneamente con las páginas visibles cargadas.

2. **Decode agresivo en segundo plano**:
   - Decodificar 4-8 páginas por frame (no 1 como antes) usando `endOfFrame` para no bloquear el UI thread.
   - Para un notebook de 50 páginas: ~6-12 frames ≈ 100-200ms a 60fps.
   - Para uno de 100 páginas: ~12-25 frames ≈ 200-400ms.
   - El usuario no alcanza a interactuar en ese tiempo (está procesando la escena).

3. **Zero evicción**:
   - Una vez decodificada, una página nunca se desaloja.
   - `_evictColdPages()` siempre retorna 0.

4. **Overview como fallback visual**:
   - Mientras una página no está decodificada, se muestra su overview borroso o papel vacío.
   - Apenas termina el decode, se hornea su overview y se muestra nítido.
   - El usuario nunca ve agujeros ni cuadros blancos.

### Cambios necesarios en notebook

| Archivo | Cambio |
|---|---|
| `_loadPages()` | Restaurar registro de shells + decode eager de first/last (como en commit c4a36bf pero sin evicción). |
| `_decodeMorePages()` | Cambiar `perBatch` de 1 a 4-8. Las páginas se priorizan por cercanía al viewport (la función `_nextPendingDecodeBlockId()` ya hace esto). |
| `_scheduleDeferredDecode()` | Restaurar con delay 0 post-entrada. |
| `_evictColdPages()` | Mantener en 0. |
| `_hasEvictableColdPages()` | Mantener en false. |
| `_onDown()` | Restaurar el chequeo `_pageData.containsKey(blockId)` para evitar dibujar en páginas no listas. |

### Cambios necesarios en pizarra

No aplica el mismo sistema. La pizarra es un canvas único, no hay páginas. Alternativas:

1. **Decode en batches agresivos**: en `_ensureCanvasBlock` en vez de `_decodeData()` síncrono, usar `_decodeDataInBatches()` con batches de 600 y 4-8 por frame.
2. **Shell metadata**: mostrar fondo y viewport inmediatamente, cargar strokes en segundo plano con prioridad al viewport visible (similar a lo que hacía `_hydrateVisibleCanvasStrokes` pero sin evicción).

### Riesgos

- Si el usuario dibuja antes de que termine el decode, los strokes se pierden o se sobrescriben. El chequeo en `_onDown()` previene esto (bloquea el stylus si la página no está lista).
- La pizarra al ser un canvas único es más riesgosa para el decode parcial. Opción más segura: mantener decode total pero optimizar el parseo de JSON (protobuf, o streaming).
