# PENDIENTES — YuLi

Cosas implementadas que faltan **verificar en dispositivo físico** (no se pueden probar en remoto). Cuando confirmes que algo funciona, bórralo de aquí.

---

## Verificación pendiente

### 2. Caja de tareas — resize por esquina y lateral (cuaderno + pizarra)

**Qué se cambió:** el bloque ahora tiene un campo `scale`. El contenido se maqueta a ancho `w/scale` y se escala uniforme con `FittedBox(fit: fitWidth)`. Se eliminó el viejo `_heightLocked` + `FittedBox.fill` (deformaba y nunca se activaba porque el lasso muta el bloque in-place).

**Cómo probar (con el lasso, bloque seleccionado):**
- **Resize por ESQUINA:**
  - ✅ Esperado: crece/encoge **uniforme** — la caja Y el **texto** escalan juntos (la letra se hace más grande/chica). Cambia ancho **y alto** a la vez. NO debe deformarse (texto estirado/aplastado).
  - ✅ Al **soltar** debe quedar exactamente como se veía durante el arrastre — **sin** deformarse y **sin** tener que "moverla un poco" para que tome forma.
- **Resize LATERAL derecho:**
  - ✅ Esperado: solo cambia el **ancho**, el texto **refluye** (se reacomoda) al mismo tamaño de letra. (Esto ya funcionaba; confirmar que sigue igual.)
- **Resize en vivo:**
  - ✅ Durante el arrastre por esquina se debe ver el cambio en tiempo real (la caja sigue al lasso). Durante el lateral la caja se queda quieta y salta al reflujo al soltar (comportamiento aceptado).
- Probar **encoger** hasta el mínimo (no debe bajar de ~220×90 px renderizados ni dejar el texto ilegible/cortado).
- **Rotar** + luego redimensionar: que siga coherente.
- **Cerrar y reabrir** el cuaderno/pizarra: el bloque debe conservar su tamaño/escala (se serializa `scale`). Bloques **viejos** (creados antes de este cambio) deben verse igual que antes (scale por defecto 1.0).
- Que el **bounding box del lasso** quede bien ajustado al bloque después de redimensionar (sin franja vacía arriba/abajo).

### v2 — Asistente IA (chat) — branch `ocr` — NECESITA TU API KEY

**Qué se implementó:** base DeepSeek (streaming, OpenAI-compatible) + key cifrada en Ajustes + panel de chat efímero anclado. Read-only (la IA habla, tú copias; NO edita notas → eso es v3). Entrada actual: desde la sheet de OCR, botón **"Preguntar a IA"**.

**Cómo probar (en dispositivo):**
1. **Ajustes → ASISTENTE IA (DEEPSEEK)** → pega tu API key → **Guardar** (se guarda cifrada; el estado pasa a "Configurada ✓"). La key NO sale del dispositivo.
2. Pizarra/cuaderno/celda: escribe a mano → lasso → **"→ TEXTO"** → en la sheet, **"Preguntar a IA"** → se abre el chat anclado a ese texto.
   - ✅ La respuesta llega en **streaming** (token a token).
   - ✅ Chips de atajo: Resumir / Limpiar / Extraer tareas / Título / Traducir.
   - ✅ Repreguntar mantiene el hilo ("más corto", "en inglés").
   - ✅ Toggle **FLASH/PRO** (modelo).
   - ✅ **Copiar** en cada respuesta de la IA.
   - ✅ Cerrar el chat / salir de la nota lo descarta (efímero).
3. **Sin key** → al abrir el chat avisa "configura tu API key en Ajustes". **Key inválida / sin red / sin saldo** → mensaje de error claro en el chat.
4. Arranque en frío (cuando exista botón global): pide "¿De qué es esto?" como ancla. (Hoy el chat soporta el ancla; falta el botón de lanzamiento en frío.)

**Aún NO hecho:** botón global para abrir el chat **en frío** y desde el **contenido de una nota** (no solo OCR); **v3** = que la IA aplique cambios (crear tareas, insertar/reemplazar celda, título).

### OCR v1 — a futuro (verificado en dispositivo, NO bloquea)

OCR v1 funciona en pizarra, cuaderno y celda de dibujo. Quedan para más adelante:
- **Elegir idioma del modelo** (hoy fijo español `es`). Sería un selector en Ajustes + pasar el `langTag` a `runOcrFlow`. La base ya soporta varios idiomas.
- **Modo Matemáticas** (Σ, integrales, etc.): el seam `InkRecognitionMode.math` ya está reservado (hoy lanza). Falta el motor manuscrito → LaTeX (Mathpix, nube) → celda Math. Ver `ONLINE_FEATURES.md`.
