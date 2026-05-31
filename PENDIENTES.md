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

### OCR v1 — COMPLETO en pizarra + cuaderno + celda de dibujo (branch `ocr`)

**Qué se implementó:** tinta→texto on-device en las 3 superficies de tinta.
- Dependencia `google_mlkit_digital_ink_recognition`. Servicio `InkRecognizer` (seam `text`/`math`; `math` lanza, reservado) + impl ML Kit + provider. Flujo compartido `runOcrFlow`.
- Lasso con **escritura** (pen/fountain; excluye figuras/resaltador/imágenes) → botón **"→ TEXTO"** → reconoce → **sheet `TEXTO RECONOCIDO`** editable: **Copiar todo** (usa accent), copiar fragmentos a mano, **Enviar a nota**, aviso "parece no-texto".
- **Enviar a nota:** selector de **carpeta** (chips) + **notas existentes** (añade celda de texto) o **NUEVA NOTA** (crea nota tipo bloque en la carpeta).
- **Ajustes → RECONOCIMIENTO (OCR):** descargar/borrar el modelo de español.

**Cómo probar (en dispositivo) — repetir en pizarra, cuaderno y una celda de dibujo de nota:**
- Escribe a mano, lasso, toca selección → **"→ TEXTO"**.
  - ✅ Primera vez descarga modelo (red una vez; spinner). Luego offline. (También se puede pre-descargar en Ajustes.)
  - ✅ Sheet editable; corriges, **Copiar todo** (botón con el color/accent de la nota) o selección manual.
  - ✅ **Enviar a nota**: elige carpeta y una nota existente (se añade celda de texto al final) o crea una nueva → SnackBar de confirmación; abre la nota y verifica la celda.
- Notación matemática (Σ, integral) → ✅ **aviso** "parece matemáticas/dibujo".
- Solo figuras/imágenes/resaltador → ✅ NO aparece "→ TEXTO".
- **Ajustes**: estado del modelo (Descargado/No), botón Descargar/Borrar funciona.
- Calidad del reconocimiento con tu letra real (punto sensible).

**Aún NO hecho:** elegir **idioma** del modelo (hoy fijo español); el **modo Matemáticas** (seam listo, motor LaTeX futuro).
