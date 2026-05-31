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

### OCR v1 — primer slice en PIZARRA (branch `ocr`)

**Qué se implementó:** base tinta→texto + enganche en pizarra.
- Dependencia `google_mlkit_digital_ink_recognition` (on-device). Servicio `InkRecognizer` (seam `text`/`math`) + impl ML Kit + provider. Solo `text`; `math` lanza error (reservado).
- Lasso con **escritura** seleccionada (pen/fountain; excluye figuras/resaltador/imágenes) → botón **"→ TEXTO"** en el mini-toolbar → reconoce → **sheet `TEXTO RECONOCIDO`** editable con **Copiar todo** + selección manual de fragmentos + aviso "parece no-texto".

**Cómo probar (en dispositivo):**
- Escribe a mano en una **pizarra**, selecciona con lasso, toca la selección → mini-toolbar → **"→ TEXTO"**.
  - ✅ Primera vez descarga el modelo de español (red una vez; spinner). Luego offline.
  - ✅ Sheet con el texto reconocido, **editable**; corriges, copias todo o seleccionas a mano.
- Escribe notación matemática (Σ, integral) → ✅ debe salir el **aviso** "parece matemáticas/dibujo" (heurística por baja proporción de letras; no detecta todos los casos).
- Seleccionar solo figuras/imágenes/resaltador → ✅ NO aparece el botón "→ TEXTO".
- Calidad del reconocimiento con tu letra real (punto sensible).

**Aún NO hecho:** enganche en **cuaderno** y **celda de dibujo de notas**; acción **"Enviar a nota"** en la sheet; pantalla de ajustes para gestionar el modelo de idioma.
