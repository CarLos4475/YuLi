# Optimización pendiente — Pizarra densa: nitidez sin lag a zoom alto

## Escenario (extremo, raro)
Una pizarra con ~569k trazos / 25,7M puntos. A zoom in (~2x), la región visible
del lienzo contiene **~18.000 trazos** (densidad: 569k sobre 10000×10000). NO es un
caso de uso normal — se documenta por completitud, no es prioridad.

## El problema
El render de la pizarra usa:
- **En movimiento / zoom out** → ráster (overview pre-horneado + focus tile). Fluido.
- **En reposo, zoomeado in** → **VECTOR** (tiles de `StrokeTileIndex`). Principio
  fijado en el trabajo de chunks: "en movimiento nunca vector; en reposo se
  normaliza a vector". Bueno para notas livianas (nítido y barato).

Con densidad extrema ese principio se rompe:
- "Vector en reposo" = grabar ~18k paths cuando un tile entra en vista.
- El focus tile (ráster) que cubre el zoom-in en movimiento **re-hornea esos 18k
  trazos en CADA settle de paneo** (~1.5s de hitch en main isolate, medido:
  `bake-focus-pizarra región 1856x1719`, frames `build 1100-1600ms`).

NO es el scan O(n): `strokeBounds` está cacheado (Expando) → escanear 569k es ~6ms.
El costo es **dibujar los 18k trazos que genuinamente caen en pantalla**. Por eso
LOD/decimación no alcanza (siguen siendo 18k draw calls) y por eso un intento de
"cull por índice espacial" en los bakes NO sirvió (los 18k están en la región
igual; revertido).

## El fix propuesto (cuando se retome)
**Eliminar el "vector en reposo" para la pizarra densa: ráster SIEMPRE.** Evolucionar
el sistema de chunks a **tiles ráster pequeños, anclados en mundo, PERSISTENTES**:
- Cada tile chico se hornea **una vez** al entrar en vista (~pocos cientos de
  trazos, <100ms), se **cachea**, y se blittea tanto en reposo como en paneo.
- Re-hornear **solo** la región editada (invalidación por rect), no por settle.
- Bake **presupuestado** (1 tile/frame) → nunca un hitch de 1.5s; ~15 tiles de
  ~100ms repartidos, con el overview tapando visualmente mientras se llenan.
- Quitar el fallback a tiles vectoriales cuando la densidad de la región supera un
  umbral (p.ej. > N trazos visibles); por debajo, el sistema actual (vector en
  reposo) se queda igual — es barato y nítido para notas normales.

Es básicamente arreglar el chunk system actual (`_chunkTiles`/`_bakeChunk` en
`whiteboard_editor_screen.dart`) para que sea **persistente + por-tile-chico +
cubra el reposo**, en vez del focus gigante re-horneado por settle.

## Fuera de alcance ahora
Esto NO bloquea nada del uso normal. Prioridad actual: carga diferida (lazy open)
en pizarra y optimización del decode (I/O de Drift), que benefician a TODAS las
notas, no solo al caso extremo.
