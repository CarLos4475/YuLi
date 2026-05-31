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

**Qué se implementó:** base DeepSeek (streaming, OpenAI-compatible) + key cifrada en Ajustes + chat read-only (habla y copias; NO edita → v3). **La conversación vive en una sesión POR NOTA** (provider autoDispose), no en el sheet. Entradas: botón **IA** (✨) en el toolbar de **pizarra/cuaderno** y en el header del **editor de notas**, y **"Preguntar a IA"** desde la sheet de OCR.

**Cómo probar (en dispositivo):**
1. **Ajustes → ASISTENTE IA (DEEPSEEK)** → pega tu API key → **Guardar** ("Configurada ✓"). No sale del dispositivo.
2. Abre el chat (botón IA en pizarra/cuaderno/nota, o desde el lasso/OCR).
   - ✅ Streaming, chips (Resumir/Limpiar/Extraer tareas/Título/Traducir), repreguntar mantiene hilo, toggle FLASH/PRO, Copiar, "N hoy" + bloqueo al llegar a 150.
   - ✅ **La respuesta se renderiza como markdown** (negritas, listas, código, blockquotes, checklists, tablas, LaTeX `$..$`/`$$..$$`) con el mismo renderer de las notas. Durante el streaming se ve texto plano y al terminar "cuaja" a markdown.
   - ✅ **Entradas:** botón IA en header de nota y en header/toolbar de pizarra/cuaderno; desde el lasso: **Enviar a Yuli** (texto OCR → contexto), **Preguntar a Yuli** (OCR → prellena el input, sin tocar el contexto), **Importar nota** (pizarra/cuaderno → elegir otra nota de la carpeta como contexto). Long-press en una nota inyecta su contenido (sin duplicar).
3. **Persistencia (lo que faltaba):**
   - ✅ **Cierra el sheet** y vuelve a abrir IA → la conversación **sigue ahí** (no se pierde).
   - ✅ **Sal de la nota/pizarra/cuaderno** y entra de nuevo → **los mensajes se descartan** (chat limpio) PERO **el contexto/ancla PERSISTE por nota** (sigue ahí, incluso tras reiniciar la app).
4. **Cambiar/añadir contexto (lo que faltaba):**
   - ✅ Toca el chip **"CONTEXTO"** arriba → editor para **editar / reemplazar / limpiar** el ancla.
   - ✅ Con un chat ya con contexto, manda **otro** (OCR de pizarra, o IA desde otra nota) → pregunta **Añadir / Reemplazar**. (Si el contexto entrante es idéntico al actual, no pregunta.)
5. **Sin key** → avisa ir a Ajustes. **Key inválida/sin red/sin saldo** → error claro en el chat.
6. **Auto-compactación del contexto (token-shielding):** carga un contexto largo (>3000 chars; p.ej. varios OCR/notas añadidos) y manda un mensaje → ✅ la IA **compacta** el contexto una vez, aparece el aviso **"✦ Compacté el contexto…"** y un botón **DESHACER** (solo en ese aviso). Deshacer restaura el contexto largo. Editar/añadir contexto vuelve a habilitar la compactación. (No debe poder enviarse otro mensaje mientras compacta.)

**Aún NO hecho:** **v3 real** = que la IA edite notas (crear tareas → FIGHT, insertar/reemplazar celda, poner título). La auto-compactación (#6) ya fue el calentamiento: la IA edita el *contexto*, no las notas. (Producción: retry con backoff, mover key/llamadas a un proxy.)

### OCR v1 — a futuro (verificado en dispositivo, NO bloquea)

OCR v1 funciona en pizarra, cuaderno y celda de dibujo. Quedan para más adelante:
- **Elegir idioma del modelo** (hoy fijo español `es`). Sería un selector en Ajustes + pasar el `langTag` a `runOcrFlow`. La base ya soporta varios idiomas.
- **Modo Matemáticas** (Σ, integrales, etc.): el seam `InkRecognitionMode.math` está reservado. Se **probó Mathpix** (manuscrito → LaTeX) y quedó **solo en debug** (botón MATH del lasso + bloque de Ajustes gateados a `kDebugMode`); **descartado por caro**. Resolver de **otra forma** (por decidir). Limpiar el código Mathpix cuando se decida el reemplazo. Ver `ONLINE_FEATURES.md`.
